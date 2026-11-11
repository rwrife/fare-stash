import 'dart:io';

import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory directory;
  late String path;
  setUp(() {
    directory = Directory.systemTemp.createTempSync('fare-stash-');
    path = '${directory.path}${Platform.pathSeparator}passes.sqlite';
  });
  tearDown(() => directory.deleteSync(recursive: true));

  final at = DateTime.parse('2026-03-01T10:00:00-05:00');
  TransitPass pack() => TransitPass(
    id: 'pack',
    title: 'Rides',
    kind: PassKind.ridePack,
    startingBalance: 2,
  );
  PassEvent ride(String id) => PassEvent(
    id: id,
    passId: 'pack',
    occurredAt: at,
    kind: PassEventKind.ride,
    units: 1,
  );

  test('reopen preserves instants, units, corrections, and order', () {
    final store = PassStore.open(path);
    store.save(pack(), [ride('a')]);
    store.record(
      PassEvent(
        id: 'undo',
        passId: 'pack',
        occurredAt: at,
        kind: PassEventKind.reversal,
        reversesId: 'a',
      ),
    );
    store.save(
      TransitPass(
        id: 'value',
        title: 'Credit',
        kind: PassKind.storedValue,
        startingBalance: 1234,
        currency: 'USD',
      ),
      [
        PassEvent(
          id: 'c',
          passId: 'value',
          occurredAt: at,
          kind: PassEventKind.correction,
          units: -34,
          currency: 'USD',
        ),
      ],
    );
    store.close();
    final reopened = PassStore.open(path);
    expect(reopened.get('pack')!.balance, 2);
    expect(reopened.get('pack')!.rideCount, 0);
    expect(
      reopened.get('pack')!.events.first.occurredAt.isAtSameMomentAs(at),
      isTrue,
    );
    expect(reopened.get('value')!.balance, 1200);
    expect(reopened.get('value')!.pass.currency, 'USD');
    expect(reopened.all().map((p) => p.pass.id), ['pack', 'value']);
    reopened.close();
  });

  test('editing revalidates history and preserves original on failure', () {
    final store = PassStore.open(path);
    store.save(pack(), [ride('a')]);
    store.update(
      TransitPass(
        id: 'pack',
        title: 'Renamed',
        kind: PassKind.ridePack,
        startingBalance: 2,
      ),
    );
    expect(store.get('pack')!.pass.title, 'Renamed');
    expect(
      () => store.update(
        TransitPass(
          id: 'pack',
          title: 'Overdraw',
          kind: PassKind.ridePack,
          startingBalance: 1,
        ),
      ),
      returnsNormally,
    );
    expect(
      () => store.update(
        TransitPass(
          id: 'pack',
          title: 'Wrong type',
          kind: PassKind.timeLimited,
          validFrom: at.add(const Duration(days: 1)),
          validUntil: at.add(const Duration(days: 2)),
        ),
      ),
      throwsStateError,
    );
    expect(store.get('pack')!.pass.title, 'Overdraw');
    expect(store.get('pack')!.events.map((e) => e.id), ['a']);
    store.close();
  });

  test('failed batch and rejected events leave history unchanged', () {
    final store = PassStore.open(path);
    store.save(pack(), [ride('a')]);
    expect(
      () => store.save(
        TransitPass(
          id: 'another',
          title: 'Other',
          kind: PassKind.ridePack,
          startingBalance: 2,
        ),
        [ride('duplicate-foreign')],
      ),
      throwsStateError,
    );
    expect(store.get('another'), isNull);
    store.record(ride('b'));
    expect(() => store.record(ride('overdraw')), throwsStateError);
    expect(() => store.record(ride('b')), throwsStateError);
    expect(store.get('pack')!.events.map((e) => e.id), ['a', 'b']);
    store.close();
  });

  test('database duplicate event ID rolls back entire insert', () {
    final store = PassStore.open(path);
    store.save(pack(), [ride('a')]);
    final other = TransitPass(
      id: 'other',
      title: 'Other',
      kind: PassKind.ridePack,
      startingBalance: 3,
    );
    expect(
      () => store.save(other, [
        PassEvent(
          id: 'a',
          passId: 'other',
          occurredAt: at,
          kind: PassEventKind.ride,
          units: 1,
        ),
      ]),
      throwsA(isA<SqliteException>()),
    );
    expect(store.get('other'), isNull);
    store.close();
  });

  test('v1 schema migrates without losing historical rides', () {
    final old = sqlite3.open(path);
    old.execute('''CREATE TABLE passes (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL,
      starting_balance INTEGER, valid_from TEXT, valid_until TEXT)''');
    old.execute('''CREATE TABLE events (
      id TEXT PRIMARY KEY, pass_id TEXT NOT NULL REFERENCES passes(id),
      occurred_at TEXT NOT NULL, kind TEXT NOT NULL, units INTEGER,
      reverses_id TEXT)''');
    old.execute(
      "INSERT INTO passes VALUES ('pack','Rides','ridePack',2,NULL,NULL)",
    );
    old.execute(
      "INSERT INTO events VALUES ('a','pack','2026-03-01T15:00:00.000Z','ride',1,NULL)",
    );
    old.execute('PRAGMA user_version = 1');
    old.close();
    final store = PassStore.open(path);
    expect(store.get('pack')!.balance, 1);
    store.record(ride('b'));
    store.close();
    final check = sqlite3.open(path);
    expect(check.select('PRAGMA user_version').single.columnAt(0), 2);
    expect(
      check.select('PRAGMA table_info(events)').map((r) => r['name']),
      contains('currency'),
    );
    check.close();
  });

  test('corrupt history and future schema refuse opening', () {
    final db = sqlite3.open(path);
    db.execute('PRAGMA user_version = 3');
    db.close();
    expect(() => PassStore.open(path), throwsStateError);
    File(path).deleteSync();
    final store = PassStore.open(path);
    store.save(pack(), [ride('a')]);
    store.close();
    final damaged = sqlite3.open(path);
    damaged.execute("UPDATE events SET units = 7 WHERE id = 'a'");
    damaged.close();
    expect(() => PassStore.open(path), throwsFormatException);
  });

  test('broken migration rolls back and leaves v1 schema intact', () {
    final old = sqlite3.open(path);
    old.execute('''CREATE TABLE passes (
      id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL,
      starting_balance INTEGER, valid_from TEXT, valid_until TEXT)''');
    old.execute('''CREATE TABLE events (
      id TEXT PRIMARY KEY, pass_id TEXT NOT NULL REFERENCES passes(id),
      occurred_at TEXT NOT NULL, kind TEXT NOT NULL, units INTEGER,
      reverses_id TEXT)''');
    old.execute(
      "INSERT INTO passes VALUES ('p','Invalid','storedValue',100,NULL,NULL)",
    );
    old.execute(
      "INSERT INTO events VALUES ('e','p','2026-03-01T10:00:00.000Z','ride',10,NULL)",
    );
    old.execute('PRAGMA user_version = 1');
    old.close();

    expect(() => PassStore.open(path), throwsFormatException);
    final preserved = sqlite3.open(path);
    expect(preserved.select('PRAGMA user_version').single.columnAt(0), 1);
    preserved.close();
  });
}

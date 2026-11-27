import 'dart:convert';

import 'package:fare_stash/data/pass_backup.dart';
import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

PassLedger storedValueLedger({String id = 'metro'}) {
  final pass = TransitPass(
    id: id,
    title: 'Metro, "Go"',
    kind: PassKind.storedValue,
    startingBalance: 1000,
    currency: 'USD',
  );
  return PassLedger(pass, [
    PassEvent(
      id: 'ride-1',
      passId: id,
      occurredAt: DateTime.utc(2025, 2, 3, 4, 5, 6, 789),
      kind: PassEventKind.ride,
      units: 275,
      currency: 'USD',
    ),
    PassEvent(
      id: 'adjustment-1',
      passId: id,
      occurredAt: DateTime.utc(2025, 2, 3, 4, 6),
      kind: PassEventKind.correction,
      units: 25,
      currency: 'USD',
    ),
    PassEvent(
      id: 'undo-adjustment',
      passId: id,
      occurredAt: DateTime.utc(2025, 2, 3, 4, 7),
      kind: PassEventKind.reversal,
      reversesId: 'adjustment-1',
    ),
  ]);
}

void main() {
  test('JSON backup preserves IDs, UTC timestamps and minor-unit balances', () {
    final exportedAt = DateTime.utc(2025, 2, 4);
    final json = PassBackup.encode([
      storedValueLedger(),
    ], exportedAt: exportedAt);
    final restored = PassBackup.decode(json).single;

    expect(restored.pass.id, 'metro');
    expect(restored.pass.currency, 'USD');
    expect(restored.balance, 725);
    expect(restored.events.map((event) => event.id), [
      'ride-1',
      'adjustment-1',
      'undo-adjustment',
    ]);
    expect(
      restored.events.first.occurredAt,
      DateTime.utc(2025, 2, 3, 4, 5, 6, 789),
    );
    expect(jsonDecode(json)['version'], 1);
    expect(jsonDecode(json)['passes'][0]['events'][0]['units'], 275);
  });

  test('unsupported or malformed backups are rejected', () {
    expect(() => PassBackup.decode('{'), throwsFormatException);
    expect(
      () => PassBackup.decode(
        '{"format":"fare-stash-backup","version":2,"passes":[]}',
      ),
      throwsFormatException,
    );
  });

  test('CSV escapes user fields and includes immutable event history', () {
    final csv = PassBackup.toCsv([storedValueLedger()]);

    expect(csv, startsWith('pass_id,pass_title,event_id,event_kind,'));
    expect(csv, contains('"Metro, ""Go""",ride-1,ride,'));
    expect(csv, contains('275,USD,'));
    expect(csv, contains('undo-adjustment,reversal,'));
    expect(csv.endsWith('\r\n'), isTrue);
  });

  test('invalid and duplicate backups never alter stored records', () {
    final store = PassStore.memory();
    addTearDown(store.close);
    store.save(
      TransitPass(
        id: 'existing',
        title: 'Existing pass',
        kind: PassKind.ridePack,
        startingBalance: 5,
      ),
      [],
    );
    final duplicate = jsonDecode(
      PassBackup.encode([storedValueLedger()]),
    ) as Map<String, dynamic>;
    final passes = duplicate['passes'] as List<dynamic>;
    final pass = passes.single as Map<String, dynamic>;
    final events = pass['events'] as List<dynamic>;
    events.add(Map<String, dynamic>.from(events.first as Map<String, dynamic>));

    expect(() => store.restoreJson('{'), throwsFormatException);
    expect(
      () => store.restoreJson(jsonEncode(duplicate)),
      throwsFormatException,
    );
    expect(store.all().map((ledger) => ledger.pass.id), ['existing']);

    store.restoreJson(PassBackup.encode([storedValueLedger()]));
    expect(store.all().map((ledger) => ledger.pass.id), ['metro']);
    expect(store.get('metro')!.events.first.id, 'ride-1');
  });
}

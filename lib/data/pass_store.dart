import 'dart:io';

import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Local, append-only pass history. Callers own the database file and close it.
final class PassStore {
  final Database _db;

  PassStore._(this._db) {
    _db.execute('PRAGMA foreign_keys = ON');
    final version = _db.select('PRAGMA user_version').single.columnAt(0) as int;
    if (version > 2) throw StateError('Unsupported database version: $version');
    _transaction(() {
      if (version == 0) {
        final existing = _db.select(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
        );
        if (existing.isNotEmpty) {
          throw FormatException('Unversioned database has existing tables');
        }
        _db.execute('''
          CREATE TABLE passes (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, kind TEXT NOT NULL,
            starting_balance INTEGER, currency TEXT,
            valid_from TEXT, valid_until TEXT
          )
        ''');
        _db.execute('''
          CREATE TABLE events (
            id TEXT PRIMARY KEY, pass_id TEXT NOT NULL REFERENCES passes(id),
            occurred_at TEXT NOT NULL, kind TEXT NOT NULL, units INTEGER,
            currency TEXT, reverses_id TEXT
          )
        ''');
      } else if (version == 1) {
        // v1 had no currency fields; ride packs and time passes remain valid.
        _db.execute('ALTER TABLE passes ADD COLUMN currency TEXT');
        _db.execute('ALTER TABLE events ADD COLUMN currency TEXT');
      }
      if (version < 2) _db.execute('PRAGMA user_version = 2');
      // Validate before committing migrations; preserve damaged originals.
      try {
        final foreignKeys = _db.select('PRAGMA foreign_key_check');
        if (foreignKeys.isNotEmpty) throw FormatException('Orphan events');
        all();
      } catch (error) {
        throw FormatException('Invalid pass history: $error');
      }
    });
  }

  static PassStore open(String path) {
    final db = sqlite3.open(path);
    try {
      return PassStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  static Future<PassStore> openDefault() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return open('${directory.path}${Platform.pathSeparator}fare-stash.sqlite');
  }

  static PassStore memory() {
    final db = sqlite3.openInMemory();
    try {
      return PassStore._(db);
    } catch (_) {
      db.close();
      rethrow;
    }
  }

  void close() => _db.close();

  T _transaction<T>(T Function() action) {
    _db.execute('BEGIN IMMEDIATE');
    try {
      final result = action();
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  /// Inserts pass and its history together; validation failure rolls all back.
  void save(TransitPass pass, Iterable<PassEvent> history) {
    final events = List<PassEvent>.of(history);
    PassLedger(pass, events);
    _transaction(() {
      _db.execute('INSERT INTO passes VALUES (?, ?, ?, ?, ?, ?, ?)', [
        pass.id,
        pass.title,
        pass.kind.name,
        pass.startingBalance,
        pass.currency,
        pass.validFrom?.toUtc().toIso8601String(),
        pass.validUntil?.toUtc().toIso8601String(),
      ]);
      for (final event in events) {
        _insertEvent(event);
      }
    });
  }

  /// Revalidates every historical ride before updating a pass. No event changes.
  void update(TransitPass pass) {
    _transaction(() {
      final current = _load(pass.id);
      if (current == null) throw StateError('Unknown pass: ${pass.id}');
      PassLedger(pass, current.events);
      _db.execute(
        '''
        UPDATE passes SET title = ?, kind = ?, starting_balance = ?, currency = ?,
          valid_from = ?, valid_until = ? WHERE id = ?
      ''',
        [
          pass.title,
          pass.kind.name,
          pass.startingBalance,
          pass.currency,
          pass.validFrom?.toUtc().toIso8601String(),
          pass.validUntil?.toUtc().toIso8601String(),
          pass.id,
        ],
      );
    });
  }

  /// Rechecks history inside write transaction; rejects duplicate or overdraw.
  void record(PassEvent event) {
    _transaction(() {
      final ledger = _load(event.passId);
      if (ledger == null) throw StateError('Unknown pass: ${event.passId}');
      ledger.record(event);
      _insertEvent(event);
    });
  }

  void _insertEvent(PassEvent event) =>
      _db.execute('INSERT INTO events VALUES (?, ?, ?, ?, ?, ?, ?)', [
        event.id,
        event.passId,
        event.occurredAt.toUtc().toIso8601String(),
        event.kind.name,
        event.units,
        event.currency,
        event.reversesId,
      ]);

  PassLedger? get(String passId) => _load(passId);

  List<PassLedger> all() => [
    for (final row in _db.select('SELECT id FROM passes ORDER BY id'))
      _load(row['id'] as String)!,
  ];

  PassLedger? _load(String id) {
    final rows = _db.select('SELECT * FROM passes WHERE id = ?', [id]);
    if (rows.isEmpty) return null;
    final row = rows.single;
    final pass = TransitPass(
      id: row['id'] as String,
      title: row['title'] as String,
      kind: PassKind.values.byName(row['kind'] as String),
      startingBalance: row['starting_balance'] as int?,
      currency: row['currency'] as String?,
      validFrom: _date(row['valid_from']),
      validUntil: _date(row['valid_until']),
    );
    final events = [
      for (final item in _db.select(
        'SELECT * FROM events WHERE pass_id = ? ORDER BY rowid',
        [id],
      ))
        PassEvent(
          id: item['id'] as String,
          passId: item['pass_id'] as String,
          occurredAt: DateTime.parse(item['occurred_at'] as String),
          kind: PassEventKind.values.byName(item['kind'] as String),
          units: item['units'] as int?,
          currency: item['currency'] as String?,
          reversesId: item['reverses_id'] as String?,
        ),
    ];
    return PassLedger(pass, events);
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}

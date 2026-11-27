import 'dart:convert';

import 'package:fare_stash/domain/pass_ledger.dart';

final class PassBackup {
  static const _format = 'fare-stash-backup';
  static const _version = 1;

  static String encode(Iterable<PassLedger> history, {DateTime? exportedAt}) {
    final ledgers = List<PassLedger>.unmodifiable(history);
    _validateIds(ledgers);
    return JsonEncoder.withIndent('  ').convert({
      'format': _format,
      'version': _version,
      'exportedAt': (exportedAt ?? DateTime.now()).toUtc().toIso8601String(),
      'passes': [
        for (final ledger in ledgers)
          {
            'id': ledger.pass.id,
            'title': ledger.pass.title,
            'kind': ledger.pass.kind.name,
            'startingBalance': ledger.pass.startingBalance,
            'currency': ledger.pass.currency,
            'validFrom': ledger.pass.validFrom?.toUtc().toIso8601String(),
            'validUntil': ledger.pass.validUntil?.toUtc().toIso8601String(),
            'events': [
              for (final event in ledger.events)
                {
                  'id': event.id,
                  'passId': event.passId,
                  'occurredAt': event.occurredAt.toUtc().toIso8601String(),
                  'kind': event.kind.name,
                  'units': event.units,
                  'currency': event.currency,
                  'reversesId': event.reversesId,
                },
            ],
          },
      ],
    });
  }

  static List<PassLedger> decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw FormatException('Invalid JSON backup: ${error.message}');
    }
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != _format ||
        decoded['version'] != _version) {
      throw const FormatException('Unsupported Fare Stash backup format');
    }
    _readDate(decoded['exportedAt'], 'exportedAt');
    final rawPasses = decoded['passes'];
    if (rawPasses is! List) {
      throw const FormatException('Backup passes must be an array');
    }
    final ledgers = [
      for (var index = 0; index < rawPasses.length; index++)
        _readLedger(rawPasses[index], 'passes[$index]'),
    ];
    _validateIds(ledgers);
    return List<PassLedger>.unmodifiable(ledgers);
  }

  static String toCsv(Iterable<PassLedger> history) {
    final rows = <List<String>>[
      [
        'pass_id',
        'pass_title',
        'event_id',
        'event_kind',
        'occurred_at',
        'units',
        'currency',
        'reverses_id',
      ],
      for (final ledger in history)
        for (final event in ledger.events)
          [
            ledger.pass.id,
            ledger.pass.title,
            event.id,
            event.kind.name,
            event.occurredAt.toUtc().toIso8601String(),
            event.units?.toString() ?? '',
            event.currency ?? '',
            event.reversesId ?? '',
          ],
    ];
    return '${rows.map((row) => row.map(_csvCell).join(',')).join('\r\n')}\r\n';
  }

  static PassLedger _readLedger(Object? value, String field) {
    final map = _readMap(value, field);
    final id = _readString(map['id'], '$field.id');
    final title = _readString(map['title'], '$field.title');
    final kind = _readPassKind(map['kind'], '$field.kind');
    final rawEvents = map['events'];
    if (rawEvents is! List) {
      throw FormatException('$field.events must be an array');
    }

    final TransitPass pass;
    try {
      pass = TransitPass(
        id: id,
        title: title,
        kind: kind,
        startingBalance: _readNullableInt(
          map['startingBalance'],
          '$field.startingBalance',
        ),
        currency: _readNullableString(map['currency'], '$field.currency'),
        validFrom: _readNullableDate(map['validFrom'], '$field.validFrom'),
        validUntil: _readNullableDate(map['validUntil'], '$field.validUntil'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('$field is invalid: $error');
    }

    final events = [
      for (var index = 0; index < rawEvents.length; index++)
        _readEvent(rawEvents[index], '$field.events[$index]'),
    ];
    try {
      return PassLedger(pass, events);
    } on StateError catch (error) {
      throw FormatException('$field history is invalid: $error');
    }
  }

  static PassEvent _readEvent(Object? value, String field) {
    final map = _readMap(value, field);
    try {
      return PassEvent(
        id: _readString(map['id'], '$field.id'),
        passId: _readString(map['passId'], '$field.passId'),
        occurredAt: _readDate(map['occurredAt'], '$field.occurredAt'),
        kind: _readEventKind(map['kind'], '$field.kind'),
        units: _readNullableInt(map['units'], '$field.units'),
        currency: _readNullableString(map['currency'], '$field.currency'),
        reversesId: _readNullableString(map['reversesId'], '$field.reversesId'),
      );
    } on ArgumentError catch (error) {
      throw FormatException('$field is invalid: $error');
    }
  }

  static void _validateIds(Iterable<PassLedger> ledgers) {
    final passIds = <String>{};
    final eventIds = <String>{};
    for (final ledger in ledgers) {
      PassLedger(ledger.pass, ledger.events);
      if (!passIds.add(ledger.pass.id)) {
        throw FormatException('Duplicate pass ID: ${ledger.pass.id}');
      }
      for (final event in ledger.events) {
        if (!eventIds.add(event.id)) {
          throw FormatException('Duplicate event ID: ${event.id}');
        }
      }
    }
  }

  static Map<String, dynamic> _readMap(Object? value, String field) {
    if (value is! Map<String, dynamic>) {
      throw FormatException('$field must be an object');
    }
    return value;
  }

  static String _readString(Object? value, String field) {
    if (value is! String || value.isEmpty || value.trim() != value) {
      throw FormatException('$field must be a nonempty string');
    }
    return value;
  }

  static String? _readNullableString(Object? value, String field) {
    if (value == null) return null;
    if (value is! String) {
      throw FormatException('$field must be a string or null');
    }
    return value;
  }

  static int? _readNullableInt(Object? value, String field) {
    if (value == null) return null;
    if (value is! int) {
      throw FormatException('$field must be an integer or null');
    }
    return value;
  }

  static DateTime _readDate(Object? value, String field) {
    if (value is! String) {
      throw FormatException('$field must be an ISO timestamp');
    }
    try {
      return DateTime.parse(value);
    } on FormatException {
      throw FormatException('$field is not a valid ISO timestamp');
    }
  }

  static DateTime? _readNullableDate(Object? value, String field) =>
      value == null ? null : _readDate(value, field);

  static PassKind _readPassKind(Object? value, String field) {
    if (value is String) {
      for (final kind in PassKind.values) {
        if (kind.name == value) return kind;
      }
    }
    throw FormatException('$field is not a supported pass kind');
  }

  static PassEventKind _readEventKind(Object? value, String field) {
    if (value is String) {
      for (final kind in PassEventKind.values) {
        if (kind.name == value) return kind;
      }
    }
    throw FormatException('$field is not a supported event kind');
  }

  static String _csvCell(String value) {
    if (!value.contains(RegExp('[,"\r\n]'))) return value;
    return '"${value.replaceAll('"', '""')}"';
  }
}

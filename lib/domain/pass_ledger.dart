/// Manual estimates only. Neither a pass nor a ride proves ticket validity.
enum PassKind { ridePack, storedValue, timeLimited }

enum PassEventKind { ride, correction, reversal }

void _requireId(String value, String name) {
  if (value.isEmpty || value.trim() != value) {
    throw ArgumentError.value(value, name, 'must be nonempty and trimmed');
  }
}

/// Validity uses instants: [validFrom, validUntil) in every timezone.
final class TransitPass {
  final String id;
  final String title;
  final PassKind kind;
  final int? startingBalance;
  final String? currency;
  final DateTime? validFrom;
  final DateTime? validUntil;

  TransitPass({
    required this.id,
    required this.title,
    required this.kind,
    this.startingBalance,
    this.currency,
    this.validFrom,
    this.validUntil,
  }) {
    _requireId(id, 'id');
    _requireId(title, 'title');
    if (validFrom != null &&
        validUntil != null &&
        !validFrom!.isBefore(validUntil!)) {
      throw ArgumentError('validUntil must follow validFrom');
    }
    switch (kind) {
      case PassKind.ridePack:
        if (startingBalance == null ||
            startingBalance! <= 0 ||
            currency != null) {
          throw ArgumentError(
            'ride pack needs positive ride count, no currency',
          );
        }
      case PassKind.storedValue:
        if (startingBalance == null ||
            startingBalance! < 0 ||
            currency == null ||
            !RegExp(r'^[A-Z]{3}$').hasMatch(currency!)) {
          throw ArgumentError(
            'stored value needs nonnegative minor units and ISO currency',
          );
        }
      case PassKind.timeLimited:
        if (startingBalance != null ||
            currency != null ||
            validFrom == null ||
            validUntil == null) {
          throw ArgumentError('time pass needs validity window, no balance');
        }
    }
  }

  bool validAt(DateTime instant) =>
      (validFrom == null || !instant.isBefore(validFrom!)) &&
      (validUntil == null || instant.isBefore(validUntil!));
}

/// A correction changes units; a reversal cancels one prior ride/correction.
/// Neither operation edits or deletes historical events.
final class PassEvent {
  final String id;
  final String passId;
  final DateTime occurredAt;
  final PassEventKind kind;
  final int? units;
  final String? currency;
  final String? reversesId;

  PassEvent({
    required this.id,
    required this.passId,
    required this.occurredAt,
    required this.kind,
    this.units,
    this.currency,
    this.reversesId,
  }) {
    _requireId(id, 'id');
    _requireId(passId, 'passId');
    if (kind == PassEventKind.reversal) {
      if (reversesId == null || units != null || currency != null) {
        throw ArgumentError(
          'reversal needs target ID and no units or currency',
        );
      }
      _requireId(reversesId!, 'reversesId');
    } else {
      if (reversesId != null ||
          units == null ||
          (kind == PassEventKind.ride && units! < 0) ||
          (kind == PassEventKind.correction && units == 0)) {
        throw ArgumentError(
          'ride needs nonnegative units; correction needs nonzero units',
        );
      }
    }
  }
}

/// Replays append-only events in recording order. No cached mutable balance.
final class PassLedger {
  final TransitPass pass;
  final List<PassEvent> events;
  final int? balance;
  final int rideCount;

  PassLedger(TransitPass pass, Iterable<PassEvent> history)
    : this._replay(pass, List<PassEvent>.unmodifiable(history));

  PassLedger._replay(this.pass, this.events)
    : balance = _balance(pass, events),
      rideCount = _rideCount(events);

  static int? _balance(TransitPass pass, List<PassEvent> events) {
    var balance = pass.startingBalance;
    final seen = <String, (PassEvent, int)>{};
    final reversed = <String>{};
    for (final event in events) {
      if (event.passId != pass.id || seen.containsKey(event.id)) {
        throw StateError('foreign pass or duplicate event ID: ${event.id}');
      }
      int delta;
      if (event.kind == PassEventKind.reversal) {
        final target = seen[event.reversesId];
        if (target == null ||
            target.$1.kind == PassEventKind.reversal ||
            !reversed.add(event.reversesId!)) {
          throw StateError(
            'missing or already reversed event: ${event.reversesId}',
          );
        }
        delta = -target.$2;
      } else {
        if (event.currency != pass.currency) {
          throw StateError('currency mismatch: ${event.id}');
        }
        if (event.kind == PassEventKind.ride) {
          if (!pass.validAt(event.occurredAt)) {
            throw StateError('ride outside validity window: ${event.id}');
          }
          if ((pass.kind == PassKind.ridePack && event.units != 1) ||
              (pass.kind == PassKind.storedValue && event.units! <= 0) ||
              (pass.kind == PassKind.timeLimited && event.units != 0)) {
            throw StateError('invalid ride deduction: ${event.id}');
          }
          delta = -event.units!;
        } else {
          if (pass.kind == PassKind.timeLimited) {
            throw StateError('time pass cannot adjust balance');
          }
          delta = event.units!;
        }
      }
      if (balance != null) {
        balance += delta;
        if (balance < 0) throw StateError('insufficient balance: ${event.id}');
      }
      seen[event.id] = (event, delta);
    }
    return balance;
  }

  static int _rideCount(List<PassEvent> events) {
    final reversed = <String>{
      for (final e in events)
        if (e.kind == PassEventKind.reversal) e.reversesId!,
    };
    return events
        .where((e) => e.kind == PassEventKind.ride && !reversed.contains(e.id))
        .length;
  }

  PassLedger record(PassEvent event) => PassLedger(pass, [...events, event]);
}

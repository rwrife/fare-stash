import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Pass construction', () {
    test('ride pack requires positive ride count without currency', () {
      expect(
        () => TransitPass(
          id: 'p1',
          title: '10 Ride',
          kind: PassKind.ridePack,
          startingBalance: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransitPass(
          id: 'p1',
          title: '10 Ride',
          kind: PassKind.ridePack,
          startingBalance: 10,
          currency: 'USD',
        ),
        throwsArgumentError,
      );
      final p = TransitPass(
        id: 'p1',
        title: '10 Ride',
        kind: PassKind.ridePack,
        startingBalance: 10,
      );
      expect(p.startingBalance, 10);
      expect(p.currency, isNull);
    });

    test('stored value requires non-negative minor units and ISO currency', () {
      expect(
        () => TransitPass(
          id: 'sv1',
          title: 'Metrocard',
          kind: PassKind.storedValue,
          startingBalance: -100,
          currency: 'USD',
        ),
        throwsArgumentError,
      );
      expect(
        () => TransitPass(
          id: 'sv1',
          title: 'Metrocard',
          kind: PassKind.storedValue,
          startingBalance: 2000,
          currency: 'dollars',
        ),
        throwsArgumentError,
      );
      final p = TransitPass(
        id: 'sv1',
        title: 'Metrocard',
        kind: PassKind.storedValue,
        startingBalance: 2000,
        currency: 'USD',
      );
      expect(p.startingBalance, 2000);
      expect(p.currency, 'USD');
    });

    test('time-limited pass requires validity window and no balance', () {
      final now = DateTime.utc(2026, 11, 1);
      final later = DateTime.utc(2026, 11, 30);
      expect(
        () => TransitPass(
          id: 't1',
          title: 'Monthly',
          kind: PassKind.timeLimited,
          startingBalance: 10,
          validFrom: now,
          validUntil: later,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransitPass(
          id: 't1',
          title: 'Monthly',
          kind: PassKind.timeLimited,
          validFrom: later,
          validUntil: now,
        ),
        throwsArgumentError,
      );
      final p = TransitPass(
        id: 't1',
        title: 'Monthly',
        kind: PassKind.timeLimited,
        validFrom: now,
        validUntil: later,
      );
      expect(p.startingBalance, isNull);
    });
  });

  group('PassLedger replays and state transitions', () {
    final start = DateTime.utc(2026, 11, 1, 0, 0, 0);
    final end = DateTime.utc(2026, 11, 10, 0, 0, 0);

    test('stored-value deductions and corrections update balance', () {
      final pass = TransitPass(
        id: 'sv',
        title: 'Oyster',
        kind: PassKind.storedValue,
        startingBalance: 500, // $5.00
        currency: 'GBP',
        validFrom: start,
        validUntil: end,
      );
      final ledger0 = PassLedger(pass, const []);
      expect(ledger0.balance, 500);
      expect(ledger0.rideCount, 0);

      // Ride deducts 240
      final r1 = PassEvent(
        id: 'e1',
        passId: 'sv',
        occurredAt: DateTime.utc(2026, 11, 2, 8, 30),
        kind: PassEventKind.ride,
        units: 240,
        currency: 'GBP',
      );
      final ledger1 = ledger0.record(r1);
      expect(ledger1.balance, 260);
      expect(ledger1.rideCount, 1);

      // Manual correction adds 50
      final c1 = PassEvent(
        id: 'e2',
        passId: 'sv',
        occurredAt: DateTime.utc(2026, 11, 2, 9, 0),
        kind: PassEventKind.correction,
        units: 50,
        currency: 'GBP',
      );
      final ledger2 = ledger1.record(c1);
      expect(ledger2.balance, 310);
      expect(ledger2.rideCount, 1);
    });

    test('reversal cancels prior ride deduction without deleting event', () {
      final pass = TransitPass(
        id: 'rp',
        title: '10 Ride',
        kind: PassKind.ridePack,
        startingBalance: 2,
      );
      final r1 = PassEvent(
        id: 'r1',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 2),
        kind: PassEventKind.ride,
        units: 1,
      );
      final rev = PassEvent(
        id: 'rev1',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 3),
        kind: PassEventKind.reversal,
        reversesId: 'r1',
      );

      final l1 = PassLedger(pass, [r1]);
      expect(l1.balance, 1);
      expect(l1.rideCount, 1);

      final l2 = l1.record(rev);
      expect(l2.balance, 2);
      expect(l2.rideCount, 0);
    });

    test('insufficient balance throws StateError', () {
      final pass = TransitPass(
        id: 'rp',
        title: 'Single Ride',
        kind: PassKind.ridePack,
        startingBalance: 1,
      );
      final r1 = PassEvent(
        id: 'r1',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 2),
        kind: PassEventKind.ride,
        units: 1,
      );
      final r2 = PassEvent(
        id: 'r2',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 3),
        kind: PassEventKind.ride,
        units: 1,
      );
      final l1 = PassLedger(pass, [r1]);
      expect(() => l1.record(r2), throwsStateError);
    });

    test('currency mismatch throws StateError', () {
      final pass = TransitPass(
        id: 'sv',
        title: 'Clipper',
        kind: PassKind.storedValue,
        startingBalance: 1000,
        currency: 'USD',
      );
      final r = PassEvent(
        id: 'r1',
        passId: 'sv',
        occurredAt: DateTime.utc(2026, 11, 2),
        kind: PassEventKind.ride,
        units: 250,
        currency: 'EUR',
      );
      expect(() => PassLedger(pass, [r]), throwsStateError);
    });

    test('expiry boundary rejects rides outside [validFrom, validUntil)', () {
      final pass = TransitPass(
        id: 't',
        title: 'Window',
        kind: PassKind.timeLimited,
        validFrom: DateTime.utc(2026, 11, 2, 10, 0),
        validUntil: DateTime.utc(2026, 11, 2, 18, 0),
      );
      // Valid at start boundary
      final atStart = PassEvent(
        id: 'r0',
        passId: 't',
        occurredAt: DateTime.utc(2026, 11, 2, 10, 0),
        kind: PassEventKind.ride,
        units: 0,
      );
      expect(PassLedger(pass, [atStart]).rideCount, 1);

      // Invalid at exact end boundary
      final atEnd = PassEvent(
        id: 'r1',
        passId: 't',
        occurredAt: DateTime.utc(2026, 11, 2, 18, 0),
        kind: PassEventKind.ride,
        units: 0,
      );
      expect(() => PassLedger(pass, [atEnd]), throwsStateError);

      // Invalid before start
      final before = PassEvent(
        id: 'r2',
        passId: 't',
        occurredAt: DateTime.utc(2026, 11, 2, 9, 59),
        kind: PassEventKind.ride,
        units: 0,
      );
      expect(() => PassLedger(pass, [before]), throwsStateError);
    });

    test('timezone offsets evaluate identically by instant', () {
      final pass = TransitPass(
        id: 't',
        title: 'Window',
        kind: PassKind.timeLimited,
        validFrom: DateTime.parse('2026-11-02T10:00:00Z'),
        validUntil: DateTime.parse('2026-11-02T18:00:00Z'),
      );
      // 14:00+04:00 is 10:00 UTC (valid start)
      final localStart = DateTime.parse('2026-11-02T14:00:00+04:00');
      expect(pass.validAt(localStart), isTrue);

      // 22:00+04:00 is 18:00 UTC (expired end boundary)
      final localEnd = DateTime.parse('2026-11-02T22:00:00+04:00');
      expect(pass.validAt(localEnd), isFalse);
    });

    test('duplicate event IDs throw StateError', () {
      final pass = TransitPass(
        id: 'rp',
        title: '10 Ride',
        kind: PassKind.ridePack,
        startingBalance: 10,
      );
      final r1 = PassEvent(
        id: 'dup',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 2),
        kind: PassEventKind.ride,
        units: 1,
      );
      final r2 = PassEvent(
        id: 'dup',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 3),
        kind: PassEventKind.ride,
        units: 1,
      );
      expect(() => PassLedger(pass, [r1, r2]), throwsStateError);
    });

    test('invalid input, foreign pass, and nonexistent reversal fail', () {
      final pass = TransitPass(
        id: 'rp',
        title: 'Rides',
        kind: PassKind.ridePack,
        startingBalance: 2,
      );
      expect(
        () => TransitPass(
          id: ' ',
          title: 'Rides',
          kind: PassKind.ridePack,
          startingBalance: 2,
        ),
        throwsArgumentError,
      );
      expect(
        () => PassEvent(
          id: 'bad',
          passId: 'rp',
          occurredAt: start,
          kind: PassEventKind.ride,
          units: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => PassEvent(
          id: 'bad',
          passId: 'rp',
          occurredAt: start,
          kind: PassEventKind.correction,
          units: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => PassLedger(pass, [
          PassEvent(
            id: 'e',
            passId: 'other',
            occurredAt: start,
            kind: PassEventKind.ride,
            units: 1,
          ),
        ]),
        throwsStateError,
      );
      expect(
        () => PassLedger(pass, [
          PassEvent(
            id: 'rev',
            passId: 'rp',
            occurredAt: start,
            kind: PassEventKind.reversal,
            reversesId: 'missing',
          ),
        ]),
        throwsStateError,
      );
    });

    test('correction reversal and replayed snapshot stay independent', () {
      final pass = TransitPass(
        id: 'rp',
        title: 'Rides',
        kind: PassKind.ridePack,
        startingBalance: 2,
      );
      final correction = PassEvent(
        id: 'c',
        passId: 'rp',
        occurredAt: start,
        kind: PassEventKind.correction,
        units: 3,
      );
      final source = [correction];
      final before = PassLedger(pass, source);
      source.clear();
      expect(before.events, hasLength(1));
      expect(() => before.events.clear(), throwsUnsupportedError);
      final after = before.record(
        PassEvent(
          id: 'undo',
          passId: 'rp',
          occurredAt: end,
          kind: PassEventKind.reversal,
          reversesId: 'c',
        ),
      );
      expect(before.balance, 5);
      expect(after.balance, 2);
      expect(after.events, hasLength(2));
    });

    test('double reversal of same event throws StateError', () {
      final pass = TransitPass(
        id: 'rp',
        title: '10 Ride',
        kind: PassKind.ridePack,
        startingBalance: 10,
      );
      final r1 = PassEvent(
        id: 'r1',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 2),
        kind: PassEventKind.ride,
        units: 1,
      );
      final rev1 = PassEvent(
        id: 'rev1',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 3),
        kind: PassEventKind.reversal,
        reversesId: 'r1',
      );
      final rev2 = PassEvent(
        id: 'rev2',
        passId: 'rp',
        occurredAt: DateTime.utc(2026, 11, 4),
        kind: PassEventKind.reversal,
        reversesId: 'r1',
      );
      expect(() => PassLedger(pass, [r1, rev1, rev2]), throwsStateError);
    });
  });
}

import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:fare_stash/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders disclaimer and empty state', (tester) async {
    final store = PassStore.memory();
    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Manual estimates only — not proof of a valid ticket.'),
      findsOneWidget,
    );
    expect(find.text('No passes yet'), findsOneWidget);
    store.close();
  });

  testWidgets('creates ride pack, logs ride, reverses ride', (tester) async {
    final store = PassStore.memory();
    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();

    // Open add pass dialog
    await tester.tap(find.text('Add pass'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Pass name'),
      'Metro 10-Ride',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Starting rides'),
      '10',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Metro 10-Ride'), findsOneWidget);
    expect(
      find.text('ridePack · 10 rides left · 0 rides logged'),
      findsOneWidget,
    );
    expect(find.text('Estimated active'), findsOneWidget);

    // Log ride with 1 deduction
    await tester.tap(find.text('Log ride on Metro 10-Ride'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('ridePack · 9 rides left · 1 rides logged'),
      findsOneWidget,
    );

    // Reverse ride
    await tester.tap(find.textContaining('Reverse ').first);
    await tester.pumpAndSettle();
    expect(
      find.text('ridePack · 10 rides left · 0 rides logged'),
      findsOneWidget,
    );

    store.close();
  });

  testWidgets('stored value deducts integer minor units and edits title', (
    tester,
  ) async {
    final store = PassStore.memory();
    store.save(
      TransitPass(
        id: 'credit',
        title: 'Credit',
        kind: PassKind.storedValue,
        startingBalance: 125,
        currency: 'USD',
      ),
      [],
    );
    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log ride on Credit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Fare in minor units'),
      '25',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      find.text('storedValue · 100 USD left · 1 rides logged'),
      findsOneWidget,
    );
    await tester.tap(find.text('Edit Credit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pass name'),
      'Renamed',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.get('credit')!.pass.title, 'Renamed');
    expect(store.get('credit')!.balance, 100);
    store.close();
  });

  testWidgets('time pass needs dates and logs zero-deduction ride', (
    tester,
  ) async {
    final store = PassStore.memory();
    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add pass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('○ timeLimited'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Pass name'),
      'Weekly',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Valid from (ISO date/time)'),
      '2020-01-01',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Valid until (ISO date/time)'),
      '2030-01-01',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log ride on Weekly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.get(store.all().single.pass.id)!.rideCount, 1);
    expect(store.all().single.balance, isNull);
    store.close();
  });

  testWidgets('blocks overdraw ride on depleted pass', (tester) async {
    final store = PassStore.memory();
    final pass = TransitPass(
      id: 'p1',
      title: 'Last Ticket',
      kind: PassKind.ridePack,
      startingBalance: 1,
    );
    store.save(pass, [
      PassEvent(
        id: 'e1',
        passId: 'p1',
        occurredAt: DateTime.now().subtract(const Duration(minutes: 5)),
        kind: PassEventKind.ride,
        units: 1,
      ),
    ]);

    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.android),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('ridePack · 0 rides left · 1 rides logged'),
      findsOneWidget,
    );
    expect(find.text('Expired or depleted (estimate)'), findsOneWidget);

    await tester.tap(find.text('Log ride on Last Ticket'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form-error')), findsOneWidget);
    store.close();
  });

  testWidgets('iOS uses Cupertino shell and dialogs', (tester) async {
    final store = PassStore.memory();
    await tester.pumpWidget(
      FareStashApp(store: store, platformOverride: TargetPlatform.iOS),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoApp), findsOneWidget);
    await tester.tap(find.text('Add pass'));
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);

    store.close();
  });
}

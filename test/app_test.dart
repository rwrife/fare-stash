import 'package:fare_stash/main.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Android uses Material shell', (tester) async {
    await tester.pumpWidget(
      const FareStashApp(platformOverride: TargetPlatform.android),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(
      find.text('Fare Stash — local transit pass journal'),
      findsOneWidget,
    );
  });

  testWidgets('iOS uses Cupertino shell', (tester) async {
    await tester.pumpWidget(
      const FareStashApp(platformOverride: TargetPlatform.iOS),
    );
    expect(find.byType(CupertinoApp), findsOneWidget);
    expect(
      find.text('Fare Stash — local transit pass journal'),
      findsOneWidget,
    );
  });
}

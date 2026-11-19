import 'dart:io';
import 'dart:ui' as ui;

import 'package:fare_stash/data/pass_store.dart';
import 'package:fare_stash/domain/pass_ledger.dart';
import 'package:fare_stash/main.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

PassStore seededStore() {
  final store = PassStore.memory();
  store.save(
    TransitPass(
      id: 'metro',
      title: 'Metro pass',
      kind: PassKind.ridePack,
      startingBalance: 10,
    ),
    [
      PassEvent(
        id: 'ride-1',
        passId: 'metro',
        occurredAt: DateTime(2026, 1, 2, 9),
        kind: PassEventKind.ride,
        units: 1,
      ),
    ],
  );
  return store;
}

Future<void> showApp(
  WidgetTester tester,
  PassStore store,
  TargetPlatform platform,
  Size size, {
  bool accessible = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.platformDispatcher.textScaleFactorTestValue = accessible ? 2 : 1;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      FakeAccessibilityFeatures(highContrast: accessible);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('screenshot'),
      child: FareStashApp(store: store, platformOverride: platform),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() {
    TestWidgetsFlutterBinding.instance.platformDispatcher
      ..clearTextScaleFactorTestValue()
      ..clearAccessibilityFeaturesTestValue();
  });

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.windows,
  ]) {
    for (final size in [
      const Size(390, 844),
      const Size(768, 1024),
      const Size(1440, 900),
    ]) {
      testWidgets('${platform.name} renders at $size', (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = seededStore();
        addTearDown(store.close);
        await showApp(tester, store, platform, size);
        expect(tester.takeException(), isNull);
        expect(find.text('Your passes'), findsOneWidget);
        expect(find.text('Metro pass'), findsAtLeastNWidgets(1));
        expect(
          find.byType(CupertinoPageScaffold),
          platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(Scaffold),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(fluent.NavigationView),
          platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
        );
        if (platform == TargetPlatform.iOS) {
          expect(find.byType(Material), findsNothing);
        } else {
          expect(find.byType(CupertinoButton), findsNothing);
        }
        if (size.width >= 900) {
          final passes = tester.getRect(
            find.byKey(const PageStorageKey('passes')),
          );
          final history = tester.getRect(
            find.byKey(const PageStorageKey('history-all')),
          );
          expect(passes.right, lessThanOrEqualTo(history.left));
          expect(history.width, greaterThan(300));
          expect(find.text('Ride history'), findsOneWidget);
        }

        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const Key('screenshot')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final pixels = (await image.toByteData())!.buffer.asUint8List();
          expect(image.width, size.width.toInt());
          expect(image.height, size.height.toInt());
          // A rendered, opaque workspace with text/control contrast, not an
          // empty surface or a transparent screenshot.
          final colors = <int>{};
          var opaque = true;
          for (var i = 0; i < pixels.length; i += 4) {
            opaque = opaque && pixels[i + 3] == 255;
            colors.add(
              (pixels[i] << 16) | (pixels[i + 1] << 8) | pixels[i + 2],
            );
          }
          expect(opaque, isTrue);
          expect(colors.length, greaterThan(10));
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(
            'build/adaptive-screenshots/${platform.name}-${size.width.toInt()}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(png.buffer.asUint8List());
          image.dispose();
        });
      });
    }

    testWidgets('${platform.name} large text, labels and native forms', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final semantics = tester.ensureSemantics();
      try {
        final store = seededStore();
        addTearDown(store.close);
        await showApp(
          tester,
          store,
          platform,
          const Size(390, 844),
          accessible: true,
        );
        expect(tester.takeException(), isNull);
        expect(find.bySemanticsLabel('Add pass'), findsOneWidget);
        expect(find.bySemanticsLabel('Your passes'), findsOneWidget);
        final context = tester.element(find.text('Your passes'));
        expect(MediaQuery.highContrastOf(context), isTrue);
        Color foreground;
        Color background;
        if (platform == TargetPlatform.windows) {
          final theme = fluent.FluentTheme.of(context);
          foreground = theme.typography.body!.color!;
          background = theme.cardColor;
        } else if (platform == TargetPlatform.iOS) {
          foreground = CupertinoDynamicColor.resolve(
            CupertinoColors.label,
            context,
          );
          background = CupertinoDynamicColor.resolve(
            CupertinoColors.secondarySystemGroupedBackground,
            context,
          );
        } else {
          final scheme = Theme.of(context).colorScheme;
          foreground = scheme.onSurface;
          background = scheme.surface;
        }
        final light = foreground.computeLuminance();
        final dark = background.computeLuminance();
        final contrast = light > dark
            ? (light + 0.05) / (dark + 0.05)
            : (dark + 0.05) / (light + 0.05);
        expect(contrast, greaterThanOrEqualTo(7));
        await tester.tap(find.text('Add pass'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.byType(CupertinoAlertDialog),
          platform == TargetPlatform.iOS ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(AlertDialog),
          platform == TargetPlatform.android ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(fluent.ContentDialog),
          platform == TargetPlatform.windows ? findsOneWidget : findsNothing,
        );
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets('${platform.name} switches between passes and history', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = seededStore();
      addTearDown(store.close);
      await showApp(tester, store, platform, const Size(390, 844));
      if (platform == TargetPlatform.windows) {
        await tester.tap(find.byIcon(fluent.FluentIcons.history));
      } else {
        await tester.tap(find.text('History'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Ride history'), findsOneWidget);
      expect(find.text('Reverse ride-1'), findsOneWidget);
      expect(find.text('Your passes'), findsNothing);
      if (platform == TargetPlatform.windows) {
        await tester.tap(find.byIcon(fluent.FluentIcons.ticket));
      } else {
        await tester.tap(find.text('Passes'));
      }
      await tester.pumpAndSettle();
      expect(find.text('Your passes'), findsOneWidget);
      expect(store.get('metro')!.rideCount, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'Windows keeps desktop navigation while resizing and supports keys',
    (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = seededStore();
      addTearDown(store.close);
      await showApp(
        tester,
        store,
        TargetPlatform.windows,
        const Size(1440, 900),
      );
      expect(find.byKey(const Key('split-workspace')), findsOneWidget);
      await tester.binding.setSurfaceSize(const Size(520, 800));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('split-workspace')), findsNothing);
      expect(find.byType(fluent.NavigationView), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(CupertinoSlidingSegmentedControl<int>), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(find.byType(fluent.ContentDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final beforeTab = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      expect(FocusManager.instance.primaryFocus, isNot(same(beforeTab)));
      final addFocus = Focus.of(tester.element(find.text('Add pass')));
      for (var i = 0; i < 20 && !addFocus.hasFocus; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      }
      expect(addFocus.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.byType(fluent.ContentDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(find.text('Add pass')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await mouse.removePointer();

      await tester.binding.setSurfaceSize(const Size(1440, 900));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('split-workspace')), findsOneWidget);
      expect(find.text('ride · 2026-01-02 09:00:00.000 · 1'), findsOneWidget);
    },
  );

  testWidgets('iOS history supports edge-swipe back and reversal', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = seededStore();
    addTearDown(store.close);
    await showApp(tester, store, TargetPlatform.iOS, const Size(390, 844));
    await tester.tap(find.text('History for Metro pass'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reverse ride-1'));
    await tester.pumpAndSettle();
    expect(store.get('metro')!.rideCount, 0);
    expect(find.text('Reverse ride-1'), findsNothing);
    await tester.dragFrom(const Offset(1, 400), const Offset(350, 0));
    await tester.pumpAndSettle();
    expect(find.text('Your passes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android history responds to system back', (tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = seededStore();
    addTearDown(store.close);
    await showApp(tester, store, TargetPlatform.android, const Size(390, 844));
    await tester.tap(find.text('History for Metro pass'));
    await tester.pumpAndSettle();
    expect(find.text('Reverse ride-1'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Your passes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

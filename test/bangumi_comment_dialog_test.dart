import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/models/bangumi_collection_submit_result.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_comment_dialog.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(
    WidgetTester tester,
    AppDisplaySurface surface, {
    int collectionType = 3,
    double textScale = 1,
    Brightness brightness = Brightness.light,
    required Future<void> Function(BangumiCollectionSubmitResult) onSubmit,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = surface == AppDisplaySurface.phone
        ? const Size(360, 780)
        : const Size(900, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
        ChangeNotifierProvider(create: (_) => BottomBarProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(brightness: brightness),
        builder: (context, child) => AppDisplaySurfaceScope(
          surface: surface,
          child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
        ),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => BangumiCommentDialog.show(
                          context: context,
                          animeTitle: '测试番剧',
                          initialRating: 8,
                          initialComment: '原有短评',
                          collectionType: collectionType,
                          onSubmit: onSubmit),
                      child: const Text('打开短评'),
                    ))),
      ),
    ));
    await tester.tap(find.text('打开短评'));
    await tester.pumpAndSettle();
  }

  for (final surface in [
    AppDisplaySurface.desktopTablet,
    AppDisplaySurface.phone
  ]) {
    testWidgets(
        '$surface short comment defaults to watched and preserves comment/rating',
        (tester) async {
      BangumiCollectionSubmitResult? result;
      await open(tester, surface, onSubmit: (value) async => result = value);
      if (surface == AppDisplaySurface.phone) {
        expect(
            tester
                .widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox))
                .value,
            isTrue);
      } else {
        expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .value,
            isTrue);
      }
      await tester.ensureVisible(find.text('确定'));
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result!.collectionType, 2);
      expect(result!.markAsWatched, isTrue);
      expect(result!.rating, 8);
      expect(result!.comment, '原有短评');
      expect(find.text('将状态改为[已看]'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final originalType in [2, 5]) {
      testWidgets(
          '$surface unchecking preserves original collection type $originalType',
          (tester) async {
        BangumiCollectionSubmitResult? result;
        await open(tester, surface,
            collectionType: originalType,
            onSubmit: (value) async => result = value);
        await tester.ensureVisible(find.text('将状态改为[已看]'));
        await tester.tap(find.text('将状态改为[已看]'));
        await tester.pump();
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();
        expect(result!.collectionType, originalType);
        expect(result!.markAsWatched, isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets(
        '$surface already watched remains watched with the option checked',
        (tester) async {
      BangumiCollectionSubmitResult? result;
      await open(tester, surface,
          collectionType: 2, onSubmit: (value) async => result = value);
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(result!.collectionType, 2);
    });

    testWidgets(
        '$surface pending submission disables checkbox and failure allows retry',
        (tester) async {
      final pending = Completer<void>();
      var calls = 0;
      BangumiCollectionSubmitResult? result;
      await open(tester, surface, onSubmit: (value) {
        calls++;
        result = value;
        return calls == 1 ? pending.future : Future<void>.value();
      });
      await tester.tap(find.text('确定'));
      await tester.pump();
      if (surface == AppDisplaySurface.phone) {
        expect(
            tester
                .widget<CupertinoCheckbox>(find.byType(CupertinoCheckbox))
                .onChanged,
            isNull);
      } else {
        expect(
            tester
                .widget<CheckboxListTile>(find.byType(CheckboxListTile))
                .onChanged,
            isNull);
      }
      pending.completeError(StateError('submission failed'));
      await tester.pumpAndSettle();
      expect(find.text('将状态改为[已看]'), findsOneWidget);
      await tester.ensureVisible(find.text('将状态改为[已看]'));
      await tester.tap(find.text('将状态改为[已看]'));
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(result!.collectionType, 3);
    });

    for (final brightness in Brightness.values) {
      testWidgets('$surface watched option fits scaled text in $brightness',
          (tester) async {
        var calls = 0;
        await open(tester, surface, textScale: 1.3, brightness: brightness,
            onSubmit: (_) async {
          calls++;
        });
        await tester.ensureVisible(find.text('将状态改为[已看]'));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(calls, 0);
      });
    }
  }
}

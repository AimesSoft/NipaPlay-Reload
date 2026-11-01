import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/app/app_size_class_scope.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/utils/cupertino_glass_navigation_insets.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_actions.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_vertical_glass_tab_bar.dart';
import 'package:nipaplay/utils/system_window_traits.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Values reported by the iPhone Duo simulator (iOS 27.1).
const _outerWindow = Size(466, 678);
const _outerPadding = EdgeInsets.only(right: 84, bottom: 34);
const _outerCamera = Rect.fromLTWH(399.67, 29.33, 37, 37);
const _outerStatusColumn = Rect.fromLTWH(382, 0, 84, 174);
const _innerLandscapeWindow = Size(951, 669);
const _innerLandscapeStatusColumn = Rect.fromLTWH(867, 0, 84, 124);

List<double> _frame(Rect rect) =>
    [rect.left, rect.top, rect.width, rect.height];

void main() {
  group('SystemWindowTraits', () {
    test('places bars on the right of the iPhone Duo outer display', () {
      final traits = SystemWindowTraits.fromPlatform({
        'verticalBarEdge': 2,
        'isRightToLeft': false,
        'occlusions': [_frame(_outerCamera), _frame(_outerStatusColumn)],
        'horizontalSizeClass': 1,
      });

      expect(traits.navigationPlacement, PhoneNavigationPlacement.right);
      expect(traits.occlusions, [_outerCamera, _outerStatusColumn]);
      expect(traits.isRegularWidth, isFalse);
    });

    test('keeps bars at the bottom on other iPhones and unknown replies', () {
      expect(
        SystemWindowTraits.fromPlatform(null).navigationPlacement,
        PhoneNavigationPlacement.bottom,
      );
      expect(
        SystemWindowTraits.fromPlatform(const {
          'verticalBarEdge': 0,
          'horizontalSizeClass': 1,
        }),
        const SystemWindowTraits(
          horizontalSizeClass: SystemSizeClass.compact,
        ),
      );
      expect(
        SystemWindowTraits.fromPlatform(const {
          'verticalBarEdge': 'trailing',
          'occlusions': [
            [1, 2],
            'frame',
          ],
          'horizontalSizeClass': 7,
        }),
        const SystemWindowTraits(),
      );
    });

    test('reports the inner display as regular width', () {
      final traits = SystemWindowTraits.fromPlatform(const {
        'verticalBarEdge': 0,
        'horizontalSizeClass': 2,
      });

      expect(traits.isRegularWidth, isTrue);
      expect(traits.navigationPlacement, PhoneNavigationPlacement.bottom);
    });

    test('resolves leading and trailing with the UIKit layout direction', () {
      PhoneNavigationPlacement resolve(
        SystemVerticalBarEdge edge, {
        required bool rtl,
      }) =>
          resolvePhoneNavigationPlacement(edge: edge, isRightToLeft: rtl);

      expect(
        resolve(SystemVerticalBarEdge.trailing, rtl: false),
        PhoneNavigationPlacement.right,
      );
      expect(
        resolve(SystemVerticalBarEdge.leading, rtl: false),
        PhoneNavigationPlacement.left,
      );
      expect(
        resolve(SystemVerticalBarEdge.trailing, rtl: true),
        PhoneNavigationPlacement.left,
      );
      expect(
        resolve(SystemVerticalBarEdge.leading, rtl: true),
        PhoneNavigationPlacement.right,
      );
      expect(
        resolve(SystemVerticalBarEdge.unspecified, rtl: true),
        PhoneNavigationPlacement.bottom,
      );
    });
  });

  group('SystemWindowTraitsObserver', () {
    const channel = MethodChannel('test/window_traits');

    testWidgets('re-reads traits when the window changes and once it settles',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var reply = <String, Object>{'verticalBarEdge': 2};
      final methods = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          methods.add(call.method);
          return reply;
        },
      );
      final observer = SystemWindowTraitsObserver(
        channel: channel,
        settleDelay: const Duration(milliseconds: 100),
      );
      addTearDown(() {
        WidgetsBinding.instance.removeObserver(observer);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      observer.ensureStarted();
      await tester.pump();
      expect(methods, ['getWindowTraits']);
      expect(
        observer.traits.value.navigationPlacement,
        PhoneNavigationPlacement.right,
      );

      reply = {'verticalBarEdge': 0, 'horizontalSizeClass': 2};
      observer.didChangeMetrics();
      await tester.pump();
      expect(methods, hasLength(2));
      expect(observer.traits.value.isRegularWidth, isTrue);

      reply = {
        'verticalBarEdge': 2,
        'occlusions': [_frame(_innerLandscapeStatusColumn)],
        'horizontalSizeClass': 2,
      };
      await tester.pump(const Duration(milliseconds: 100));
      expect(methods, hasLength(3));
      expect(observer.traits.value.occlusions, [_innerLandscapeStatusColumn]);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('stays idle outside iOS', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var calls = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async {
          calls++;
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final observer = SystemWindowTraitsObserver(channel: channel);

      observer.ensureStarted();
      await tester.pump();

      expect(calls, 0);
      expect(observer.traits.value, const SystemWindowTraits());
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('resolveSideNavigationLayout', () {
    test('keeps the bottom bar when the system has no vertical bar', () {
      expect(
        resolveSideNavigationLayout(
          placement: PhoneNavigationPlacement.bottom,
          windowSize: const Size(402, 874),
          viewPadding: const EdgeInsets.only(top: 62, bottom: 34),
          occlusions: const [],
          barWidth: cupertinoVerticalGlassTabBarWidth,
        ),
        isNull,
      );
    });

    test('fills the outer display status column under the camera', () {
      final layout = resolveSideNavigationLayout(
        placement: PhoneNavigationPlacement.right,
        windowSize: _outerWindow,
        viewPadding: _outerPadding,
        occlusions: const [_outerCamera, _outerStatusColumn],
        barWidth: cupertinoVerticalGlassTabBarWidth,
      )!;

      expect(layout.columnWidth, 84);
      expect(layout.contentPadding, const EdgeInsets.only(right: 84));
      // Controls line up with the camera, not the middle of the column.
      expect(
        layout.controlsCenterOffset,
        closeTo(_outerWindow.width - _outerCamera.center.dx, 0.01),
      );
      expect(layout.pageActionsTop, 178);
      expect(layout.tabBarBottom, 40);
      expect(
        layout.edgeOffsetFor(cupertinoVerticalGlassTabBarWidth),
        closeTo(19.83, 0.01),
      );
    });

    test('centers the controls in the inner display column', () {
      final layout = resolveSideNavigationLayout(
        placement: PhoneNavigationPlacement.right,
        windowSize: _innerLandscapeWindow,
        viewPadding: _outerPadding,
        occlusions: const [_innerLandscapeStatusColumn],
        barWidth: cupertinoVerticalGlassTabBarWidth,
      )!;

      expect(layout.controlsCenterOffset, 42);
      expect(layout.pageActionsTop, 128);
    });

    test('mirrors the column for a left-hand Split View app', () {
      final layout = resolveSideNavigationLayout(
        placement: PhoneNavigationPlacement.left,
        windowSize: const Size(475, 669),
        viewPadding: const EdgeInsets.only(left: 84, bottom: 34),
        occlusions: const [],
        barWidth: cupertinoVerticalGlassTabBarWidth,
      )!;

      expect(layout.isLeft, isTrue);
      expect(layout.contentPadding, const EdgeInsets.only(left: 84));
      expect(layout.controlsCenterOffset, 42);
    });

    test('keeps a region crossing the column out of the controls', () {
      // The status bar briefly spans the top while the device folds closed.
      final layout = resolveSideNavigationLayout(
        placement: PhoneNavigationPlacement.right,
        windowSize: _outerWindow,
        viewPadding: _outerPadding,
        occlusions: const [
          _outerCamera,
          Rect.fromLTWH(266, 0, 200, 82),
          Rect.fromLTWH(400, 600, 40, 60),
        ],
        barWidth: cupertinoVerticalGlassTabBarWidth,
      )!;

      expect(layout.pageActionsTop, 86);
      expect(layout.tabBarBottom, 84);
      expect(
        layout.controlsCenterOffset,
        closeTo(_outerWindow.width - _outerCamera.center.dx, 0.01),
      );
    });

    test('widens a narrow system inset to fit the bar', () {
      final layout = resolveSideNavigationLayout(
        placement: PhoneNavigationPlacement.right,
        windowSize: _outerWindow,
        viewPadding: EdgeInsets.zero,
        occlusions: const [],
        barWidth: cupertinoVerticalGlassTabBarWidth,
      )!;

      expect(layout.columnWidth, cupertinoVerticalGlassTabBarWidth + 12);
    });
  });

  testWidgets('vertical glass tab bar stacks the tabs and reports taps',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      CupertinoApp(
        home: Center(
          child: StatefulBuilder(
            builder: (context, setState) => CupertinoVerticalGlassTabBar(
              tabs: const [
                CupertinoVerticalGlassTab(
                  icon: CupertinoIcons.house_fill,
                  label: '主页',
                ),
                CupertinoVerticalGlassTab(
                  icon: CupertinoIcons.play_rectangle_fill,
                  label: '视频播放',
                ),
                CupertinoVerticalGlassTab(
                  icon: CupertinoIcons.collections_solid,
                  label: '媒体库',
                ),
              ],
              selectedIndex: selected,
              onTabSelected: (index) => setState(() => selected = index),
              selectedColor: CupertinoColors.systemPink,
              unselectedColor: CupertinoColors.black,
            ),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(CupertinoVerticalGlassTabBar)),
      Size(
        cupertinoVerticalGlassTabBarWidth,
        CupertinoVerticalGlassTabBar.heightFor(3),
      ),
    );
    final home = tester.getCenter(find.byIcon(CupertinoIcons.house_fill));
    final library =
        tester.getCenter(find.byIcon(CupertinoIcons.collections_solid));
    expect(library.dx, home.dx);
    expect(library.dy, greaterThan(home.dy));
    expect(find.bySemanticsLabel('媒体库'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.collections_solid));
    await tester.pumpAndSettle();

    expect(selected, 2);
    final icon = tester.widget<Icon>(
      find.byIcon(CupertinoIcons.collections_solid),
    );
    expect(icon.color, CupertinoColors.systemPink);
  });

  testWidgets('page actions stack vertically beside side bars', (tester) async {
    await tester.pumpWidget(
      const CupertinoApp(
        home: Center(
          child: CupertinoAppPageActions(
            actionIds: [AppActionIds.toggleTheme, AppActionIds.settings],
            direction: Axis.vertical,
          ),
        ),
      ),
    );

    final theme = tester.getCenter(find.byIcon(CupertinoIcons.moon_fill));
    final settings =
        tester.getCenter(find.byIcon(CupertinoIcons.gear_alt_fill));
    expect(settings.dx, theme.dx);
    expect(settings.dy - theme.dy, cupertinoPageActionButtonSize);
  });

  group('regular width', () {
    testWidgets('defaults to compact without a scope', (tester) async {
      late bool isRegularWidth;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            isRegularWidth = AppSizeClassScope.isRegularWidthOf(context);
            return const SizedBox();
          },
        ),
      );

      expect(isRegularWidth, isFalse);
    });

    testWidgets('pairs stacked blocks into two columns', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              width: 400,
              child: Column(
                children: buildTwoColumnRows(
                  const [
                    SizedBox(key: ValueKey('a'), height: 50),
                    SizedBox(key: ValueKey('b'), height: 80),
                    SizedBox(key: ValueKey('c'), height: 50),
                  ],
                  columnSpacing: 20,
                ),
              ),
            ),
          ),
        ),
      );

      final a = tester.getRect(find.byKey(const ValueKey('a')));
      final b = tester.getRect(find.byKey(const ValueKey('b')));
      final c = tester.getRect(find.byKey(const ValueKey('c')));
      expect(a.width, 190);
      expect(b.left, a.right + 20);
      expect(b.top, a.top);
      expect(c.left, a.left);
      expect(c.top, b.bottom);
    });

    Future<void> pumpPhoneCollection(
      WidgetTester tester, {
      required bool isRegularWidth,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      tester.view.physicalSize = const Size(867, 669);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final items = [
        for (final id in [1, 2, 3])
          WatchHistoryItem(
            animeId: id,
            animeName: '番剧 $id',
            episodeTitle: '第一集',
            filePath: '/media/$id.mkv',
            lastWatchTime: DateTime(2026),
            watchProgress: 0.5,
            lastPosition: 60,
            duration: 120,
          ),
      ];

      await tester.pumpWidget(
        ChangeNotifierProvider<AppearanceSettingsProvider>(
          create: (_) => AppearanceSettingsProvider(),
          child: MaterialApp(
            home: Scaffold(
              body: AppDisplaySurfaceScope(
                surface: AppDisplaySurface.phone,
                child: AppSizeClassScope(
                  isRegularWidth: isRegularWidth,
                  child: AdaptiveMediaCollectionItems(
                    source: UnifiedMediaLibrarySource.local,
                    sourceLabel: '本地媒体库',
                    isLoading: false,
                    items: items,
                    allHistory: items,
                    details: const {},
                    newAnimeIds: const <int>{},
                    onRefresh: () async {},
                    onTap: (_) {},
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Rect cardRect(WidgetTester tester, int id) => tester.getRect(
          find.byKey(ValueKey<String>('media-collection-local-$id')),
        );

    testWidgets('media library shows two card columns at regular width',
        (tester) async {
      await pumpPhoneCollection(tester, isRegularWidth: true);

      final first = cardRect(tester, 1);
      final second = cardRect(tester, 2);
      final third = cardRect(tester, 3);
      expect(second.top, first.top);
      expect(second.left, greaterThan(first.right));
      expect(second.width, first.width);
      expect(third.left, first.left);
      expect(third.top, greaterThan(first.bottom));
    });

    testWidgets('media library keeps one column at compact width',
        (tester) async {
      await pumpPhoneCollection(tester, isRegularWidth: false);

      final first = cardRect(tester, 1);
      final second = cardRect(tester, 2);
      expect(second.left, first.left);
      expect(second.top, greaterThan(first.bottom));
    });
  });
}

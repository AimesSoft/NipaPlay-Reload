import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/l10n/app_localizations.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/android_tv_remote_key_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_scaffold_layout.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_tab_panel.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late _FakeVideoState videoState;
  late GlobalKey<NavigatorState> navigatorKey;
  late List<MethodCall> platformCalls;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    videoState = _FakeVideoState();
    navigatorKey = GlobalKey<NavigatorState>();
    platformCalls = [];
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      platformCalls.add(call);
      return null;
    });
    for (final channel in [
      'dev.universal_gamepad/events',
      'dev.fluttercommunity.plus/charging',
    ]) {
      messenger.setMockMethodCallHandler(
          MethodChannel(channel), (_) async => null);
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/battery'),
      (call) async => call.method == 'getBatteryLevel' ? 100 : 'full',
    );
  });

  tearDown(() {
    videoState.dispose();
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final channel in [
      SystemChannels.platform.name,
      'dev.universal_gamepad/events',
      'dev.fluttercommunity.plus/charging',
      'dev.fluttercommunity.plus/battery',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), null);
    }
  });

  Future<void> openApp(WidgetTester tester, {int index = 1}) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<VideoPlayerState>.value(value: videoState),
        ChangeNotifierProvider(create: (_) => LargeScreenUiSfxService()),
        ChangeNotifierProvider<PluginService>(
            create: (_) => _FakePluginService()),
        ChangeNotifierProvider(create: (_) => ThemeNotifier()),
        ChangeNotifierProvider(create: (_) => AppearanceSettingsProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => HomeSectionsSettingsProvider()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        builder: (_, child) => NipaplayAndroidTvRemoteKeyScope(
          navigatorKey: navigatorKey,
          child: child!,
        ),
        home: DefaultTabController(
          length: 3,
          initialIndex: index,
          child: Builder(
              builder: (context) => NipaplayLargeScreenModeScope(
                    isActive: true,
                    child: Scaffold(
                        body: NipaplayLargeScreenScaffoldLayout(
                      currentIndex: index,
                      currentPageId:
                          index == 1 ? AppPageIds.video : AppPageIds.home,
                      pageIds: const [
                        AppPageIds.home,
                        AppPageIds.video,
                        AppPageIds.mediaLibrary
                      ],
                      isDarkMode: true,
                      tabPage: const [
                        Text('Home'),
                        Text('Video'),
                        Text('Library')
                      ],
                      tabController: DefaultTabController.of(context),
                      content: const Focus(
                          autofocus: true,
                          child: Center(child: Text('content'))),
                    )),
                  )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> disposeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  }

  bool getDidExit() =>
      platformCalls.any((call) => call.method == 'SystemNavigator.pop');

  bool isPanelOpen(WidgetTester tester, Type panelType) => !tester
      .element(find.byType(panelType))
      .findAncestorWidgetOfExactType<IgnorePointer>()!
      .ignoring;

  RoutePopDisposition disposition(WidgetTester tester) => ModalRoute.of(
        tester.element(find.byType(NipaplayLargeScreenScaffoldLayout)),
      )!
          .popDisposition;

  testWidgets('Android root advertises playback back handling to the system',
      (tester) async {
    await openApp(tester);
    expect(disposition(tester), RoutePopDisposition.doNotPop);
    expect(
        platformCalls
            .where((call) =>
                call.method == 'SystemNavigator.setFrameworkHandlesBack')
            .last
            .arguments,
        isTrue);
    expect(getDidExit(), isFalse);
    await disposeApp(tester);
  });

  testWidgets(
      'system back closes the navigation menu before allowing root exit',
      (tester) async {
    videoState.hasVideoValue = false;
    await openApp(tester, index: 0);
    expect(disposition(tester), RoutePopDisposition.bubble);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(isPanelOpen(tester, NipaplayLargeScreenTabPanel), isTrue);
    expect(disposition(tester), RoutePopDisposition.doNotPop);
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(isPanelOpen(tester, NipaplayLargeScreenTabPanel), isFalse);
    expect(getDidExit(), isFalse);
    expect(disposition(tester), RoutePopDisposition.bubble);
    expect(await tester.binding.handlePopRoute(), isFalse);
    await tester.pump();
    expect(getDidExit(), isTrue);
    await disposeApp(tester);
  });

  testWidgets('a dialog route handles system back before the root player',
      (tester) async {
    await openApp(tester);
    navigatorKey.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('dialog'))));
    await tester.pumpAndSettle();
    expect(await tester.binding.handlePopRoute(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('dialog'), findsNothing);
    expect(getDidExit(), isFalse);
    await disposeApp(tester);
  });

  testWidgets('remote back repeats and key up cannot reopen a closed menu',
      (tester) async {
    videoState.hasVideoValue = false;
    await openApp(tester, index: 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(
        await tester.sendKeyDownEvent(LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape),
        isTrue);
    await tester.pumpAndSettle();
    expect(
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape),
        isTrue);
    expect(
        await tester.sendKeyUpEvent(LogicalKeyboardKey.goBack,
            physicalKey: PhysicalKeyboardKey.escape),
        isTrue);
    await tester.pumpAndSettle();
    expect(isPanelOpen(tester, NipaplayLargeScreenTabPanel), isFalse);
    expect(getDidExit(), isFalse);
    await disposeApp(tester);
  });

  testWidgets('desktop root retains its existing pop behavior', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await openApp(tester);
    expect(disposition(tester), RoutePopDisposition.bubble);
    await disposeApp(tester);
  });
}

class _FakeVideoState extends ChangeNotifier implements VideoPlayerState {
  final Player _player = _FakePlayer();
  bool hasVideoValue = true;
  bool controlsVisible = false;

  @override
  Player get player => _player;
  @override
  bool get hasVideo => hasVideoValue;
  @override
  bool get showControls => controlsVisible;
  @override
  String? get currentVideoPath => null;
  @override
  String? get currentExternalSubtitlePath => null;
  @override
  int? get animeId => null;
  @override
  bool get playerTopSendDanmakuButtonVisible => false;
  @override
  bool get danmakuVisible => true;
  @override
  bool get minimalProgressBarEnabled => false;
  @override
  bool get showDanmakuDensityChart => false;
  @override
  Color get minimalProgressBarColor => Colors.white;
  @override
  bool get playerTopResizeButtonVisible => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePluginService extends ChangeNotifier implements PluginService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePlayer implements Player {
  @override
  PlayerMediaInfo get mediaInfo =>
      PlayerMediaInfo(duration: 0, subtitle: const [], audio: const []);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/plugins/danmaku/plugin_danmaku_webview_overlay.dart';
import 'package:nipaplay/plugins/danmaku/titan_danmaku_settings.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
import 'package:nipaplay/utils/video_player_state.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

class _VideoState extends ChangeNotifier implements VideoPlayerState {
  @override
  PlayerStatus status = PlayerStatus.playing;
  @override
  bool isBuffering = false;
  @override
  int seekRevision = 0;
  @override
  double effectivePlaybackRate = 1.5;
  @override
  final ValueNotifier<double> playbackTimeMs = ValueNotifier<double>(12000);
  @override
  Duration get videoDuration => const Duration(minutes: 2);
  @override
  Future<void> get initialDanmakuSettingsReady => Future<void>.value();
  @override
  TitanDanmakuSettings get titanDanmakuSettings => const TitanDanmakuSettings();
  @override
  List<Map<String, dynamic>> get danmakuList => const [];
  @override
  int get danmakuListVersion => 0;
  @override
  int get locallySentDanmakuRevision => 0;
  @override
  int get locallySentDanmakuListVersion => -1;

  // Settings are stable in these tests; the real host still serializes them.
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      switch (invocation.memberName) {
        #danmakuVisible => true,
        #danmakuOpacity ||
        #danmakuFontSize ||
        #danmakuDisplayArea ||
        #danmakuScrollDurationSeconds =>
          1.0,
        #danmakuFontFamily => 'sans-serif',
        #danmakuStacking ||
        #mergeDanmaku ||
        #blockTopDanmaku ||
        #blockBottomDanmaku ||
        #blockScrollDanmaku =>
          false,
        #danmakuBlockWords => <String>[],
        #manualDanmakuOffset || #autoDanmakuOffset => 0.0,
        _ => super.noSuchMethod(invocation),
      };

  @override
  void dispose() {
    playbackTimeMs.dispose();
    super.dispose();
  }
}

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _WebViewPlatform extends WebViewPlatform {
  final loaded = Completer<void>();
  late _Controller controller;

  @override
  PlatformWebViewController createPlatformWebViewController(
          PlatformWebViewControllerCreationParams params) =>
      controller = _Controller(params, loaded);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _NavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _WebViewWidget(params);
}

class _Controller extends PlatformWebViewController {
  _Controller(super.params, this.loaded) : super.implementation();
  final Completer<void> loaded;
  final initialStateLoaded = Completer<void>();
  late JavaScriptChannelParams channel;
  final messages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> get clocks =>
      messages.where((message) => message['type'] == 'clock').toList();

  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate delegate) async {}

  @override
  Future<void> loadFile(String path) async {
    expectSync(await File(path).exists(), isTrue);
    loaded.complete();
  }

  @override
  Future<void> runJavaScript(String script) async {
    const prefix = 'window.NipaDanmakuRenderer.handle(';
    expectSync(script, startsWith(prefix));
    messages.add(jsonDecode(script.substring(prefix.length, script.length - 2))
        as Map<String, dynamic>);
    if (messages.last['type'] == 'load' && !initialStateLoaded.isCompleted) {
      initialStateLoaded.complete();
    }
  }

  void ready() => channel
      .onMessageReceived(const JavaScriptMessage(message: '{"type":"ready"}'));
}

class _NavigationDelegate extends PlatformNavigationDelegate {
  _NavigationDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(
      NavigationRequestCallback callback) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _WebViewWidget extends PlatformWebViewWidget {
  _WebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  late Directory temp;
  late PathProviderPlatform previousPaths;
  WebViewPlatform? previousWebView;
  late _WebViewPlatform platform;
  late _VideoState state;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('plugin_danmaku_buffering_');
    SharedPreferences.setMockInitialValues({
      'macos_storage_migration_completed': true,
      'macos_storage_migration_version': 1,
    });
    previousPaths = PathProviderPlatform.instance;
    previousWebView = WebViewPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    platform = _WebViewPlatform();
    WebViewPlatform.instance = platform;
    state = _VideoState();
  });

  tearDown(() async {
    state.dispose();
    PathProviderPlatform.instance = previousPaths;
    if (previousWebView != null) WebViewPlatform.instance = previousWebView;
    await temp.delete(recursive: true);
  });

  Future<_Controller> mount(WidgetTester tester) async {
    // Only HTML cache I/O uses the real event loop; no external scripts load.
    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        home: PluginDanmakuWebViewOverlay(
          renderer: const PluginDanmakuRenderer(
            pluginId: 'test',
            id: 'javascript',
            name: 'Test renderer',
            description: '',
            bootstrap: 'window.NipaDanmakuRenderer = {handle() {}};',
            externalScripts: [],
            platforms: {'android', 'ios'},
          ),
          videoState: state,
        ),
      ));
      await platform.loaded.future.timeout(const Duration(seconds: 5));
      platform.controller.ready();
      await platform.controller.initialStateLoaded.future
          .timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pump();
    expect(platform.controller.messages.last['type'], 'load');
    return platform.controller;
  }

  Future<void> flushMessages(WidgetTester tester) async {
    // The queue was created while loading the cache in runAsync.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }

  testWidgets('rapid buffering and recovery bypass clock throttling',
      (tester) async {
    final controller = await mount(tester);
    expect(controller.clocks.single['playing'], isTrue);
    controller.messages.clear();

    // Establish a just-sent clock, then buffer/resume without awaiting a frame.
    state.seekRevision++;
    state.notifyListeners();
    state.isBuffering = true;
    state.notifyListeners();
    state.isBuffering = false;
    state.notifyListeners();
    await flushMessages(tester);

    expect(controller.clocks.map((message) => message['playing']),
        [true, false, true]);
    expect(controller.clocks.map((message) => message['positionSeconds']),
        everyElement(12.0));
    expect(controller.clocks.map((message) => message['seekRevision']),
        everyElement(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('recovery respects a user pause during buffering',
      (tester) async {
    final controller = await mount(tester);
    controller.messages.clear();
    state.isBuffering = true;
    state.notifyListeners();
    state.status = PlayerStatus.paused;
    state.notifyListeners();
    state.isBuffering = false;
    state.notifyListeners();
    await flushMessages(tester);

    expect(controller.clocks.map((message) => message['playing']),
        [false, false, false]);
    state.status = PlayerStatus.playing;
    state.notifyListeners();
    await flushMessages(tester);
    expect(controller.clocks.last['playing'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('renderer initialized during buffering stays paused',
      (tester) async {
    state.isBuffering = true;
    final controller = await mount(tester);
    expect(controller.clocks.single['playing'], isFalse);

    // A play request while still buffering must not restart the JS engine.
    state.status = PlayerStatus.paused;
    state.notifyListeners();
    state.status = PlayerStatus.playing;
    state.notifyListeners();
    await flushMessages(tester);
    expect(controller.clocks.map((message) => message['playing']),
        everyElement(false));

    state.isBuffering = false;
    state.notifyListeners();
    await flushMessages(tester);
    expect(controller.clocks.last['playing'], isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('seek and recovered position reach JS with playback rate intact',
      (tester) async {
    final controller = await mount(tester);
    state.isBuffering = true;
    state.notifyListeners();
    state.seekRevision++;
    state.playbackTimeMs.value = 42000;
    state.notifyListeners();
    await flushMessages(tester);
    expect(controller.clocks.last, containsPair('playing', false));
    expect(controller.clocks.last, containsPair('seekRevision', 1));
    expect(controller.clocks.last, containsPair('positionSeconds', 42.0));

    state.isBuffering = false;
    state.playbackTimeMs.value = 41500;
    state.notifyListeners();
    await flushMessages(tester);
    expect(controller.clocks.last, containsPair('playing', true));
    expect(controller.clocks.last, containsPair('positionSeconds', 41.5));
    expect(controller.clocks.last, containsPair('playbackRate', 1.5));
    expect(controller.clocks.last, containsPair('durationSeconds', 120.0));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

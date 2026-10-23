import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/danmaku/source.dart';
import 'package:nipaplay/next/player/danmaku/controller.dart';
import 'package:nipaplay/next/player/danmaku/plugin_layer.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'fake_driver.dart';

DanmakuEntry entry(int time, String text) => DanmakuEntry(
    sourceId: 'test', videoId: '12', platform: 'bilibili',
    sourceTimeMs: time, text: text, mode: 1, colorRgb: 0xFFFFFF);

Map<String, dynamic> binding(String id) => {
      'id': id, 'enabled': 1, 'deduplicate': 1, 'offset_ms': 0,
      'revision': 1, 'cache_revision': 1, 'cache_key': id,
      'video': {'sourceId': 'test', 'videoId': '12', 'title': 'episode 12'}
    };

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
  late JavaScriptChannelParams channel;
  final messages = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> of(String type) =>
      messages.where((m) => m['type'] == type).toList();

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

const _renderer = PluginDanmakuRenderer(
  pluginId: 'test',
  id: 'javascript',
  name: 'Test renderer',
  description: '',
  bootstrap: 'window.NipaDanmakuRenderer = {handle() {}};',
  externalScripts: [],
  platforms: {'macos'},
  supportsRealtimeAdd: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the enabled plugins\' block words filter the timeline build', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('a change of plugins reaches the next build, as a rule or a literal',
        () async {
      final c = SessionDanmakuController(
          initialSettings: {'danmaku.timelineEnabled': false});
      addTearDown(c.dispose);
      c.bind('s');
      c.inputs(duration: 1440000);
      c.install('t', binding('t'), [
        entry(1000, 'hello'), entry(2000, 'bad word'), entry(3000, 'nice123')]);
      await c.settled;
      final plugins = ValueNotifier<List<String>>(const []);
      c.followPluginBlockWords(plugins, () => plugins.value);
      await c.settled;
      Future<List<String>> texts() async =>
          [for (final e in await c.displayList()) e['content'] as String];
      expect(await texts(), ['hello', 'bad word', 'nice123']);

      plugins.value = ['bad', 'digits/\\d+/'];
      await c.settled;
      expect(await texts(), ['hello']);
      expect(c.facts()['pluginBlockWords'], 2);

      // The user's own words and the plugins' add up.
      await c.writeSetting('danmaku.blockWords', ['hello']);
      await c.settled;
      expect(await texts(), isEmpty);

      // Disabling the plugin gives its comments back.
      await c.writeSetting('danmaku.blockWords', <String>[]);
      plugins.value = const [];
      await c.settled;
      expect(await texts(), ['hello', 'bad word', 'nice123']);
    });

    test('a window for a plugin renderer holds the window\'s comments only, as text',
        () async {
      final c = SessionDanmakuController(
          initialSettings: {'danmaku.timelineEnabled': false});
      addTearDown(c.dispose);
      c.bind('s');
      c.inputs(duration: 3600000);
      c.install('t', binding('t'),
          [for (var i = 0; i < 3000; i++) entry(i * 1000, 'm$i')]);
      await c.settled;
      final (version, text) = await c.pluginWindow(1000, 1010);
      expect(version, c.version);
      final message = jsonDecode(text) as Map<String, dynamic>;
      expect(message['type'], 'load');
      expect(message['window'], {'startSeconds': 1000.0, 'endSeconds': 1010.0});
      final items = (message['items'] as List).cast<Map<String, dynamic>>();
      expect(items.map((e) => e['content']), [for (var i = 1000; i < 1010; i++) 'm$i']);
      expect(items.first['time'], 1000.0);
      expect(items.first['type'], 'scroll');
    });
  });

  group('the renderer\'s page', () {
    late Directory temp;
    late PathProviderPlatform previousPaths;
    WebViewPlatform? previousWebView;
    late _WebViewPlatform platform;
    late FakeHost rig;
    late SessionPlayback playback;
    late String video;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('next_plugin_layer_');
      SharedPreferences.setMockInitialValues({
        'macos_storage_migration_completed': true,
        'macos_storage_migration_version': 1,
      });
      previousPaths = PathProviderPlatform.instance;
      previousWebView = WebViewPlatform.instance;
      PathProviderPlatform.instance = _Paths(temp.path);
      platform = _WebViewPlatform();
      WebViewPlatform.instance = platform;
      video = '${temp.path}/12.mkv';
      await File(video).writeAsString('fake media');
      rig = FakeHost();
      playback = SessionPlayback(rig.host);
    });

    tearDown(() async {
      await playback.close(reason: 'test');
      await playback.dispose();
      PathProviderPlatform.instance = previousPaths;
      if (previousWebView != null) WebViewPlatform.instance = previousWebView;
      await temp.delete(recursive: true);
    });

    test('the facts name what draws, and say when the plugin chosen does not',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        DanmakuKernelFactory.setAvailablePluginRenderers(const []);
      });
      expect(playback.danmakuRendererFacts.containsKey('pluginRenderer'), false);
      DanmakuKernelFactory.setAvailablePluginRenderers(const [_renderer]);
      await DanmakuKernelFactory.savePluginRenderer(_renderer.selectionId);
      var facts = playback.danmakuRendererFacts;
      expect(facts['id'], 'plugin:test/javascript');
      expect(facts['pluginRenderer'],
          {'selected': 'plugin:test/javascript', 'drawing': true, 'status': null});
      // The plugin is turned off: the engine draws, and the selection is kept.
      DanmakuKernelFactory.setAvailablePluginRenderers(const []);
      facts = playback.danmakuRendererFacts;
      expect(facts['id'], isNot(startsWith('plugin:')));
      expect(facts['pluginRenderer'], {
        'selected': 'plugin:test/javascript',
        'drawing': false,
        'reason': 'plugin_not_enabled_or_not_supported'
      });
    });

    Future<void> real(WidgetTester tester, [int ms = 80]) async {
      await tester.runAsync(
          () => Future<void>.delayed(Duration(milliseconds: ms)));
      await tester.pump();
    }

    Future<_Controller> mount(WidgetTester tester) async {
      await tester.runAsync(() async {
        await playback.openItem(PlayableItem(videoPath: video));
        playback.danmaku.bind(playback.session!.id);
        playback.danmaku.install('t', binding('t'),
            [for (var i = 0; i < 3000; i++) entry(i * 1000, 'm$i')]);
        await playback.danmaku.settled;
        await tester.pumpWidget(MaterialApp(
            home: NextPluginDanmakuLayer(
                playback: playback, renderer: _renderer)));
        await platform.loaded.future.timeout(const Duration(seconds: 5));
        platform.controller.ready();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      return platform.controller;
    }

    testWidgets('gets its settings, the clock and one window of comments; '
        'a seek out of the window gets another', (tester) async {
      final web = await mount(tester);
      await real(tester);
      expect(web.messages.first['type'], 'initialize');
      expect(web.of('settings').first['value']['opacity'], 1.0);
      final load = web.of('load').single;
      expect(load['window']['startSeconds'], lessThanOrEqualTo(0));
      final first = (load['items'] as List).length;
      expect(first, inInclusiveRange(1, 300), reason: 'about four minutes of m<i>');
      expect(playback.danmaku.pluginRendererStatus, 'ready');

      final before = web.of('clock').length;
      await tester.runAsync(() => playback.session!
          .seek(const Duration(seconds: 1200), origin: 'agent'));
      await real(tester, 300);
      expect(web.of('clock').length, greaterThan(before));
      expect(web.of('clock').last['positionSeconds'], closeTo(1200, 5));
      final second = web.of('load').last;
      expect(web.of('load').length, 2);
      final texts = [for (final i in second['items'] as List) i['content']];
      expect(texts, contains('m1200'));
      expect(texts, isNot(contains('m100')));
      expect(texts.length, lessThan(300), reason: 'a window, not the list');
      await tester.pumpWidget(const SizedBox.shrink());
      await real(tester);
      expect(web.of('dispose'), hasLength(1));
      expect(playback.danmaku.pluginRendererStatus, isNull);
    });

    testWidgets('a comment the user sent is added at once, without a reload',
        (tester) async {
      final web = await mount(tester);
      await real(tester);
      final loads = web.of('load').length;
      playback.danmaku.echo({'time': 5.0, 'content': 'mine', 'type': 1,
        'color': 'rgb(255,255,255)'});
      await real(tester, 300);
      expect(web.of('add').single['item']['content'], 'mine');
      expect(web.of('load').length, loads);
      await tester.pumpWidget(const SizedBox.shrink());
      await real(tester);
    });
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:nipaplay/plugins/danmaku/plugin_external_script_cache.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';

import '../core/clock.dart';
import '../perf/budget.dart';
import '../ports/session_playback.dart';

/// A plugin's danmaku renderer (a page in a WebView), hosted by Next's own
/// layer: it reads the session's clock, the comments the timeline worker
/// holds and the settings, and nothing of Classic's player.
///
/// What the page is sent (`window.NipaDanmakuRenderer.handle(message)`, the
/// protocol of `assets/plugins/README.md`):
/// - `load`: the comments of one window of list time (about four minutes
///   around the clock), made on the timeline worker as JSON text. The
///   message carries `window: {startSeconds, endSeconds}`. A new `load`
///   follows when the clock comes within a minute of the window's end, goes
///   out of it, or the list changes; the work grows with the window, never
///   with the length of the list.
/// - `clock`: at most every 100 ms while the comments move, and at once at
///   any discontinuity (seek, pause, resume, another rate).
/// - `settings`, `add` (a comment the user just sent, to a renderer that
///   takes it live) and `dispose`.
class NextPluginDanmakuLayer extends StatefulWidget {
  const NextPluginDanmakuLayer(
      {super.key, required this.playback, required this.renderer});
  final SessionPlayback playback;
  final PluginDanmakuRenderer renderer;

  @override
  State<NextPluginDanmakuLayer> createState() => _NextPluginDanmakuLayerState();
}

class _NextPluginDanmakuLayerState extends State<NextPluginDanmakuLayer> {
  /// Length of one window of list time, how far before the clock it starts,
  /// and how close to its end the clock may come before the next one is asked.
  static const _ahead = 210.0, _behind = 30.0, _renew = 60.0;

  WebViewController? _web;
  bool _ready = false, _initialSent = false;
  int _generation = 0;
  Future<void> _queue = Future.value();
  PlaybackClockView? _clock;
  Timer? _tick;
  StreamSubscription<Map<String, dynamic>>? _echoes;

  // The window held by the page, in list time.
  double _from = 0, _to = -1;
  int _loadedVersion = -1, _loadSeq = 0;
  bool _loading = false;
  DateTime? _echoedAt;

  // What the page was last told.
  String _lastSettings = '';
  int _seekRevision = 0;
  int _visibleRevision = 0;
  bool? _lastVisible;
  Duration _anchorPosition = Duration.zero;
  Duration _anchorAt = Duration.zero;
  double _anchorRate = 1;
  bool _anchorAdvancing = false;

  SessionPlayback get _p => widget.playback;
  PluginDanmakuRenderer get _renderer => widget.renderer;
  bool get _visible => _p.danmaku.visible;

  @override
  void initState() {
    super.initState();
    _p.media.addListener(_bind);
    _p.danmaku.addListener(_controllerChanged);
    _echoes = _p.danmaku.echoes.listen(_echoed);
    _p.danmaku.pluginRendererStatus = 'loading';
    _p.danmaku.pluginRendererError = null;
    _bind();
    unawaited(_initialize());
  }

  void _bind() {
    final next = _p.session?.clock;
    if (!identical(next, _clock)) {
      _clock?.removeListener(_anchored);
      _clock = next;
      _clock?.addListener(_anchored);
      _remember();
      _seekRevision++;
    }
    _anchored();
  }

  void _remember() {
    final clock = _clock;
    _anchorPosition = clock?.now() ?? Duration.zero;
    _anchorAt = PlayerTime.now();
    _anchorRate = clock?.rate ?? 1;
    _anchorAdvancing = clock?.advancing ?? false;
  }

  /// The clock was re-anchored: a seek when the position is not where the
  /// course before it would have been, else play, pause or another rate.
  void _anchored() {
    final clock = _clock;
    if (clock == null) {
      _tick?.cancel();
      _tick = null;
      return;
    }
    final now = clock.now();
    final expected = _anchorAdvancing
        ? _anchorPosition + (PlayerTime.now() - _anchorAt) * _anchorRate
        : _anchorPosition;
    if ((now - expected).abs() > const Duration(milliseconds: 400)) {
      _seekRevision++;
    }
    _remember();
    _syncTimer();
    unawaited(_sendClock());
    _maybeLoad();
  }

  void _syncTimer() {
    final moving = _ready && _visible && (_clock?.advancing ?? false);
    if (moving && _tick == null) {
      _tick = Timer.periodic(const Duration(milliseconds: 100), (_) {
        unawaited(_sendClock());
        _maybeLoad();
      });
    } else if (!moving && _tick != null) {
      _tick!.cancel();
      _tick = null;
    }
  }

  void _controllerChanged() {
    if (!_ready || !_initialSent) return;
    unawaited(_sendSettings());
    final recentEcho = _echoedAt != null &&
        DateTime.now().difference(_echoedAt!) < const Duration(milliseconds: 1500);
    if (recentEcho && _renderer.supportsRealtimeAdd &&
        _p.danmaku.version != _loadedVersion) {
      // The rebuild the live-added comment caused: the page has it already.
      _loadedVersion = _p.danmaku.version;
      _echoedAt = null;
    }
    _syncTimer();
    _maybeLoad();
  }

  void _echoed(Map<String, dynamic> comment) {
    if (!_ready || !_initialSent || !_renderer.supportsRealtimeAdd) return;
    _echoedAt = DateTime.now();
    final item = _renderer.prepareRealtimeItem({
      'time': comment['time'],
      'content': comment['content'].toString(),
      'type': comment['type'] is num
          ? (comment['type'] == 5 ? 'top' : comment['type'] == 4 ? 'bottom' : 'scroll')
          : (comment['type']?.toString() ?? 'scroll'),
      'color': comment['color'],
      'isMe': true,
    });
    unawaited(_send(jsonEncode({'type': 'add', 'item': item})));
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    try {
      final pagePath = await PluginExternalScriptCache.prepareRendererPage(_renderer);
      if (!mounted || generation != _generation) return;
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.addJavaScriptChannel('NipaDanmakuHost',
          onMessageReceived: (message) => _fromPage(message, generation));
      await controller.setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && (uri.scheme == 'file' || uri.scheme == 'about')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onWebResourceError: (error) => debugPrint(
            '[PluginDanmaku:${_renderer.selectionId}] WebView: ${error.description}'),
      ));
      if (!mounted || generation != _generation) return;
      setState(() => _web = controller);
      await controller.loadFile(pagePath);
    } catch (error, stack) {
      debugPrint('[PluginDanmaku:${_renderer.selectionId}] load failed: $error\n$stack');
      _fail(error.toString());
    }
  }

  void _fail(String message) {
    _p.danmaku.pluginRendererStatus = 'failed';
    _p.danmaku.pluginRendererError = message;
  }

  void _fromPage(JavaScriptMessage message, int generation) {
    if (!mounted || generation != _generation) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      switch (decoded['type']) {
        case 'ready':
          _ready = true;
          unawaited(_sendFullState(generation));
        case 'error':
          debugPrint('[PluginDanmaku:${_renderer.selectionId}] ${decoded['message']}');
          _fail('${decoded['message']}');
        case 'log':
          debugPrint('[PluginDanmaku:${_renderer.selectionId}] ${decoded['message']}');
      }
    } catch (_) {}
  }

  Future<void> _sendFullState(int generation) async {
    await _send(jsonEncode({
      'type': 'initialize',
      'apiVersion': PluginDanmakuRenderer.supportedApiVersion,
      'pluginId': _renderer.pluginId,
      'rendererId': _renderer.id,
    }));
    await _sendSettings(force: true);
    await _sendClock(force: true);
    if (!mounted || generation != _generation) return;
    _initialSent = true;
    _p.danmaku.pluginRendererStatus = 'ready';
    _p.danmaku.pluginRendererError = null;
    _syncTimer();
    _maybeLoad();
  }

  /// The window in list time the page should hold: the clock plus the offset
  /// is where the comments are read from, as in the renderers of Next.
  double _listTime() =>
      (_clock?.now().inMicroseconds ?? 0) / 1e6 + _p.danmaku.offset;

  void _maybeLoad() {
    if (!_ready || !_initialSent || _loading) return;
    final c = _p.danmaku;
    if (c.sessionId == null) return;
    final lt = _listTime();
    final behind = _behind < c.scrollSeconds * 2 ? c.scrollSeconds * 2 : _behind;
    final stale = c.version != _loadedVersion ||
        lt < _from + 2 ||
        lt > _to - _renew;
    if (!stale) return;
    _loading = true;
    final id = ++_loadSeq;
    final generation = _generation;
    final from = lt - behind, to = lt + _ahead;
    unawaited(c.pluginWindow(from, to).then((reply) {
      _loading = false;
      if (!mounted || generation != _generation || id != _loadSeq) return;
      _from = from;
      _to = to;
      _loadedVersion = reply.$1;
      PlayerPerf.span('danmaku.plugin.load', () => _sendNow(reply.$2));
      _maybeLoad();
    }, onError: (Object error) {
      _loading = false;
      debugPrint('[PluginDanmaku:${_renderer.selectionId}] window: $error');
    }));
  }

  Map<String, dynamic> _settings() {
    final c = _p.danmaku;
    final rendererSettings = c.titan.toJson();
    return {
      'visible': _visible,
      // Linear, as everywhere in Next (D4).
      'opacity': c.number('danmaku.opacity'),
      'fontSize': c.fontSize,
      'fontFamily': c.settings['danmaku.fontFamily'],
      'displayArea': c.number('danmaku.displayArea'),
      'scrollDurationSeconds': c.scrollSeconds,
      'stacking': c.settings['danmaku.stacking'] == true,
      'merge': c.settings['danmaku.merge'] == true,
      'blockTop': c.settings['danmaku.blockTop'] == true,
      'blockBottom': c.settings['danmaku.blockBottom'] == true,
      'blockScroll': c.settings['danmaku.blockScroll'] == true,
      'blockWords': c.settings['danmaku.blockWords'],
      'timeOffsetSeconds': c.offset,
      if (_renderer.usesTitanSettings) 'rendererSettings': rendererSettings,
    };
  }

  Future<void> _sendSettings({bool force = false}) async {
    final encoded = jsonEncode(_settings());
    if (!force && encoded == _lastSettings) return;
    _lastSettings = encoded;
    await _send('{"type":"settings","value":$encoded}');
  }

  Future<void> _sendClock({bool force = false}) async {
    final clock = _clock;
    if (!_ready || clock == null) return;
    final visible = _visible;
    // Back to visible after hidden playback: the page restores the window
    // without reloading data.
    if (visible && _lastVisible == false) _visibleRevision++;
    _lastVisible = visible;
    await _send(jsonEncode({
      'type': 'clock',
      'positionSeconds': clock.now().inMicroseconds / 1e6,
      'durationSeconds': _p.duration.inMicroseconds / 1e6,
      'playing': visible && clock.advancing,
      'playbackRate': clock.rate,
      'seekRevision': _seekRevision + _visibleRevision,
    }));
  }

  Future<void> _send(String encoded) {
    final web = _web;
    if (!_ready || web == null) return Future.value();
    _queue = _queue.then((_) => web.runJavaScript(
        'window.NipaDanmakuRenderer.handle($encoded);')).catchError((Object error) {
      debugPrint('[PluginDanmaku:${_renderer.selectionId}] send failed: $error');
    });
    return _queue;
  }

  void _sendNow(String encoded) => unawaited(_send(encoded));

  @override
  void dispose() {
    _generation++;
    _tick?.cancel();
    _p.media.removeListener(_bind);
    _p.danmaku.removeListener(_controllerChanged);
    _clock?.removeListener(_anchored);
    unawaited(_echoes?.cancel());
    _p.danmaku.pluginRendererStatus = null;
    _p.danmaku.pluginRendererError = null;
    if (_ready && _web != null) unawaited(_send('{"type":"dispose"}'));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final web = _web;
    if (web == null) return const SizedBox.shrink();
    return ColoredBox(
        color: Colors.transparent, child: WebViewWidget(controller: web));
  }
}

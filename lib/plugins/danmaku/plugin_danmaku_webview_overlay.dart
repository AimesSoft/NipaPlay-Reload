import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/plugins/danmaku/plugin_external_script_cache.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
import 'package:nipaplay/utils/video_player_state.dart';

/// Transparent, pointer-pass-through host for an installed plugin renderer.
class PluginDanmakuWebViewOverlay extends StatefulWidget {
  const PluginDanmakuWebViewOverlay({
    super.key,
    required this.renderer,
    required this.videoState,
  });

  final PluginDanmakuRenderer renderer;
  final VideoPlayerState videoState;

  @override
  State<PluginDanmakuWebViewOverlay> createState() =>
      _PluginDanmakuWebViewOverlayState();
}

class _PluginDanmakuWebViewOverlayState
    extends State<PluginDanmakuWebViewOverlay> {
  WebViewController? _controller;
  Object? _loadError;
  bool _rendererReady = false;
  int _lastClockSentAtMs = 0;
  int _lastDanmakuListVersion = -1;
  int _lastLocallySentDanmakuRevision = -1;
  int _lastSeekRevision = -1;
  String _lastSettingsJson = '';
  String _lastPlaybackState = '';
  Future<void> _sendQueue = Future<void>.value();
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.videoState.addListener(_onVideoStateChanged);
    widget.videoState.playbackTimeMs.addListener(_onPlaybackClock);
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant PluginDanmakuWebViewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoState != widget.videoState) {
      oldWidget.videoState.removeListener(_onVideoStateChanged);
      oldWidget.videoState.playbackTimeMs.removeListener(_onPlaybackClock);
      widget.videoState.addListener(_onVideoStateChanged);
      widget.videoState.playbackTimeMs.addListener(_onPlaybackClock);
    }
    if (oldWidget.renderer.selectionId != widget.renderer.selectionId) {
      _rendererReady = false;
      _controller = null;
      _loadError = null;
      unawaited(_initialize());
    }
  }

  Future<void> _initialize() async {
    final generation = ++_loadGeneration;
    try {
      final pagePath =
          await PluginExternalScriptCache.prepareRendererPage(widget.renderer);
      if (!mounted || generation != _loadGeneration) return;
      final controller = WebViewController();
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setBackgroundColor(Colors.transparent);
      await controller.addJavaScriptChannel(
        'NipaDanmakuHost',
        onMessageReceived: (message) => _onRendererMessage(message, generation),
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            return uri != null &&
                    (uri.scheme == 'file' || uri.scheme == 'about')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onWebResourceError: (error) {
            debugPrint(
              '[PluginDanmaku:${widget.renderer.selectionId}] WebView: '
              '${error.description}',
            );
          },
        ),
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _controller = controller);
      await controller.loadFile(pagePath);
    } catch (error, stackTrace) {
      debugPrint(
        '[PluginDanmaku:${widget.renderer.selectionId}] 加载失败: '
        '$error\n$stackTrace',
      );
      if (mounted) setState(() => _loadError = error);
    }
  }

  void _onRendererMessage(JavaScriptMessage message, int generation) {
    if (!mounted || generation != _loadGeneration) return;
    try {
      final decoded = jsonDecode(message.message);
      if (decoded is! Map) return;
      switch (decoded['type']) {
        case 'ready':
          _rendererReady = true;
          unawaited(_sendFullState());
          return;
        case 'error':
          debugPrint(
            '[PluginDanmaku:${widget.renderer.selectionId}] '
            '${decoded['message']}',
          );
          return;
        case 'log':
          debugPrint(
            '[PluginDanmaku:${widget.renderer.selectionId}] '
            '${decoded['message']}',
          );
          return;
      }
    } catch (_) {}
  }

  Future<void> _sendFullState() async {
    await _send(<String, dynamic>{
      'type': 'initialize',
      'apiVersion': PluginDanmakuRenderer.supportedApiVersion,
      'pluginId': widget.renderer.pluginId,
      'rendererId': widget.renderer.id,
    });
    await _sendDanmaku(force: true);
    await _sendSettings(force: true);
    await _sendClock(force: true);
  }

  void _onVideoStateChanged() {
    if (!_rendererReady) return;
    unawaited(_sendDanmaku());
    unawaited(_sendSettings());
    unawaited(
        _sendClock(force: _lastSeekRevision != widget.videoState.seekRevision));
  }

  void _onPlaybackClock() {
    if (!_rendererReady) return;
    unawaited(_sendClock());
  }

  Future<void> _sendDanmaku({bool force = false}) async {
    final state = widget.videoState;
    final version = state.danmakuListVersion;
    final localRevision = state.locallySentDanmakuRevision;
    final isRealtimeLocalSend = widget.renderer.shouldUseRealtimeAdd(
      force: force,
      listVersion: version,
      locallySentListVersion: state.locallySentDanmakuListVersion,
      locallySentRevision: localRevision,
      lastLocallySentRevision: _lastLocallySentDanmakuRevision,
    );

    if (isRealtimeLocalSend) {
      _lastDanmakuListVersion = version;
      _lastLocallySentDanmakuRevision = localRevision;
      final item = state.locallySentDanmaku;
      if (state.locallySentDanmakuDisplayable && item != null) {
        await _send(<String, dynamic>{
          'type': 'add',
          'item': DanmakuItem.fromMap(item).toMap(),
        });
      }
      return;
    }

    if (!force && version == _lastDanmakuListVersion) return;
    _lastDanmakuListVersion = version;
    _lastLocallySentDanmakuRevision = localRevision;
    final items = state.danmakuList
        .map((item) => DanmakuItem.fromMap(item).toMap())
        .toList(growable: false);
    await _send(<String, dynamic>{
      'type': 'load',
      'version': version,
      'items': items,
    });
  }

  Future<void> _sendSettings({bool force = false}) async {
    final state = widget.videoState;
    final settings = <String, dynamic>{
      'visible': state.danmakuVisible,
      'opacity': state.mappedDanmakuOpacity,
      'fontSize': state.actualDanmakuFontSize,
      'fontFamily': state.danmakuFontFamily,
      'displayArea': state.danmakuDisplayArea,
      'scrollDurationSeconds': state.danmakuScrollDurationSeconds,
      'stacking': state.danmakuStacking,
      'merge': state.mergeDanmaku,
      'blockTop': state.blockTopDanmaku,
      'blockBottom': state.blockBottomDanmaku,
      'blockScroll': state.blockScrollDanmaku,
      'blockWords': state.danmakuBlockWords,
      'timeOffsetSeconds': state.manualDanmakuOffset + state.autoDanmakuOffset,
      if (widget.renderer.usesTitanSettings)
        'rendererSettings': state.titanDanmakuSettings.toJson(),
    };
    final encoded = jsonEncode(settings);
    if (!force && encoded == _lastSettingsJson) return;
    _lastSettingsJson = encoded;
    await _send(<String, dynamic>{'type': 'settings', 'value': settings});
  }

  Future<void> _sendClock({bool force = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = widget.videoState;
    final playbackState = state.status.toString().split('.').last;
    final seekChanged = state.seekRevision != _lastSeekRevision;
    final stateChanged = playbackState != _lastPlaybackState;
    if (!force &&
        !seekChanged &&
        !stateChanged &&
        now - _lastClockSentAtMs < 100) {
      return;
    }
    _lastClockSentAtMs = now;
    _lastSeekRevision = state.seekRevision;
    _lastPlaybackState = playbackState;
    await _send(<String, dynamic>{
      'type': 'clock',
      'positionSeconds': state.playbackTimeMs.value / 1000,
      'durationSeconds': state.videoDuration.inMilliseconds / 1000,
      'playing': playbackState == 'playing',
      'playbackRate': state.effectivePlaybackRate,
      'seekRevision': state.seekRevision,
    });
  }

  Future<void> _send(Map<String, dynamic> message) async {
    final controller = _controller;
    if (!_rendererReady || controller == null) return;
    final encoded = jsonEncode(message);
    _sendQueue = _sendQueue.then((_) async {
      await controller.runJavaScript(
        'window.NipaDanmakuRenderer.handle($encoded);',
      );
    }).catchError((Object error) {
      debugPrint(
        '[PluginDanmaku:${widget.renderer.selectionId}] 消息发送失败: $error',
      );
    });
    await _sendQueue;
  }

  @override
  void dispose() {
    _loadGeneration++;
    widget.videoState.removeListener(_onVideoStateChanged);
    widget.videoState.playbackTimeMs.removeListener(_onPlaybackClock);
    if (_rendererReady && _controller != null) {
      unawaited(_send(<String, dynamic>{'type': 'dispose'}));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) return const SizedBox.shrink();
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      ignoring: true,
      child: ColoredBox(
        color: Colors.transparent,
        child: WebViewWidget(controller: controller),
      ),
    );
  }
}

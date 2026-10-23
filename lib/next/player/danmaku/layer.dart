import 'dart:async';

import 'package:danmaku_canvas/canvas_danmaku_renderer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';
import 'package:nipaplay/danmaku_dfm/dfm_plus_layout_bridge.dart';
import 'package:nipaplay/danmaku_dfm/dfm_plus_overlay.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_config.dart';
import 'package:nipaplay/danmaku_gpu/lib/gpu_danmaku_overlay.dart';
import 'package:nipaplay/danmaku_next/next2_layout_bridge.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next2_overlay.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_old_overlay.dart';
import 'package:nipaplay/danmaku_next/nipaplay_next_overlay.dart';
import 'package:nipaplay/utils/danmaku/style.dart';

import '../core/clock.dart';
import '../perf/budget.dart';
import '../ports/session_playback.dart';
import 'controller.dart';

/// Next's own overlay: reused renderers, driven exclusively by the session
/// clock. No Classic notifications, no native getters, no timeline traversal.
class NextDanmakuLayer extends StatefulWidget {
  const NextDanmakuLayer({super.key, required this.playback});
  final SessionPlayback playback;

  @override
  State<NextDanmakuLayer> createState() => _NextDanmakuLayerState();
}

class _NextDanmakuLayerState extends State<NextDanmakuLayer>
    with SingleTickerProviderStateMixin {
  final _time = ValueNotifier<double>(0);
  PlaybackClockView? _clock;
  late final Ticker _ticker;
  late final DfmPlusLayoutBridge _dfm;
  late final Next2LayoutBridge _next2;
  StreamSubscription? _engineChanges, _rendererChanges;
  int _seekRevision = 0;

  @override
  void initState() {
    super.initState();
    _dfm = DfmPlusLayoutBridge(prepareInBackground: (c) =>
        widget.playback.danmaku.prepareLayout('dfm', c));
    _next2 = Next2LayoutBridge(prepareInBackground: (c) =>
        widget.playback.danmaku.prepareLayout('next2', c));
    _ticker = createTicker((_) => PlayerPerf.span('danmaku.clock', _sample));
    widget.playback.media.addListener(_bind);
    widget.playback.danmaku.addListener(_changed);
    _engineChanges = DanmakuKernelFactory.onKernelChanged.listen((_) => _changed());
    _rendererChanges = DanmakuKernelFactory.onRendererChanged.listen((_) => _changed());
    _bind();
  }

  void _bind() {
    final next = widget.playback.session?.clock;
    if (!identical(next, _clock)) {
      _clock?.removeListener(_anchor);
      _clock = next;
      _clock?.addListener(_anchor);
    }
    _anchor();
  }

  void _sample() => _time.value = (_clock?.now().inMicroseconds ?? 0) / 1000;

  void _anchor() {
    _seekRevision++;
    _sample();
    _changed();
  }

  void _changed() {
    final active = widget.playback.hasVideo &&
        widget.playback.danmaku.visible && !widget.playback.danmaku.native &&
        (_clock?.advancing ?? false);
    if (active && !_ticker.isActive) _ticker.start();
    if (!active && _ticker.isActive) _ticker.stop();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.playback.media.removeListener(_bind);
    widget.playback.danmaku.removeListener(_changed);
    _clock?.removeListener(_anchor);
    unawaited(_engineChanges?.cancel());
    unawaited(_rendererChanges?.cancel());
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.playback;
    final c = p.danmaku;
    if (!p.hasVideo || c.native) return const SizedBox.shrink();
    final engine = DanmakuKernelFactory.getKernelType();
    // The comments stay on the worker; the renderers that prepare layout take
    // their data from it (the version tells them when it changed).
    const list = <Map<String, dynamic>>[];
    final settings = c.settings;
    final outline = DanmakuOutlineStyle.values.byName(settings['danmaku.outlineStyle'] as String);
    final shadow = DanmakuShadowStyle.values.byName(settings['danmaku.shadowStyle'] as String);
    final font = settings['danmaku.fontFamily'] as String;
    final file = settings['danmaku.fontFilePath'] as String;
    final stacking = settings['danmaku.stacking'] == true;
    final merge = settings['danmaku.merge'] == true;
    final playing = _clock?.advancing ?? false;
    final opacity = c.number('danmaku.opacity');
    final area = c.number('danmaku.displayArea');
    Widget renderer;
    switch (engine) {
      case DanmakuRenderEngine.dfmPlus:
        renderer = DfmPlusOverlay(
          layoutBridge: _dfm, danmakuList: list, danmakuListVersion: c.version,
          playbackTimeMs: _time, currentTimeSeconds: _time.value / 1000,
          fontSize: c.fontSize, isVisible: c.visible, opacity: opacity,
          displayArea: area, timeOffset: c.offset, scrollDurationSeconds: c.scrollSeconds,
          allowStacking: stacking, mergeDanmaku: merge,
          customFontFamily: font, customFontFilePath: file,
          outlineWidth: c.number('danmaku.outlineWidth'), shadowStyle: shadow,
          trackGapRatio: c.number('danmaku.trackGap'),
          seekRevision: _seekRevision, clockRevision: _seekRevision,
          isPlaying: playing, playbackRate: _clock?.rate ?? 1);
      case DanmakuRenderEngine.next2:
        renderer = NipaPlayNext2Overlay(
          layoutBridge: _next2, danmakuList: list, danmakuListVersion: c.version,
          playbackTimeMs: _time, currentTimeSeconds: _time.value / 1000,
          fontSize: c.fontSize, isVisible: c.visible, opacity: opacity,
          displayArea: area, timeOffset: c.offset, scrollDurationSeconds: c.scrollSeconds,
          allowStacking: stacking, mergeDanmaku: merge,
          customFontFamily: font, customFontFilePath: file,
          outlineWidth: c.number('danmaku.outlineWidth'), shadowStyle: shadow);
      case DanmakuRenderEngine.cpu:
      case DanmakuRenderEngine.gpu:
        renderer = _PositionedRenderer(playback: p, time: _time,
            gpu: engine == DanmakuRenderEngine.gpu);
      case DanmakuRenderEngine.canvas:
      case DanmakuRenderEngine.nipaplayNext:
        // These legacy renderers own their layout. Feed only their current
        // clock window, selected by binary search (no full-list build scan).
        renderer = _WindowRenderer(controller: c, time: _time,
            version: c.version, builder: (window) {
          if (engine == DanmakuRenderEngine.canvas) {
            return CanvasDanmakuManager.createRenderer(
              fontSize: c.fontSize, opacity: opacity, displayArea: area,
              visible: c.visible, stacking: stacking, mergeDanmaku: merge,
              blockTopDanmaku: false, blockBottomDanmaku: false,
              blockScrollDanmaku: false, blockWords: const [],
              danmakuList: window, currentTime: _time.value / 1000 + c.offset,
              isPlaying: playing, playbackRate: _clock?.rate ?? 1,
              scrollDurationSeconds: c.scrollSeconds, seekRevision: _seekRevision,
              danmakuListVersion: c.version, timeOffsetSeconds: c.offset);
          }
          if (DanmakuKernelFactory.isNextPlusPlusEnabled) {
            return NipaPlayNextOverlay(
              danmakuList: window, playbackTimeMs: _time,
              currentTimeSeconds: _time.value / 1000,
              fontSize: c.fontSize, isVisible: c.visible, opacity: opacity,
              displayArea: area, timeOffset: c.offset, scrollDurationSeconds: c.scrollSeconds,
              allowStacking: stacking, mergeDanmaku: merge,
              customFontFamily: font, outlineStyle: outline, shadowStyle: shadow,
              isPlaying: playing, playbackRate: _clock?.rate ?? 1);
          }
          return NipaPlayNextOldOverlay(
            danmakuList: window, playbackTimeMs: _time,
            currentTimeSeconds: _time.value / 1000,
            fontSize: c.fontSize, isVisible: c.visible, opacity: opacity,
            displayArea: area, timeOffset: c.offset, scrollDurationSeconds: c.scrollSeconds,
            allowStacking: stacking, mergeDanmaku: merge,
            customFontFamily: font, outlineStyle: outline, shadowStyle: shadow,
            isPlaying: playing);
        });
    }
    return IgnorePointer(child: RepaintBoundary(child: renderer));
  }
}

/// For the renderers that lay out for themselves: the comments around the
/// clock, 4 minutes at a time, asked of the worker when the clock comes
/// within a minute of either end (or the list changes), and shown meanwhile
/// from the window held, if the clock is still inside it.
class _WindowRenderer extends StatefulWidget {
  const _WindowRenderer({required this.controller, required this.time,
    required this.version, required this.builder});
  final SessionDanmakuController controller;
  final ValueNotifier<double> time;
  final int version;
  final Widget Function(List<Map<String, dynamic>>) builder;
  @override
  State<_WindowRenderer> createState() => _WindowRendererState();
}

class _WindowRendererState extends State<_WindowRenderer> {
  List<Map<String, dynamic>> _window = const [];
  double _from = 0, _to = -1;
  int _version = -1, _asked = 0;
  bool _asking = false;

  void _ask(double seconds) {
    if (_asking) return;
    _asking = true;
    final id = ++_asked;
    final version = widget.version;
    final from = seconds - 90, to = seconds + 150;
    unawaited(widget.controller.window(from, to).then((window) {
      _asking = false;
      if (!mounted || id != _asked) return;
      setState(() {
        _window = window;
        _from = from;
        _to = to;
        _version = version;
      });
    }, onError: (Object error) {
      _asking = false;
      debugPrint('[NextDanmaku] window: $error');
    }));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<double>(
    valueListenable: widget.time,
    builder: (context, time, _) {
      final seconds = time / 1000;
      if (_version != widget.version || seconds - _from < 30 || _to - seconds < 60) {
        _ask(seconds);
      }
      final inside = seconds >= _from && seconds <= _to;
      return widget.builder(inside ? _window : const []);
    });
}

/// CPU text and the existing GPU shader consume the same prepared layout.
/// Only visible items are visited on the UI isolate; all-track assignment and
/// font metrics happen in the session's background worker.
class _PositionedRenderer extends StatefulWidget {
  const _PositionedRenderer({required this.playback, required this.time, required this.gpu});
  final SessionPlayback playback;
  final ValueNotifier<double> time;
  final bool gpu;
  @override
  State<_PositionedRenderer> createState() => _PositionedRendererState();
}

class _PositionedRendererState extends State<_PositionedRenderer> {
  late final DfmPlusLayoutBridge _bridge = DfmPlusLayoutBridge(
      prepareInBackground: (c) => widget.playback.danmaku.prepareLayout('dfm', c));
  bool _busy = false;
  Object? _last;

  @override
  void dispose() {
    _bridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final c = widget.playback.danmaku;
    final size = constraints.biggest;
    final merge = c.settings['danmaku.merge'] == true;
    final key = (size, merge, c.version, c.fontSize, c.number('danmaku.displayArea'),
      c.scrollSeconds, c.settings['danmaku.stacking'], c.number('danmaku.trackGap'),
      c.settings['danmaku.fontFilePath']);
    if (!_busy && _last != key) {
      _busy = true;
      final preparing = _bridge.configure(danmakuList: const [],
        danmakuListVersion: c.version, size: size, fontSize: c.fontSize,
        displayArea: c.number('danmaku.displayArea'), scrollDurationSeconds: c.scrollSeconds,
        allowStacking: c.settings['danmaku.stacking'] == true, mergeDanmaku: merge,
        trackGapRatio: c.number('danmaku.trackGap'),
        customFontFilePath: c.settings['danmaku.fontFilePath'] as String);
      unawaited(preparing.then((_) {
        if (mounted) setState(() { _last = key; _busy = false; });
      }, onError: (Object error) {
        _busy = false;
        debugPrint('[NextDanmaku] layout: $error');
      }));
    }
    return ValueListenableBuilder<double>(valueListenable: widget.time,
      builder: (context, ms, _) {
        if (!c.visible) return const SizedBox.shrink();
        final positioned = _bridge.layout(ms / 1000 + c.offset);
        if (widget.gpu) return GPUDanmakuOverlay(
          positionedDanmaku: positioned, isPlaying: widget.playback.playIntent,
          config: GPUDanmakuConfig(fontSize: c.fontSize,
              screenUsageRatio: c.number('danmaku.displayArea'),
              scrollScreensPerSecond: 1 / c.scrollSeconds),
          isVisible: c.visible, opacity: c.number('danmaku.opacity'),
          currentTime: ms / 1000 + c.offset);
        return Stack(clipBehavior: Clip.hardEdge, children: [
          for (final item in positioned) Positioned(left: item.x, top: item.y,
            child: const CpuDanmakuTextRenderer().build(context, item.content,
                c.fontSize, c.number('danmaku.opacity'))),
        ]);
      });
  });
}

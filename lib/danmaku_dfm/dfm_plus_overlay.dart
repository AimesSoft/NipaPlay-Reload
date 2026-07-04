import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_emoji_pipeline.dart';
import 'package:nipaplay/danmaku_next/next2_overlay_viewport.dart';
import 'package:nipaplay/danmaku_next/next2_texture_bridge.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

import 'dfm_plus_layout_bridge.dart';

class DfmPlusOverlay extends StatefulWidget {
  const DfmPlusOverlay({
    super.key,
    required this.danmakuList,
    required this.danmakuListVersion,
    required this.playbackTimeMs,
    required this.currentTimeSeconds,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
    required this.displayArea,
    required this.timeOffset,
    required this.scrollDurationSeconds,
    required this.allowStacking,
    required this.mergeDanmaku,
    required this.customFontFamily,
    required this.customFontFilePath,
    required this.outlineWidth,
    required this.shadowStyle,
    required this.trackGapRatio,
    this.maxQuantity,
    this.maxLinesPerType,
    this.blockWords = const [],
    this.onLayoutCalculated,
    required this.isPlaying,
    required this.playbackRate,
  });

  final List<Map<String, dynamic>> danmakuList;
  final int danmakuListVersion;
  final ValueListenable<double> playbackTimeMs;
  final double currentTimeSeconds;
  final double fontSize;
  final bool isVisible;
  final double opacity;
  final double displayArea;
  final double timeOffset;
  final double scrollDurationSeconds;
  final bool allowStacking;
  final bool mergeDanmaku;
  final String customFontFamily;
  final String customFontFilePath;
  final double outlineWidth;
  final DanmakuShadowStyle shadowStyle;
  final double trackGapRatio;
  final int? maxQuantity;
  final int? maxLinesPerType;
  final List<String> blockWords;
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;
  final bool isPlaying;
  final double playbackRate;

  @override
  State<DfmPlusOverlay> createState() => _DfmPlusOverlayState();
}

class _DfmPlusOverlayState extends State<DfmPlusOverlay>
    with SingleTickerProviderStateMixin {
  final DfmPlusLayoutBridge _bridge = DfmPlusLayoutBridge();
  final Next2TextureBridge _textureBridge = Next2TextureBridge();
  final Next2EmojiPipeline _emojiPipeline = Next2EmojiPipeline();

  Size _layoutSize = Size.zero;

  bool _updateScheduled = false;
  bool _updateInFlight = false;
  bool _updateQueued = false;

  bool _forceLayout = false;

  // Optimized texture update state: avoid redundant per-frame async calls
  // when texture ID is already stable. Only re-acquire when size changes.
  int _lastTextureWidth = 0;
  int _lastTextureHeight = 0;
  String _lastTextureSurfaceId = '';

  int? _textureId;
  bool _textureReady = false;
  String _surfaceId = 'dfm-default';
  double _lastDevicePixelRatio = 1.0;

  /// Tracks whether the native scene is currently empty. Lets us skip the
  /// per-vsync JSON-encode + MethodChannel hop when there are no visible
  /// danmaku: we push ONE empty setFrame to clear the previous frame, then
  /// short-circuit subsequent empty frames until content returns. Big
  /// battery/CPU win on quiet scenes and low-end devices. Reset to false
  /// on any non-empty frame or a non-fresh texture re-acquire.
  bool _sceneCleared = false;

  /// Reference layout width (px) for scroll-duration normalization (P2-12).
  /// Danmaku scroll duration scales with layout width relative to this, so
  /// the on-screen pixel velocity (px/s) stays roughly constant across
  /// device sizes instead of making danmaku fly faster on wider screens.
  /// 1280px = typical 16:9 landscape player — so common desktop/landscape
  /// windows land near scale 1.0 (no perceptible change from the old fixed
  /// 10s), while ultra-wide screens slow modestly and narrow windows speed
  /// up modestly. Clamp bounds keep the correction gentle.
  static const double _refLayoutWidth = 1280.0;
  static const double _scrollDurationScaleMin = 0.9;
  static const double _scrollDurationScaleMax = 1.3;

  /// Effective scroll duration = base × (layoutWidth / refWidth), clamped.
  /// A 1280px landscape window → 1.0 (unchanged); 1920px → 1.3 (mildly
  /// slower, vs the old un-scaled ~1.5× px/s fly-by); 900px → 0.9 (mildly
  /// faster). Keeps the familiar speed on common screens while taming the
  /// wide-screen fly-by.
  double _scaledScrollDuration() {
    if (_layoutSize.width <= 0) {
      return widget.scrollDurationSeconds;
    }
    final scale = (_layoutSize.width / _refLayoutWidth)
        .clamp(_scrollDurationScaleMin, _scrollDurationScaleMax)
        .toDouble();
    return widget.scrollDurationSeconds * scale;
  }

  // ── Wall-clock display-time model ──
  // Keep a continuously advancing display media time that is driven by the
  // real vsync wall-clock delta, not by every coarse playbackTimeMs tick.
  //
  //   displayMediaTime += wallDt * playbackRate
  //
  // playbackTimeMs is used only to correct drift (or snap on seek), instead of
  // re-anchoring on every media-clock tick. This avoids quantizing 120Hz motion
  // back to the media clock's lower update rate, which looks like a sticky /
  // 60Hz-ish texture movement even when frames are being produced at 120Hz.
  final Stopwatch _wallClock = Stopwatch()..start();

  /// Wall time captured at the vsync callback entry point (not inside
  /// _runUpdateLoop which includes _tryUpdateTexture latency). Using the
  /// vsync-stamped time for dt computation prevents the async GPU submission
  /// latency from distorting the frame interval measurement.
  int _vsyncWallUs = 0;

  /// Continuous media time used for layout. Advances by real wall-clock dt at
  /// EXACTLY playbackRate — the rate is never modulated, so danmaku on-screen
  /// speed is always consistent. It is kept from running ahead of the
  /// authoritative media clock by a ceiling (see _aheadToleranceSec) so that
  /// during buffering the danmaku follow the (slowed/held) media clock instead
  /// of running ahead and snapping back, and it snaps forward on seeks.
  double _displayMediaTime = 0.0;

  /// Wall-clock microseconds of the previous display-time update.
  int _lastDisplayWallUs = 0;

  /// Whether _displayMediaTime has been initialized from playbackTimeMs.
  bool _displayTimeInitialized = false;

  /// Per-frame wall dt cap. Prevents a long app stall/backgrounding event from
  /// jumping danmaku far ahead; playbackTimeMs will snap/correct us afterward.
  static const double _maxFrameDtSec = 0.2;

  /// Ceiling tolerance: the display clock may run ahead of the authoritative
  /// media clock by at most this much. During buffering / seek-settle the media
  /// clock advances slower than wall-clock (the upstream smooth clock is pulled
  /// back toward the stalled player position), so the display clock would
  /// otherwise race ahead and then get yanked back by a backward snap every
  /// ~150ms — the visible "forward a bit, back a little" oscillation. The
  /// ceiling makes the display clock gently follow the media clock's actual
  /// (slowed) rate instead: danmaku slow / freeze with the video. Must exceed
  /// one frame of wall-clock advance (dt*rate ≈ 17ms at 60Hz) so it never
  /// binds during normal in-sync playback, and stay below _snapThresholdSec.
  static const double _aheadToleranceSec = 0.05;

  /// Forward drift above this (but below _hardResyncThresholdSec) is corrected
  /// by a one-shot position snap to the media clock — NOT by modulating the
  /// rate. Because layout is a pure function of time (x = width - speed * (t -
  /// item.time)), a snap translates to a single-frame horizontal shift of
  /// on-screen danmaku (sub-pixel-imperceptible for small drift at typical
  /// scroll speeds) while the per-frame advance rate — i.e. the visible speed
  /// — stays exactly playbackRate. Backward drift (display ahead of media) is
  /// NOT snapped — the _aheadToleranceSec ceiling handles it continuously, and
  /// a backward snap was the source of the buffering oscillation. Below this
  /// threshold, drift is ignored to preserve smooth per-vsync motion.
  static const double _snapThresholdSec = 0.15;

  /// Treat very large forward drift as seek and snap immediately (resets the
  /// wall-clock baseline too). Large backward drift (loop restart) is handled
  /// by the ceiling pulling the display clock back to mediaTime + tolerance.
  static const double _hardResyncThresholdSec = 1.0;

  // ── Submit-rate throttle (P1-4) ──
  // On high-refresh panels (>60Hz) the Dart layout+setFrame pipeline is
  // capped at 60Hz; the native renderer interpolates scroll motion between
  // submissions, so motion stays smooth at the display rate while Dart CPU
  // work is halved on 120Hz screens. dt/anchor still advance every vsync
  // (cheap), so skipped frames lose no time precision. 0 = no throttle
  // (≤60Hz panels or refresh-rate detection unavailable).
  int _lastSubmitWallUs = 0;
  int _minSubmitIntervalUs = 0;
  double _cachedRefreshRate = 0.0;

  /// No GPU submission throttle needed — the Rust engine's 16ms tick loop
  /// naturally drains the mpsc queue (try_recv after first recv_timeout),
  /// always rendering the latest submitted frame. Submitting every vsync
  /// frame ensures the engine always has fresh data; throttling introduces
  /// phase-drift between the Dart vsync and engine tick, causing stutter.

  /// vsync-driven animation controller — fires _queueUpdate at display refresh
  /// rate (60/120Hz) so wall-clock dt is computed every vsync frame.
  late final AnimationController _vsyncController;

  @override
  void initState() {
    super.initState();
    _surfaceId = 'dfm-${identityHashCode(this)}';
    _lastTextureSurfaceId = _surfaceId;

    _vsyncController = AnimationController(
      vsync: this,
      duration: const Duration(days: 365),
    );
    _vsyncController.addListener(_queueUpdate);
    widget.playbackTimeMs.addListener(_queueUpdate);

    if (widget.isVisible && widget.isPlaying) {
      _vsyncController.repeat();
    }
  }

  @override
  void dispose() {
    widget.playbackTimeMs.removeListener(_queueUpdate);
    _vsyncController.removeListener(_queueUpdate);
    _vsyncController.dispose();
    _bridge.dispose();
    _textureBridge.disposeSurface(_surfaceId);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DfmPlusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.danmakuListVersion != widget.danmakuListVersion ||
        oldWidget.allowStacking != widget.allowStacking ||
        oldWidget.mergeDanmaku != widget.mergeDanmaku ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.displayArea != widget.displayArea ||
        oldWidget.scrollDurationSeconds != widget.scrollDurationSeconds ||
        oldWidget.customFontFamily != widget.customFontFamily ||
        oldWidget.customFontFilePath != widget.customFontFilePath ||
        oldWidget.outlineWidth != widget.outlineWidth ||
        oldWidget.shadowStyle != widget.shadowStyle ||
        oldWidget.trackGapRatio != widget.trackGapRatio ||
        oldWidget.maxQuantity != widget.maxQuantity ||
        oldWidget.maxLinesPerType != widget.maxLinesPerType ||
        !listEquals(oldWidget.blockWords, widget.blockWords)) {
      _forceLayout = true;
      _queueUpdate();
    } else if (oldWidget.isVisible != widget.isVisible) {
      // Visibility only affects display layer, not layout — skip full reconfigure
      _queueUpdate();
    }
    // opacity changes are handled in build() via Opacity widget, no update needed

    if (oldWidget.playbackTimeMs != widget.playbackTimeMs) {
      oldWidget.playbackTimeMs.removeListener(_queueUpdate);
      widget.playbackTimeMs.addListener(_queueUpdate);
      _resetDisplayTimeToMedia();
      _queueUpdate();
    }

    // ── AnimationController lifecycle ──
    final shouldAnimate = widget.isVisible && widget.isPlaying;
    if (shouldAnimate && !_vsyncController.isAnimating) {
      _vsyncController.repeat();
      // Reset on resume so wall dt does not include the paused duration. The
      // next frame starts from the current media time and then advances by the
      // true display-frame dt — no slow convergence period.
      _resetDisplayTimeToMedia();
    } else if (!shouldAnimate && _vsyncController.isAnimating) {
      _vsyncController.stop();
    }

    // ── Playback rate change: reset wall dt baseline ──
    if (oldWidget.playbackRate != widget.playbackRate) {
      _resetDisplayTimeToMedia();
    }

    // ── isPlaying transition: reset wall dt baseline ──
    if (oldWidget.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _resetDisplayTimeToMedia();
      }
    }
  }

  /// Snap the continuous display time to the current media time and reset the
  /// wall-clock baseline. Used for first frame, seek, resume, and clock source
  /// changes. This is a hard reset, not the normal playback correction path.
  void _resetDisplayTimeToMedia() {
    _displayMediaTime = widget.playbackTimeMs.value / 1000.0;
    _lastDisplayWallUs = _wallClock.elapsedMicroseconds;
    _displayTimeInitialized = true;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final constrainedSize = Size(
          constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : constraints.minWidth,
          constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : constraints.minHeight,
        );
        final layoutSize = Next2OverlayViewport.resolveLayoutSize(
          context,
          constraints,
        );
        if (layoutSize.isEmpty) {
          return const SizedBox.expand();
        }

        if (_layoutSize != layoutSize) {
          final oldSize = _layoutSize;
          _layoutSize = layoutSize;
          _queueUpdate();
          // Sub-pixel jitter (e.g. Windows focus-loss) should not trigger
          // the async configure() pipeline. Only force re-prepare when the
          // layout size change is meaningful (>= 1 logical pixel) or this
          // is the initial layout.
          if (oldSize.isEmpty ||
              (oldSize.width - layoutSize.width).abs() >= 2.0 ||
              (oldSize.height - layoutSize.height).abs() >= 2.0) {
            _forceLayout = true;
          }
        }

        final dpr =
            MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;

        // ── Detect display refresh rate for submit-rate throttling (P1-4) ──
        // On >60Hz panels we cap Dart layout+setFrame at 60Hz (native renderer
        // interpolates the rest). refreshRate may be unavailable/0 on some
        // platforms or older Flutter; in that case stay at 0 = no throttle.
        _maybeUpdateSubmitInterval();
        // DPR can micro-jitter on Windows when the window loses focus or the
        // user clicks the taskbar (didChangeMetrics fires with a slightly
        // different value). DPR only affects the texture's pixel size, not the
        // danmaku layout (layout uses logical pixels). So we update the cached
        // DPR for the next texture-acquire path, but we do NOT trigger
        // _forceLayout — the texture path will pick up the new DPR on its own
        // and re-acquire a different-sized texture if needed. Re-running
        // prepareLayout here would re-execute overwriteInsert and cause
        // visible flicker.
        if ((_lastDevicePixelRatio - dpr).abs() > 0.001) {
          _lastDevicePixelRatio = dpr;
          // DPR change may affect pixelWidth/pixelHeight → needsNewTexture.
          // Queue an update so the texture size is re-evaluated, but do NOT
          // set _forceLayout (that would re-run configure/overwriteInsert).
          _queueUpdate();
        }

        final hasTexture =
            _textureReady &&
            _textureId != null &&
            Next2TextureBridge.isSupported;

        final needsSupersample = context
            .watch<SettingsProvider>()
            .danmakuSupersample;
        final filterQuality = needsSupersample > 0.0
            ? FilterQuality.low
            : FilterQuality.none;
        final Widget content = hasTexture
            ? Texture(textureId: _textureId!, filterQuality: filterQuality)
            : const SizedBox.expand();

        return Next2OverlayViewport.buildLayer(
          layoutSize: layoutSize,
          constrainedSize: constrainedSize,
          child: Opacity(
            opacity: widget.opacity.clamp(0.0, 1.0).toDouble(),
            child: content,
          ),
        );
      },
    );
  }

  /// Detect the display refresh rate and set the submit interval accordingly.
  /// Do NOT throttle 120Hz ProMotion panels: throttling them to ~60Hz makes the
  /// whole texture layer update every other vsync, perceived as all scrolling
  /// danmaku synchronously micro-stuttering. Only keep the protective 60Hz cap
  /// for very-high-refresh panels (>120Hz). ≤120Hz or undetectable → no throttle.
  void _maybeUpdateSubmitInterval() {
    double refreshRate = 0.0;
    try {
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        refreshRate = views.first.display.refreshRate;
      }
    } catch (_) {
      refreshRate = 0.0;
    }
    if (refreshRate == _cachedRefreshRate) {
      return;
    }
    _cachedRefreshRate = refreshRate;
    // iPad ProMotion reports ~120Hz. Keep that unthrottled; otherwise texture
    // updates land every other vsync and the entire danmaku layer appears to
    // hiccup in sync. Use a small margin for platform-reported 120.0x values.
    _minSubmitIntervalUs = refreshRate > 121.0 ? 16000 : 0;
    // Reset so the next frame after a rate change submits immediately.
    _lastSubmitWallUs = 0;
  }

  void _queueUpdate() {
    // Capture wall time at vsync callback entry BEFORE any bail-out checks.
    // If a new vsync fires while _tryUpdateTexture is in-flight, we still
    // need the latest timestamp for the next loop iteration's dt computation.
    _vsyncWallUs = _wallClock.elapsedMicroseconds;
    _updateQueued = true;
    if (_updateScheduled || _updateInFlight) {
      return;
    }
    _updateScheduled = true;
    Future.microtask(_runUpdateLoop);
  }

  /// Update loop: layout is synchronous (Dart-side), so the per-frame
  /// position computation has zero async overhead. Only configure() and
  /// texture upload remain async.
  ///
  /// Uses wall-clock time interpolation: accumulates dt since last
  /// playbackTimeMs update to create a vsync-rate smooth time value.
  /// The existing absolute-position layout() handles the rest naturally
  /// — no per-item drift correction needed.
  Future<void> _runUpdateLoop() async {
    _updateScheduled = false;
    if (_updateInFlight) {
      return;
    }

    _updateInFlight = true;
    try {
      while (mounted && _updateQueued) {
        _updateQueued = false;

        if (_layoutSize.isEmpty) {
          continue;
        }

        // ── Continuous display-time update ──
        // _vsyncWallUs is captured in _queueUpdate() (vsync callback entry),
        // NOT at the top of _runUpdateLoop — otherwise async texture latency
        // would inflate the measured frame interval.
        final currentWallUs = _vsyncWallUs;
        final double mediaTime = widget.playbackTimeMs.value / 1000.0;

        if (!_displayTimeInitialized) {
          _displayMediaTime = mediaTime;
          _lastDisplayWallUs = currentWallUs;
          _displayTimeInitialized = true;
        }

        // Advance by real wall-clock frame time at EXACTLY playbackRate — never
        // modulated by drift. This is what gives 120Hz panels 120 distinct
        // positions and keeps danmaku speed constant during normal playback.
        if (widget.isPlaying && currentWallUs > _lastDisplayWallUs) {
          final deltaUs = currentWallUs - _lastDisplayWallUs;
          final dt = (deltaUs / 1000000.0).clamp(0.0, _maxFrameDtSec);
          _displayMediaTime += dt * widget.playbackRate;
        }
        _lastDisplayWallUs = currentWallUs;

        // ── Ceiling: don't let the display clock run ahead of the media clock ──
        // During buffering / seek-settle the media clock advances SLOWER than
        // wall-clock (the upstream smooth clock is periodically pulled back
        // toward the stalled player position). Without this ceiling the display
        // clock races ahead, drift passes _snapThresholdSec, and the backward
        // snap yanks it back — repeating every ~150ms as a visible "forward a
        // bit, back a little" oscillation. The ceiling makes the display clock
        // gently follow the media clock's actual rate instead, so danmaku slow
        // or freeze with the video. Never binds during normal in-sync playback
        // (drift stays within one frame ≪ _aheadToleranceSec).
        if (_displayMediaTime > mediaTime + _aheadToleranceSec) {
          _displayMediaTime = mediaTime + _aheadToleranceSec;
        }

        // ── Forward snap only (seek catch-up) — never a backward snap ──
        // A snap is a single-frame position jump; the per-frame advance rate
        // (the visible speed) stays at playbackRate. Only forward drift (media
        // clock jumped ahead) is snapped; backward drift is already bounded by
        // the ceiling above, and a backward snap was the oscillation source.
        final drift = mediaTime - _displayMediaTime; // >= -_aheadToleranceSec
        if (drift >= _hardResyncThresholdSec) {
          // Large seek — snap and reset the wall-clock baseline.
          _displayMediaTime = mediaTime;
          _lastDisplayWallUs = currentWallUs;
        } else if (drift > _snapThresholdSec) {
          // Small/medium forward seek — snap to the media clock.
          _displayMediaTime = mediaTime;
        }

        final double interpolatedTime = _displayMediaTime + widget.timeOffset;

        // If config changed, run async configure first.
        final bool mustSubmit = _forceLayout;
        if (mustSubmit) {
          _forceLayout = false;
          await _bridge.configure(
            danmakuList: widget.danmakuList,
            danmakuListVersion: widget.danmakuListVersion,
            size: _layoutSize,
            fontSize: widget.fontSize,
            displayArea: widget.displayArea,
            scrollDurationSeconds: _scaledScrollDuration(),
            allowStacking: widget.allowStacking,
            mergeDanmaku: widget.mergeDanmaku,
            maxQuantity: widget.maxQuantity,
            maxLinesPerType: widget.maxLinesPerType,
            trackGapRatio: widget.trackGapRatio,
            outlineWidth: widget.outlineWidth,
            customFontFamily: widget.customFontFamily,
            customFontFilePath: widget.customFontFilePath,
            blockWords: widget.blockWords,
          );
          if (!mounted) {
            return;
          }
          // Reset after configure so motion resumes from the current media time
          // with a fresh wall-clock baseline.
          _resetDisplayTimeToMedia();
        }

        // ── Submit-rate throttle (P1-4) ──
        // On >60Hz panels, skip the layout+setFrame work on vsync frames
        // that fall within 16ms of the last submission. dt and anchor still
        // advanced above, so time precision is preserved; the native renderer
        // interpolates scroll motion between submissions. Force-configure
        // frames always submit. The first frame after (re)start has a huge
        // gap → submits immediately.
        if (!mustSubmit &&
            _minSubmitIntervalUs > 0 &&
            _lastSubmitWallUs != 0 &&
            currentWallUs - _lastSubmitWallUs < _minSubmitIntervalUs) {
          continue;
        }
        _lastSubmitWallUs = currentWallUs;

        // ── Layout with interpolated time ──
        // The interpolatedTime advances smoothly every vsync frame.
        // layout() computes absolute positions from it naturally:
        //   x = width - speed * (interpolatedTime - item.time)
        // We submit every vsync frame — the Rust engine's 16ms tick loop
        // drains its mpsc queue and always renders the latest submission.
        final frame = _bridge.layout(interpolatedTime);

        await _tryUpdateTexture(frame);
        widget.onLayoutCalculated?.call(frame);
      }
    } catch (_) {
      // Keep overlay alive and retry on next frame.
      _queueUpdate();
    } finally {
      _updateInFlight = false;
    }
  }

  Future<bool> _tryUpdateTexture(List<PositionedDanmakuItem> frame) async {
    if (!Next2TextureBridge.isSupported || _layoutSize.isEmpty) {
      return false;
    }

    final locale = Localizations.maybeLocaleOf(context);

    // Use cached DPR from build() instead of reading platformDispatcher.views
    // directly. On Windows, DPR can micro-jitter when the window loses focus,
    // causing pixelWidth/pixelHeight to oscillate by ±1 pixel, which triggers
    // needsNewTexture → ensureTexture → isNewEngine → resetScene → flicker.
    final dpr = _lastDevicePixelRatio;

    final supersample = context
        .read<SettingsProvider>()
        .danmakuSupersample;
    // True supersampling: texture pixels = backing × supersample, where
    // backing = layout × dpr. Flutter downsamples the texture to the backing
    // store on display, which is what produces the anti-aliased edges (the
    // whole point of supersampling). So the ratio MUST be dpr × supersample.
    //
    // This means on a DPR=2 panel, 2x supersample renders at 4× backing
    // (16× texture area) — a real cost. That cost is the price of real
    // supersampling; the 1.5x setting exists as a lighter alternative. We do
    // NOT collapse it to max(dpr, ss) — that would make 1.5x/2x silently no-op
    // on DPR≥2 devices (rendering == backing, zero AA benefit), defeating the
    // setting. The clamp only guards extreme cases (e.g. DPR=4 + 2x = 8×).
    final baseDpr = dpr.isFinite ? dpr.clamp(1.0, 4.0).toDouble() : 1.0;
    final ss = supersample > 0.0 ? supersample : 1.0;
    final double pixelRatio = (baseDpr * ss).clamp(1.0, 6.0);

    final int pixelWidth = (_layoutSize.width * pixelRatio)
        .round()
        .clamp(1, 16384)
        .toInt();
    final int pixelHeight = (_layoutSize.height * pixelRatio)
        .round()
        .clamp(1, 16384)
        .toInt();

    // Optimized: only re-acquire texture if size changed (avoids redundant
    // ensureTexture await on every frame when texture ID is already stable).
    // Also apply a pixel threshold: Windows DPR micro-jitter on focus loss can
    // cause pixelWidth/pixelHeight to oscillate by ±1 pixel, which would
    // trigger a full texture/engine rebuild (isNewEngine → resetScene → flicker).
    // Only rebuild when the pixel size change is significant (>=2 pixels).
    final int pwDelta = (pixelWidth - _lastTextureWidth).abs();
    final int phDelta = (pixelHeight - _lastTextureHeight).abs();
    bool needsNewTexture =
        _textureId == null ||
        (pwDelta >= 2) ||
        (phDelta >= 2) ||
        _surfaceId != _lastTextureSurfaceId;

    if (needsNewTexture) {
      _lastTextureWidth = pixelWidth;
      _lastTextureHeight = pixelHeight;
      _lastTextureSurfaceId = _surfaceId;

      final info = await _textureBridge.ensureTexture(
        surfaceId: _surfaceId,
        width: pixelWidth,
        height: pixelHeight,
      );

      if (info == null) {
        if (_textureReady || _textureId != null) {
          setState(() {
            _textureReady = false;
            _textureId = null;
          });
        }
        return false;
      }

      if (!mounted) {
        return false;
      }

      if (_textureId != info.textureId || !_textureReady) {
        setState(() {
          _textureId = info.textureId;
          _textureReady = true;
        });
      }

      // When isNewEngine is true, the Rust engine was recreated or resized.
      // Do NOT call resetScene() here — it clears the glyph atlas, causing
      // all characters to need re-rasterization (MSDF generation), which
      // blocks the render thread and causes a visible black flash.
      // Instead, just mark the emoji atlas dirty and let the next setFrame
      // call naturally render new content on top of the fresh engine.
      if (info.isNewEngine) {
        _emojiPipeline.markAtlasDirty();
        // A fresh engine starts with an empty scene, so we can skip the
        // clearing setFrame below if the frame is also empty.
        _sceneCleared = true;
      } else {
        // Same engine, texture re-acquired (surface/size change) — it may
        // still hold the last pushed scene, so force a re-evaluation.
        _sceneCleared = false;
      }
    }

    // ── Empty-frame short-circuit ──
    // With no visible danmaku, skip the per-vsync buildPayload (allocation)
    // + jsonEncode + MethodChannel hop. We push exactly ONE empty setFrame
    // to clear the previous frame's content, then short-circuit until
    // content returns. The scene-cleared state is tracked so we never leave
    // stale danmaku on screen and never re-clear an already-empty scene.
    if (frame.isEmpty) {
      if (_sceneCleared) {
        return true; // already clear — nothing to submit this vsync
      }
      // Fall through: send one empty setFrame to clear the scene.
    } else {
      _sceneCleared = false;
    }

    final widthScale = pixelWidth > 0 ? pixelWidth / _layoutSize.width : 1.0;
    final heightScale = pixelHeight > 0
        ? pixelHeight / _layoutSize.height
        : 1.0;
    final fontScale = ((widthScale + heightScale) * 0.5)
        .clamp(0.25, 8.0)
        .toDouble();

    final prepared = await _emojiPipeline.buildPayload(
      items: frame,
      fontSize: widget.fontSize,
      scaleX: widthScale,
      scaleY: heightScale,
      fontScale: fontScale,
      locale: locale,
      playbackRate: widget.playbackRate,
    );

    final pushed = await _textureBridge.setFrame(
      items: frame,
      fontSize: widget.fontSize,
      outlineWidth: widget.outlineWidth,
      shadowStyle: widget.shadowStyle,
      opacity: 1.0,
      customFontFamily: widget.customFontFamily,
      customFontFilePath: widget.customFontFilePath,
      scaleX: widthScale,
      scaleY: heightScale,
      fontScale: fontScale,
      playbackRate: widget.playbackRate,
      framePayload: prepared.toJson(),
    );

    if (pushed) {
      _emojiPipeline.markAtlasSynced();
      if (frame.isEmpty) {
        _sceneCleared = true; // scene now confirmed empty
      }
    } else {
      _emojiPipeline.markAtlasDirty();
    }

    return pushed;
  }
}

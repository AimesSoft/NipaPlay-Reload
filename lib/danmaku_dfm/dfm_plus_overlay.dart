import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_emoji_pipeline.dart';
import 'package:nipaplay/danmaku_next/next2_overlay_viewport.dart';
import 'package:nipaplay/danmaku_next/next2_texture_bridge.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
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
  bool _contentHotReload = false;

  // Optimized texture update state: avoid redundant per-frame async calls
  // when texture ID is already stable. Only re-acquire when size changes.
  int _lastTextureWidth = 0;
  int _lastTextureHeight = 0;
  String _lastTextureSurfaceId = '';

  int? _textureId;
  bool _textureReady = false;
  String _surfaceId = 'dfm-default';
  double _lastDevicePixelRatio = 1.0;
  double _danmakuSupersample = 0.0;
  Locale? _danmakuLocale;

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

  // ── Vsync display-time model ──
  // Keep a continuously advancing display media time that is driven by the
  // the Ticker's vsync delta, not by every coarse playbackTimeMs tick.
  //
  //   displayMediaTime += wallDt * playbackRate
  //
  // playbackTimeMs is used only to correct drift (or snap on seek), instead of
  // re-anchoring on every media-clock tick. This avoids quantizing 120Hz motion
  // back to the media clock's lower update rate, which looks like a sticky /
  // 60Hz-ish texture movement even when frames are being produced at 120Hz.
  final Stopwatch _timingClock = Stopwatch()..start();

  /// Ticker elapsed captured at the vsync callback entry point. It remains
  /// independent of async layout, emoji and GPU submission latency.
  int _vsyncElapsedUs = 0;

  /// Continuous media time used for layout. Advances by vsync timeline dt at
  /// EXACTLY playbackRate — monotonic non-decreasing between snaps, never
  /// modulated, so danmaku on-screen speed is always consistent and matches the
  /// decoder (which always plays at playbackRate). The authoritative media
  /// clock (playbackTimeMs) is used only to snap on seeks/loops — NOT to pace
  /// the display clock, because the upstream progressively corrects
  /// playbackTimeMs toward the decoder (slowing/freezing it after a
  /// seek/buffer), and following or yanking back to that held clock caused the
  /// "creep slowly" and "scroll-to-middle-then-snap-back" (twitch) symptoms.
  double _displayMediaTime = 0.0;

  /// Wall-clock microseconds of the previous display-time update.
  int _lastDisplayVsyncUs = 0;

  /// Whether _displayMediaTime has been initialized from playbackTimeMs.
  bool _displayTimeInitialized = false;

  /// Last observed media-clock value (seconds). Used to detect actual mediaTime
  /// *jumps* (seek / loop / backward seek) as opposed to mere drift, so the
  /// backward snap only fires on a real backward jump — never on accumulated
  /// backward drift, which is just the display clock pacing the decoder while
  /// the media clock is held during an upstream correction.
  double _lastMediaTimeSec = double.nan;

  /// Per-frame vsync dt cap. Prevents a long app stall/backgrounding event from
  /// jumping danmaku far ahead; playbackTimeMs will snap/correct us afterward.
  static const double _maxFrameDtSec = 0.2;

  /// Drift / mediaTime-jump threshold for a one-shot position snap. Because
  /// layout is a pure function of time (x = width - speed * (t - item.time)),
  /// a snap is a single-frame horizontal shift of on-screen danmaku while the
  /// per-frame advance rate — the visible speed — stays exactly playbackRate.
  /// Forward snaps fire on drift (displayTime fell behind mediaTime = seek);
  /// backward snaps fire only on a mediaTime backward *jump* (loop / backward
  /// seek), never on accumulated backward drift. Below this, drift is ignored
  /// (smooth per-vsync motion).
  static const double _snapThresholdSec = 0.15;

  /// Large seek/loop threshold: a snap of this magnitude also resets the
  /// vsync baseline (the overlay may not have ticked during the seek).
  static const double _hardResyncThresholdSec = 1.0;

  /// Lookahead window (seconds) for rolling glyph prefetch - danmaku entering
  /// the screen within this window have their chars async-rasterized so they
  /// hit the atlas before display. 3s balances worker throughput vs coverage.
  static const double _prefetchLookaheadSec = 3.0;

  /// First-frame prefetch window after configure. Kept equal to the rolling
  /// window (3s) - a larger first-frame window (e.g. 15s) caused a long
  /// first-frame stall because all those chars hit the synchronous fallback
  /// before workers finished. 3s covers the on-screen burst; the rolling 3s
  /// lookahead picks up the rest. Combined with the ensureTexture-time early
  /// prefetch (isInitialPrefetch in _tryUpdateTexture), workers get a head
  /// start before the first draw.
  static const double _initialPrefetchLookaheadSec = 3.0;

  /// Whether the initial large-window prefetch has been done since the last
  /// configure. Reset to false when configure runs.
  bool _initialPrefetchDone = false;

  /// Ticker elapsed is the sole continuous motion clock. Unlike a Stopwatch
  /// sampled after async work, it represents the display's vsync timeline.
  late final Ticker _vsyncTicker;

  @override
  void initState() {
    super.initState();
    _surfaceId = 'dfm-${identityHashCode(this)}';
    _lastTextureSurfaceId = _surfaceId;

    _vsyncTicker = createTicker(_onVsync);
    widget.playbackTimeMs.addListener(_onPlaybackTimeChanged);

    if (widget.isVisible && widget.isPlaying) {
      _vsyncTicker.start();
    }
  }

  @override
  void dispose() {
    widget.playbackTimeMs.removeListener(_onPlaybackTimeChanged);
    _vsyncTicker.dispose();
    _bridge.dispose();
    _textureBridge.disposeSurface(_surfaceId);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DfmPlusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final contentChanged =
        oldWidget.danmakuListVersion != widget.danmakuListVersion;
    final layoutConfigChanged =
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
            !listEquals(oldWidget.blockWords, widget.blockWords);
    if (contentChanged || layoutConfigChanged) {
      // A content-only revision can atomically replace the prepared layout
      // without clearing the native scene or re-running first-frame prewarm.
      // Never downgrade an already-pending full reconfigure to a hot reload.
      if (!_forceLayout) {
        _contentHotReload = contentChanged && !layoutConfigChanged;
      } else if (layoutConfigChanged) {
        _contentHotReload = false;
      }
      _forceLayout = true;
      _queueUpdate();
    } else if (oldWidget.isVisible != widget.isVisible) {
      // Visibility only affects display layer, not layout — skip full reconfigure
      _queueUpdate();
    }
    // opacity changes are handled in build() via Opacity widget, no update needed

    if (oldWidget.playbackTimeMs != widget.playbackTimeMs) {
      oldWidget.playbackTimeMs.removeListener(_onPlaybackTimeChanged);
      widget.playbackTimeMs.addListener(_onPlaybackTimeChanged);
      _resetDisplayTimeToMedia();
      _queueUpdate();
    }

    // ── Ticker lifecycle ──
    final shouldAnimate = widget.isVisible && widget.isPlaying;
    if (shouldAnimate && !_vsyncTicker.isActive) {
      _vsyncElapsedUs = 0;
      _vsyncTicker.start();
      // Reset on resume so wall dt does not include the paused duration. The
      // next frame starts from the current media time and then advances by the
      // true display-frame dt — no slow convergence period.
      _resetDisplayTimeToMedia();
    } else if (!shouldAnimate && _vsyncTicker.isActive) {
      _vsyncTicker.stop();
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
  /// vsync baseline. Used for first frame, seek, resume, and clock source
  /// changes. This is a hard reset, not the normal playback correction path.
  void _resetDisplayTimeToMedia() {
    final mediaTime = widget.playbackTimeMs.value / 1000.0;
    _displayMediaTime = mediaTime;
    _lastDisplayVsyncUs = _vsyncElapsedUs;
    _lastMediaTimeSec = mediaTime;
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

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;
        final supersample =
            context.watch<SettingsProvider>().danmakuSupersample;
        final locale = Localizations.maybeLocaleOf(context);

        if (_danmakuSupersample != supersample) {
          _danmakuSupersample = supersample;
          _queueUpdate();
        }
        if (_danmakuLocale != locale) {
          _danmakuLocale = locale;
          _forceLayout = true;
          _queueUpdate();
        }

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

        final hasTexture = _textureReady &&
            _textureId != null &&
            Next2TextureBridge.isSupported;

        final filterQuality =
            supersample > 0.0 ? FilterQuality.low : FilterQuality.none;
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

  void _onVsync(Duration elapsed) {
    _vsyncElapsedUs = elapsed.inMicroseconds;
    _queueUpdate();
  }

  void _onPlaybackTimeChanged() {
    // During playback, the next vsync observes authoritative media time and
    // handles seek/drift. Do not create a second, off-vsync animation stream.
    if (!widget.isPlaying || !_vsyncTicker.isActive) {
      _queueUpdate();
    }
  }

  void _queueUpdate() {
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
  /// Uses the Ticker timeline: accumulates vsync dt since last
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
        final currentWallUs = _vsyncElapsedUs;
        final double mediaTime = widget.playbackTimeMs.value / 1000.0;

        if (!_displayTimeInitialized) {
          _displayMediaTime = mediaTime;
          _lastDisplayVsyncUs = currentWallUs;
          _lastMediaTimeSec = mediaTime;
          _displayTimeInitialized = true;
        }

        // Advance at EXACTLY playbackRate — monotonic non-decreasing, never
        // modulated. This is the decoder's rate, so danmaku stay aligned with
        // the actual video frame even while the upstream is progressively
        // correcting playbackTimeMs (slowing / freezing it toward the
        // decoder). Because the display clock paces the decoder, any drift
        // accumulated while the media clock is held returns to 0 on its own
        // when the decoder catches up — no backward correction needed.
        if (widget.isPlaying && currentWallUs > _lastDisplayVsyncUs) {
          final deltaUs = currentWallUs - _lastDisplayVsyncUs;
          final dt = (deltaUs / 1000000.0).clamp(0.0, _maxFrameDtSec);
          _displayMediaTime += dt * widget.playbackRate;
        }
        _lastDisplayVsyncUs = currentWallUs;

        // ── Snaps: one-shot position jumps, never rate modulation ──
        // A snap is a single-frame position jump; the per-frame advance rate
        // (the visible speed) stays at playbackRate.
        //
        // Forward snap on DRIFT: displayTime fell behind mediaTime (seek /
        // scrub forward). Drift-based is correct here because forward drift
        // only grows when mediaTime genuinely moved ahead.
        //
        // Backward snap on mediaTime JUMP (not drift): a real backward jump
        // (loop restart / backward seek). Backward drift is NOT snapped — it
        // accumulates when the display clock paces the decoder while mediaTime
        // is held during an upstream correction, and yanking it back repeatedly
        // was the "scroll to middle, jump back to right edge" twitch. Letting
        // it resolve on its own (decoder catches up) keeps displayMediaTime
        // monotonic between snaps.
        final drift = mediaTime - _displayMediaTime;
        if (drift > _snapThresholdSec) {
          _displayMediaTime = mediaTime;
          if (drift >= _hardResyncThresholdSec) {
            _lastDisplayVsyncUs = currentWallUs;
          }
        }
        final double mediaDelta = mediaTime - _lastMediaTimeSec;
        if (mediaDelta < -_snapThresholdSec) {
          _displayMediaTime = mediaTime;
          if (mediaDelta <= -_hardResyncThresholdSec) {
            _lastDisplayVsyncUs = currentWallUs;
          }
        }
        _lastMediaTimeSec = mediaTime;

        double interpolatedTime = _displayMediaTime + widget.timeOffset;

        // If config changed, run async configure first.
        final bool mustSubmit = _forceLayout;
        if (mustSubmit) {
          if (!mounted) {
            return;
          }
          final contentHotReload = _contentHotReload;
          _contentHotReload = false;
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
            locale: _danmakuLocale,
            blockWords: widget.blockWords,
          );
          if (!mounted) {
            return;
          }
          // Reset after configure so motion resumes from the current media time
          // with a fresh vsync baseline.
          _resetDisplayTimeToMedia();
          interpolatedTime = _displayMediaTime + widget.timeOffset;
          // Only a genuine renderer/layout configuration change needs the
          // initial empty-scene prewarm. Content hot reloads retain the scene
          // and atlas, then replace the visible frame atomically.
          if (!contentHotReload) {
            _initialPrefetchDone = false;
          }
        }

        // ── Layout with interpolated time ──
        // The interpolatedTime advances smoothly every vsync frame.
        // layout() computes absolute positions from it naturally:
        //   x = width - speed * (interpolatedTime - item.time)
        // We submit every available vsync frame. The in-flight gate coalesces
        // callbacks while native submission is busy and renders the latest time.
        final layoutStartUs = _timingClock.elapsedMicroseconds;
        final frame = _bridge.layout(interpolatedTime);
        final layoutMs =
            (_timingClock.elapsedMicroseconds - layoutStartUs) / 1000.0;

        // Lookahead prefetch: dispatch chars from danmaku entering the screen
        // in the next few seconds to the Rust MSDF workers (async), so glyphs
        // are ready in the atlas before display. First frame after configure
        // uses a large window to pre-warm the opening minute (OP/character
        // names); subsequent frames send only the small rolling delta.
        final bool isInitialPrefetch = !_initialPrefetchDone;
        final double prefetchLookahead = isInitialPrefetch
            ? _initialPrefetchLookaheadSec
            : _prefetchLookaheadSec;
        final String? prefetchChars =
            _bridge.prefetchChars(_displayMediaTime, prefetchLookahead);

        final submitStartUs = _timingClock.elapsedMicroseconds;
        await _tryUpdateTexture(
          frame,
          prefetchChars: prefetchChars,
          isInitialPrefetch: isInitialPrefetch,
        );
        final submitMs =
            (_timingClock.elapsedMicroseconds - submitStartUs) / 1000.0;
        SystemResourceMonitor().recordDfmFrameTimings(
          layoutMs: layoutMs,
          submitMs: submitMs,
        );
        _initialPrefetchDone = true;
        widget.onLayoutCalculated?.call(frame);
      }
    } catch (_) {
      // Keep overlay alive and retry on next frame.
      _queueUpdate();
    } finally {
      _updateInFlight = false;
    }
  }

  Future<bool> _tryUpdateTexture(
    List<PositionedDanmakuItem> frame, {
    String? prefetchChars,
    bool isInitialPrefetch = false,
  }) async {
    if (!Next2TextureBridge.isSupported || _layoutSize.isEmpty) {
      return false;
    }

    // Use cached DPR from build() instead of reading platformDispatcher.views
    // directly. On Windows, DPR can micro-jitter when the window loses focus,
    // causing pixelWidth/pixelHeight to oscillate by ±1 pixel, which triggers
    // needsNewTexture → ensureTexture → isNewEngine → resetScene → flicker.
    final dpr = _lastDevicePixelRatio;

    final supersample = _danmakuSupersample;
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

    final int pixelWidth =
        (_layoutSize.width * pixelRatio).round().clamp(1, 16384).toInt();
    final int pixelHeight =
        (_layoutSize.height * pixelRatio).round().clamp(1, 16384).toInt();

    // Optimized: only re-acquire texture if size changed (avoids redundant
    // ensureTexture await on every frame when texture ID is already stable).
    // Also apply a pixel threshold: Windows DPR micro-jitter on focus loss can
    // cause pixelWidth/pixelHeight to oscillate by ±1 pixel, which would
    // trigger a full texture/engine rebuild (isNewEngine → resetScene → flicker).
    // Only rebuild when the pixel size change is significant (>=2 pixels).
    final int pwDelta = (pixelWidth - _lastTextureWidth).abs();
    final int phDelta = (pixelHeight - _lastTextureHeight).abs();
    bool needsNewTexture = _textureId == null ||
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
    final heightScale =
        pixelHeight > 0 ? pixelHeight / _layoutSize.height : 1.0;
    final fontScale =
        ((widthScale + heightScale) * 0.5).clamp(0.25, 8.0).toDouble();

    // Texture 就绪后先投递首屏字符给 worker，再立即提交首帧。不要在这里
    // 固定等待：等待期间坐标会过期，并把传输延迟变化转换成水平抖动。
    String? effectivePrefetch = prefetchChars;
    if (isInitialPrefetch &&
        effectivePrefetch != null &&
        effectivePrefetch.isNotEmpty) {
      try {
        await _textureBridge.setFrame(
          items: const <PositionedDanmakuItem>[],
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
          motionMode: 'vsync_snapshot',
          framePayload: <String, dynamic>{
            'items': const <Map<String, dynamic>>[],
            'prefetch_chars': effectivePrefetch,
          },
        );
      } catch (_) {}
      if (!mounted) return false;
      effectivePrefetch = null;
    }

    final prepared = await _emojiPipeline.buildPayload(
      items: frame,
      fontSize: widget.fontSize,
      scaleX: widthScale,
      scaleY: heightScale,
      fontScale: fontScale,
      locale: _danmakuLocale,
      playbackRate: widget.playbackRate,
      prefetchChars: effectivePrefetch,
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
      motionMode: 'vsync_snapshot',
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

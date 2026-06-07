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

  @override
  State<DfmPlusOverlay> createState() => _DfmPlusOverlayState();
}

class _DfmPlusOverlayState extends State<DfmPlusOverlay> {
  final DfmPlusLayoutBridge _bridge = DfmPlusLayoutBridge();
  final Next2TextureBridge _textureBridge = Next2TextureBridge();
  final Next2EmojiPipeline _emojiPipeline = Next2EmojiPipeline();

  Size _layoutSize = Size.zero;

  bool _updateScheduled = false;
  bool _updateInFlight = false;
  bool _updateQueued = false;

  double _lastTimeSeconds = -1.0;
  bool _forceLayout = false;
  bool _configurePending = false;

  // Optimized texture update state: avoid redundant per-frame async calls
  // when texture ID is already stable. Only re-acquire when size changes.
  int _lastTextureWidth = 0;
  int _lastTextureHeight = 0;
  String _lastTextureSurfaceId = '';

  int? _textureId;
  bool _textureReady = false;
  String _surfaceId = 'dfm-default';
  double _lastDevicePixelRatio = 1.0;

  /// Low-DPR screens render at 2x then downscale to fix aliasing.
  static const double _supersampleMultiplier = 2.0;

  @override
  void initState() {
    super.initState();
    _surfaceId = 'dfm-${identityHashCode(this)}';
    _lastTextureSurfaceId = _surfaceId;
  }

  @override
  void dispose() {
    _bridge.dispose();
    _textureBridge.disposeSurface(_surfaceId);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant DfmPlusOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.danmakuListVersion != widget.danmakuListVersion ||
        oldWidget.danmakuList != widget.danmakuList ||
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

        return ValueListenableBuilder<double>(
          valueListenable: widget.playbackTimeMs,
          builder: (context, _, __) {
            _queueUpdate();

            final hasTexture = _textureReady &&
                _textureId != null &&
                Next2TextureBridge.isSupported;

            final needsSupersample =
                context.watch<SettingsProvider>().danmakuSupersample;
            final filterQuality =
                needsSupersample ? FilterQuality.low : FilterQuality.none;
            final Widget content = hasTexture
                ? Texture(
                    textureId: _textureId!,
                    filterQuality: filterQuality,
                  )
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
      },
    );
  }

  void _queueUpdate() {
    _updateQueued = true;
    if (_updateScheduled || _updateInFlight) {
      return;
    }
    _updateScheduled = true;
    Future.microtask(_runUpdateLoop);
  }

  /// Update loop: layout is now synchronous (Dart-side), so the per-frame
  /// position computation has zero async overhead. Only configure() and
  /// texture upload remain async.
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

        double currentTime =
            widget.playbackTimeMs.value / 1000.0 + widget.timeOffset;

        if (!_forceLayout && (currentTime - _lastTimeSeconds).abs() < 0.0001) {
          continue;
        }

        // If config changed, run async configure first. configure() takes
        // tens to hundreds of milliseconds (Rust prepare + font load), and
        // the player position may advance significantly during that time.
        // The worst case: a resumed video where playbackTimeMs is briefly 0
        // while the player is loading, then jumps to the saved position.
        // Using the pre-configure currentTime would paint t=0 danmaku.
        if (_forceLayout || _configurePending) {
          _forceLayout = false;
          _configurePending = false;
          await _bridge.configure(
            danmakuList: widget.danmakuList,
            danmakuListVersion: widget.danmakuListVersion,
            size: _layoutSize,
            fontSize: widget.fontSize,
            displayArea: widget.displayArea,
            scrollDurationSeconds: widget.scrollDurationSeconds,
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
          // Re-read playback position — it may have jumped from 0 to the
          // saved resume point while configure was running.
          currentTime =
              widget.playbackTimeMs.value / 1000.0 + widget.timeOffset;
          _lastTimeSeconds = currentTime;
        } else {
          _lastTimeSeconds = currentTime;
        }

        // Synchronous layout — no await, no microtask delay
        final frame = _bridge.layout(currentTime);

        await _tryUpdateTexture(frame);
        widget.onLayoutCalculated?.call(frame);
      }
    } catch (_) {
      // Keep overlay alive and retry on next frame.
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

    final needsSupersample =
        context.read<SettingsProvider>().danmakuSupersample;
    final supersample = needsSupersample ? _supersampleMultiplier : 1.0;
    final double pixelRatio =
        (dpr.isFinite ? dpr.clamp(1.0, 4.0).toDouble() : 1.0) * supersample;

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
      }
    }

    final widthScale = pixelWidth > 0 ? pixelWidth / _layoutSize.width : 1.0;
    final heightScale = pixelHeight > 0 ? pixelHeight / _layoutSize.height : 1.0;
    final fontScale =
        ((widthScale + heightScale) * 0.5).clamp(0.25, 8.0).toDouble();

    final prepared = await _emojiPipeline.buildPayload(
      items: frame,
      fontSize: widget.fontSize,
      scaleX: widthScale,
      scaleY: heightScale,
      fontScale: fontScale,
      locale: locale,
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
      framePayload: prepared.toJson(),
    );

    if (pushed) {
      _emojiPipeline.markAtlasSynced();
    } else {
      _emojiPipeline.markAtlasDirty();
    }

    return pushed;
  }
}

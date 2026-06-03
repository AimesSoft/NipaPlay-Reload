import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_emoji_pipeline.dart';
import 'package:nipaplay/danmaku_next/next2_overlay_viewport.dart';
import 'package:nipaplay/danmaku_next/next2_texture_bridge.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

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
        oldWidget.opacity != widget.opacity ||
        oldWidget.isVisible != widget.isVisible ||
        oldWidget.maxQuantity != widget.maxQuantity ||
        oldWidget.maxLinesPerType != widget.maxLinesPerType ||
        !listEquals(oldWidget.blockWords, widget.blockWords)) {
      _forceLayout = true;
      _queueUpdate();
    }
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
          _layoutSize = layoutSize;
          _forceLayout = true;
          _queueUpdate();
        }

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;
        if ((_lastDevicePixelRatio - dpr).abs() > 0.001) {
          _lastDevicePixelRatio = dpr;
          _forceLayout = true;
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
                globals.isTablet || (globals.isDesktop && dpr < 2.0);
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

        final currentTime =
            widget.playbackTimeMs.value / 1000.0 + widget.timeOffset;

        if (!_forceLayout && (currentTime - _lastTimeSeconds).abs() < 0.0001) {
          continue;
        }

        _lastTimeSeconds = currentTime;

        // If config changed, run async configure first
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
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final dpr =
        views.isNotEmpty ? views.first.devicePixelRatio : _lastDevicePixelRatio;

    final needsSupersample =
        globals.isTablet || (globals.isDesktop && dpr < 2.0);
    final supersample = needsSupersample ? _supersampleMultiplier : 1.0;
    final double pixelRatio =
        (dpr.isFinite ? dpr.clamp(1.0, 4.0).toDouble() : 1.0) * supersample;

    final int pixelWidth =
        (_layoutSize.width * pixelRatio).round().clamp(1, 16384).toInt();
    final int pixelHeight =
        (_layoutSize.height * pixelRatio).round().clamp(1, 16384).toInt();

    // Optimized: only re-acquire texture if size changed (avoids redundant
    // ensureTexture await on every frame when texture ID is already stable)
    bool needsNewTexture = _textureId == null ||
        pixelWidth != _lastTextureWidth ||
        pixelHeight != _lastTextureHeight ||
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

      if (info.isNewEngine) {
        await _textureBridge.resetScene();
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

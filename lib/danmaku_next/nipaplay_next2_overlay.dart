import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

import 'next2_emoji_pipeline.dart';
import 'next2_layout_bridge.dart';
import 'next2_overlay_viewport.dart';
import 'next2_texture_bridge.dart';

class NipaPlayNext2Overlay extends StatefulWidget {
  const NipaPlayNext2Overlay({
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
  final ValueChanged<List<PositionedDanmakuItem>>? onLayoutCalculated;

  @override
  State<NipaPlayNext2Overlay> createState() => _NipaPlayNext2OverlayState();
}

class _NipaPlayNext2OverlayState extends State<NipaPlayNext2Overlay> {
  final Next2LayoutBridge _bridge = Next2LayoutBridge();
  final Next2TextureBridge _textureBridge = Next2TextureBridge();
  final Next2EmojiPipeline _emojiPipeline = Next2EmojiPipeline();

  Size _layoutSize = Size.zero;

  bool _updateScheduled = false;
  bool _updateInFlight = false;
  bool _updateQueued = false;

  int? _textureId;
  bool _textureReady = false;
  String _surfaceId = 'next2-default';
  double _lastDevicePixelRatio = 1.0;
  int _lastTextureWidth = 0;
  int _lastTextureHeight = 0;
  String _lastTextureSurfaceId = '';

  @override
  void initState() {
    super.initState();
    _surfaceId = 'next2-${identityHashCode(this)}';
  }

  @override
  void dispose() {
    _textureBridge.disposeSurface(_surfaceId);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NipaPlayNext2Overlay oldWidget) {
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
        oldWidget.opacity != widget.opacity ||
        oldWidget.isVisible != widget.isVisible) {
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
          _queueUpdate();
        }

        final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ??
            View.of(context).devicePixelRatio;
        // DPR can micro-jitter on Windows when the window loses focus.
        // DPR only affects texture pixel size, not danmaku layout.
        // Update the cached DPR silently — the texture path will pick up
        // the new DPR on its own. Re-running configure here would cause
        // visible flicker.
        if ((_lastDevicePixelRatio - dpr).abs() > 0.001) {
          _lastDevicePixelRatio = dpr;
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
                needsSupersample > 0.0 ? FilterQuality.low : FilterQuality.none;
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

        await _bridge.configure(
          danmakuList: widget.danmakuList,
          danmakuListVersion: widget.danmakuListVersion,
          size: _layoutSize,
          fontSize: widget.fontSize,
          displayArea: widget.displayArea,
          scrollDurationSeconds: widget.scrollDurationSeconds,
          allowStacking: widget.allowStacking,
          mergeDanmaku: widget.mergeDanmaku,
          customFontFamily: widget.customFontFamily,
          customFontFilePath: widget.customFontFilePath,
        );

        final frame = await _bridge.layout(
          widget.playbackTimeMs.value / 1000.0 + widget.timeOffset,
        );

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
    // ensureTexture → isNewEngine → resetScene → flicker.
    final dpr = _lastDevicePixelRatio;

    final supersample = context
        .read<SettingsProvider>()
        .danmakuSupersample;
    final double pixelRatio =
        (dpr.isFinite ? dpr.clamp(1.0, 4.0).toDouble() : 1.0) *
        (supersample > 0.0 ? supersample : 1.0);

    final int pixelWidth =
        (_layoutSize.width * pixelRatio).round().clamp(1, 16384).toInt();
    final int pixelHeight =
        (_layoutSize.height * pixelRatio).round().clamp(1, 16384).toInt();

    // Only re-acquire texture if pixel size changed significantly (>=2 pixels).
    // Windows DPR micro-jitter on focus loss can cause ±1 pixel oscillation,
    // which would trigger a full engine rebuild → resetScene → flicker.
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

      if (info.isNewEngine) {
        // Don't call resetScene() — it clears the glyph atlas, causing
        // all characters to need re-rasterization and a visible black flash.
        // Let the next setFrame naturally render new content.
        _emojiPipeline.markAtlasDirty();
      }
    }

    final widthScale = pixelWidth > 0 ? pixelWidth / _layoutSize.width : 1.0;
    final heightScale =
        pixelHeight > 0 ? pixelHeight / _layoutSize.height : 1.0;
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
      // Overall opacity is applied by the outer Flutter Opacity widget.
      // Keep Rust-side glyph compositing at full alpha to avoid edge fringe.
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

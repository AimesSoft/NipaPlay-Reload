import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'next2_native_vsync.dart';
import 'package:nipaplay/utils/danmaku/style.dart';

class Next2TextureInfo {
  const Next2TextureInfo({
    required this.textureId,
    required this.engineHandle,
    required this.width,
    required this.height,
    required this.isNewEngine,
  });

  final int textureId;
  final int engineHandle;
  final int width;
  final int height;
  final bool isNewEngine;
}

class Next2DfmPrewarmState {
  const Next2DfmPrewarmState({
    required this.publishedFrameSerial,
    required this.pendingGlyphs,
  });

  final int publishedFrameSerial;
  final int pendingGlyphs;
}

class Next2TextureBridge {
  static const MethodChannel _channel = MethodChannel('nipaplay/next2_texture');

  static bool get isSupported => Next2PlatformSupport.isNativeTextureSupported;

  int? _engineHandle;
  bool signalVsync(int elapsedUs) {
    final handle = _engineHandle;
    return handle != null && Next2NativeVsync.signal(handle, elapsedUs);
  }

  Future<Next2TextureInfo?> ensureTexture({
    required String surfaceId,
    required int width,
    required int height,
  }) async {
    if (!isSupported) {
      return null;
    }

    Map<dynamic, dynamic>? raw;
    try {
      raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getTextureInfo',
        <String, dynamic>{
          'surfaceId': surfaceId,
          'width': width,
          'height': height,
        },
      );
    } on PlatformException catch (e) {
      if (e.code == 'plugin_detached' || e.code == 'surface_disposed') {
        return null;
      }
      rethrow;
    }

    if (raw == null) {
      return null;
    }

    final textureId = (raw['textureId'] as num?)?.toInt();
    final engineHandle = (raw['engineHandle'] as num?)?.toInt();
    final outWidth = (raw['width'] as num?)?.toInt() ?? width;
    final outHeight = (raw['height'] as num?)?.toInt() ?? height;
    final isNewEngine = raw['isNewEngine'] == true;

    if (textureId == null ||
        textureId < 0 ||
        engineHandle == null ||
        engineHandle <= 0) {
      return null;
    }

    _engineHandle = engineHandle;

    return Next2TextureInfo(
      textureId: textureId,
      engineHandle: engineHandle,
      width: outWidth,
      height: outHeight,
      isNewEngine: isNewEngine,
    );
  }

  Future<bool> setFrame({
    required List<PositionedDanmakuItem> items,
    required double fontSize,
    required double outlineWidth,
    required DanmakuShadowStyle shadowStyle,
    required double opacity,
    String customFontFamily = '',
    String customFontFilePath = '',
    double scaleX = 1.0,
    double scaleY = 1.0,
    double fontScale = 1.0,
    double playbackRate = 1.0,
    Map<String, dynamic>? framePayload,
    String motionMode = 'legacy_interpolation',
  }) async {
    if (!isSupported) {
      return false;
    }

    final engineHandle = _engineHandle;
    if (engineHandle == null || engineHandle <= 0) {
      return false;
    }

    final payload = <String, dynamic>{
      ...?framePayload,
      if (framePayload == null)
        'items': items
            .map(
              (item) => _itemToJson(
                item,
                scaleX: scaleX,
                scaleY: scaleY,
                playbackRate: playbackRate,
              ),
            )
            .toList(growable: false),
      'motion_mode': motionMode,
    };

    final frameJson = jsonEncode(payload);
    final ok = await _channel.invokeMethod<bool>(
      'setFrame',
      <String, dynamic>{
        'engineHandle': engineHandle,
        'frameJson': frameJson,
        'fontSize': fontSize * fontScale,
        'outlineWidth': outlineWidth,
        'shadowStyle': _shadowStyleCode(shadowStyle),
        'opacity': opacity,
        'customFontFamily': customFontFamily,
        'customFontFilePath': customFontFilePath,
      },
    );
    return ok == true;
  }

  Future<Next2DfmPrewarmState?> getDfmPrewarmState() async {
    final engineHandle = _engineHandle;
    if (!isSupported || engineHandle == null || engineHandle <= 0) {
      return null;
    }
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getDfmPrewarmState',
        <String, dynamic>{'engineHandle': engineHandle},
      );
      if (raw == null) return null;
      final serial = (raw['publishedFrameSerial'] as num?)?.toInt();
      final pending = (raw['pendingGlyphs'] as num?)?.toInt();
      if (serial == null || pending == null) return null;
      return Next2DfmPrewarmState(
        publishedFrameSerial: serial,
        pendingGlyphs: pending,
      );
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      if (e.code == 'plugin_detached' ||
          e.code == 'surface_disposed' ||
          e.code == 'engine_unavailable') {
        return null;
      }
      rethrow;
    }
  }

  Future<Next2DfmPrewarmState?> waitForDfmPrewarm({
    required int publishedAfter,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = await getDfmPrewarmState();
      if (state == null) return null;
      if (state.pendingGlyphs == 0 &&
          state.publishedFrameSerial > publishedAfter) {
        return state;
      }
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    return null;
  }

  Future<bool> waitForDfmFramePublished({
    required int publishedAfter,
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final state = await getDfmPrewarmState();
      if (state == null) return false;
      if (state.publishedFrameSerial > publishedAfter) return true;
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    return false;
  }

  Future<void> resetScene() async {
    if (!isSupported) {
      return;
    }

    final engineHandle = _engineHandle;
    if (engineHandle == null || engineHandle <= 0) {
      return;
    }

    try {
      await _channel.invokeMethod<bool>(
        'resetScene',
        <String, dynamic>{
          'engineHandle': engineHandle,
        },
      );
    } catch (_) {
      // noop
    }
  }

  Future<void> disposeSurface(String surfaceId) async {
    if (!isSupported) {
      return;
    }
    _engineHandle = null;
    try {
      await _channel.invokeMethod<void>(
        'disposeTexture',
        <String, dynamic>{
          'surfaceId': surfaceId,
        },
      );
    } catch (_) {
      // noop
    }
  }

  Map<String, dynamic> _itemToJson(
    PositionedDanmakuItem item, {
    required double scaleX,
    required double scaleY,
    double playbackRate = 1.0,
  }) {
    return <String, dynamic>{
      'text': item.content.text,
      'count_text': item.content.countText,
      'x': item.x * scaleX,
      'y': item.y * scaleY,
      'color_argb': item.content.color.toARGB32().toSigned(32),
      'font_size_multiplier': item.content.fontSizeMultiplier,
      'is_me': item.content.isMe,
      'width': item.width * scaleX,
      if (item.endMediaSeconds != null) ...{
        'start_media_s': item.time,
        'end_media_s': item.endMediaSeconds,
      },
      // Mirror Next2EmojiPipeline._signedScrollSpeed so the fallback path
      // (framePayload == null) stays consistent with the production path.
      // playbackRate folds video speed into the velocity so native
      // interpolation matches Dart's rate-scaled position advancement.
      'scroll_speed': item.scrollSpeed == 0.0
          ? 0.0
          : item.typeCode == 6
              ? item.scrollSpeed * scaleX * playbackRate
              : item.typeCode == 1
                  ? -item.scrollSpeed * scaleX * playbackRate
                  : 0.0,
    };
  }

  int _shadowStyleCode(DanmakuShadowStyle style) {
    switch (style) {
      case DanmakuShadowStyle.none:
        return 0;
      case DanmakuShadowStyle.soft:
        return 1;
      case DanmakuShadowStyle.medium:
        return 2;
      case DanmakuShadowStyle.strong:
        return 3;
    }
  }
}

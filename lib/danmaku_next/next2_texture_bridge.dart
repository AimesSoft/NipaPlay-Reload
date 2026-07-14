import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
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

class Next2TextureBridge {
  static const MethodChannel _channel = MethodChannel('nipaplay/next2_texture');

  static bool get isSupported => Next2PlatformSupport.isNativeTextureSupported;

  int? _engineHandle;

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
  }) async {
    if (!isSupported) {
      return false;
    }

    final engineHandle = _engineHandle;
    if (engineHandle == null || engineHandle <= 0) {
      return false;
    }

    final payload = framePayload ??
        <String, dynamic>{
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
        };

    final ok = await _channel.invokeMethod<bool>(
      'setFrame',
      <String, dynamic>{
        'engineHandle': engineHandle,
        'frameJson': jsonEncode(payload),
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

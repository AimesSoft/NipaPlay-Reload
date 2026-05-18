import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';

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

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  int? _engineHandle;

  Future<Next2TextureInfo?> ensureTexture({
    required String surfaceId,
    required int width,
    required int height,
  }) async {
    if (!isSupported) {
      return null;
    }

    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getTextureInfo',
      <String, dynamic>{
        'surfaceId': surfaceId,
        'width': width,
        'height': height,
      },
    );

    if (raw == null) {
      return null;
    }

    final textureId = (raw['textureId'] as num?)?.toInt();
    final engineHandle = (raw['engineHandle'] as num?)?.toInt();
    final outWidth = (raw['width'] as num?)?.toInt() ?? width;
    final outHeight = (raw['height'] as num?)?.toInt() ?? height;
    final isNewEngine = raw['isNewEngine'] == true;

    if (textureId == null || engineHandle == null) {
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
    double scaleX = 1.0,
    double scaleY = 1.0,
    double fontScale = 1.0,
  }) async {
    if (!isSupported) {
      return false;
    }

    final engineHandle = _engineHandle;
    if (engineHandle == null || engineHandle <= 0) {
      return false;
    }

    final payload = <String, dynamic>{
      'items': items
          .map(
            (item) => _itemToJson(
              item,
              scaleX: scaleX,
              scaleY: scaleY,
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
  }) {
    return <String, dynamic>{
      'text': item.content.text,
      'count_text': item.content.countText,
      'x': item.x * scaleX,
      'y': item.y * scaleY,
      'color_argb': item.content.color.toARGB32().toSigned(32),
      'font_size_multiplier': item.content.fontSizeMultiplier,
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

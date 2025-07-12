import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../danmaku/lib/danmaku_content_item.dart';
import 'dynamic_font_atlas.dart';
import 'gpu_danmaku_config.dart';

// 根据文字颜色判断使用的描边颜色，与 NipaPlay 保持一致
Color _getShadowColor(Color textColor) {
  // 计算亮度，与 NipaPlay 的算法保持一致
  final luminance = (0.299 * textColor.red + 0.587 * textColor.green + 0.114 * textColor.blue) / 255;
  // 如果亮度小于0.2，说明是深色，使用白色描边；否则使用黑色描边
  return luminance < 0.2 ? Colors.white : Colors.black;
}

// 获取描边偏移量，与 NipaPlay 保持一致
double _getStrokeOffset() {
  // 统一使用1.0像素偏移，与 NipaPlay 保持一致
  return 1.0;
}

class GPUTopDanmakuRenderer extends CustomPainter {
  final GPUDanmakuConfig config;
  double opacity;
  final List<_GPUTopDanmakuItem> _danmakuItems = [];
  final VoidCallback? _onNeedRepaint;

  final DynamicFontAtlas _fontAtlas;
  bool _isInitialized = false;
  
  final Map<int, List<_GPUTopDanmakuItem>> _trackItems = {};
  
  bool _showCollisionBoxes = false;
  bool _showTrackNumbers = false;
  bool _isPaused = false;
  int _baseTime = DateTime.now().millisecondsSinceEpoch;
  int _pausedTime = 0;
  int _lastPauseStart = 0;

  GPUTopDanmakuRenderer({
    required this.config,
    required this.opacity,
    VoidCallback? onNeedRepaint,
    bool isPaused = false,
    bool showCollisionBoxes = false,
    bool showTrackNumbers = false,
  })  : _onNeedRepaint = onNeedRepaint,
       _isPaused = isPaused,
       _showCollisionBoxes = showCollisionBoxes,
        _showTrackNumbers = showTrackNumbers,
        _fontAtlas = DynamicFontAtlas(fontSize: config.fontSize) {
    _initialize();
  }

  Future<void> _initialize() async {
    await _fontAtlas.generate();
    _isInitialized = true;
    _onNeedRepaint?.call();
    debugPrint('GPUTopDanmakuRenderer: 初始化完成 (字体图集)');
  }

  double get fontSize => config.fontSize;

  void updateOptions({GPUDanmakuConfig? newConfig, double? newOpacity}) {
    // 注意: 更改字体大小等需要重新生成图集，此处暂不处理
    if (newOpacity != null && opacity != newOpacity) {
      opacity = newOpacity;
      _onNeedRepaint?.call();
    }
  }

  void updateDebugOptions({bool? showCollisionBoxes, bool? showTrackNumbers}) {
    if ((showCollisionBoxes != null && _showCollisionBoxes != showCollisionBoxes) ||
        (showTrackNumbers != null && _showTrackNumbers != showTrackNumbers)) {
      _showCollisionBoxes = showCollisionBoxes ?? _showCollisionBoxes;
      _showTrackNumbers = showTrackNumbers ?? _showTrackNumbers;
      _onNeedRepaint?.call();
    }
  }

  void setPaused(bool paused) {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    if (paused && !_isPaused) {
      _lastPauseStart = currentTime;
    } else if (!paused && _isPaused) {
      if (_lastPauseStart > 0) {
        _pausedTime += currentTime - _lastPauseStart;
      }
    }
    _isPaused = paused;
  }

  int _getCurrentTime() {
    final currentTime = DateTime.now().millisecondsSinceEpoch;
    return _isPaused ? (_lastPauseStart - _baseTime - _pausedTime) : (currentTime - _baseTime - _pausedTime);
  }

  void addDanmaku(DanmakuContentItem item) {
    if (item.type != DanmakuItemType.top) return;
    final danmakuItem = _GPUTopDanmakuItem(
      text: item.text,
      timeOffset: item.timeOffset,
      createdAt: _getCurrentTime(),
      color: item.color, // 传入颜色
    );
    _danmakuItems.add(danmakuItem);
    // 将新弹幕的文本添加到动态图集进行处理
    _fontAtlas.addText(item.text);
  }

  void clear() {
    _danmakuItems.clear();
    _trackItems.clear();
  }

  void dispose() {
    _fontAtlas.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!_isInitialized || _fontAtlas.atlasTexture == null) {
      return;
    }
    
    final currentTime = _getCurrentTime();
    _updateActiveDanmaku(currentTime, size);

    // --- 准备两套绘制参数：描边和填充 ---
    final strokeTransforms = <RSTransform>[];
    final strokeRects = <Rect>[];
    final strokeColors = <Color>[];

    final fillTransforms = <RSTransform>[];
    final fillRects = <Rect>[];
    final fillColors = <Color>[];

    final double scale = 0.5; // 从2倍图集缩小回1倍
    final double strokeOffset = _getStrokeOffset();
    
    _trackItems.forEach((trackIndex, items) {
      // 垂直居中对齐
      final yPos = trackIndex * config.trackHeight + config.verticalSpacing + (config.trackHeight - fontSize) / 2;
      for (final item in items) {
        // 守卫：确保弹幕所需字符都已在图集中
        if (!_fontAtlas.isReady(item.text)) {
          continue;
        }

        // --- 实时计算宽度 ---
        double textWidth2x = 0;
        for (var char in item.text.runes) {
          final charInfo = _fontAtlas.getCharRect(String.fromCharCode(char));
          textWidth2x += charInfo!.width;
        }
        final double textWidth = textWidth2x * scale;
        // --- 实时计算宽度结束 ---
        
        double xPos = (size.width - textWidth) / 2;
        final double startX = xPos;

        // 获取当前弹幕的描边颜色
        final shadowColor = _getShadowColor(item.color).withOpacity(opacity);

        for (var char in item.text.runes) {
          final charStr = String.fromCharCode(char);
          final charInfo = _fontAtlas.getCharRect(charStr)!;

          final charWidthScaled = charInfo.width * scale;
          final charCenterX = xPos + charWidthScaled / 2;
          final charCenterY = yPos + fontSize / 2;

          // 1. 准备描边层参数 (8个方向)
          final offsets = [
            Offset(-strokeOffset, -strokeOffset), Offset(strokeOffset, -strokeOffset),
            Offset(strokeOffset, strokeOffset),   Offset(-strokeOffset, strokeOffset),
            Offset(0, -strokeOffset),             Offset(0, strokeOffset),
            Offset(-strokeOffset, 0),             Offset(strokeOffset, 0),
          ];

          for (final offset in offsets) {
            strokeTransforms.add(RSTransform.fromComponents(
              rotation: 0, scale: scale,
              anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
              translateX: charCenterX + offset.dx, translateY: charCenterY + offset.dy,
            ));
            strokeRects.add(charInfo);
            strokeColors.add(shadowColor);
          }

          // 2. 准备填充层参数
          fillTransforms.add(RSTransform.fromComponents(
            rotation: 0, scale: scale,
            anchorX: charInfo.width / 2, anchorY: charInfo.height / 2,
            translateX: charCenterX, translateY: charCenterY,
          ));
          fillRects.add(charInfo);
          fillColors.add(item.color.withOpacity(opacity));

          xPos += charWidthScaled;
        }

        if (_showCollisionBoxes) {
          _drawCollisionBox(canvas, startX, yPos, textWidth, fontSize);
        }
        if (_showTrackNumbers) {
          _drawTrackNumber(canvas, startX, yPos + fontSize, trackIndex);
        }
      }
    });

    // --- 执行绘制 ---
    final paint = Paint()..filterQuality = FilterQuality.low; // 🔥 设置采样质量为low，实现抗锯齿

    // 第一遍：绘制描边
    if (strokeTransforms.isNotEmpty) {
      canvas.drawAtlas(
        _fontAtlas.atlasTexture!,
        strokeTransforms,
        strokeRects,
        strokeColors,
        BlendMode.modulate,
        null,
        paint,
      );
    }

    // 第二遍：绘制填充
    if (fillTransforms.isNotEmpty) {
      canvas.drawAtlas(
        _fontAtlas.atlasTexture!,
        fillTransforms,
        fillRects,
        fillColors,
        BlendMode.modulate,
        null,
        paint,
      );
    }
  }
  
  void _updateActiveDanmaku(int currentTime, Size size) {
    // 弹幕到期则移除
    _danmakuItems.removeWhere((item) => (currentTime - item.createdAt + item.timeOffset) > config.danmakuDuration);
    
    _trackItems.clear();
    final maxTracks = (size.height * config.screenUsageRatio / config.trackHeight).floor();
    if (maxTracks <= 0) return;

    final availableTracks = List<bool>.filled(maxTracks, true);

    // 第一遍：处理已经分配了轨道的弹幕
    for (final item in _danmakuItems) {
      if (item.trackId != -1) {
        // 检查轨道是否仍然有效（例如屏幕尺寸变小）
        if (item.trackId < maxTracks) {
          _trackItems.putIfAbsent(item.trackId, () => []).add(item);
          availableTracks[item.trackId] = false;
        } else {
          // 轨道失效，标记为需要重新分配
          item.trackId = -1;
        }
      }
      }
      
    // 第二遍：为新弹幕或轨道失效的弹幕分配新轨道
    for (final item in _danmakuItems) {
      if (item.trackId == -1) {
        final elapsed = currentTime - item.createdAt + item.timeOffset;
        if (elapsed < 0) continue; // 还未到显示时间

        // 寻找一个可用轨道
        for (int i = 0; i < maxTracks; i++) {
          if (availableTracks[i]) {
            item.trackId = i; // 分配并持久化轨道ID
            _trackItems.putIfAbsent(i, () => []).add(item);
            availableTracks[i] = false; // 标记轨道为已占用
            break;
  }
        }
      }
    }
  }

  void _drawCollisionBox(Canvas canvas, double x, double y, double width, double height) {
    final paint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..style = PaintingStyle.stroke..strokeWidth = 1;
    canvas.drawRect(Rect.fromLTWH(x, y, width, height), paint);
  }

  void _drawTrackNumber(Canvas canvas, double x, double y, int trackIndex) {
    final textPainter = TextPainter(
      text: TextSpan(text: trackIndex.toString(), style: const TextStyle(color: Colors.red, fontSize: 12)),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x - 20, y - 12));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GPUTopDanmakuItem {
  final String text;
  final int timeOffset;
  final int createdAt;
  final Color color; // 新增：弹幕颜色
  int trackId = -1; // -1 表示尚未分配轨道

  _GPUTopDanmakuItem({
    required this.text,
    required this.timeOffset,
    required this.createdAt,
    required this.color,
  });
} 
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// 动态字体图集
// 能够从传入的文本中提取新字符，并增量更新图集
class DynamicFontAtlas {
  ui.Image? atlasTexture;
  Map<String, Rect> characterRectMap = {}; // 只存储像素Rect
  
  final double fontSize;
  final Color color;

  final Set<String> _allChars = {};
  final Set<String> _pendingChars = {};
  bool _isUpdating = false;

  DynamicFontAtlas({required this.fontSize, this.color = Colors.white});

  // 初始化，生成一个包含基本字符的初始图集
  Future<void> generate() async {
    const initialChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz .!?';
    _allChars.addAll(initialChars.split(''));
    await _regenerateAtlas();
    debugPrint('DynamicFontAtlas: 初始图集生成完毕');
  }

  // 从文本中提取新字符，并触发更新
  void addText(String text) {
    bool hasNewChars = false;
    for (final char in text.runes) {
      final charStr = String.fromCharCode(char);
      if (!_allChars.contains(charStr)) {
        _pendingChars.add(charStr);
        hasNewChars = true;
      }
    }

    if (hasNewChars) {
      _triggerUpdate();
    }
  }

  // 触发一次异步的图集更新
  void _triggerUpdate() async {
    if (_isUpdating) return;
    _isUpdating = true;
    
    // 延迟一小段时间，以合并短时间内的多个更新请求
    await Future.delayed(const Duration(milliseconds: 100));

    _allChars.addAll(_pendingChars);
    _pendingChars.clear();
    
    await _regenerateAtlas();
    
    _isUpdating = false;
    debugPrint('DynamicFontAtlas: 图集已动态更新');
  }
  
  // 核心方法：重新生成整个图集
  Future<void> _regenerateAtlas() async {
    final oldTexture = atlasTexture;
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    
    double x = 0;
    double y = 0;
    double maxRowHeight = 0;
    const atlasWidth = 2048.0; // 使用更大的图集宽度以容纳更多字符

    final newCharMap = <String, Rect>{};

    for (final charStr in _allChars) {
      final textPainter = TextPainter(
        text: TextSpan(
          text: charStr,
          style: TextStyle(fontSize: fontSize * 2.0, color: color), // 2x 渲染
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      if (x + textPainter.width > atlasWidth) {
        x = 0;
        y += maxRowHeight;
        maxRowHeight = 0;
      }
      
      textPainter.paint(canvas, Offset(x, y));

      newCharMap[charStr] = Rect.fromLTWH(x, y, textPainter.width, textPainter.height);
      
      x += textPainter.width;
      if (textPainter.height > maxRowHeight) {
        maxRowHeight = textPainter.height;
      }
    }

    final picture = recorder.endRecording();
    atlasTexture = await picture.toImage(atlasWidth.toInt(), (y + maxRowHeight).toInt());
    characterRectMap = newCharMap;

    // 释放旧纹理
    oldTexture?.dispose();
  }

  // 检查指定的文本所需的所有字符是否都已在图集中准备就绪
  bool isReady(String text) {
    return text.runes.every((rune) {
      return characterRectMap.containsKey(String.fromCharCode(rune));
    });
  }

  // 获取字符信息
  Rect? getCharRect(String char) => characterRectMap[char];

  void dispose() {
    atlasTexture?.dispose();
  }
} 
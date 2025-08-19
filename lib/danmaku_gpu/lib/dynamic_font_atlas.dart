import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// 全局字体图集管理器
/// 
/// 管理不同配置的字体图集实例，避免重复生成
class FontAtlasManager {
  static final Map<String, DynamicFontAtlas> _instances = {};
  static final Map<String, bool> _initialized = {};

  /// 获取或创建字体图集实例
  static DynamicFontAtlas getInstance({
    required double fontSize,
    Color color = Colors.white,
    VoidCallback? onAtlasUpdated,
  }) {
    final key = '${fontSize}_${color.value}';
    
    if (!_instances.containsKey(key)) {
      _instances[key] = DynamicFontAtlas(
        fontSize: fontSize,
        color: color,
        onAtlasUpdated: onAtlasUpdated,
      );
      _initialized[key] = false;
    }
    
    return _instances[key]!;
  }

  /// 预初始化字体图集
  static Future<void> preInitialize({
    required double fontSize,
    Color color = Colors.white,
  }) async {
    final key = '${fontSize}_${color.value}';
    
    if (!_initialized[key]!) {
      final atlas = _instances[key]!;
      await atlas.generate();
      _initialized[key] = true;
      debugPrint('FontAtlasManager: 预初始化字体图集 - 字体大小: $fontSize, 颜色: $color');
    }
  }

  /// 预构建字体图集（添加文本）
  static Future<void> prebuildFromTexts({
    required double fontSize,
    required List<String> texts,
    Color color = Colors.white,
  }) async {
    final key = '${fontSize}_${color.value}';
    
    if (!_initialized[key]!) {
      await preInitialize(fontSize: fontSize, color: color);
    }
    
    final atlas = _instances[key]!;
    await atlas.prebuildFromTexts(texts);
    debugPrint('FontAtlasManager: 预构建字体图集完成 - 字体大小: $fontSize, 文本数量: ${texts.length}');
  }

  /// 清理所有实例
  static void disposeAll() {
    for (final atlas in _instances.values) {
      atlas.dispose();
    }
    _instances.clear();
    _initialized.clear();
    debugPrint('FontAtlasManager: 清理所有字体图集实例');
  }

  /// 清理特定配置的实例
  static void disposeInstance({
    required double fontSize,
    Color color = Colors.white,
  }) {
    final key = '${fontSize}_${color.value}';
    final atlas = _instances.remove(key);
    _initialized.remove(key);
    atlas?.dispose();
    debugPrint('FontAtlasManager: 清理字体图集实例 - 字体大小: $fontSize, 颜色: $color');
  }
}

// 动态字体图集
// 能够从传入的文本中提取新字符，并增量更新图集
class DynamicFontAtlas {
  ui.Image? atlasTexture;
  Map<String, Rect> characterRectMap = {}; // 只存储像素Rect
  
  final double fontSize;
  final Color color;
  final VoidCallback? onAtlasUpdated; // 添加回调

  final Set<String> _allChars = {};
  final Set<String> _pendingChars = {};
  bool _isUpdating = false;

  DynamicFontAtlas({
    required this.fontSize,
    this.color = Colors.white,
    this.onAtlasUpdated,
  });

  // 初始化，生成一个包含基本字符的初始图集
  Future<void> generate() async {
    // 如果已经生成过，直接返回
    if (atlasTexture != null) {
      debugPrint('DynamicFontAtlas: 字体图集已存在，跳过重新生成');
      return;
    }
    
    const initialChars = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz .!?';
    _allChars.addAll(initialChars.split(''));
    await _regenerateAtlas();
    debugPrint('DynamicFontAtlas: 初始图集生成完毕');
  }

  // 预扫描大量文本并批量生成字符集（用于视频初始化时预处理）
  Future<void> prebuildFromTexts(List<String> texts) async {
    if (_isUpdating) return;
    _isUpdating = true;
    
    debugPrint('DynamicFontAtlas: 开始预扫描 ${texts.length} 条弹幕文本');
    
    final Set<String> newChars = {};
    int totalChars = 0;
    
    // 批量提取所有唯一字符
    for (final text in texts) {
      for (final char in text.runes) {
        final charStr = String.fromCharCode(char);
        totalChars++;
        if (!_allChars.contains(charStr)) {
          newChars.add(charStr);
        }
      }
    }
    
    if (newChars.isNotEmpty) {
      debugPrint('DynamicFontAtlas: 发现 ${newChars.length} 个新字符（总计 $totalChars 个字符）');
      
      _allChars.addAll(newChars);
      await _regenerateAtlas();
      
      debugPrint('DynamicFontAtlas: 预构建完成，图集包含 ${_allChars.length} 个字符');
      onAtlasUpdated?.call();
    } else {
      debugPrint('DynamicFontAtlas: 所有字符已在图集中，无需重建');
    }
    
    _isUpdating = false;
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
    onAtlasUpdated?.call(); // 触发回调
    //debugPrint('DynamicFontAtlas: 图集已动态更新');
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
    
    // 🔥 新增：计算字体度量信息，确保包含完整的ascender和descender
    final fontMetrics = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: fontSize * 2.0,
        fontStyle: ui.FontStyle.normal,
      ),
    )..addText('Ag😀yg|'); // 使用包含各种字符高度的测试字符串
    final paragraph = fontMetrics.build();
    paragraph.layout(const ui.ParagraphConstraints(width: double.infinity));
    
    // 计算额外的上下边距，确保包含完整的字符高度
    final standardHeight = fontSize * 2.0;
    final actualHeight = paragraph.height;
    final extraPadding = (actualHeight - standardHeight).clamp(0.0, fontSize * 0.5);
    final topPadding = extraPadding;
    final bottomPadding = extraPadding;

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
      
      // 🔥 修改：计算包含上下边距的实际渲染高度
      final actualCharHeight = textPainter.height + topPadding + bottomPadding;

      if (x + textPainter.width > atlasWidth) {
        x = 0;
        y += maxRowHeight;
        maxRowHeight = 0;
      }
      
      // 🔥 修改：在绘制时添加顶部边距，确保字符不被裁剪
      textPainter.paint(canvas, Offset(x, y + topPadding));

      // 🔥 修改：保存包含完整边距的字符矩形区域
      newCharMap[charStr] = Rect.fromLTWH(x, y, textPainter.width, actualCharHeight);
      
      x += textPainter.width;
      if (actualCharHeight > maxRowHeight) {
        maxRowHeight = actualCharHeight;
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
    // 如果图集还未生成，返回false
    if (atlasTexture == null) return false;
    
    return text.runes.every((rune) {
      final charStr = String.fromCharCode(rune);
      final rect = characterRectMap[charStr];
      // 检查字符是否存在且矩形有效
      return rect != null && !rect.isEmpty && rect.isFinite;
    });
  }

  // 获取字符信息
  Rect? getCharRect(String char) {
    final rect = characterRectMap[char];
    // 确保返回的矩形是有效的
    if (rect != null && !rect.isEmpty && rect.isFinite) {
      return rect;
    }
    return null;
  }

  void dispose() {
    atlasTexture?.dispose();
  }
} 
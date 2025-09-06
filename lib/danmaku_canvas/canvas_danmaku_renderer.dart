import 'package:flutter/material.dart';
import 'lib/canvas_danmaku.dart';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

/// 简单的弹幕缓存项，避免命名冲突
class _DanmakuBufferItem {
  final String text;
  final double time;
  final int mode;
  final int color;

  _DanmakuBufferItem({
    required this.text,
    required this.time,
    required this.mode,
    required this.color,
  });
}

/// Canvas弹幕渲染器
class CanvasDanmakuRenderer extends StatefulWidget {
  final double fontSize;
  final double opacity;
  final double displayArea;
  final bool visible;
  final bool stacking;
  final bool mergeDanmaku;
  final bool blockTopDanmaku;
  final bool blockBottomDanmaku;
  final bool blockScrollDanmaku;
  final List<String> blockWords;
  final double currentTime;
  final bool isPlaying;

  const CanvasDanmakuRenderer({
    super.key,
    required this.fontSize,
    required this.opacity,
    required this.displayArea,
    required this.visible,
    required this.stacking,
    required this.mergeDanmaku,
    required this.blockTopDanmaku,
    required this.blockBottomDanmaku,
    required this.blockScrollDanmaku,
    required this.blockWords,
    required this.currentTime,
    required this.isPlaying,
  });

  @override
  State<CanvasDanmakuRenderer> createState() => _CanvasDanmakuRendererState();
}

class _CanvasDanmakuRendererState extends State<CanvasDanmakuRenderer> {
  late DanmakuController _danmakuController;
  final List<_DanmakuBufferItem> _danmakuBuffer = [];
  List<Map<String, dynamic>> _currentDanmakuList = [];

  @override
  void initState() {
    super.initState();
  }

  /// 解析颜色数据，支持多种格式
  int _parseColor(dynamic colorData) {
    if (colorData == null) return 0xFFFFFFFF; // 默认白色
    
    if (colorData is int) {
      return colorData;
    }
    
    if (colorData is String) {
      // 处理 rgb(r,g,b) 格式
      if (colorData.startsWith('rgb(') && colorData.endsWith(')')) {
        try {
          final colorValues = colorData
              .replaceAll('rgb(', '')
              .replaceAll(')', '')
              .split(',')
              .map((s) => int.tryParse(s.trim()) ?? 255)
              .toList();
          
          if (colorValues.length >= 3) {
            return Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]).value;
          }
        } catch (e) {
          debugPrint('解析RGB颜色失败: $e');
        }
      }
      
      // 处理十六进制字符串格式
      try {
        if (colorData.startsWith('#')) {
          return int.parse(colorData.substring(1), radix: 16) | 0xFF000000;
        } else if (colorData.startsWith('0x')) {
          return int.parse(colorData.substring(2), radix: 16);
        } else {
          // 尝试直接解析数字字符串
          return int.parse(colorData);
        }
      } catch (e) {
        debugPrint('解析颜色字符串失败: $e');
      }
    }
    
    return 0xFFFFFFFF; // 解析失败时返回默认白色
  }

  @override
  void didUpdateWidget(CanvasDanmakuRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 检查播放状态变化
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _danmakuController.resume();
      } else {
        _danmakuController.pause();
      }
    }
  }

  /// 加载弹幕数据
  void loadDanmaku(List<Map<String, dynamic>> danmakuList) {
    _currentDanmakuList = danmakuList;
    clearDanmaku();
    
    for (final danmaku in danmakuList) {
      _addDanmakuToBatch(danmaku);
    }
  }

  /// 批量添加弹幕到Canvas渲染器
  void _addDanmakuToBatch(Map<String, dynamic> danmakuData) {
    if (!widget.visible) return;

    // 解析弹幕数据
    final text = danmakuData['content'] as String? ?? '';
    final time = (danmakuData['time'] as double?) ?? 0.0;
    final mode = (danmakuData['mode'] as int?) ?? 1;
    final color = _parseColor(danmakuData['color']);

    // 检查屏蔽词
    bool isBlocked = widget.blockWords.any(
        (word) => text.toLowerCase().contains(word.toLowerCase())
    );
    if (isBlocked) return;

    // 检查弹幕类型屏蔽
    switch (mode) {
      case 5: // 顶部弹幕
        if (widget.blockTopDanmaku) return;
        break;
      case 4: // 底部弹幕
        if (widget.blockBottomDanmaku) return;
        break;
      case 1: // 滚动弹幕
      case 6:
        if (widget.blockScrollDanmaku) return;
        break;
    }

    // 处理合并相同弹幕
    if (widget.mergeDanmaku) {
      bool hasSimilar = _danmakuBuffer.any(
          (item) => item.text == text &&
              (time - item.time).abs() < 5.0
      );
      if (hasSimilar) return;
    }

    // 创建弹幕缓存项
    final danmakuItem = _DanmakuBufferItem(
      text: text,
      time: time,
      mode: mode,
      color: color,
    );
    _danmakuBuffer.add(danmakuItem);

    // 创建简单的Canvas弹幕项
    try {
      // 根据弹幕模式确定类型
      DanmakuItemType danmakuType = DanmakuItemType.scroll;
      switch (mode) {
        case 5: // 顶部弹幕
          danmakuType = DanmakuItemType.top;
          break;
        case 4: // 底部弹幕
          danmakuType = DanmakuItemType.bottom;
          break;
        case 1: // 滚动弹幕
        case 6:
        default:
          danmakuType = DanmakuItemType.scroll;
          break;
      }

      DanmakuContentItem canvasDanmaku = DanmakuContentItem(
        text,
        color: Color(color),
        type: danmakuType,
      );
      
      // 添加到Canvas弹幕控制器
      _danmakuController.addDanmaku(canvasDanmaku);
    } catch (e) {
      // 如果API不匹配，记录错误但不中断程序
      debugPrint('Canvas弹幕添加失败: $e');
    }
  }

  /// 清空弹幕
  void clearDanmaku() {
    _danmakuBuffer.clear();
    _danmakuController.clear();
  }

  /// 暂停弹幕
  void pauseDanmaku() {
    _danmakuController.pause();
  }

  /// 继续弹幕
  void resumeDanmaku() {
    _danmakuController.resume();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 监听弹幕数据变化
        if (_currentDanmakuList != videoState.danmakuList) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            loadDanmaku(videoState.danmakuList);
          });
        }

        return DanmakuScreen(
          createdController: (controller) {
            _danmakuController = controller;
            // 延迟加载弹幕数据，等待DanmakuScreen初始化完成
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                loadDanmaku(videoState.danmakuList);
              }
            });
          },
          option: DanmakuOption(
            fontSize: widget.fontSize,
            area: widget.displayArea,
            opacity: widget.opacity,
            hideTop: widget.blockTopDanmaku,
            hideBottom: widget.blockBottomDanmaku,
            hideScroll: widget.blockScrollDanmaku,
            massiveMode: widget.stacking, // 注意：massiveMode=true表示允许叠加，与stacking含义相同
            showStroke: true, // 显示描边，提高可读性
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _danmakuBuffer.clear();
    super.dispose();
  }
}

/// Canvas弹幕渲染器管理类
class CanvasDanmakuManager {
  static CanvasDanmakuRenderer? _instance;
  static GlobalKey<_CanvasDanmakuRendererState>? _key;

  /// 获取Canvas弹幕渲染器实例
  static Widget createRenderer({
    required double fontSize,
    required double opacity,
    required double displayArea,
    required bool visible,
    required bool stacking,
    required bool mergeDanmaku,
    required bool blockTopDanmaku,
    required bool blockBottomDanmaku,
    required bool blockScrollDanmaku,
    required List<String> blockWords,
    required double currentTime,
    required bool isPlaying,
  }) {
    _key = GlobalKey<_CanvasDanmakuRendererState>();
    _instance = CanvasDanmakuRenderer(
      key: _key,
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      visible: visible,
      stacking: stacking,
      mergeDanmaku: mergeDanmaku,
      blockTopDanmaku: blockTopDanmaku,
      blockBottomDanmaku: blockBottomDanmaku,
      blockScrollDanmaku: blockScrollDanmaku,
      blockWords: blockWords,
      currentTime: currentTime,
      isPlaying: isPlaying,
    );
    return _instance!;
  }

  /// 加载弹幕数据
  static void loadDanmaku(List<Map<String, dynamic>> danmakuList) {
    _key?.currentState?.loadDanmaku(danmakuList);
  }

  /// 清空弹幕
  static void clearDanmaku() {
    _key?.currentState?.clearDanmaku();
  }

  /// 暂停弹幕
  static void pauseDanmaku() {
    _key?.currentState?.pauseDanmaku();
  }

  /// 继续弹幕
  static void resumeDanmaku() {
    _key?.currentState?.resumeDanmaku();
  }
}
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/video_player_state.dart';
import '../../danmaku/lib/danmaku_content_item.dart';
import '../../providers/developer_options_provider.dart';
import 'gpu_danmaku_renderer.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_test.dart';

/// GPU弹幕覆盖层组件
/// 
/// 使用Flutter GPU API和自定义着色器渲染弹幕
/// 目前仅支持顶部弹幕的渲染
class GPUDanmakuOverlay extends StatefulWidget {
  final int currentPosition;
  final int videoDuration;
  final bool isPlaying;
  final GPUDanmakuConfig config;
  final bool isVisible;
  final double opacity;

  const GPUDanmakuOverlay({
    Key? key,
    required this.currentPosition,
    required this.videoDuration,
    required this.isPlaying,
    required this.config,
    required this.isVisible,
    required this.opacity,
  }) : super(key: key);

  @override
  State<GPUDanmakuOverlay> createState() => _GPUDanmakuOverlayState();
}

class _GPUDanmakuOverlayState extends State<GPUDanmakuOverlay> {
  GPUDanmakuRenderer? _renderer;
  double _lastSyncTime = 0.0;
  final Set<String> _addedDanmaku = {};
  bool _hasAnalyzed = false;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();
  }

  void _initializeRenderer() {
    debugPrint('GPUDanmakuOverlay: 初始化渲染器');
    
    // 读取开发者设置
    final devOptions = context.read<DeveloperOptionsProvider>();
    
    _renderer = GPUDanmakuRenderer(
      config: widget.config,
      opacity: widget.opacity,
      isPaused: !widget.isPlaying, // 传递暂停状态
      showCollisionBoxes: devOptions.showGPUDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showGPUDanmakuTrackNumbers,
      onNeedRepaint: () {
        if (mounted) {
          debugPrint('GPUDanmakuOverlay: 收到重绘请求，调用setState');
          setState(() {
            // 触发重绘
          });
        }
      },
    );
  }

  @override
  void didUpdateWidget(GPUDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 暂停状态变化
    if (widget.isPlaying != oldWidget.isPlaying) {
      debugPrint('GPUDanmakuOverlay: 播放状态变化 - isPlaying: ${widget.isPlaying}');
      _renderer?.setPaused(!widget.isPlaying);
    }

    // 弹幕可见性变化
    if (widget.isVisible != oldWidget.isVisible) {
      if (widget.isVisible) {
        debugPrint('GPUDanmakuOverlay: 弹幕变为可见，开始同步');
        _syncDanmaku();
      } else {
        debugPrint('GPUDanmakuOverlay: 弹幕变为隐藏，清理弹幕');
        _clearDanmaku();
      }
    }

    // 检测时间轴切换（拖拽进度条或跳转）
    final timeDelta = (widget.currentPosition - oldWidget.currentPosition).abs();
    if (timeDelta > 2000) {
      debugPrint('GPUDanmakuOverlay: 检测到时间跳转（${timeDelta}ms），清理弹幕');
      _clearDanmaku();
      _addedDanmaku.clear();
      _lastSyncTime = 0.0;
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncDanmaku());
    }

    // 字体大小或透明度变化
    if (widget.config != oldWidget.config || widget.opacity != oldWidget.opacity) {
      debugPrint('GPUDanmakuOverlay: 更新显示选项 - 配置:${widget.config}, 透明度:${widget.opacity}');
      _renderer?.updateOptions(config: widget.config, opacity: widget.opacity);
      // 重新创建渲染器以应用新的参数
      _initializeRenderer();
    }
    
    // 检查开发者设置变化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkDebugOptionsChange();
      }
    });
  }

  /// 检查开发者设置变化
  void _checkDebugOptionsChange() {
    final devOptions = context.read<DeveloperOptionsProvider>();
    _renderer?.updateDebugOptions(
      showCollisionBoxes: devOptions.showGPUDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showGPUDanmakuTrackNumbers,
    );
  }

  void _syncDanmaku() {
    if (!mounted || _renderer == null || !widget.isVisible) {
      return;
    }

    final currentTimeSeconds = widget.currentPosition / 1000;
    
    // 避免频繁同步
    if ((currentTimeSeconds - _lastSyncTime).abs() < 0.1) return;
    _lastSyncTime = currentTimeSeconds;

    final videoState = context.read<VideoPlayerState>();
    final activeList = videoState.getActiveDanmakuList(currentTimeSeconds);

    // 只分析一次弹幕数据
    if (!_hasAnalyzed && activeList.isNotEmpty) {
      GPUDanmakuTest.analyzeDanmakuData(context, currentTimeSeconds);
      _hasAnalyzed = true;
    }

    int topDanmakuCount = 0;
    // 只处理顶部弹幕
    for (final danmaku in activeList) {
      final danmakuTime = (danmaku['time'] ?? 0.0) as double;
      final danmakuTypeRaw = danmaku['type'];
      final danmakuText = danmaku['content']?.toString() ?? '';
      final danmakuId = '${danmakuTime}_${danmakuText}_${danmaku['color']}';

      // 判断是否为顶部弹幕
      // 现有系统使用字符串类型
      bool isTopDanmaku = false;
      if (danmakuTypeRaw is String) {
        // 字符串类型：'top' 表示顶部弹幕
        isTopDanmaku = (danmakuTypeRaw == 'top');
      } else if (danmakuTypeRaw is int) {
        // 数字类型：通常 5 表示顶部弹幕
        isTopDanmaku = (danmakuTypeRaw == 5);
      }

      // 只处理顶部弹幕
      if (!isTopDanmaku) continue;
      
      topDanmakuCount++;

      // 检查是否已经添加
      if (_addedDanmaku.contains(danmakuId)) continue;

      // 检查是否在显示时间范围内
      final timeDiff = currentTimeSeconds - danmakuTime;
      if (timeDiff >= 0 && timeDiff <= 5.0) {
        _addTopDanmaku(danmaku, timeDiff);
        _addedDanmaku.add(danmakuId);
      }
    }
    
    if (topDanmakuCount > 0) {
      debugPrint('GPUDanmakuOverlay: 同步弹幕 - 当前时间:${currentTimeSeconds.toStringAsFixed(1)}s, 顶部弹幕数量:$topDanmakuCount');
    }
  }

  void _addTopDanmaku(Map<String, dynamic> danmaku, double timeOffset) {
    // 弹幕文本字段名为 'content'
    final text = danmaku['content']?.toString() ?? '';
    
    // 解析颜色字符串，例如 rgb(255,255,255)
    Color color = Colors.white;
    final colorStr = danmaku['color']?.toString();
    if (colorStr != null && colorStr.startsWith('rgb(')) {
      final vals = colorStr
          .replaceAll('rgb(', '')
          .replaceAll(')', '')
          .split(',')
          .map((e) => int.tryParse(e.trim()) ?? 255)
          .toList();
      if (vals.length == 3) {
        color = Color.fromARGB(255, vals[0], vals[1], vals[2]);
      }
    }

    final danmakuItem = DanmakuContentItem(
      text,
      color: color,
      type: DanmakuItemType.top,
      timeOffset: (timeOffset * 1000).toInt(),
    );

    debugPrint('GPUDanmakuOverlay: 添加顶部弹幕 - 文本:"$text", 颜色:$color, 时间偏移:${timeOffset.toStringAsFixed(2)}s');
    _renderer?.addDanmaku(danmakuItem);
  }

  void _clearDanmaku() {
    debugPrint('GPUDanmakuOverlay: 清理弹幕');
    _renderer?.clear();
  }

  @override
  void dispose() {
    debugPrint('GPUDanmakuOverlay: 释放资源');
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isVisible || _renderer == null) {
      return const SizedBox.shrink();
    }

    return Consumer2<VideoPlayerState, DeveloperOptionsProvider>(
      builder: (context, videoState, devOptions, child) {
        // 只在播放状态下定期同步弹幕
        if (widget.isPlaying) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _syncDanmaku());
        }

        return SizedBox.expand(
          child: CustomPaint(
            painter: _renderer,
            size: Size.infinite,
          ),
        );
      },
    );
  }
} 
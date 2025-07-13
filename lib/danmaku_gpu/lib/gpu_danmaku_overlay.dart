import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/video_player_state.dart';
import '../../danmaku/lib/danmaku_content_item.dart';
import '../../providers/developer_options_provider.dart';
import 'gpu_danmaku_renderer.dart';
import 'gpu_danmaku_config.dart';
import 'gpu_danmaku_test.dart';
import 'dynamic_font_atlas.dart';

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

  /// 预构建弹幕字符集（用于视频初始化时优化）
  /// 
  /// 在视频初始化时调用，预扫描所有弹幕文本并生成完整字符图集
  /// 避免播放时的动态图集更新导致的延迟
  static Future<void> prebuildDanmakuCharset(List<Map<String, dynamic>> danmakuList) async {
    if (danmakuList.isEmpty) return;
    
    debugPrint('GPUDanmakuOverlay: 开始预构建弹幕字符集');
    
    // 提取所有弹幕文本
    final List<String> texts = [];
    for (final danmaku in danmakuList) {
      final text = danmaku['content']?.toString() ?? '';
      if (text.isNotEmpty) {
        texts.add(text);
      }
    }
    
    if (texts.isEmpty) {
      debugPrint('GPUDanmakuOverlay: 没有弹幕文本，跳过字符集预构建');
      return;
    }
    
    // 创建临时字体图集进行预构建
    final config = GPUDanmakuConfig();
    final tempAtlas = DynamicFontAtlas(
      fontSize: config.fontSize,
      color: Colors.white,
    );
    
    try {
      // 生成基础字符集
      await tempAtlas.generate();
      
      // 预构建弹幕字符集
      await tempAtlas.prebuildFromTexts(texts);
      
      debugPrint('GPUDanmakuOverlay: 弹幕字符集预构建完成');
    } finally {
      // 释放临时图集资源
      tempAtlas.dispose();
    }
  }

  @override
  State<GPUDanmakuOverlay> createState() => _GPUDanmakuOverlayState();
}

class _GPUDanmakuOverlayState extends State<GPUDanmakuOverlay> with SingleTickerProviderStateMixin {
  GPUDanmakuRenderer? _renderer;
  double _lastSyncTime = 0.0;
  final Set<String> _addedDanmaku = {};
  bool _hasAnalyzed = false;
  
  // 使用AnimationController来驱动动画，避免setState循环
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();

    // 初始化AnimationController
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(days: 999), // 一个足够长的时间
    )..repeat(); // 让它一直运行

    // 添加监听器，在每一帧同步弹幕
    _controller.addListener(_onTick);
  }

  void _onTick() {
    // 总是同步弹幕数据，无论播放状态如何
    // 这样确保在暂停时隐藏/显示弹幕时，数据状态是完整的
    _syncDanmaku();
  }

  void _initializeRenderer() {
    debugPrint('GPUDanmakuOverlay: 初始化渲染器');

    // 读取开发者设置
    final devOptions = context.read<DeveloperOptionsProvider>();

    _renderer = GPUDanmakuRenderer(
      config: widget.config,
      opacity: widget.opacity,
      isPaused: !widget.isPlaying, // 传递暂停状态
      isVisible: widget.isVisible, // 传递可见性
      showCollisionBoxes: devOptions.showGPUDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showGPUDanmakuTrackNumbers,
      onNeedRepaint: () {
        if (mounted) {
          debugPrint('GPUDanmakuOverlay: 收到重绘请求，调用setState');
          setState(() {
            // 触发重绘, 通常由字体图集更新等事件触发
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
      _renderer?.setVisibility(widget.isVisible);
      
      // 移除：不再清空已添加记录，保持弹幕状态以避免重新显示时的延迟
      // 原代码：if (!widget.isVisible) { _addedDanmaku.clear(); }
      
      debugPrint('GPUDanmakuOverlay: 弹幕可见性变化 - isVisible: ${widget.isVisible}');
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
      // 优化：只在字体大小变化时才重新创建渲染器
      if (widget.config.fontSize != oldWidget.config.fontSize) {
        debugPrint('GPUDanmakuOverlay: 字体大小变化，重新创建渲染器');
        _initializeRenderer();
        // 字体大小变化时才需要清空并重新添加弹幕
        _addedDanmaku.clear();
      }
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
    if (!mounted || _renderer == null) {
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

    // 优化：定期清理过期的弹幕记录，避免内存泄漏
    if (_addedDanmaku.length > 1000) {
      _cleanupExpiredDanmakuRecords(currentTimeSeconds);
    }

    int topDanmakuCount = 0;
    int newDanmakuCount = 0; // 新增：统计新添加的弹幕数量
    
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
        newDanmakuCount++; // 新增：计数新添加的弹幕
      }
    }
    
    // 优化：只在有新弹幕时才打印日志
    if (newDanmakuCount > 0) {
      debugPrint('GPUDanmakuOverlay: 同步弹幕 - 当前时间:${currentTimeSeconds.toStringAsFixed(1)}s, 顶部弹幕总数:$topDanmakuCount, 新添加:$newDanmakuCount');
    }
  }

  /// 清理过期的弹幕记录
  void _cleanupExpiredDanmakuRecords(double currentTimeSeconds) {
    final expiredIds = <String>[];
    
    for (final danmakuId in _addedDanmaku) {
      // 从ID中提取时间戳
      final parts = danmakuId.split('_');
      if (parts.isNotEmpty) {
        final danmakuTime = double.tryParse(parts[0]) ?? 0.0;
        // 如果弹幕时间超过当前时间10秒，认为已过期
        if (currentTimeSeconds - danmakuTime > 10.0) {
          expiredIds.add(danmakuId);
        }
      }
    }
    
    // 移除过期记录
    for (final id in expiredIds) {
      _addedDanmaku.remove(id);
    }
    
    if (expiredIds.isNotEmpty) {
      debugPrint('GPUDanmakuOverlay: 清理过期弹幕记录 ${expiredIds.length} 个');
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
    _controller.removeListener(_onTick);
    _controller.dispose();
    _renderer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_renderer == null) {
      return const SizedBox.shrink();
    }

    return Consumer2<VideoPlayerState, DeveloperOptionsProvider>(
      builder: (context, videoState, devOptions, child) {
        // 即使弹幕不可见，也要保持组件在树上，以维持状态
        return IgnorePointer(
          ignoring: !widget.isVisible,
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _renderer,
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
} 
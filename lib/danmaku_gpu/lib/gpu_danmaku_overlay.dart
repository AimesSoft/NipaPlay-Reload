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
    
    // 使用全局字体图集管理器进行预构建
    final config = GPUDanmakuConfig();
    
    try {
      // 使用全局管理器预构建弹幕字符集
      await FontAtlasManager.prebuildFromTexts(
        fontSize: config.fontSize,
        texts: texts,
      );
      
      debugPrint('GPUDanmakuOverlay: 弹幕字符集预构建完成');
    } catch (e) {
      debugPrint('GPUDanmakuOverlay: 弹幕字符集预构建失败: $e');
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
  
  // 添加屏蔽词变化检测
  List<String> _lastBlockWords = [];
  
  // 添加合并弹幕变化检测
  bool _lastMergeDanmaku = false;
  
  // 🔥 新增：添加弹幕轨道状态变化检测
  Map<String, bool> _lastTrackEnabled = {};
  
  // 🔥 新增：添加弹幕类型过滤设置变化检测
  bool _lastBlockTopDanmaku = false;
  bool _lastBlockBottomDanmaku = false;
  bool _lastBlockScrollDanmaku = false;
  
  // 使用AnimationController来驱动动画，避免setState循环
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _initializeRenderer();

    // 初始化屏蔽词列表和合并弹幕状态
    final videoState = context.read<VideoPlayerState>();
    _lastBlockWords = List<String>.from(videoState.danmakuBlockWords);
    _lastMergeDanmaku = videoState.mergeDanmaku;
    _lastTrackEnabled = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    _lastBlockTopDanmaku = videoState.blockTopDanmaku;
    _lastBlockBottomDanmaku = videoState.blockBottomDanmaku;
    _lastBlockScrollDanmaku = videoState.blockScrollDanmaku;

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

    // 设置初始屏蔽词列表和合并弹幕状态
    final videoState = context.read<VideoPlayerState>();
    _renderer?.setBlockWords(videoState.danmakuBlockWords);
    _renderer?.setMergeDanmaku(videoState.mergeDanmaku);
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
      // 优化：不再重新创建渲染器，只清理弹幕数据
      // 字体图集由全局管理器管理，可以复用
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
    
    // 检测屏蔽词变化
    final videoState = context.read<VideoPlayerState>();
    final currentBlockWords = List<String>.from(videoState.danmakuBlockWords);
    final blockWordsChanged = !_listEquals(_lastBlockWords, currentBlockWords);
    
    if (blockWordsChanged) {
      debugPrint('GPUDanmakuOverlay: 检测到屏蔽词变化，更新渲染器屏蔽词列表');
      _lastBlockWords = currentBlockWords;
      
      // 直接更新渲染器的屏蔽词列表，不清空弹幕
      _renderer?.setBlockWords(currentBlockWords);
    }

    // 检测合并弹幕变化
    final currentMergeDanmaku = videoState.mergeDanmaku;
    final mergeDanmakuChanged = _lastMergeDanmaku != currentMergeDanmaku;
    
    if (mergeDanmakuChanged) {
      debugPrint('GPUDanmakuOverlay: 检测到合并弹幕设置变化，更新渲染器合并弹幕状态');
      _lastMergeDanmaku = currentMergeDanmaku;
      
      // 直接更新渲染器的合并弹幕状态，不清空弹幕
      _renderer?.setMergeDanmaku(currentMergeDanmaku);
    }
    
    // 🔥 新增：检测弹幕轨道状态变化
    final currentTracks = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    final tracksChanged = !_mapEquals(_lastTrackEnabled, currentTracks);
    
    if (tracksChanged) {
      debugPrint('GPUDanmakuOverlay: 检测到弹幕轨道状态变化，清空弹幕记录');
      _lastTrackEnabled = currentTracks;
      _addedDanmaku.clear(); // 清空已添加的弹幕记录
      _renderer?.clear(); // 清空渲染器中的弹幕
      _lastSyncTime = 0.0; // 🔥 关键修复：重置同步时间，确保弹幕能重新加载
      
      // 🔥 新增：立即触发同步，不等待下一次同步周期
      debugPrint('GPUDanmakuOverlay: 立即触发弹幕同步');
      _syncDanmaku(); // 直接调用同步，不等待postFrameCallback
    }
    
    // 🔥 新增：检测弹幕类型过滤设置变化
    final currentBlockTopDanmaku = videoState.blockTopDanmaku;
    final currentBlockBottomDanmaku = videoState.blockBottomDanmaku;
    final currentBlockScrollDanmaku = videoState.blockScrollDanmaku;

    final blockTopDanmakuChanged = _lastBlockTopDanmaku != currentBlockTopDanmaku;
    final blockBottomDanmakuChanged = _lastBlockBottomDanmaku != currentBlockBottomDanmaku;
    final blockScrollDanmakuChanged = _lastBlockScrollDanmaku != currentBlockScrollDanmaku;

    if (blockTopDanmakuChanged || blockBottomDanmakuChanged || blockScrollDanmakuChanged) {
      debugPrint('GPUDanmakuOverlay: 检测到弹幕类型过滤设置变化，清空弹幕记录');
      _lastBlockTopDanmaku = currentBlockTopDanmaku;
      _lastBlockBottomDanmaku = currentBlockBottomDanmaku;
      _lastBlockScrollDanmaku = currentBlockScrollDanmaku;
      _addedDanmaku.clear(); // 清空已添加的弹幕记录
      _renderer?.clear(); // 清空渲染器中的弹幕
      _lastSyncTime = 0.0; // 🔥 关键修复：重置同步时间，确保弹幕能重新加载
      
      // 🔥 新增：立即触发同步，不等待下一次同步周期
      debugPrint('GPUDanmakuOverlay: 立即触发弹幕同步');
      _syncDanmaku(); // 直接调用同步，不等待postFrameCallback
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

  /// 比较两个列表是否相等
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 比较两个Map是否相等
  bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
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
    
    // 🔥 新增：支持多弹幕来源的轨道管理
    // 获取所有启用的弹幕轨道
    final enabledTracks = <String, List<Map<String, dynamic>>>{};
    final tracks = videoState.danmakuTracks;
    final trackEnabled = videoState.danmakuTrackEnabled;
    
    // 只处理启用的轨道
    for (final trackId in tracks.keys) {
      if (trackEnabled[trackId] == true) {
        final trackData = tracks[trackId]!;
        final trackDanmaku = trackData['danmakuList'] as List<Map<String, dynamic>>;
        
        // 过滤当前时间窗口内的弹幕
        final activeDanmaku = trackDanmaku.where((d) {
          final t = d['time'] as double? ?? 0.0;
          return t >= currentTimeSeconds - 15.0 && t <= currentTimeSeconds + 15.0;
        }).toList();
        
        if (activeDanmaku.isNotEmpty) {
          enabledTracks[trackId] = activeDanmaku;
        }
      }
    }
    
    // 合并所有启用轨道的弹幕
    final List<Map<String, dynamic>> activeList = [];
    for (final trackDanmaku in enabledTracks.values) {
      activeList.addAll(trackDanmaku);
    }
    
    // 按时间排序
    activeList.sort((a, b) {
      final timeA = (a['time'] as double?) ?? 0.0;
      final timeB = (b['time'] as double?) ?? 0.0;
      return timeA.compareTo(timeB);
    });

    // 只分析一次弹幕数据
    if (!_hasAnalyzed && activeList.isNotEmpty) {
      GPUDanmakuTest.analyzeDanmakuData(context, currentTimeSeconds);
      _hasAnalyzed = true;
    }

    // 优化：定期清理过期的弹幕记录，避免内存泄漏
    if (_addedDanmaku.length > 1000) {
      _cleanupExpiredDanmakuRecords(currentTimeSeconds);
    }

    // 如果启用了合并弹幕，先预处理弹幕列表
    List<Map<String, dynamic>> processedList = activeList;
    if (_lastMergeDanmaku) {
      processedList = _preprocessDanmakuForMerging(activeList, currentTimeSeconds);
    }

    int topDanmakuCount = 0;
    int newDanmakuCount = 0; // 新增：统计新添加的弹幕数量
    
    // 只处理顶部弹幕
    for (final danmaku in processedList) {
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
      
      // 🔥 新增：检查是否屏蔽顶部弹幕
      if (videoState.blockTopDanmaku) {
        continue; // 如果屏蔽顶部弹幕，跳过这条弹幕
      }
      
      topDanmakuCount++;

      // 检查是否已经添加
      if (_addedDanmaku.contains(danmakuId)) continue;

      // 检查是否在显示时间范围内
      final timeDiff = currentTimeSeconds - danmakuTime;
      if (timeDiff >= 0 && timeDiff <= 5.0) {
        // 🔥 关键修复：当开启合并弹幕时，只显示isFirstInGroup为true的弹幕
        if (_lastMergeDanmaku) {
          final isMerged = danmaku['isMerged'] == true;
          final isFirstInGroup = danmaku['isFirstInGroup'] == true;
          
          // 如果是合并弹幕但不是组内第一条，则跳过
          if (isMerged && !isFirstInGroup) {
            continue;
          }
        }
        
        _addTopDanmaku(danmaku, timeDiff);
        _addedDanmaku.add(danmakuId);
        newDanmakuCount++; // 新增：计数新添加的弹幕
      }
    }
    
    // 优化：只在有新弹幕时才打印日志
    if (newDanmakuCount > 0) {
      debugPrint('GPUDanmakuOverlay: 同步弹幕 - 当前时间:${currentTimeSeconds.toStringAsFixed(1)}s, 顶部弹幕总数:$topDanmakuCount, 新添加:$newDanmakuCount, 启用轨道数:${enabledTracks.length}');
    }
  }

  /// 预处理弹幕列表，实现合并逻辑
  List<Map<String, dynamic>> _preprocessDanmakuForMerging(
    List<Map<String, dynamic>> danmakuList,
    double currentTimeSeconds,
  ) {
    final Map<String, List<Map<String, dynamic>>> contentGroups = {};
    final List<Map<String, dynamic>> result = [];
    
    // 按内容分组，只考虑顶部弹幕
    for (final danmaku in danmakuList) {
      final danmakuTypeRaw = danmaku['type'];
      bool isTopDanmaku = false;
      
      if (danmakuTypeRaw is String) {
        isTopDanmaku = (danmakuTypeRaw == 'top');
      } else if (danmakuTypeRaw is int) {
        isTopDanmaku = (danmakuTypeRaw == 5);
      }
      
      if (!isTopDanmaku) {
        result.add(danmaku);
        continue;
      }
      
      final content = danmaku['content']?.toString() ?? '';
      final time = (danmaku['time'] ?? 0.0) as double;
      
      // 在45秒窗口内统计相同内容
      if ((currentTimeSeconds - time).abs() <= 45.0) {
        if (!contentGroups.containsKey(content)) {
          contentGroups[content] = [];
        }
        contentGroups[content]!.add(danmaku);
      } else {
        result.add(danmaku);
      }
    }
    
    // 处理分组，只保留每组的第一条，并标记合并信息
    for (final entry in contentGroups.entries) {
      final content = entry.key;
      final group = entry.value;
      
      if (group.length > 1) {
        // 按时间排序，取最早的一条
        group.sort((a, b) => (a['time'] as double).compareTo(b['time'] as double));
        final firstDanmaku = Map<String, dynamic>.from(group.first);
        
        // 标记合并信息
        firstDanmaku['isMerged'] = true;
        firstDanmaku['mergeCount'] = group.length;
        firstDanmaku['isFirstInGroup'] = true;
        firstDanmaku['groupContent'] = content;
        
        result.add(firstDanmaku);
      } else {
        result.add(group.first);
      }
    }
    
    return result;
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

    // 处理合并弹幕信息
    final isMerged = danmaku['isMerged'] == true;
    final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
    final isFirstInGroup = danmaku['isFirstInGroup'] == true;
    final groupContent = danmaku['groupContent']?.toString();

    // 根据合并状态调整字体大小
    double fontSizeMultiplier = 1.0;
    String? countText;
    if (isMerged) {
      // 使用GPU渲染器的计算方法
      fontSizeMultiplier = _renderer?.calculateMergedFontSizeMultiplier?.call(mergeCount) ?? 1.0;
      countText = 'x$mergeCount';
    }

    final danmakuItem = DanmakuContentItem(
      text,
      color: color,
      type: DanmakuItemType.top,
      timeOffset: (timeOffset * 1000).toInt(),
      fontSizeMultiplier: fontSizeMultiplier,
      countText: countText,
    );

    final mergeInfo = isMerged ? ' (合并${mergeCount}条)' : '';
    debugPrint('GPUDanmakuOverlay: 添加顶部弹幕 - 文本:"$text"$mergeInfo, 颜色:$color, 时间偏移:${timeOffset.toStringAsFixed(2)}s');
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
    
    // 清理全局字体图集管理器（在应用退出时）
    FontAtlasManager.disposeAll();
    
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
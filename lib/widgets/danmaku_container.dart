import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer_factory.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'single_danmaku.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
// import 'danmaku_group_widget.dart'; // 已移除分组渲染

class DanmakuContainer extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final double currentTime;
  final double videoDuration;
  final double fontSize;
  final bool isVisible;
  final double opacity;
  final String status; // 添加播放状态参数
  final double playbackRate; // 添加播放速度参数
  final double displayArea; // 弹幕轨道显示区域
  final Function(List<PositionedDanmakuItem>)? onLayoutCalculated;

  const DanmakuContainer({
    super.key,
    required this.danmakuList,
    required this.currentTime,
    required this.videoDuration,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
    required this.status, // 添加播放状态参数
    required this.playbackRate, // 添加播放速度参数
    required this.displayArea, // 弹幕轨道显示区域
    this.onLayoutCalculated,
  });

  @override
  State<DanmakuContainer> createState() => _DanmakuContainerState();
}

class _DanmakuContainerState extends State<DanmakuContainer> {
  final double _danmakuHeight = 25.0; // 弹幕高度
  late final double _verticalSpacing; // 上下间距
  // final double _horizontalSpacing = 20.0; // 左右间距（未使用，移除）
  // 文本宽度缓存，减少 TextPainter.layout 开销
  final Map<String, double> _textWidthCache = {};
  // 可见窗口的二分索引范围（基于已排序列表）
  int _visibleLeftIndex = 0;
  int _visibleRightIndex = -1;
  // 滚动轨道的“可用时间”表：track -> nextAvailableTime（基于10s滚动模型）
  final Map<int, double> _scrollLaneNextAvailableUntil = {};
  // 安全间距比例（相对屏幕宽度）
  static const double _safetyMarginRatio = 0.02;
  
  // 为每种类型的弹幕创建独立的轨道系统
  final Map<String, List<Map<String, dynamic>>> _trackDanmaku = {
    'scroll': [], // 滚动弹幕轨道
    'top': [], // 顶部弹幕轨道
    'bottom': [], // 底部弹幕轨道
  };
  
  // 每种类型弹幕的当前轨道
  final Map<String, int> _currentTrack = {
    'scroll': 0,
    'top': 0,
    'bottom': 0,
  };
  
  // 存储每个弹幕的Y轴位置
  final Map<String, double> _danmakuYPositions = {};
  
  // 存储弹幕的轨道信息，用于持久化
  final Map<String, Map<String, dynamic>> _danmakuTrackInfo = {};
  
  // 存储当前画布大小
  Size _currentSize = Size.zero;
  
  // 存储已处理过的弹幕信息，用于合并判断
  final Map<String, Map<String, dynamic>> _processedDanmaku = {};
  
  // 存储按时间排序的弹幕列表，用于预测未来45秒内的弹幕
  List<Map<String, dynamic>> _sortedDanmakuList = [];
  
  // 存储内容组的第一个出现时间
  final Map<String, double> _contentFirstTime = {};
  
  // 存储内容组的合并信息
  final Map<String, Map<String, dynamic>> _contentGroupInfo = {};
  
  // 添加一个变量追踪屏蔽状态的哈希值
  String _lastBlockStateHash = '';

  // 文本渲染器
  DanmakuTextRenderer? _textRenderer;
  
  // 计算当前屏蔽状态的哈希值
  String _getBlockStateHash(VideoPlayerState videoState) {
    return '${videoState.blockTopDanmaku}-${videoState.blockBottomDanmaku}-${videoState.blockScrollDanmaku}-${videoState.danmakuBlockWords.length}';
  }

  // 计算合并弹幕的字体大小倍率
  double _calcMergedFontSizeMultiplier(int mergeCount) {
    // 按照数量计算放大倍率，例如15条是1.5倍
    double multiplier = 1.0 + (mergeCount / 10.0);
    // 限制最大倍率避免过大
    return multiplier.clamp(1.0, 2.0);
  }

  @override
  void initState() {
    super.initState();
    // 根据设备类型设置垂直间距
    _verticalSpacing = globals.isPhone ? 10.0 : 20.0;
    
    // 初始化文本渲染器
    _initializeTextRenderer();
    
    // 初始化时获取画布大小
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _currentSize = MediaQuery.of(context).size;
      });
    });
    
    // 初始化时对弹幕列表进行预处理和排序
    _preprocessDanmakuList();
  }

  Future<void> _initializeTextRenderer() async {
    _textRenderer = await DanmakuTextRendererFactory.create();
    if (mounted) {
      setState(() {});
    }
  }
  
  // 对弹幕列表进行预处理和排序
  void _preprocessDanmakuList() {
    // 清空所有旧的布局和位置缓存，确保全新渲染
    _danmakuYPositions.clear();
    _danmakuTrackInfo.clear();
    for (var type in _trackDanmaku.keys) {
      _trackDanmaku[type]!.clear();
    }

    if (widget.danmakuList.isEmpty) {
      // 如果新列表为空，确保清空相关状态
      _sortedDanmakuList.clear();
      _processedDanmaku.clear();
      _contentFirstTime.clear();
      _contentGroupInfo.clear();
      // 触发一次重绘以清空屏幕上的弹幕
      if (mounted) {
        setState(() {});
      }
      return;
    }
    
    // 清空缓存
    _contentFirstTime.clear();
    _contentGroupInfo.clear();
    _processedDanmaku.clear();
    
    // 复制一份弹幕列表以避免修改原数据
    _sortedDanmakuList = List<Map<String, dynamic>>.from(widget.danmakuList);
    
    // 按时间排序
    _sortedDanmakuList.sort((a, b) => 
      (a['time'] as double).compareTo(b['time'] as double));
      
    // 使用滑动窗口法处理弹幕
    _processDanmakuWithSlidingWindow();

  // 重置可见窗口与滚动轨道状态
  _visibleLeftIndex = 0;
  _visibleRightIndex = -1;
  _scrollLaneNextAvailableUntil.clear();
  // 可选：在切换视频或重置时清一轮宽度缓存
  _textWidthCache.clear();
  }
  
  // 使用滑动窗口法处理弹幕
  void _processDanmakuWithSlidingWindow() {
    if (_sortedDanmakuList.isEmpty) return;
    
    // 使用双指针实现滑动窗口
    int left = 0;
    int right = 0;
    final int n = _sortedDanmakuList.length;
    
    // 使用哈希表记录窗口内各内容的出现次数
    final Map<String, int> windowContentCount = {};
    
    while (right < n) {
      final currentDanmaku = _sortedDanmakuList[right];
      final content = currentDanmaku['content'] as String;
      final time = currentDanmaku['time'] as double;
      
      // 更新窗口内内容计数
      windowContentCount[content] = (windowContentCount[content] ?? 0) + 1;
      
      // 移动左指针，保持窗口在45秒内
      while (left <= right && time - (_sortedDanmakuList[left]['time'] as double) > 45.0) {
        final leftContent = _sortedDanmakuList[left]['content'] as String;
        windowContentCount[leftContent] = (windowContentCount[leftContent] ?? 1) - 1;
        if (windowContentCount[leftContent] == 0) {
          windowContentCount.remove(leftContent);
        }
        left++;
      }
      
      // 处理当前弹幕
      final danmakuKey = '$content-$time';
      final count = windowContentCount[content] ?? 1;
      
      if (count > 1) {
        // 如果窗口内出现多次，标记为合并状态
        if (!_contentGroupInfo.containsKey(content)) {
          // 记录组的第一个出现时间
          _contentFirstTime[content] = time;
          _contentGroupInfo[content] = {
            'firstTime': time,
            'count': count,
            'processed': false
          };
        }
        
        // 更新组的计数
        _contentGroupInfo[content]!['count'] = count;
        
        // 处理当前弹幕
        _processedDanmaku[danmakuKey] = {
          ...currentDanmaku,
          'merged': true,
          'mergeCount': count,
          'isFirstInGroup': time == _contentFirstTime[content],
          'groupContent': content
        };
      } else {
        // 只出现一次，保持原样
        _processedDanmaku[danmakuKey] = currentDanmaku;
      }
      
      right++;
    }
  }

  @override
  void didUpdateWidget(DanmakuContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 我们将在build方法中处理列表的变化，以确保总是使用最新的数据
    // 因此这里的检查可以移除或保留以作备用
    if (widget.danmakuList != oldWidget.danmakuList) {
      _preprocessDanmakuList(); // 在列表对象变化时调用
    }
  }

  // 重新计算所有弹幕位置
  void _resize(Size newSize) {
    // 更新当前大小
    _currentSize = newSize;
    
    // 清空轨道信息，重新分配轨道
    
    // 保存当前轨道信息，用于恢复
    final tempTrackInfo = Map<String, Map<String, dynamic>>.from(_danmakuTrackInfo);
    
    // 清空当前轨道系统
    for (var type in _trackDanmaku.keys) {
      _trackDanmaku[type]!.clear();
    }
    
    // 清空Y轴位置缓存，强制重新计算
    _danmakuYPositions.clear();
  // 轨道时间状态也需要清理，避免尺寸变化导致安全距离不同步
  _scrollLaneNextAvailableUntil.clear();
    
    // 恢复轨道信息，同时更新Y轴位置
    for (var entry in tempTrackInfo.entries) {
      final key = entry.key;
      final info = entry.value;
      
      if (key.contains('-')) {
        final parts = key.split('-');
        if (parts.length >= 3) {
          final type = parts[0];
          final content = parts.length > 3 ? parts.sublist(1, parts.length - 1).join('-') : parts[1];
          final time = double.tryParse(parts.last) ?? 0.0;
          
          final track = info['track'] as int;
          final isMerged = info['isMerged'] as bool? ?? false;
          final mergeCount = isMerged ? (info['mergeCount'] as int? ?? 1) : 1;
          
          // 根据新的窗口高度重新计算Y轴位置
          final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
          final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
          double newYPosition;
          
          if (type == 'bottom') {
            // 底部弹幕从底部开始计算，确保不会超出窗口
            newYPosition = newSize.height - (track + 1) * trackHeight - adjustedDanmakuHeight;
          } else {
            // 其他弹幕从顶部开始计算，加上间距
            newYPosition = track * trackHeight + _verticalSpacing;
          }
          
          // 保存新的Y轴位置
          _danmakuYPositions[key] = newYPosition;
          
          // 添加到轨道系统中，恢复轨道信息
          _trackDanmaku[type]!.add({
            'content': content,
            'time': time,
            'track': track,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
            'width': info['width'],
          });
        }
      }
    }
    
    // 触发重绘
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        // 更新后强制刷新
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 不再在这里监听大小变化，改为在LayoutBuilder中处理
  }

  

  // 顶部和底部弹幕的重叠检测
  bool _willOverlap(Map<String, dynamic> existingDanmaku, Map<String, dynamic> newDanmaku, double currentTime) {
    final existingTime = existingDanmaku['time'] as double;
    final newTime = newDanmaku['time'] as double;
    
    // 计算两个弹幕的显示时间范围
    final existingStartTime = existingTime;
    final existingEndTime = existingTime + 5; // 顶部和底部弹幕显示5秒
    
    final newStartTime = newTime;
    final newEndTime = newTime + 5;
    
    // 增加安全时间间隔，避免弹幕过于接近
    const safetyTime = 0.5; // 0.5秒的安全时间
    
    // 如果两个弹幕的显示时间有重叠，且间隔小于安全时间，则会发生重叠
    return (newStartTime <= existingEndTime + safetyTime && newEndTime + safetyTime >= existingStartTime);
  }

  // 检查顶部/底部弹幕轨道密度
  bool _isStaticTrackFull(List<Map<String, dynamic>> trackDanmaku, double currentTime) {
    // 只统计当前在屏幕内的弹幕
    final visibleDanmaku = trackDanmaku.where((danmaku) {
      final time = danmaku['time'] as double;
      return currentTime - time >= 0 && currentTime - time <= 5;
    }).toList();
    
    // 如果当前轨道有弹幕，就认为轨道已满
    return visibleDanmaku.isNotEmpty;
  }

  double _getYPosition(String type, String content, double time, bool isMerged, [int mergeCount = 1]) {
    final screenHeight = _currentSize.height;
    final screenWidth = _currentSize.width;
    final danmakuKey = '$type-$content-$time';
    
    // 如果弹幕已经有位置，直接返回
    if (_danmakuYPositions.containsKey(danmakuKey)) {
      return _danmakuYPositions[danmakuKey]!;
    }
    
    // 确保mergeCount不为null
    mergeCount = mergeCount > 0 ? mergeCount : 1;
    
    // 获取弹幕堆叠设置状态
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final allowStacking = videoState.danmakuStacking;
    
    // 从 VideoPlayerState 获取轨道信息
    if (videoState.danmakuTrackInfo.containsKey(danmakuKey)) {
      final trackInfo = videoState.danmakuTrackInfo[danmakuKey]!;
      final track = trackInfo['track'] as int;
      
      // 考虑合并状态调整轨道高度
      final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
      final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
      
      // 根据类型计算Y轴位置
      double yPosition;
      if (type == 'bottom') {
        yPosition = screenHeight - (track + 1) * trackHeight - adjustedDanmakuHeight - _verticalSpacing;
      } else {
        yPosition = track * trackHeight + _verticalSpacing;
      }
      
      // 更新轨道信息
      _trackDanmaku[type]!.add({
        'content': content,
        'time': time,
        'track': track,
        'width': trackInfo['width'] as double,
        'isMerged': isMerged,
      });
      
      _danmakuYPositions[danmakuKey] = yPosition;
      return yPosition;
    }
    
  // 计算弹幕宽度和高度（带缓存）
  final fontSize = isMerged ? widget.fontSize * _calcMergedFontSizeMultiplier(mergeCount) : widget.fontSize;
  final danmakuWidth = _getTextWidth(content, fontSize);
    
    // 清理已经消失的弹幕
    _trackDanmaku[type]!.removeWhere((danmaku) {
      final danmakuTime = danmaku['time'] as double;
      return widget.currentTime - danmakuTime > 10;
    });
    
    // 计算可用轨道数，考虑弹幕高度和间距以及显示区域
    final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
    final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
    final effectiveHeight = screenHeight * widget.displayArea; // 根据显示区域调整有效高度
    int maxTracks = ((effectiveHeight - adjustedDanmakuHeight - _verticalSpacing) / trackHeight).floor();
    // 安全保护：当可用轨道数<=0（极小窗口/显示区域）时，夹紧为至少1条轨道，维持原有堆叠/重叠逻辑
    if (maxTracks <= 0) {
      maxTracks = 1;
    }
    
    // 根据弹幕类型分配轨道
    if (type == 'scroll') {
      // 使用“每轨道可用时间”贪心分配，避免逐一碰撞
      // 基于恒定速度滚动模型：duration=10s，总距离=S+W
      final double D = 10.0; // 滚动总时长
      // 安全间距（合并弹幕更大）
      double safetyMargin = screenWidth * _safetyMarginRatio;
      if (isMerged) {
        safetyMargin = screenWidth * (_safetyMarginRatio + (mergeCount / 100.0));
      }

      int? chosenTrack;
      for (int track = 0; track < maxTracks; track++) {
        final nextAvail = _scrollLaneNextAvailableUntil[track] ?? double.negativeInfinity;
        if (time >= nextAvail) {
          chosenTrack = track;
          break;
        }
      }
      if (chosenTrack == null) {
        if (!allowStacking) {
          _danmakuYPositions[danmakuKey] = -1000;
          return -1000;
        }
        // 允许堆叠则轮询一个轨道（维持现有行为）
        _currentTrack[type] = (_currentTrack[type]! + 1) % maxTracks;
        chosenTrack = _currentTrack[type]!;
      }

      // 记录本次分配，并计算该轨道的下一次可用时间
      _trackDanmaku['scroll']!.add({
        'content': content,
        'time': time,
        'track': chosenTrack,
        'width': danmakuWidth,
        'isMerged': isMerged,
        'mergeCount': mergeCount,
      });

      // nextAvailable = time + D * (W + margin) / (S + W)
      final nextAvailable = time + D * ((danmakuWidth + safetyMargin) / (screenWidth + danmakuWidth));
      _scrollLaneNextAvailableUntil[chosenTrack] = nextAvailable;

      final yPosition = chosenTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': chosenTrack,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        });
      });
      return yPosition;
    } else if (type == 'top') {
      // 顶部弹幕：从顶部开始逐轨道分配
      final availableTracks = maxTracks;
      
      // 从顶部开始尝试分配轨道
      for (int track = 0; track < availableTracks; track++) {
        final trackDanmaku = _trackDanmaku['top']!.where((d) => d['track'] == track).toList();
        
        if (trackDanmaku.isEmpty) {
          _trackDanmaku['top']!.add({
            'content': content,
            'time': time,
            'track': track,
            'width': danmakuWidth,
            'isMerged': isMerged,
          });
          final yPosition = track * trackHeight + _verticalSpacing;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
              'isMerged': isMerged,
            });
          });
          return yPosition;
        }
        
        // 检查轨道是否已满
        if (!_isStaticTrackFull(trackDanmaku, widget.currentTime)) {
          bool hasOverlap = false;
          for (var danmaku in trackDanmaku) {
            if (_willOverlap(danmaku, {
              'time': time,
              'width': danmakuWidth,
              'isMerged': isMerged,
              'mergeCount': mergeCount,
            }, widget.currentTime)) {
              hasOverlap = true;
              break;
            }
          }
          
          if (!hasOverlap) {
            _trackDanmaku['top']!.add({
              'content': content,
              'time': time,
              'track': track,
              'width': danmakuWidth,
              'isMerged': isMerged,
              'mergeCount': mergeCount,
            });
            final yPosition = track * trackHeight + _verticalSpacing;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
                'isMerged': isMerged,
                'mergeCount': mergeCount,
              });
            });
            return yPosition;
          }
        }
      }
      
      // 如果所有轨道都满了且允许弹幕堆叠，则使用循环轨道
      if (allowStacking) {
        // 所有轨道都满了，循环使用轨道
        _currentTrack[type] = (_currentTrack[type]! + 1) % availableTracks;
        final track = _currentTrack[type]!;
        
        _trackDanmaku['top']!.add({
          'content': content,
          'time': time,
          'track': track,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        });
        final yPosition = track * trackHeight + _verticalSpacing;
        _danmakuYPositions[danmakuKey] = yPosition;
        // 延迟更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          videoState.updateDanmakuTrackInfo(danmakuKey, {
            'track': track,
            'width': danmakuWidth,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
          });
        });
        return yPosition;
      } else {
        // 如果不允许堆叠，则返回屏幕外位置
        _danmakuYPositions[danmakuKey] = -1000;
        return -1000;
      }
    } else if (type == 'bottom') {
      // 底部弹幕：从底部开始逐轨道分配
      final availableTracks = maxTracks;
      
      // 从底部开始尝试分配轨道
      for (int i = 0; i < availableTracks; i++) {
        final track = i; // 从0开始，表示从底部开始的轨道编号
        final trackDanmaku = _trackDanmaku['bottom']!.where((d) => d['track'] == track).toList();
        
        if (trackDanmaku.isEmpty) {
          _trackDanmaku['bottom']!.add({
            'content': content,
            'time': time,
            'track': track,
            'width': danmakuWidth,
            'isMerged': isMerged,
          });
          // 修改Y轴位置计算，从底部开始计算，并考虑合并状态下的高度
          final yPosition = screenHeight - (track + 1) * trackHeight - adjustedDanmakuHeight;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
              'isMerged': isMerged,
            });
          });
          return yPosition;
        }
        
        // 检查轨道是否已满
        if (!_isStaticTrackFull(trackDanmaku, widget.currentTime)) {
          bool hasOverlap = false;
          for (var danmaku in trackDanmaku) {
            if (_willOverlap(danmaku, {
              'time': time,
              'width': danmakuWidth,
              'isMerged': isMerged,
              'mergeCount': mergeCount,
            }, widget.currentTime)) {
              hasOverlap = true;
              break;
            }
          }
          
          if (!hasOverlap) {
            _trackDanmaku['bottom']!.add({
              'content': content,
              'time': time,
              'track': track,
              'width': danmakuWidth,
              'isMerged': isMerged,
              'mergeCount': mergeCount,
            });
            // 修改Y轴位置计算，从底部开始计算，并考虑合并状态下的高度
            final yPosition = screenHeight - (track + 1) * trackHeight - adjustedDanmakuHeight;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
                'isMerged': isMerged,
                'mergeCount': mergeCount,
              });
            });
            return yPosition;
          }
        }
      }
      
      // 如果所有轨道都满了且允许弹幕堆叠，则使用循环轨道
      if (allowStacking) {
        // 所有轨道都满了，循环使用轨道
        _currentTrack[type] = (_currentTrack[type]! + 1) % availableTracks;
        final track = _currentTrack[type]!;
        
        _trackDanmaku['bottom']!.add({
          'content': content,
          'time': time,
          'track': track,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        });
        // 修改Y轴位置计算，从底部开始计算，并考虑合并状态下的高度
        final yPosition = screenHeight - (track + 1) * trackHeight - adjustedDanmakuHeight;
        _danmakuYPositions[danmakuKey] = yPosition;
        // 延迟更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          videoState.updateDanmakuTrackInfo(danmakuKey, {
            'track': track,
            'width': danmakuWidth,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
          });
        });
        return yPosition;
      } else {
        // 如果不允许堆叠，则返回屏幕外位置
        _danmakuYPositions[danmakuKey] = -1000;
        return -1000;
      }
    }
    
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    // 弹幕不可见时，彻底不渲染，避免 TextPainter/ParagraphBuilder 开销
    if (!widget.isVisible) {
      return const SizedBox.shrink();
    }
    if (_textRenderer == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);

        if (newSize != _currentSize) {
          _resize(newSize);
        }

        // 总是在build方法中重新处理弹幕列表，以响应外部变化
        // _preprocessDanmakuList(); // 从build方法移回didUpdateWidget

        return Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            // 弹幕不可见时仍然避免不必要计算
            if (!widget.isVisible) {
              return const SizedBox.shrink();
            }
            final mergeDanmaku = videoState.danmakuVisible && videoState.mergeDanmaku;
            final allowStacking = videoState.danmakuStacking;
            final forceRefresh = _getBlockStateHash(videoState) != _lastBlockStateHash;
            if (forceRefresh) {
              _lastBlockStateHash = _getBlockStateHash(videoState);
            }

            final groupedDanmaku = _getCachedGroupedDanmaku(
              widget.danmakuList,
              widget.currentTime,
              mergeDanmaku,
              allowStacking,
              force: forceRefresh,
            );

            final List<Widget> danmakuWidgets = [];
            final List<PositionedDanmakuItem> positionedItems = [];

            for (var entry in groupedDanmaku.entries) {
              final type = entry.key;
              for (var danmaku in entry.value) {
                final time = danmaku['time'] as double;
                final content = danmaku['content'] as String;
                final colorStr = danmaku['color'] as String;
                final isMerged = danmaku['merged'] == true;
                final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
                
                final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.tryParse(s.trim()) ?? 255).toList();
                final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);

                final danmakuType = DanmakuItemType.values.firstWhere((e) => e.toString().split('.').last == type, orElse: () => DanmakuItemType.scroll);

                final danmakuItem = DanmakuContentItem(
                  content,
                  type: danmakuType,
                  color: color,
                  fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
                  countText: isMerged ? 'x$mergeCount' : null,
                  isMe: danmaku['isMe'] ?? false,
                );

                final yPosition = _getYPosition(type, content, time, isMerged, mergeCount);
                if (yPosition < -500) continue;

                final textWidth = _getTextWidth(danmakuItem.text, widget.fontSize * danmakuItem.fontSizeMultiplier);
                
                double xPosition;
                double offstageX = newSize.width;

                if (danmakuType == DanmakuItemType.scroll) {
                  const duration = 10.0; // 保持10秒的移动时间
                  const earlyStartTime = 1.0; // 提前1秒开始
                  final elapsed = widget.currentTime - time;
                  
                  if (elapsed >= -earlyStartTime && elapsed <= duration) {
                    // 🔥 修复：弹幕从更远的屏幕外开始，确保时间轴时间点时刚好在屏幕边缘
                    final extraDistance = (newSize.width + textWidth) / 10; // 额外距离
                    final startX = newSize.width + extraDistance; // 起始位置
                    final totalDistance = extraDistance + newSize.width + textWidth; // 总移动距离
                    final adjustedElapsed = elapsed + earlyStartTime; // 调整到[0, 11]范围
                    final totalDuration = duration + earlyStartTime; // 总时长11秒
                    
                    xPosition = startX - (adjustedElapsed / totalDuration) * totalDistance;
                  } else {
                    xPosition = elapsed < -earlyStartTime ? newSize.width : -textWidth;
                  }
                  offstageX = newSize.width;
                } else {
                  xPosition = (newSize.width - textWidth) / 2;
                }

                positionedItems.add(PositionedDanmakuItem(
                  content: danmakuItem,
                  x: xPosition,
                  y: yPosition,
                  offstageX: offstageX,
                  time: time,
                ));

                if (widget.onLayoutCalculated == null) {
                  danmakuWidgets.add(
                    SingleDanmaku(
                      key: ValueKey('$type-$content-$time-${UniqueKey()}'),
                      content: danmakuItem,
                      videoDuration: widget.videoDuration,
                      currentTime: widget.currentTime,
                      danmakuTime: time,
                      fontSize: widget.fontSize,
                      isVisible: widget.isVisible,
                      yPosition: yPosition,
                      opacity: widget.opacity,
                      textRenderer: _textRenderer!,
                    ),
                  );
                }
              }
            }

            if (widget.onLayoutCalculated != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (positionedItems.isNotEmpty) {
                  //debugPrint('[DanmakuContainer] Calculated layout for ${positionedItems.length} items.');
                }
                widget.onLayoutCalculated!(positionedItems);
              });
            }

            return widget.onLayoutCalculated != null
                ? const SizedBox.expand()
                : IgnorePointer(child: Stack(children: danmakuWidgets));
          },
        );
      },
    );
  }
  
  // 缓存弹幕分组结果
  Map<String, List<Map<String, dynamic>>> _groupedDanmakuCache = {
    'scroll': <Map<String, dynamic>>[],
    'top': <Map<String, dynamic>>[],
    'bottom': <Map<String, dynamic>>[],
  };
  double _lastGroupedTime = 0;
  
  // 获取缓存的弹幕分组
  Map<String, List<Map<String, dynamic>>> _getCachedGroupedDanmaku(
    List<Map<String, dynamic>> danmakuList,
    double currentTime,
    bool mergeDanmaku,
    bool allowStacking,
    {bool force = false}
  ) {
    // 如果时间变化小于0.1秒且没有强制刷新，使用缓存
    if (!force && (currentTime - _lastGroupedTime).abs() < 0.1 && _groupedDanmakuCache.isNotEmpty) {
      return _groupedDanmakuCache;
    }

    // 使用已排序列表与二分查找获取可见窗口 [currentTime-10, currentTime]
    final double windowStart = currentTime - 10.0;
    final int left = _lowerBoundByTime(windowStart);
    final int right = _upperBoundByTime(currentTime) - 1; // 右开区间转闭区间
    _visibleLeftIndex = left;
    _visibleRightIndex = right;

    // 重新计算分组（仅遍历可见窗口）
    final groupedDanmaku = <String, List<Map<String, dynamic>>>{
      'scroll': <Map<String, dynamic>>[],
      'top': <Map<String, dynamic>>[],
      'bottom': <Map<String, dynamic>>[],
    };
    
    if (_sortedDanmakuList.isNotEmpty && _visibleLeftIndex <= _visibleRightIndex) {
      for (int i = _visibleLeftIndex; i <= _visibleRightIndex; i++) {
        final danmaku = _sortedDanmakuList[i];
        final time = danmaku['time'] as double? ?? 0.0;
        final type = danmaku['type'] as String? ?? 'scroll';
        final content = danmaku['content'] as String? ?? '';
        // 处理合并弹幕逻辑
        var processedDanmaku = danmaku;
        if (mergeDanmaku) {
          final danmakuKey = '$content-$time';
          if (_processedDanmaku.containsKey(danmakuKey)) {
            processedDanmaku = _processedDanmaku[danmakuKey]!;
            // 合并弹幕只显示组内首条
            if (processedDanmaku['merged'] == true && !processedDanmaku['isFirstInGroup']) {
              continue;
            }
          }
        }
        if (groupedDanmaku.containsKey(type)) {
          groupedDanmaku[type]!.add(processedDanmaku);
        }
      }
    }
    
    // 更新缓存
    _groupedDanmakuCache = groupedDanmaku;
    _lastGroupedTime = currentTime;
    
    return groupedDanmaku;
  }
  
  // 溢出弹幕层与缓存逻辑已移除
  
  // 已废弃：溢出弹幕单独层，功能移除
  
  // 构建主弹幕层
  // 分组渲染层已移除（不再使用）
  
  // 构建溢出弹幕层
  // 溢出弹幕渲染层已移除（不再使用）

  // 为溢出弹幕分配轨道并构建widget
  // 溢出弹幕轨道分配逻辑已移除（不再使用）
  
  // 为溢出弹幕分配新的轨道
  // 溢出轨道分配辅助方法已移除（不再使用）
  
  // 构建普通弹幕组件
  // 旧的单弹幕构建方法已移除（不再使用）
  
  // 构建溢出弹幕组件
  // 溢出弹幕构建已移除（不再使用）

  // 计算在未来45秒内出现的相同内容弹幕的数量
  // 未来相似弹幕计数逻辑已移除（不再使用）
  
  // 基于 TextPainter 的文本宽度测量，带简单缓存
  double _getTextWidth(String text, double fontSize) {
    final String key = '$fontSize|$text';
    final cached = _textWidthCache[key];
    if (cached != null) return cached;

    // 使用 TextPainter 计算宽度
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          // 与渲染路径尽可能一致；如有指定字体可在此补充 family
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: 0, maxWidth: double.infinity);

    final width = tp.size.width;
    // 简单容量控制，避免无限增长
    if (_textWidthCache.length > 5000) {
      _textWidthCache.clear();
    }
    _textWidthCache[key] = width;
    return width;
  }

  // 已排序列表上按 time 的二分查找：首个 time >= t 的下标
  int _lowerBoundByTime(double t) {
    int lo = 0;
    int hi = _sortedDanmakuList.length; // 开区间 [lo, hi)
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final midTime = (_sortedDanmakuList[mid]['time'] as double?) ?? 0.0;
      if (midTime < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo; // 若全都 < t，则返回 length
  }

  // 已排序列表上按 time 的二分查找：首个 time > t 的下标
  int _upperBoundByTime(double t) {
    int lo = 0;
    int hi = _sortedDanmakuList.length; // 开区间 [lo, hi)
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      final midTime = (_sortedDanmakuList[mid]['time'] as double?) ?? 0.0;
      if (midTime <= t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo; // 若全都 <= t，则返回 length
  }
  
  // 这个方法已经不需要了，由_precomputeDanmakuStates替代
} 
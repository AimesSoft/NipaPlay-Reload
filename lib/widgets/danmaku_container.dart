import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_content_item.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_text_renderer_factory.dart';
import 'package:nipaplay/danmaku_abstraction/positioned_danmaku_item.dart';
import 'single_danmaku.dart';
import 'dart:math';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import '../utils/globals.dart' as globals;
import 'danmaku_group_widget.dart';

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
  final double _horizontalSpacing = 20.0; // 左右间距
  
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
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    
    // 保存当前轨道信息，用于恢复
    final tempTrackInfo = Map<String, Map<String, dynamic>>.from(_danmakuTrackInfo);
    
    // 清空当前轨道系统
    for (var type in _trackDanmaku.keys) {
      _trackDanmaku[type]!.clear();
    }
    
    // 清空Y轴位置缓存，强制重新计算
    _danmakuYPositions.clear();
    
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

  // 滚动弹幕的碰撞检测
  bool _willCollide(Map<String, dynamic> existingDanmaku, Map<String, dynamic> newDanmaku, double currentTime) {
    final screenWidth = _currentSize.width;
    final existingTime = existingDanmaku['time'] as double;
    final newTime = newDanmaku['time'] as double;
    
    final existingWidth = existingDanmaku['width'] as double? ?? screenWidth * 0.2;
    final newWidth = newDanmaku['width'] as double? ?? screenWidth * 0.2;
    
    // 获取弹幕的放大状态
    final existingIsMerged = existingDanmaku['isMerged'] as bool? ?? false;
    final newIsMerged = newDanmaku['isMerged'] as bool? ?? false;
    final existingMergeCount = existingIsMerged ? (existingDanmaku['mergeCount'] as int? ?? 1) : 1;
    final newMergeCount = newIsMerged ? (newDanmaku['mergeCount'] as int? ?? 1) : 1;
    
    // 计算现有弹幕的当前位置
    final existingElapsed = currentTime - existingTime;
    final existingPosition = screenWidth - (existingElapsed / 10) * (screenWidth + existingWidth);
    final existingLeft = existingPosition;
    final existingRight = existingPosition + existingWidth;
    
    // 计算新弹幕的当前位置
    final newElapsed = currentTime - newTime;
    final newPosition = screenWidth - (newElapsed / 10) * (screenWidth + newWidth);
    final newLeft = newPosition;
    final newRight = newPosition + newWidth;
    
    // 减小安全距离，让弹幕更密集，但考虑放大弹幕需要更多空间
    double safetyMargin = screenWidth * 0.02; // 标准弹幕的安全距离
    if (existingIsMerged || newIsMerged) {
      // 根据合并数量调整安全距离
      final maxCount = max(existingMergeCount, newMergeCount);
      safetyMargin = screenWidth * (0.02 + (maxCount / 100.0)); // 动态调整安全距离
    }
    
    // 记录弹幕的边界坐标
    existingDanmaku['left'] = existingLeft;
    existingDanmaku['right'] = existingRight;
    newDanmaku['left'] = newLeft;
    newDanmaku['right'] = newRight;
    
    // 如果两个弹幕在屏幕上的位置有重叠，且距离小于安全距离，则会发生碰撞
    return (existingRight + safetyMargin > newLeft) && 
           (existingLeft - safetyMargin < newRight);
  }

  // 检查轨道密度
  bool _isTrackFull(List<Map<String, dynamic>> trackDanmaku, double currentTime) {
    // 只统计当前在屏幕内的弹幕
    final visibleDanmaku = trackDanmaku.where((danmaku) {
      final time = danmaku['time'] as double;
      return currentTime - time >= 0 && currentTime - time <= 5;
    }).toList();
    
    // 计算当前轨道的弹幕总宽度和重叠情况
    double totalWidth = 0;
    double maxOverlap = 0;
    
    // 按左边界排序
    visibleDanmaku.sort((a, b) {
      final aLeft = a['left'] as double? ?? 0.0;
      final bLeft = b['left'] as double? ?? 0.0;
      return aLeft.compareTo(bLeft);
    });
    
    // 计算重叠情况，同时考虑放大弹幕
    for (int i = 0; i < visibleDanmaku.length; i++) {
      final current = visibleDanmaku[i];
      final isMerged = current['isMerged'] as bool? ?? false;
      // 放大弹幕占用更多空间
      final mergeCount = isMerged ? (current['mergeCount'] as int? ?? 1) : 1;
      final widthMultiplier = isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0;
      totalWidth += (current['width'] as double) * widthMultiplier;
      
      // 检查与后续弹幕的重叠
      for (int j = i + 1; j < visibleDanmaku.length; j++) {
        final next = visibleDanmaku[j];
        final currentRight = current['right'] as double? ?? 0.0;
        final nextLeft = next['left'] as double? ?? 0.0;
        
        if (currentRight > nextLeft) {
          final overlap = currentRight - nextLeft;
          maxOverlap = max(maxOverlap, overlap);
        } else {
          break; // 由于已排序，后续弹幕不会重叠
        }
      }
    }
    
    // 考虑重叠情况，调整轨道密度判断
    final adjustedWidth = totalWidth - maxOverlap;
    const safetyFactor = 0.7; // 从80%增加到90%，让轨道更容易被判定为满
    
    return adjustedWidth > _currentSize.width * safetyFactor;
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
    
    // 计算弹幕宽度和高度
    final fontSize = isMerged ? widget.fontSize * _calcMergedFontSizeMultiplier(mergeCount) : widget.fontSize;
    final textPainter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontSize: fontSize,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final danmakuWidth = textPainter.width;
    
    // 清理已经消失的弹幕
    _trackDanmaku[type]!.removeWhere((danmaku) {
      final danmakuTime = danmaku['time'] as double;
      return widget.currentTime - danmakuTime > 10;
    });
    
    // 计算可用轨道数，考虑弹幕高度和间距以及显示区域
    final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
    final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
    final effectiveHeight = screenHeight * widget.displayArea; // 根据显示区域调整有效高度
    final maxTracks = ((effectiveHeight - adjustedDanmakuHeight - _verticalSpacing) / trackHeight).floor();
    
    // 根据弹幕类型分配轨道
    if (type == 'scroll') {
      // 优化：遍历所有轨道，优先分配不会碰撞的轨道
      int? availableTrack;
      for (int track = 0; track < maxTracks; track++) {
        final trackDanmaku = _trackDanmaku['scroll']!.where((d) => d['track'] == track).toList();
        bool hasCollision = false;
        for (var danmaku in trackDanmaku) {
          if (_willCollide(danmaku, {
            'time': time,
            'width': danmakuWidth,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
          }, widget.currentTime)) {
            hasCollision = true;
            break;
          }
        }
        if (!hasCollision) {
          availableTrack = track;
          break;
        }
      }
      if (availableTrack != null) {
        _trackDanmaku['scroll']!.add({
          'content': content,
          'time': time,
          'track': availableTrack,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        });
        final yPosition = availableTrack * trackHeight + _verticalSpacing;
        _danmakuYPositions[danmakuKey] = yPosition;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          videoState.updateDanmakuTrackInfo(danmakuKey, {
            'track': availableTrack,
            'width': danmakuWidth,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
          });
        });
        return yPosition;
      }
      // 如果所有轨道都碰撞
      if (!allowStacking) {
        _danmakuYPositions[danmakuKey] = -1000;
        return -1000;
      }
      // 允许堆叠时，循环分配轨道
      _currentTrack[type] = (_currentTrack[type]! + 1) % maxTracks;
      final fallbackTrack = _currentTrack[type]!;
      _trackDanmaku['scroll']!.add({
        'content': content,
        'time': time,
        'track': fallbackTrack,
        'width': danmakuWidth,
        'isMerged': isMerged,
        'mergeCount': mergeCount,
      });
      final yPosition = fallbackTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': fallbackTrack,
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
            final mergeDanmaku = videoState.danmakuVisible && (videoState.mergeDanmaku ?? false);
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

                final textPainter = TextPainter(
                  text: TextSpan(text: danmakuItem.text, style: TextStyle(fontSize: widget.fontSize * danmakuItem.fontSizeMultiplier)),
                  textDirection: TextDirection.ltr,
                )..layout();
                final textWidth = textPainter.width;
                
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
                  final first = positionedItems.first;
                  //debugPrint('[DanmakuContainer] First item details: pos=(${first.x.toStringAsFixed(2)}, ${first.y.toStringAsFixed(2)}), text="${first.content.text}"');
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
    
    // 重新计算分组
    final groupedDanmaku = <String, List<Map<String, dynamic>>>{
      'scroll': <Map<String, dynamic>>[],
      'top': <Map<String, dynamic>>[],
      'bottom': <Map<String, dynamic>>[],
    };
    
    // 记录当前已显示的内容
    final Set<String> displayedContents = {};
    
    for (var danmaku in danmakuList) {
      final time = danmaku['time'] as double? ?? 0.0;
      final timeDiff = currentTime - time;
      
      if (timeDiff >= 0 && timeDiff <= 10) {
        final type = danmaku['type'] as String? ?? 'scroll';
        final content = danmaku['content'] as String? ?? '';
        // 处理合并弹幕逻辑
        var processedDanmaku = danmaku;
        if (mergeDanmaku) {
          final danmakuKey = '$content-$time';
          if (_processedDanmaku.containsKey(danmakuKey)) {
            processedDanmaku = _processedDanmaku[danmakuKey]!;
            // 合并弹幕只显示组内首条（不分轨道）
            if (processedDanmaku['merged'] == true && !processedDanmaku['isFirstInGroup']) {
              continue;
            }
          }
        }
        // 确保type是有效的类型
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
  
  // 缓存溢出弹幕结果
  Map<String, List<Map<String, dynamic>>> _overflowDanmakuCache = {
    'scroll': <Map<String, dynamic>>[],
    'top': <Map<String, dynamic>>[],
    'bottom': <Map<String, dynamic>>[],
  };
  double _lastOverflowTime = 0;
  
  // 获取缓存的溢出弹幕
  Map<String, List<Map<String, dynamic>>> _getCachedOverflowDanmaku(
    List<Map<String, dynamic>> danmakuList,
    double currentTime,
    bool mergeDanmaku,
    bool allowStacking,
    {bool force = false}
  ) {
    // 如果时间变化小于0.1秒且没有强制刷新，使用缓存
    if (!force && (currentTime - _lastOverflowTime).abs() < 0.1 && _overflowDanmakuCache.isNotEmpty) {
      return _overflowDanmakuCache;
    }
    
    final overflowDanmaku = <String, List<Map<String, dynamic>>>{
      'scroll': <Map<String, dynamic>>[],
      'top': <Map<String, dynamic>>[],
      'bottom': <Map<String, dynamic>>[],
    };
    
    for (var danmaku in danmakuList) {
      final time = danmaku['time'] as double;
      final timeDiff = currentTime - time;
      
      if (timeDiff >= 0 && timeDiff <= 10) {
        final type = danmaku['type'] as String;
        final content = danmaku['content'] as String;
        final danmakuKey = '$content-$time';
        
        if (_processedDanmaku.containsKey(danmakuKey)) {
          final processed = _processedDanmaku[danmakuKey]!;
          if (processed['hidden'] != true) {
            final yPosition = _getYPosition(type, content, time, processed['merged'] == true);
            if (yPosition < -500) {
              overflowDanmaku[type]!.add(processed);
            }
          }
        }
      }
    }
    
    // 更新缓存
    _overflowDanmakuCache = overflowDanmaku;
    _lastOverflowTime = currentTime;
    
    return overflowDanmaku;
  }
  
  // 构建主弹幕层
  Widget _buildMainDanmakuLayer(
    Map<String, List<Map<String, dynamic>>> groupedDanmaku,
    bool isPaused,
    Size newSize
  ) {
    // 新增：对每个轨道的弹幕按50ms分组
    List<Widget> groupWidgets = [];
    for (var type in ['scroll', 'bottom', 'top']) {
      final danmakuList = groupedDanmaku[type]!;
      if (danmakuList.isEmpty) continue;
      // 按轨道分组
      Map<int, List<Map<String, dynamic>>> trackMap = {};
      for (var danmaku in danmakuList) {
        final y = _getYPosition(
          type,
          danmaku['content'] as String,
          danmaku['time'] as double,
          danmaku['merged'] == true,
          danmaku['mergeCount'] as int? ?? 1,
        );
        // 反查轨道号
        final danmakuKey = '$type-${danmaku['content']}-${danmaku['time']}';
        int track = 0;
        if (_danmakuTrackInfo.containsKey(danmakuKey)) {
          track = _danmakuTrackInfo[danmakuKey]!['track'] as int? ?? 0;
        } else if (danmaku.containsKey('track')) {
          track = danmaku['track'] as int? ?? 0;
        }
        trackMap.putIfAbsent(track, () => []).add({...danmaku, 'y': y});
      }
      // 每个轨道内按时间排序并分组
      for (var entry in trackMap.entries) {
        final trackDanmakus = entry.value;
        trackDanmakus.sort((a, b) => (a['time'] as double).compareTo(b['time'] as double));
        List<List<Map<String, dynamic>>> timeGroups = [];
        for (var danmaku in trackDanmakus) {
          if (timeGroups.isEmpty) {
            timeGroups.add([danmaku]);
          } else {
            final lastGroup = timeGroups.last;
            final lastTime = lastGroup.last['time'] as double;
            if ((danmaku['time'] as double) - lastTime <= 0.2) {
              lastGroup.add(danmaku);
            } else {
              timeGroups.add([danmaku]);
            }
          }
        }
        // 每组用一个DanmakuGroupWidget渲染
        for (var group in timeGroups) {
          groupWidgets.add(DanmakuGroupWidget(
            danmakus: group,
            type: type,
            videoDuration: widget.videoDuration,
            currentTime: widget.currentTime,
            fontSize: widget.fontSize,
            isVisible: widget.isVisible,
            opacity: widget.opacity,
          ));
        }
      }
    }
    return IgnorePointer(
      child: Stack(children: groupWidgets),
    );
  }
  
  // 构建溢出弹幕层
  Widget? _buildOverflowLayer(
    Map<String, List<Map<String, dynamic>>> overflowDanmaku,
    bool isPaused,
    Size newSize,
    bool allowStacking,
    VideoPlayerState videoState
  ) {
    if (!allowStacking || overflowDanmaku.isEmpty) {
      return null;
    }
    
    final List<Widget> overflowWidgets = [];
    
    // 处理溢出弹幕的轨道分配
    _assignTracksForOverflowDanmaku(
      overflowDanmaku['scroll']!, 
      overflowWidgets, 
      'scroll', 
      {}, 
      ((newSize.height - _danmakuHeight - _verticalSpacing) / (_danmakuHeight + _verticalSpacing)).floor(), 
      newSize, 
      isPaused, 
      videoState
    );
    
    _assignTracksForOverflowDanmaku(
      overflowDanmaku['top']!, 
      overflowWidgets, 
      'top', 
      {}, 
      ((newSize.height - _danmakuHeight - _verticalSpacing) / (_danmakuHeight + _verticalSpacing)).floor() ~/ 4, 
      newSize, 
      isPaused, 
      videoState
    );
    
    _assignTracksForOverflowDanmaku(
      overflowDanmaku['bottom']!, 
      overflowWidgets, 
      'bottom', 
      {}, 
      ((newSize.height - _danmakuHeight - _verticalSpacing) / (_danmakuHeight + _verticalSpacing)).floor() ~/ 4, 
      newSize, 
      isPaused, 
      videoState
    );
    
    return overflowWidgets.isNotEmpty
      ? IgnorePointer(child: Stack(children: overflowWidgets))
      : null;
  }

  // 为溢出弹幕分配轨道并构建widget
  void _assignTracksForOverflowDanmaku(
    List<Map<String, dynamic>> danmakus, 
    List<Widget> widgets, 
    String type, 
    Set<int> usedTracks, 
    int maxTracks, 
    Size screenSize, 
    bool isPaused, 
    VideoPlayerState videoState
  ) {
    for (var danmaku in danmakus) {
      final content = danmaku['content'] as String;
      final time = danmaku['time'] as double;
      final isMerged = danmaku['merged'] == true;
      final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
      
      // 创建溢出弹幕的唯一标识
      final overflowKey = 'overflow-$type-$content-$time';
      
      // 如果已有持久化的轨道信息，使用它；否则分配新的轨道
      int trackToUse;
      double danmakuWidth;
      
      // 优先使用已经持久化的轨道信息，确保轨道分配的稳定性
      if (_danmakuTrackInfo.containsKey(overflowKey)) {
        final trackInfo = _danmakuTrackInfo[overflowKey]!;
        trackToUse = trackInfo['track'] as int;
        danmakuWidth = trackInfo['width'] as double;
      } else {
        // 计算弹幕宽度用于保存
        final fontSize = isMerged ? widget.fontSize * _calcMergedFontSizeMultiplier(mergeCount) : widget.fontSize;
        final textPainter = TextPainter(
          text: TextSpan(
            text: content,
            style: TextStyle(
              fontSize: fontSize,
              color: Colors.white,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        danmakuWidth = textPainter.width;
        
        // 分配新轨道并确保不冲突
        trackToUse = _assignNewTrackForOverflow(type, usedTracks, maxTracks);
        usedTracks.add(trackToUse);
        
        // 保存轨道信息到本地缓存，确保后续帧使用相同的轨道
        _danmakuTrackInfo[overflowKey] = {
          'track': trackToUse,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        };
        
        // 延迟更新状态
        WidgetsBinding.instance.addPostFrameCallback((_) {
          videoState.updateDanmakuTrackInfo(overflowKey, {
            'track': trackToUse,
            'width': danmakuWidth,
            'isMerged': isMerged,
            'mergeCount': mergeCount,
          });
        });
      }
      
      // 标记此轨道为已使用，避免其他弹幕分配到相同轨道
      usedTracks.add(trackToUse);
      
      // 计算Y轴位置
      final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
      final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
      double yPosition;
      
      if (type == 'bottom') {
        yPosition = screenSize.height - (trackToUse + 1) * trackHeight - adjustedDanmakuHeight;
      } else {
        yPosition = trackToUse * trackHeight + _verticalSpacing;
      }
      
      // 保存Y轴位置，确保位置稳定
      _danmakuYPositions[overflowKey] = yPosition;
      
      // 创建溢出弹幕widget并添加到列表
      widgets.add(_buildOverflowDanmaku(type, danmaku, isPaused, yPosition, overflowKey));
    }
  }
  
  // 为溢出弹幕分配新的轨道
  int _assignNewTrackForOverflow(String type, Set<int> usedTracks, int maxTracks) {
    // 先尝试使用最低的未使用轨道
    for (int i = 0; i < maxTracks; i++) {
      if (!usedTracks.contains(i)) {
        return i;
      }
    }
    
    // 如果所有轨道都被使用，则使用轮询策略
    return _currentTrack[type] = (_currentTrack[type]! + 1) % maxTracks;
  }
  
  // 构建普通弹幕组件
  Widget _buildDanmaku(String type, Map<String, dynamic> danmaku, bool isPaused) {
    // 如果弹幕被标记为隐藏，不显示
    if (danmaku['hidden'] == true) {
      return const SizedBox.shrink();
    }
    
    final time = danmaku['time'] as double;
    final content = danmaku['content'] as String;
    final colorStr = danmaku['color'] as String;
    final isMerged = danmaku['merged'] == true;
    final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
    
    final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
    final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
    
    DanmakuItemType danmakuType;
    switch (type) {
      case 'scroll':
        danmakuType = DanmakuItemType.scroll;
        break;
      case 'top':
        danmakuType = DanmakuItemType.top;
        break;
      case 'bottom':
        danmakuType = DanmakuItemType.bottom;
        break;
      default:
        danmakuType = DanmakuItemType.scroll;
    }
    
    final danmakuItem = DanmakuContentItem(
      content,
      type: danmakuType,
      color: color,
      fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
      countText: isMerged ? 'x$mergeCount' : null,
    );
    
    // 计算Y位置时考虑合并状态
    final yPosition = _getYPosition(type, content, time, isMerged, mergeCount);
    
    // 创建单个弹幕，传递视频的暂停状态
    return SingleDanmaku(
      key: ValueKey('$type-$content-$time-${UniqueKey().toString()}'),
      content: danmakuItem,
      videoDuration: widget.videoDuration,
      currentTime: widget.currentTime,
      danmakuTime: time,
      fontSize: widget.fontSize,
      isVisible: widget.isVisible,
      yPosition: yPosition,
      opacity: widget.opacity,
      textRenderer: _textRenderer!,
    );
  }
  
  // 构建溢出弹幕组件
  Widget _buildOverflowDanmaku(String type, Map<String, dynamic> danmaku, bool isPaused, double yPosition, String overflowKey) {
    final time = danmaku['time'] as double;
    final content = danmaku['content'] as String;
    final colorStr = danmaku['color'] as String;
    final isMerged = danmaku['merged'] == true;
    final mergeCount = isMerged ? (danmaku['mergeCount'] as int? ?? 1) : 1;
    
    final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
    final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
    
    DanmakuItemType danmakuType;
    switch (type) {
      case 'scroll':
        danmakuType = DanmakuItemType.scroll;
        break;
      case 'top':
        danmakuType = DanmakuItemType.top;
        break;
      case 'bottom':
        danmakuType = DanmakuItemType.bottom;
        break;
      default:
        danmakuType = DanmakuItemType.scroll;
    }
    
    final danmakuItem = DanmakuContentItem(
      content,
      type: danmakuType,
      color: color,
      fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
      countText: isMerged ? 'x$mergeCount' : null,
    );
    
    // 为溢出弹幕创建一个带有特殊标记的key
    return SingleDanmaku(
      key: ValueKey('$overflowKey-${UniqueKey().toString()}'),
      content: danmakuItem,
      videoDuration: widget.videoDuration,
      currentTime: widget.currentTime,
      danmakuTime: time,
      fontSize: widget.fontSize,
      isVisible: widget.isVisible,
      yPosition: yPosition,
      opacity: widget.opacity,
      textRenderer: _textRenderer!,
    );
  }

  // 计算在未来45秒内出现的相同内容弹幕的数量
  int _countFutureSimilarDanmaku(String content, double startTime) {
    // 查找45秒时间窗口内的相同内容弹幕
    final endTime = startTime + 45.0;
    int count = 0;
    
    for (var danmaku in _sortedDanmakuList) {
      final time = danmaku['time'] as double;
      if (time >= startTime && time <= endTime) {
        if (danmaku['content'] == content) {
          count++;
        }
      }
      if (time > endTime) {
        // 由于列表已排序，超过结束时间后可以直接退出循环
        break;
      }
    }
    
    return count;
  }
  
  // 这个方法已经不需要了，由_precomputeDanmakuStates替代
} 
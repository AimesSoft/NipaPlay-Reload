import 'package:flutter/material.dart';
import 'danmaku_content_item.dart';
import 'single_danmaku.dart';
import 'dart:math';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

class DanmakuContainer extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final double currentTime;
  final double videoDuration;
  final double fontSize;
  final bool isVisible;
  final double opacity;

  const DanmakuContainer({
    Key? key,
    required this.danmakuList,
    required this.currentTime,
    required this.videoDuration,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
  }) : super(key: key);

  @override
  State<DanmakuContainer> createState() => _DanmakuContainerState();
}

class _DanmakuContainerState extends State<DanmakuContainer> {
  final double _danmakuHeight = 25.0; // 弹幕高度
  final double _verticalSpacing = 20.0; // 上下间距
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
    // 初始化时获取画布大小
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _currentSize = MediaQuery.of(context).size;
      });
    });
    
    // 初始化时对弹幕列表进行预处理和排序
    _preprocessDanmakuList();
  }
  
  // 对弹幕列表进行预处理和排序
  void _preprocessDanmakuList() {
    if (widget.danmakuList.isEmpty) return;
    
    // 复制一份弹幕列表以避免修改原数据
    _sortedDanmakuList = List<Map<String, dynamic>>.from(widget.danmakuList);
    
    // 按时间排序
    _sortedDanmakuList.sort((a, b) => 
      (a['time'] as double).compareTo(b['time'] as double));
      
    // 预计算所有弹幕的状态
    _precomputeDanmakuStates();
  }
  
  // 预计算所有弹幕的显示状态
  void _precomputeDanmakuStates() {
    // 用于跟踪已处理的内容组
    Map<String, double> contentFirstTime = {};
    
    // 使用滑动窗口法处理弹幕
    for (int i = 0; i < _sortedDanmakuList.length; i++) {
      final current = _sortedDanmakuList[i];
      final content = current['content'] as String;
      final time = current['time'] as double;
      
      // 弹幕唯一标识
      final danmakuKey = '$content-$time';
      
      // 检查此内容是否已经有了第一个出现时间
      if (contentFirstTime.containsKey(content)) {
        final firstTime = contentFirstTime[content]!;
        // 如果当前弹幕在第一次出现后的45秒内，标记为隐藏
        if (time - firstTime <= 45.0) {
          _processedDanmaku[danmakuKey] = {
            ...current,
            'hidden': true,
            'belongsToGroup': content
          };
          continue;
        } else {
          // 超过45秒窗口，这是一个新的组的开始
          contentFirstTime[content] = time;
        }
      } else {
        // 第一次出现此内容
        contentFirstTime[content] = time;
      }
      
      // 计算这个内容在未来45秒内出现的次数
      int futureCount = 1; // 至少包括自己
      for (int j = i + 1; j < _sortedDanmakuList.length; j++) {
        final future = _sortedDanmakuList[j];
        final futureContent = future['content'] as String;
        final futureTime = future['time'] as double;
        
        if (futureContent == content && futureTime - time <= 45.0) {
          futureCount++;
        }
        
        // 如果已经超过45秒窗口，停止计数
        if (futureTime - time > 45.0) {
          break;
        }
      }
      
      // 如果有多次出现，标记为合并状态
      if (futureCount > 1) {
        _processedDanmaku[danmakuKey] = {
          ...current,
          'merged': true,
          'mergeCount': futureCount,
          'isFirstInGroup': true,
          'groupContent': content
        };
      } else {
        // 只出现一次，保持原样
        _processedDanmaku[danmakuKey] = current;
      }
    }
  }

  @override
  void didUpdateWidget(DanmakuContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 如果弹幕列表变化，重新预处理
    if (widget.danmakuList != oldWidget.danmakuList) {
      _preprocessDanmakuList();
    }
  }

  // 重新计算所有弹幕位置
  void _resize(Size newSize) {
    // 更新当前大小
    _currentSize = newSize;
    
    // 保持轨道信息不变，只更新Y轴位置
    for (var type in _trackDanmaku.keys) {
      for (var danmaku in _trackDanmaku[type]!) {
        final time = danmaku['time'] as double;
        final content = danmaku['content'] as String;
        final track = danmaku['track'] as int;
        final danmakuKey = '$type-$content-$time';
        
        // 根据新的窗口高度重新计算Y轴位置
        final trackHeight = _danmakuHeight + _verticalSpacing;
        double newYPosition;
        
        if (type == 'bottom') {
          // 底部弹幕从底部开始计算，确保不会超出窗口
          newYPosition = newSize.height - (track + 1) * trackHeight - _danmakuHeight;
        } else {
          // 其他弹幕从顶部开始计算，加上间距
          newYPosition = track * trackHeight + _verticalSpacing;
        }
        
        _danmakuYPositions[danmakuKey] = newYPosition;
      }
    }
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
    final safetyFactor = 0.7; // 从80%增加到90%，让轨道更容易被判定为满
    
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
    final safetyTime = 0.5; // 0.5秒的安全时间
    
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
    
    // 从 VideoPlayerState 获取轨道信息
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
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
    
    // 计算可用轨道数，考虑弹幕高度和间距
    final adjustedDanmakuHeight = isMerged ? _danmakuHeight * _calcMergedFontSizeMultiplier(mergeCount) : _danmakuHeight;
    final trackHeight = adjustedDanmakuHeight + _verticalSpacing;
    final maxTracks = ((screenHeight - adjustedDanmakuHeight - _verticalSpacing) / trackHeight).floor();
    
    // 根据弹幕类型分配轨道
    if (type == 'scroll') {
      // 滚动弹幕：优先使用上半部分轨道，满了才使用下半部分
      final availableTracks = maxTracks;
      final halfTracks = (availableTracks / 2).floor(); // 上半部分轨道数
      
      // 根据时间差选择初始轨道
      final timeDiff = widget.currentTime - time;
      final initialTrack = ((timeDiff * 0.1) % availableTracks).floor();
      
      // 先尝试在上半部分分配轨道
      for (int i = 0; i < halfTracks; i++) {
        final track = (initialTrack + i) % halfTracks;
        final trackDanmaku = _trackDanmaku['scroll']!.where((d) => d['track'] == track).toList();
        
        // 检查轨道中是否有合并弹幕占用多行
        bool hasMergedDanmaku = false;
        for (var danmaku in trackDanmaku) {
          if (danmaku['isMerged'] == true) {
            final danmakuTime = danmaku['time'] as double;
            final danmakuMergeCount = danmaku['mergeCount'] as int? ?? 1;
            // 只考虑时间上重叠的部分，且只有当合并数较大时才避开
            if (widget.currentTime - danmakuTime <= 10 && widget.currentTime - danmakuTime >= 0 && danmakuMergeCount > 5) {
              hasMergedDanmaku = true;
              break;
            }
          }
        }
        
        // 如果当前轨道被合并弹幕占用，并且当前弹幕也是合并弹幕，尝试下一个轨道
        if (hasMergedDanmaku && isMerged && mergeCount > 5) {
          continue;
        }
        
        if (trackDanmaku.isEmpty) {
          _trackDanmaku['scroll']!.add({
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
        if (!_isTrackFull(trackDanmaku, widget.currentTime)) {
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
            _trackDanmaku['scroll']!.add({
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
      
      // 如果上半部分轨道都满了，尝试在下半部分分配
      for (int i = 0; i < halfTracks; i++) {
        final track = halfTracks + i; // 使用下半部分轨道
        final trackDanmaku = _trackDanmaku['scroll']!.where((d) => d['track'] == track).toList();
        
        if (trackDanmaku.isEmpty) {
          _trackDanmaku['scroll']!.add({
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
        if (!_isTrackFull(trackDanmaku, widget.currentTime)) {
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
            _trackDanmaku['scroll']!.add({
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
      
      // 如果所有轨道都满了，尝试使用最空闲的轨道
      int bestTrack = initialTrack;
      int minCollisions = _trackDanmaku['scroll']!.length;
      
      // 先在上半部分寻找最空闲的轨道
      for (int i = 0; i < halfTracks; i++) {
        final track = (initialTrack + i) % halfTracks;
        final currentTrackDanmaku = _trackDanmaku['scroll']!.where((d) => d['track'] == track).toList();
        if (currentTrackDanmaku.length < minCollisions) {
          minCollisions = currentTrackDanmaku.length;
          bestTrack = track;
        }
      }
      
      // 如果上半部分都满了，才考虑下半部分
      if (minCollisions == _trackDanmaku['scroll']!.length) {
        for (int i = 0; i < halfTracks; i++) {
          final track = halfTracks + i;
          final currentTrackDanmaku = _trackDanmaku['scroll']!.where((d) => d['track'] == track).toList();
          if (currentTrackDanmaku.length < minCollisions) {
            minCollisions = currentTrackDanmaku.length;
            bestTrack = track;
          }
        }
      }
      
      _trackDanmaku['scroll']!.add({
        'content': content,
        'time': time,
        'track': bestTrack,
        'width': danmakuWidth,
        'isMerged': isMerged,
        'mergeCount': mergeCount,
      });
      final yPosition = bestTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
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
      
      // 如果所有轨道都满了，尝试使用最空闲的轨道
      int bestTrack = 0;
      int minCollisions = _trackDanmaku['top']!.length;
      
      for (int track = 0; track < availableTracks; track++) {
        final currentTrackDanmaku = _trackDanmaku['top']!.where((d) => d['track'] == track).toList();
        if (currentTrackDanmaku.length < minCollisions) {
          minCollisions = currentTrackDanmaku.length;
          bestTrack = track;
        }
      }
      
      _trackDanmaku['top']!.add({
        'content': content,
        'time': time,
        'track': bestTrack,
        'width': danmakuWidth,
        'isMerged': isMerged,
        'mergeCount': mergeCount,
      });
      final yPosition = bestTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
          'width': danmakuWidth,
          'isMerged': isMerged,
          'mergeCount': mergeCount,
        });
      });
      return yPosition;
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
              });
            });
            return yPosition;
          }
        }
      }
      
      // 如果所有轨道都满了，尝试使用最空闲的轨道
      int bestTrack = 0;
      int minCollisions = _trackDanmaku['bottom']!.length;
      
      for (int i = 0; i < availableTracks; i++) {
        final track = i;
        final currentTrackDanmaku = _trackDanmaku['bottom']!.where((d) => d['track'] == track).toList();
        if (currentTrackDanmaku.length < minCollisions) {
          minCollisions = currentTrackDanmaku.length;
          bestTrack = track;
        }
      }
      
      _trackDanmaku['bottom']!.add({
        'content': content,
        'time': time,
        'track': bestTrack,
        'width': danmakuWidth,
        'isMerged': isMerged,
        'mergeCount': mergeCount,
      });
      // 修改Y轴位置计算，从底部开始计算，并考虑合并状态下的高度
      final yPosition = screenHeight - (bestTrack + 1) * trackHeight - adjustedDanmakuHeight;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
          'width': danmakuWidth,
          'isMerged': isMerged,
        });
      });
      return yPosition;
    }
    
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用 constraints 获取实际的窗口大小
        final newSize = Size(constraints.maxWidth, constraints.maxHeight);
        
        // 如果窗口大小发生变化，重新计算位置
        if (newSize != _currentSize) {
          _resize(newSize);
        }
        
        // 获取VideoPlayerState，用于检查是否开启合并弹幕功能
        final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        // 使用getter检测是否存在mergeDanmaku
        final mergeDanmaku = videoState.danmakuVisible && (videoState.mergeDanmaku ?? false);
        
        // 按类型分组弹幕
        final Map<String, List<Map<String, dynamic>>> groupedDanmaku = {
          'scroll': [],
          'top': [],
          'bottom': [],
        };

        // 记录当前已显示的内容，确保同一内容在同一时间只显示一次
        final Set<String> displayedContents = {};

        // 过滤并分组弹幕
        for (var danmaku in widget.danmakuList) {
          final time = danmaku['time'] as double;
          final timeDiff = widget.currentTime - time;
          
          // 修改可见性判断，确保放大弹幕完全离开屏幕才消失
          // 根据弹幕类型和是否合并计算不同的可见时间
          double visibleDuration = 10.0; // 默认10秒
          bool isMerged = false;
          
          // 检查是否是合并弹幕
          final content = danmaku['content'] as String;
          final danmakuKey = '$content-$time';
          if (mergeDanmaku && _processedDanmaku.containsKey(danmakuKey)) {
            final processed = _processedDanmaku[danmakuKey]!;
            isMerged = processed['merged'] == true;
            
            // 如果是合并弹幕，增加可见时间以确保完全离开屏幕
            if (isMerged) {
              // 放大弹幕需要更长的时间才能完全滚出屏幕
              visibleDuration = 15.0; // 增加到15秒
            }
          }
          
          if (timeDiff >= 0 && timeDiff <= visibleDuration) {
            final type = danmaku['type'] as String;
            
            // 处理合并弹幕逻辑
            var processedDanmaku = danmaku;
            if (mergeDanmaku) {
              // 如果这个弹幕已经处理过，使用缓存的结果
              if (_processedDanmaku.containsKey(danmakuKey)) {
                processedDanmaku = _processedDanmaku[danmakuKey]!;
                
                // 如果这个内容在当前屏幕已经显示过，强制隐藏
                if (displayedContents.contains(content) && 
                    !processedDanmaku.containsKey('isFirstInGroup')) {
                  processedDanmaku = {...processedDanmaku, 'hidden': true};
                } else if (!processedDanmaku.containsKey('hidden')) {
                  // 如果这个内容没有被隐藏，标记为已显示
                  displayedContents.add(content);
                }
              }
            }
            
            groupedDanmaku[type]!.add(processedDanmaku);
          }
        }

        // 按顺序构建弹幕：滚动弹幕 -> 底部弹幕 -> 顶部弹幕
        return Stack(
          children: [
            // 滚动弹幕（最底层）
            ...groupedDanmaku['scroll']!.map((danmaku) {
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
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.scroll,
                color: color,
                fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
                countText: isMerged ? 'x$mergeCount' : null,
              );
              
              // 计算Y位置时考虑合并状态
              final yPosition = _getYPosition('scroll', content, time, isMerged, mergeCount);
              
              return SingleDanmaku(
                content: danmakuItem,
                videoDuration: widget.videoDuration,
                currentTime: widget.currentTime,
                danmakuTime: time,
                fontSize: widget.fontSize,
                isVisible: widget.isVisible,
                yPosition: yPosition,
                opacity: widget.opacity,
              );
            }),
            
            // 底部弹幕（中间层）
            ...groupedDanmaku['bottom']!.map((danmaku) {
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
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.bottom,
                color: color,
                fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
                countText: isMerged ? 'x$mergeCount' : null,
              );
              
              // 计算Y位置时考虑合并状态
              final yPosition = _getYPosition('bottom', content, time, isMerged, mergeCount);
              
              return SingleDanmaku(
                content: danmakuItem,
                videoDuration: widget.videoDuration,
                currentTime: widget.currentTime,
                danmakuTime: time,
                fontSize: widget.fontSize,
                isVisible: widget.isVisible,
                yPosition: yPosition,
                opacity: widget.opacity,
              );
            }),
            
            // 顶部弹幕（最上层）
            ...groupedDanmaku['top']!.map((danmaku) {
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
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.top,
                color: color,
                fontSizeMultiplier: isMerged ? _calcMergedFontSizeMultiplier(mergeCount) : 1.0,
                countText: isMerged ? 'x$mergeCount' : null,
              );
              
              // 计算Y位置时考虑合并状态
              final yPosition = _getYPosition('top', content, time, isMerged, mergeCount);
              
              return SingleDanmaku(
                content: danmakuItem,
                videoDuration: widget.videoDuration,
                currentTime: widget.currentTime,
                danmakuTime: time,
                fontSize: widget.fontSize,
                isVisible: widget.isVisible,
                yPosition: yPosition,
                opacity: widget.opacity,
              );
            }),
          ],
        );
      },
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
  bool _isSimilarDanmakuFirstOccurrence(String content, double time) {
    return true;
  }
} 
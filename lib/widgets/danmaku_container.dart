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
  final double _verticalSpacing = 10.0; // 上下间距
  final double _horizontalSpacing = 5.0; // 左右间距
  
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

  @override
  void initState() {
    super.initState();
    // 初始化时获取画布大小
    WidgetsBinding.instance.addPostFrameCallback((_) {
      setState(() {
        _currentSize = MediaQuery.of(context).size;
      });
    });
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
    
    // 减小安全距离，让弹幕更密集
    final safetyMargin = screenWidth * 0.02; // 从5%减小到2%的安全距离
    
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
    
    // 计算重叠情况
    for (int i = 0; i < visibleDanmaku.length; i++) {
      final current = visibleDanmaku[i];
      totalWidth += current['width'] as double;
      
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
    final safetyFactor = 0.9; // 从80%增加到90%，让轨道更容易被判定为满
    
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

  double _getYPosition(String type, String content, double time) {
    final screenHeight = _currentSize.height;
    final screenWidth = _currentSize.width;
    final danmakuKey = '$type-$content-$time';
    
    // 如果弹幕已经有位置，直接返回
    if (_danmakuYPositions.containsKey(danmakuKey)) {
      return _danmakuYPositions[danmakuKey]!;
    }
    
    // 从 VideoPlayerState 获取轨道信息
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    if (videoState.danmakuTrackInfo.containsKey(danmakuKey)) {
      final trackInfo = videoState.danmakuTrackInfo[danmakuKey]!;
      final track = trackInfo['track'] as int;
      final trackHeight = _danmakuHeight + _verticalSpacing;
      
      // 根据类型计算Y轴位置
      double yPosition;
      if (type == 'bottom') {
        yPosition = screenHeight - (track + 1) * trackHeight - _danmakuHeight - _verticalSpacing;
      } else {
        yPosition = track * trackHeight + _verticalSpacing;
      }
      
      // 更新轨道信息
      _trackDanmaku[type]!.add({
        'content': content,
        'time': time,
        'track': track,
        'width': trackInfo['width'] as double,
      });
      
      _danmakuYPositions[danmakuKey] = yPosition;
      return yPosition;
    }
    
    // 计算弹幕宽度
    final textPainter = TextPainter(
      text: TextSpan(
        text: content,
        style: TextStyle(
          fontSize: widget.fontSize,
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
    final trackHeight = _danmakuHeight + _verticalSpacing;
    final maxTracks = ((screenHeight - _danmakuHeight - _verticalSpacing) / trackHeight).floor();
    
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
        
        if (trackDanmaku.isEmpty) {
          _trackDanmaku['scroll']!.add({
            'content': content,
            'time': time,
            'track': track,
            'width': danmakuWidth,
          });
          final yPosition = track * trackHeight + _verticalSpacing;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
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
            });
            final yPosition = track * trackHeight + _verticalSpacing;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
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
          });
          final yPosition = track * trackHeight + _verticalSpacing;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
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
            });
            final yPosition = track * trackHeight + _verticalSpacing;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
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
      });
      final yPosition = bestTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
          'width': danmakuWidth,
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
          });
          final yPosition = track * trackHeight + _verticalSpacing;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
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
            });
            final yPosition = track * trackHeight + _verticalSpacing;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
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
      });
      final yPosition = bestTrack * trackHeight + _verticalSpacing;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
          'width': danmakuWidth,
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
          });
          // 修改Y轴位置计算，从底部开始计算
          final yPosition = screenHeight - (track + 1) * trackHeight - _danmakuHeight;
          _danmakuYPositions[danmakuKey] = yPosition;
          // 延迟更新状态
          WidgetsBinding.instance.addPostFrameCallback((_) {
            videoState.updateDanmakuTrackInfo(danmakuKey, {
              'track': track,
              'width': danmakuWidth,
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
            });
            // 修改Y轴位置计算，从底部开始计算
            final yPosition = screenHeight - (track + 1) * trackHeight - _danmakuHeight;
            _danmakuYPositions[danmakuKey] = yPosition;
            // 延迟更新状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              videoState.updateDanmakuTrackInfo(danmakuKey, {
                'track': track,
                'width': danmakuWidth,
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
      });
      // 修改Y轴位置计算，从底部开始计算
      final yPosition = screenHeight - (bestTrack + 1) * trackHeight - _danmakuHeight;
      _danmakuYPositions[danmakuKey] = yPosition;
      // 延迟更新状态
      WidgetsBinding.instance.addPostFrameCallback((_) {
        videoState.updateDanmakuTrackInfo(danmakuKey, {
          'track': bestTrack,
          'width': danmakuWidth,
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
        
        // 按类型分组弹幕
        final Map<String, List<Map<String, dynamic>>> groupedDanmaku = {
          'scroll': [],
          'top': [],
          'bottom': [],
        };

        // 过滤并分组弹幕
        for (var danmaku in widget.danmakuList) {
          final time = danmaku['time'] as double;
          final timeDiff = widget.currentTime - time;
          if (timeDiff >= 0 && timeDiff <= 10) {
            final type = danmaku['type'] as String;
            groupedDanmaku[type]!.add(danmaku);
          }
        }

        // 按顺序构建弹幕：滚动弹幕 -> 底部弹幕 -> 顶部弹幕
        return Stack(
          children: [
            // 滚动弹幕（最底层）
            ...groupedDanmaku['scroll']!.map((danmaku) {
              final time = danmaku['time'] as double;
              final content = danmaku['content'] as String;
              final colorStr = danmaku['color'] as String;
              
              final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
              final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.scroll,
                color: color,
              );
              
              final yPosition = _getYPosition('scroll', content, time);
              
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
              final time = danmaku['time'] as double;
              final content = danmaku['content'] as String;
              final colorStr = danmaku['color'] as String;
              
              final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
              final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.bottom,
                color: color,
              );
              
              final yPosition = _getYPosition('bottom', content, time);
              
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
              final time = danmaku['time'] as double;
              final content = danmaku['content'] as String;
              final colorStr = danmaku['color'] as String;
              
              final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
              final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
              
              final danmakuItem = DanmakuContentItem(
                content,
                type: DanmakuItemType.top,
                color: color,
              );
              
              final yPosition = _getYPosition('top', content, time);
              
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
} 
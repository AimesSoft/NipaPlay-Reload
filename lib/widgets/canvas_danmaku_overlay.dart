import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math';

import '../utils/video_player_state.dart';
import 'package:nipaplay/canvas_danmaku/lib/canvas_danmaku.dart' as canvas;
import '../providers/developer_options_provider.dart';

/// 🔥 新增：弹幕状态保存类
class DanmakuState {
  final String content;
  final Color color;
  final canvas.DanmakuItemType type;
  final double normalizedProgress; // 归一化进度 (0.0-1.0)
  final int originalCreationTime; // 原始创建时间
  final int remainingTime; // 剩余显示时间（毫秒）
  final double yPosition; // Y轴位置
  final int saveTime; // 🔥 新增：保存时的时间戳
  final int trackIndex; // 🔥 新增：轨道编号
  
  DanmakuState({
    required this.content,
    required this.color,
    required this.type,
    required this.normalizedProgress,
    required this.originalCreationTime,
    required this.remainingTime,
    required this.yPosition,
    required this.saveTime, // 🔥 新增
    required this.trackIndex, // 🔥 新增：轨道编号
  });
}

/// Canvas_Danmaku 渲染器的外层封装，保持与原 `DanmakuOverlay` 相同的入参。
class CanvasDanmakuOverlay extends StatefulWidget {
  final double currentPosition;
  final double videoDuration;
  final bool isPlaying;
  final double fontSize;
  final bool isVisible;
  final double opacity;

  const CanvasDanmakuOverlay({
    super.key,
    required this.currentPosition,
    required this.videoDuration,
    required this.isPlaying,
    required this.fontSize,
    required this.isVisible,
    required this.opacity,
  });

  @override
  State<CanvasDanmakuOverlay> createState() => _CanvasDanmakuOverlayState();
}

class _CanvasDanmakuOverlayState extends State<CanvasDanmakuOverlay> {
  canvas.DanmakuController? _controller;
  final Set<String> _addedDanmaku = <String>{};
  double _lastSyncTime = -1;
  canvas.DanmakuOption _option = canvas.DanmakuOption();
  
  // 🔥 添加屏蔽词变化检测
  List<String> _lastBlockWords = [];
  
  // 记录上次的弹幕类型过滤设置，用于检测变化
  String _lastFilterSettings = '';
  
  // 记录上次的弹幕轨道堆叠设置，用于检测变化
  bool _lastStackingSettings = false;
  
  // 🔥 添加弹幕轨道变化检测
  Map<String, bool> _lastTrackEnabled = {};
  String _lastTrackHash = '';
  
  // 🔥 新增：弹幕状态保存
  final List<DanmakuState> _savedDanmakuStates = [];
  bool _isRestoring = false;

  @override
  void didUpdateWidget(covariant CanvasDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mounted) return;
    
    // 播放状态变化
    if (widget.isPlaying != oldWidget.isPlaying && _controller != null) {
      if (widget.isPlaying) {

        _controller!.resume();
        // 🔥 修复：恢复播放时重新启动弹幕同步
        if (widget.isVisible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncDanmaku();
          });
        }
      } else {

        _controller!.pause();
      }
    }

    // 可见性或透明度变化
    if (widget.opacity != oldWidget.opacity || widget.isVisible != oldWidget.isVisible) {

      _updateOption();
      
      // 🔥 关键修复：当弹幕从隐藏变为显示时，恢复弹幕状态
      if (widget.isVisible && !oldWidget.isVisible) {
        // 保存当前状态，用于判断是否成功恢复
        final hadSavedStates = _savedDanmakuStates.isNotEmpty;
        
        // 恢复保存的弹幕状态
        _restoreDanmakuStates();
        
        // 🔥 关键修复：只有在没有保存状态的情况下才重新同步
        // 如果有保存的状态且成功恢复，就不再调用_syncDanmaku()避免轨道重新分配
        if (!hadSavedStates) {
          // 重置同步时间，强制立即同步
          _lastSyncTime = 0.0;
          // 立即同步弹幕，而不是等待下一次调度
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _syncDanmaku();
            // 🔥 关键修复：如果是暂停状态，需要特殊处理让弹幕显示
            if (!widget.isPlaying) {
              _handlePausedDanmakuDisplay();
            }
          });
        } else {
          // 🔥 如果成功恢复状态，设置合理的同步时间，避免立即触发时间轴跳转逻辑
          _lastSyncTime = widget.currentPosition / 1000;
        }
      }
      
      // 🔥 修改：当弹幕从显示变为隐藏时，保存弹幕状态并清空画布
      if (!widget.isVisible && oldWidget.isVisible && _controller != null) {
        // 保存当前弹幕状态
        _saveDanmakuStates();
        
        _controller!.clear();
      }
    }

    // 字体大小变化
    if (widget.fontSize != oldWidget.fontSize) {

      _updateOption();
    }

    // 🔥 检测弹幕轨道开关变化 - 移到这里来立即生效
    final videoState = context.read<VideoPlayerState>();
    final currentTrackEnabled = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    final currentTrackHash = currentTrackEnabled.entries
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    final trackEnabledChanged = _lastTrackHash != currentTrackHash;
    
    if (trackEnabledChanged) {
      _lastTrackEnabled = currentTrackEnabled;
      _lastTrackHash = currentTrackHash;
      
      // 弹幕轨道变化时，立即重新同步弹幕
      if (_controller != null && widget.isVisible) {
        // 清空已添加的弹幕记录，重新添加符合新设置的弹幕
        _addedDanmaku.clear();
        _controller!.clear();
        _lastSyncTime = 0.0;
        
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _syncDanmaku();
          // 🔥 关键修复：如果是暂停状态，需要特殊处理让弹幕显示
          if (!widget.isPlaying) {
            _handlePausedDanmakuDisplay();
          }
        });
      }
    }

    // 检测时间轴切换（拖拽进度条或跳转）
    final timeDelta = (widget.currentPosition - oldWidget.currentPosition).abs();
    if (timeDelta > 2000) { // 时间跳跃超过2秒

      
      // 清空已添加的弹幕记录
      _addedDanmaku.clear();
      
      // 清空画布上的所有弹幕
      if (_controller != null) {
        _controller!.clear();
      }
      
      // 重置同步时间，标记为需要重新同步
      _lastSyncTime = 0.0;
      
      // 立即同步新时间点的弹幕
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncDanmaku();
      });
    }
    
    // 检测视频时长变化（切换视频）
    if (widget.videoDuration != oldWidget.videoDuration) {

      _addedDanmaku.clear();
      if (_controller != null) {
        // 🔥 关键修复：切换视频时使用彻底重置，包括重置交叉绘制策略状态
        _controller!.resetAll();
      }
      _lastSyncTime = 0.0;
    }
    
    // 🔥 新增：检测弹幕轨道状态变化
    final currentTracks = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    final tracksChanged = !_mapEquals(_lastTrackEnabled, currentTracks);
    
    if (tracksChanged) {
      debugPrint('CanvasDanmakuOverlay: 检测到弹幕轨道状态变化，清空弹幕记录');
      _lastTrackEnabled = currentTracks;
      _addedDanmaku.clear(); // 清空已添加的弹幕记录
      if (_controller != null) {
        _controller!.clear(); // 清空控制器中的弹幕
      }
      _lastSyncTime = 0.0; // 🔥 关键修复：重置同步时间，确保弹幕能重新加载
      
      // 🔥 新增：立即触发同步，不等待下一次同步周期
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncDanmaku();
        }
      });
    }
  }

  /// 比较两个Map是否相等
  bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _updateOption() {
    if (!mounted) return;
    
    final videoState = context.read<VideoPlayerState>();
    final devOptions = context.read<DeveloperOptionsProvider>();
    final updated = _option.copyWith(
      fontSize: widget.fontSize,
      // 直接使用原始不透明度值，映射将在DanmakuScreen中处理
      opacity: widget.isVisible ? widget.opacity : 0.0,
      hideTop: videoState.blockTopDanmaku,
      hideBottom: videoState.blockBottomDanmaku,
      hideScroll: videoState.blockScrollDanmaku,
      showStroke: true,
      massiveMode: videoState.danmakuStacking,
      showCollisionBoxes: devOptions.showCanvasDanmakuCollisionBoxes,
      showTrackNumbers: devOptions.showCanvasDanmakuTrackNumbers,
    );
    
    // 🔥 检测弹幕类型过滤变化
    bool filterChanged = false;
    if (_option.hideTop != updated.hideTop || 
        _option.hideBottom != updated.hideBottom || 
        _option.hideScroll != updated.hideScroll) {
      filterChanged = true;
    }
    
    // 🔥 检测弹幕轨道堆叠设置变化
    bool stackingChanged = false;
    if (_option.massiveMode != updated.massiveMode) {
      stackingChanged = true;
    }
    
    _option = updated;
    if (_controller != null) {
      _controller!.updateOption(updated);
      
      // 🔥 关键修改：弹幕类型过滤变化时不清空弹幕，只更新选项
      // 这样可以保持弹幕的动画状态，绘制器会根据选项决定是否渲染
      if ((filterChanged || stackingChanged) && widget.isVisible) {
        // 只更新弹幕选项，不清空弹幕列表
        // 绘制器会根据hideXXX选项决定是否显示弹幕
      }
    }
  }

  /// 将项目中的 Map 弹幕数据转换为 Canvas_Danmaku 的实体
  canvas.DanmakuContentItem _convert(Map<String, dynamic> danmaku) {
    final content = danmaku['content']?.toString() ?? '';
    final typeStr = danmaku['type']?.toString() ?? 'scroll';
    late canvas.DanmakuItemType itemType;
    switch (typeStr) {
      case 'top':
        itemType = canvas.DanmakuItemType.top;
        break;
      case 'bottom':
        itemType = canvas.DanmakuItemType.bottom;
        break;
      default:
        itemType = canvas.DanmakuItemType.scroll;
    }

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
    return canvas.DanmakuContentItem(content, color: color, type: itemType);
  }

  /// 将项目中的 Map 弹幕数据转换为 Canvas_Danmaku 的实体（带时间偏移）
  canvas.DanmakuContentItem _convertWithTimeOffset(Map<String, dynamic> danmaku, double currentTimeSeconds) {
    final content = danmaku['content']?.toString() ?? '';
    final typeStr = danmaku['type']?.toString() ?? 'scroll';
    final danmakuTime = (danmaku['time'] ?? 0.0) as double;
    
    late canvas.DanmakuItemType itemType;
    switch (typeStr) {
      case 'top':
        itemType = canvas.DanmakuItemType.top;
        break;
      case 'bottom':
        itemType = canvas.DanmakuItemType.bottom;
        break;
      default:
        itemType = canvas.DanmakuItemType.scroll;
    }

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
    
    // 🔥 关键：计算时间偏移，模拟弹幕已经运动的时间
    final timeDiff = currentTimeSeconds - danmakuTime;
    final timeOffsetMs = (timeDiff * 1000).round();
    
    // 🔥 关键修复：在时间轴跳转时不指定trackIndex，让轨道管理器重新分配
    // 这样可以确保弹幕按照交叉绘制策略正常分布，而不是每个轨道一个弹幕
    return canvas.DanmakuContentItem(
      content, 
      color: color, 
      type: itemType,
      timeOffset: timeOffsetMs, // 设置时间偏移
      trackIndex: null, // 🔥 不指定轨道编号，让轨道管理器重新分配
    );
  }

  /// 检查弹幕是否应该被过滤
  bool _shouldFilterDanmaku(Map<String, dynamic> danmaku, VideoPlayerState videoState) {
    // 应用屏蔽词过滤
    final content = danmaku['content']?.toString() ?? '';
    for (final blockWord in videoState.danmakuBlockWords) {
      if (content.contains(blockWord)) {
        return true;
      }
    }
    
    // 应用类型过滤
    final type = danmaku['type']?.toString() ?? 'scroll';
    if (type == 'top' && videoState.blockTopDanmaku) return true;
    if (type == 'bottom' && videoState.blockBottomDanmaku) return true;
    if (type == 'scroll' && videoState.blockScrollDanmaku) return true;
    
    return false;
  }

  // 添加自定义的不透明度映射函数
  double _mapOpacity(double originalOpacity) {
    // 使用分段线性函数，确保整个范围内都有明显的变化
    // 0%   -> 10%（最低底线，确保永远可见）
    // 10%  -> 40%（低值区域快速提升可见度）
    // 30%  -> 60%（中值区域适度提升）
    // 50%  -> 75%（中高值区域）
    // 70%  -> 85%（高值区域）
    // 100% -> 100%（最高值保持不变）
    
    if (originalOpacity < 0.0) {
      return 0.1; // 安全检查
    } else if (originalOpacity < 0.1) {
      // 0-10% 映射到 10-40%
      return 0.1 + (originalOpacity * 3.0);
    } else if (originalOpacity < 0.3) {
      // 10-30% 映射到 40-60%
      return 0.4 + ((originalOpacity - 0.1) * 1.0);
    } else if (originalOpacity < 0.5) {
      // 30-50% 映射到 60-75%
      return 0.6 + ((originalOpacity - 0.3) * 0.75);
    } else if (originalOpacity < 0.7) {
      // 50-70% 映射到 75-85%
      return 0.75 + ((originalOpacity - 0.5) * 0.5);
    } else {
      // 70-100% 映射到 85-100%
      return 0.85 + ((originalOpacity - 0.7) * 0.5);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<VideoPlayerState, DeveloperOptionsProvider>(
      builder: (context, videoState, devOptions, child) {
        // 🔥 检测屏蔽词变化
        final currentBlockWords = List<String>.from(videoState.danmakuBlockWords);
        final blockWordsChanged = !_listEquals(_lastBlockWords, currentBlockWords);
        
        // 🔥 检测弹幕类型过滤设置变化
        final currentFilterSettings = '${videoState.blockTopDanmaku}-${videoState.blockBottomDanmaku}-${videoState.blockScrollDanmaku}';
        final filterSettingsChanged = _lastFilterSettings != currentFilterSettings;
        
        // 🔥 检测弹幕轨道堆叠设置变化
        final stackingSettingsChanged = _lastStackingSettings != videoState.danmakuStacking;
        
        // 🔥 检测碰撞箱显示设置变化
        final collisionBoxesChanged = _option.showCollisionBoxes != devOptions.showCanvasDanmakuCollisionBoxes;
        
        // 🔥 检测轨道编号显示设置变化
        final trackNumbersChanged = _option.showTrackNumbers != devOptions.showCanvasDanmakuTrackNumbers;
      
      if (blockWordsChanged || filterSettingsChanged || stackingSettingsChanged || collisionBoxesChanged || trackNumbersChanged) {
        _lastBlockWords = currentBlockWords;
        _lastFilterSettings = currentFilterSettings;
        _lastStackingSettings = videoState.danmakuStacking;
        
        // 🔥 关键修改：对于屏蔽词变化，需要重新同步弹幕，因为需要过滤内容
        // 对于类型过滤变化、堆叠变化、碰撞箱变化、轨道编号变化，只更新选项，不重新同步
        if (_controller != null && widget.isVisible) {
          if (blockWordsChanged) {
            // 只有屏蔽词变化才需要重新同步弹幕
            _addedDanmaku.clear();
            _controller!.clear();
            _lastSyncTime = 0.0;
            
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _syncDanmaku();
              // 🔥 关键修复：如果是暂停状态，需要特殊处理让弹幕显示
              if (!widget.isPlaying) {
                _handlePausedDanmakuDisplay();
              }
            });
          } else {
            // 类型过滤、堆叠、碰撞箱、轨道编号变化时只更新选项，保持弹幕状态
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _updateOption();
              // 🔥 重要：保持当前的播放/暂停状态，不要重新启动动画
              if (!widget.isPlaying && _controller != null) {
                _controller!.pause();
              }
            });
          }
        }
      }
      

      
      // 🔥 使用 Visibility 而不是 Opacity，确保隐藏时完全不渲染
      return Visibility(
        visible: widget.isVisible,
        child: Opacity(
          // 使用自定义映射函数，确保低透明度值在视觉上更加平滑
          opacity: _mapOpacity(widget.opacity),
          child: canvas.DanmakuScreen(
            createdController: (ctrl) {
              _controller = ctrl;

              // 延迟调用 _updateOption，确保 DanmakuScreen 完全初始化
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _controller != null) {
                  _updateOption();
                  // 🔥 关键修复：不要在这里调用resume()或pause()，因为这会在build重建时错误地改变状态
                  // 让_updateOption()和其他逻辑来处理播放/暂停状态
                  
                  // 🔥 关键修复：确保在初始化时也正确设置播放/暂停状态
                  if (!widget.isPlaying) {
                    _controller!.pause(); // 暂停状态保持暂停
                  }
                  
                  // 🔥 修复：无论播放状态如何，如果当前是可见状态，都要立即同步弹幕
                  if (widget.isVisible) {
                    _lastSyncTime = 0.0;
                    _syncDanmaku();
                    
                    // 🔥 关键修复：如果是暂停状态，需要特殊处理让弹幕显示
                    if (!widget.isPlaying) {
                      _handlePausedDanmakuDisplay();
                    }
                  }
                }
              });
            },
            option: _option.copyWith(
              fontSize: widget.fontSize,
              // 直接使用原始不透明度值，映射将在DanmakuScreen中处理
              opacity: widget.isVisible ? widget.opacity : 0.0,
              hideTop: videoState.blockTopDanmaku,
              hideBottom: videoState.blockBottomDanmaku,
              hideScroll: videoState.blockScrollDanmaku,
              showStroke: true,
              massiveMode: videoState.danmakuStacking,
              showCollisionBoxes: Provider.of<DeveloperOptionsProvider>(context, listen: false).showCanvasDanmakuCollisionBoxes,
              showTrackNumbers: Provider.of<DeveloperOptionsProvider>(context, listen: false).showCanvasDanmakuTrackNumbers,
            ),
          ),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    // 🔥 新增：初始化弹幕轨道状态
    if (_lastTrackEnabled.isEmpty) {
      final videoState = context.read<VideoPlayerState>();
      _lastTrackEnabled = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    }
    
    // 监听视频播放时间，按需添加弹幕
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDanmaku());
  }

  @override
  void dispose() {
    // 🔥 修复：在 dispose 时不要调用可能触发 setState 的方法
    if (_controller != null) {
      // 不要调用 clear()，因为它可能会触发 setState
      _controller = null;
    }
    _addedDanmaku.clear();
    super.dispose();
  }

  void _syncDanmaku() {
    if (!mounted || _controller == null || !context.mounted) return;
    
    final currentTimeSeconds = widget.currentPosition / 1000;
    
    // 检查是否是时间轴切换后的首次同步
    bool isAfterTimeJump = _lastSyncTime == 0.0 || (currentTimeSeconds - _lastSyncTime).abs() > 2.0;
    
    // 🔥 修复：在暂停状态下，如果是首次同步或时间轴切换，立即执行同步
    bool shouldSyncImmediately = isAfterTimeJump || !widget.isPlaying;
    
    // 避免频繁同步，每100ms同步一次（除非是时间轴切换后的首次同步或暂停状态）
    if (!shouldSyncImmediately && (currentTimeSeconds - _lastSyncTime).abs() < 0.1) {
      if (mounted && context.mounted && widget.isPlaying) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncDanmaku());
      }
      return;
    }
    
    _lastSyncTime = currentTimeSeconds;
    
    // 再次检查上下文是否有效
    if (!context.mounted) return;
    
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
      final timeA = (a['time'] ?? 0.0) as double;
      final timeB = (b['time'] ?? 0.0) as double;
      return timeA.compareTo(timeB);
    });

    // 如果是时间轴切换后的首次同步，需要预加载更大范围的弹幕
    double timeWindow = isAfterTimeJump ? 1.0 : 0.2; // 时间轴切换后扩大到1秒窗口
    
    if (isAfterTimeJump) {
      // 🔥 重大改进：时间轴切换后，加载所有应该在当前时间显示的弹幕（包括运动中途的）
      // 滚动弹幕：10秒运动时间，顶部/底部弹幕：5秒显示时间
      var allCurrentDanmaku = activeList.where((danmaku) {
        final danmakuTime = (danmaku['time'] ?? 0.0) as double;
        final danmakuType = danmaku['type']?.toString() ?? 'scroll';
        final timeDiff = currentTimeSeconds - danmakuTime;
        
        // 根据弹幕类型判断是否应该显示
        if (danmakuType == 'scroll') {
          // 滚动弹幕：在10秒运动时间内都应该显示
          return timeDiff >= 0 && timeDiff <= 10.0;
        } else {
          // 顶部/底部弹幕：在5秒显示时间内都应该显示
          return timeDiff >= 0 && timeDiff <= 5.0;
        }
      }).toList();
      
      // 🔥 关键修复：按照原始时间顺序排序弹幕，确保轨道管理器按正确顺序处理
      allCurrentDanmaku.sort((a, b) {
        final timeA = (a['time'] ?? 0.0) as double;
        final timeB = (b['time'] ?? 0.0) as double;
        return timeA.compareTo(timeB);
      });
      
      // 🔥 关键修复：设置时间跳转标记，确保时间跳转场景使用正确的轨道分配策略
      _controller!.setTimeJumpOrRestoring(true);
      
      // 🔥 关键修复：模拟原始弹幕添加顺序，而不是同时添加所有弹幕
      // 通过临时修改轨道管理器的时间，让它认为弹幕是按原始顺序添加的
      for (final danmaku in allCurrentDanmaku) {
        final danmakuTime = (danmaku['time'] ?? 0.0) as double;
        final content = danmaku['content']?.toString() ?? '';
        final key = '${danmakuTime.toStringAsFixed(3)}_$content';
        
        if (!_addedDanmaku.contains(key) && !_shouldFilterDanmaku(danmaku, videoState)) {
          // 🔥 关键修复：临时设置轨道管理器的时间为弹幕的原始时间
          // 这样轨道管理器会认为弹幕是在原始时间点添加的，而不是同时添加
          final originalTime = (danmakuTime * 1000).round(); // 转换为毫秒
          final savedCurrentTick = _controller!.getCurrentTick();
          _controller!.setCurrentTick(originalTime);
          
          // 创建运动中途的弹幕
          final convertedDanmaku = _convertWithTimeOffset(danmaku, currentTimeSeconds);
          _controller!.addDanmaku(convertedDanmaku);
          _addedDanmaku.add(key);
          
          // 恢复真实的当前时间
          _controller!.setCurrentTick(savedCurrentTick);
        }
      }
      
      // 🔥 关键修复：时间跳转处理完成后重置时间跳转标记
      _controller!.setTimeJumpOrRestoring(false);
    }

    int addedCount = 0;
    for (final danmaku in activeList) {
      final danmakuTime = (danmaku['time'] ?? 0.0) as double;
      final content = danmaku['content']?.toString() ?? '';
      
      // 创建唯一标识符
      final key = '${danmakuTime.toStringAsFixed(3)}_$content';
      
      // 检查是否已添加
      if (_addedDanmaku.contains(key)) continue;
      
      // 检查是否应该过滤
      if (_shouldFilterDanmaku(danmaku, videoState)) continue;
      
      // 检查时间窗口（即将播放的弹幕）
      if (danmakuTime <= currentTimeSeconds + timeWindow && danmakuTime >= currentTimeSeconds - timeWindow) {
        _controller!.addDanmaku(_convert(danmaku));
        _addedDanmaku.add(key);
        addedCount++;
      }
    }
    
    // 清理过期的已添加记录（超过30秒的）
    _addedDanmaku.removeWhere((key) {
      final timeStr = key.split('_')[0];
      final time = double.tryParse(timeStr) ?? 0.0;
      return (currentTimeSeconds - time).abs() > 30;
    });

    // 🔥 修复：只在播放状态下继续调度同步
    if (mounted && context.mounted && widget.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncDanmaku());
    }
  }

  // 🔥 添加列表比较辅助方法
  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 🔥 新增：保存当前弹幕状态
  void _saveDanmakuStates() {
    _savedDanmakuStates.clear();
    
    if (_controller == null) return;
    
    // 获取当前弹幕状态
    final danmakuStates = _controller!.getDanmakuStates();
    final currentTime = DateTime.now().millisecondsSinceEpoch; // 🔥 记录保存时间
    
    // 转换为DanmakuState格式并保存
    for (final state in danmakuStates) {
      _savedDanmakuStates.add(DanmakuState(
        content: state.content,
        color: state.color,
        type: state.type,
        normalizedProgress: state.normalizedProgress,
        originalCreationTime: state.originalCreationTime,
        remainingTime: state.remainingTime,
        yPosition: state.yPosition,
        saveTime: currentTime, // 🔥 新增：保存时间
        trackIndex: state.trackIndex, // 🔥 新增：轨道编号
      ));
    }
    
  }

  /// 🔥 新增：恢复弹幕状态
  void _restoreDanmakuStates() {
    if (_savedDanmakuStates.isEmpty || _controller == null) return;
    
    _isRestoring = true;
    
    // 清空当前弹幕
    _controller!.clear();
    
    final restoreTime = DateTime.now().millisecondsSinceEpoch; // 🔥 记录恢复时间
    
    // 恢复保存的弹幕状态
    int validCount = 0;
    int totalCount = _savedDanmakuStates.length;
    
    for (final state in _savedDanmakuStates) {
      // 🔥 关键修复：计算隐藏期间过去的时间
      final timeDuringHide = restoreTime - state.saveTime;
      
      // 🔥 关键修复：计算考虑隐藏时间的新剩余时间
      final newRemainingTime = state.remainingTime - timeDuringHide;
      
      // 🔥 关键修复：只恢复仍然有效的弹幕
      if (newRemainingTime > 0) {
        validCount++;
        final totalDuration = state.type == canvas.DanmakuItemType.scroll ? 10000 : 5000; // 毫秒
        final totalElapsedTime = totalDuration - newRemainingTime; // 包括隐藏期间的总运行时间
        
        // 创建带有时间偏移的弹幕项，让它从正确的位置开始
        final danmakuItem = canvas.DanmakuContentItem(
          state.content,
          color: state.color,
          type: state.type,
          timeOffset: totalElapsedTime, // 使用总运行时间作为偏移
          trackIndex: state.trackIndex, // 🔥 修复：使用保存的轨道编号，避免重新分配导致轨道调整
        );
        
        _controller!.addDanmaku(danmakuItem);
      }
    }
    
    _isRestoring = false;
    
    // 🔥 添加轨道信息调试
    if (validCount > 0) {
      final trackCounts = <int, int>{};
      for (final state in _savedDanmakuStates) {
        final timeDuringHide = restoreTime - state.saveTime;
        final newRemainingTime = state.remainingTime - timeDuringHide;
        if (newRemainingTime > 0) {
          trackCounts[state.trackIndex] = (trackCounts[state.trackIndex] ?? 0) + 1;
        }
      }
    }
    _savedDanmakuStates.clear();
    
    // 如果是暂停状态，需要特殊处理
    if (!widget.isPlaying) {
      _handlePausedDanmakuDisplay();
    }
  }

  /// 🔥 关键修复：处理暂停状态下的弹幕显示
  /// Canvas_Danmaku在暂停状态下不会渲染新添加的弹幕，需要特殊处理
  void _handlePausedDanmakuDisplay() {
    if (_controller == null || !mounted) return;
    
    // 🔥 修复：在暂停状态下，需要特殊处理来确保弹幕能够显示
    if (!widget.isPlaying) {
      // 🔥 关键修复：使用最小时间渲染，避免弹幕位置偏移
      // 先暂时恢复动画，立即在下一帧暂停
      _controller!.resume();
      
      // 立即在下一帧暂停，确保弹幕位置不会发生偏移
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null && !widget.isPlaying) {
          _controller!.pause();
        }
      });
    }
  }
} 
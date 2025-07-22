import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../canvas_danmaku/lib/danmaku_timeline_manager.dart';
import '../utils/video_player_state.dart';
import 'package:nipaplay/canvas_danmaku/lib/canvas_danmaku.dart' as canvas;
import '../providers/developer_options_provider.dart';

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
  
  // 🔥 新增：弹幕轨道记忆地图
  final Map<String, int> _danmakuTrackMap = {};
  
  // 🔥 添加屏蔽词变化检测
  List<String> _lastBlockWords = [];
  
  // 记录上次的弹幕类型过滤设置，用于检测变化
  String _lastFilterSettings = '';
  
  // 记录上次的弹幕轨道堆叠设置，用于检测变化
  bool _lastStackingSettings = false;
  
  // 🔥 添加弹幕轨道变化检测
  Map<String, bool> _lastTrackEnabled = {};
  String _lastTrackHash = '';
  
  // 🔥 移除：不再需要临时的状态保存列表
  // final List<DanmakuState> _savedDanmakuStates = [];
  bool _isRestoring = false;

  @override
  void didUpdateWidget(covariant CanvasDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!mounted) return;
    
    // 播放状态变化
    if (widget.isPlaying != oldWidget.isPlaying && _controller != null) {
      if (widget.isPlaying) {
        if (mounted) {
          // 恢复播放时，触发一次完全同步
          _lastSyncTime = 0.0;
          _syncDanmaku();
          _controller!.resume();
        }
      } else {
        if (mounted) {
          // 暂停弹幕
          _controller!.pause();
        }
      }
    }

    // 可见性或透明度变化
    if (widget.opacity != oldWidget.opacity || widget.isVisible != oldWidget.isVisible) {
      if (mounted) {
        _updateOption();
        
        if (widget.isVisible) {
          // 🔥 统一逻辑：显示弹幕时，触发一次与“时间跳转”完全相同的同步
          _lastSyncTime = 0.0;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncDanmaku();
            }
          });
        } else {
          // 🔥 统一逻辑：隐藏弹幕时，只清空屏幕，保留轨道记忆
          _controller?.clear();
        }
      }
    }

    // 字体大小变化
    if (widget.fontSize != oldWidget.fontSize) {
      if (mounted) {
        _updateOption();
      }
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
      if (_controller != null && widget.isVisible && mounted) {
        // 清空已添加的弹幕记录，重新添加符合新设置的弹幕
        _addedDanmaku.clear();
        
        if (mounted) {
          _controller!.clear();
          _lastSyncTime = 0.0;
          
          // 使用安全检查，确保组件仍然挂载
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _syncDanmaku();
              // 🔥 关键修复：如果是暂停状态，需要特殊处理让弹幕显示
              if (!widget.isPlaying && _controller != null) {
                _handlePausedDanmakuDisplay();
              }
            }
          });
        }
      }
    }

    // 检测时间轴切换（拖拽进度条或跳转）
    final timeDelta = (widget.currentPosition - oldWidget.currentPosition).abs();
    if (timeDelta > 2000) { // 时间跳跃超过2秒
      
      if (mounted) {
        // 清空已添加的弹幕记录
        _addedDanmaku.clear();
        
        // 清空画布上的所有弹幕
        if (_controller != null && mounted) {
          _controller!.clear();
        }
        
        // 重置同步时间，标记为需要重新同步
        _lastSyncTime = 0.0;
        
        // 立即同步新时间点的弹幕
        // 使用安全检查，确保组件仍然挂载
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncDanmaku();
          }
        });
      }
    }
    
    // 检测视频时长变化（切换视频）
    if (widget.videoDuration != oldWidget.videoDuration) {
      if (mounted) {
        _addedDanmaku.clear();
        if (_controller != null && mounted) {
          // 🔥 关键修复：切换视频时使用彻底重置，包括重置交叉绘制策略状态
          _controller!.resetAll();
        }
        _lastSyncTime = 0.0;
      }
    }
    
    // 🔥 新增：检测弹幕轨道状态变化
    final currentTracks = Map<String, bool>.from(videoState.danmakuTrackEnabled);
    final tracksChanged = !_mapEquals(_lastTrackEnabled, currentTracks);
    
    if (tracksChanged && mounted) {
      debugPrint('CanvasDanmakuOverlay: 检测到弹幕轨道状态变化，清空弹幕记录');
      _lastTrackEnabled = currentTracks;
      _addedDanmaku.clear(); // 清空已添加的弹幕记录
      if (_controller != null && mounted) {
        _controller!.clear(); // 清空控制器中的弹幕
      }
      _lastSyncTime = 0.0; // 🔥 关键修复：重置同步时间，确保弹幕能重新加载
      
      // 🔥 新增：立即触发同步，不等待下一次同步周期
      // 使用安全检查，确保组件仍然挂载
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _syncDanmaku();
          }
        });
      }
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
      try {
        _controller!.updateOption(updated);
      } catch (e) {
        // 安全处理异常，避免更新配置时崩溃
        debugPrint('更新弹幕配置时出错: $e');
      }
      
      // 🔥 关键修改：弹幕类型过滤变化时不清空弹幕，只更新选项
      // 这样可以保持弹幕的动画状态，绘制器会根据选项决定是否渲染
      if ((filterChanged || stackingChanged) && widget.isVisible) {
        // 只更新弹幕选项，不清空弹幕列表
        // 绘制器会根据hideXXX选项决定是否显示弹幕
      }
    }
  }

  /// 将项目中的 Map 弹幕数据转换为 Canvas_Danmaku 的实体
  canvas.DanmakuContentItem _convert(Map<String, dynamic> danmaku, [int? trackIndex]) {
    final content = danmaku['content']?.toString() ?? '';
    final time = (danmaku['time'] ?? 0.0) as double;
    final id = '${time}_$content'; // 🔥 生成唯一ID

    final colorStr = danmaku['color']?.toString() ?? '#FFFFFF';
    final type = danmaku['type']?.toString() ?? 'scroll';

    Color color = Colors.white;
    try {
      if (colorStr.startsWith('#')) {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } else if (colorStr.startsWith('0x')) {
        color = Color(int.parse(colorStr.substring(2), radix: 16));
      }
    } catch (e) {
      // 颜色解析失败，使用默认白色
    }

    canvas.DanmakuItemType itemType;
    switch (type) {
      case 'top':
        itemType = canvas.DanmakuItemType.top;
        break;
      case 'bottom':
        itemType = canvas.DanmakuItemType.bottom;
        break;
      case 'scroll':
      default:
        itemType = canvas.DanmakuItemType.scroll;
    }

    return canvas.DanmakuContentItem(
      content,
      id: id, // 🔥 传递ID
      color: color,
      type: itemType,
      timeOffset: 0,
      trackIndex: trackIndex, // 🔥 修改：使用传入的轨道索引
    );
  }

  /// 将原始弹幕数据转换为带时间偏移的DanmakuContentItem
  canvas.DanmakuContentItem _convertWithTimeOffset(Map<String, dynamic> danmaku, double timeOffset, [int? trackIndex]) {
    final content = danmaku['content']?.toString() ?? '';
    final danmakuTime = (danmaku['time'] ?? 0.0) as double;
    final id = '${danmakuTime}_$content'; // 🔥 生成唯一ID
    
    final colorStr = danmaku['color']?.toString() ?? '#FFFFFF';
    final type = danmaku['type']?.toString() ?? 'scroll';
    
    // 🔥 关键修复：直接使用传入的时间偏移量
    final timeOffsetMs = (timeOffset * 1000).round();

    Color color = Colors.white;
    try {
      if (colorStr.startsWith('#')) {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } else if (colorStr.startsWith('0x')) {
        color = Color(int.parse(colorStr.substring(2), radix: 16));
      }
    } catch (e) {
      // 颜色解析失败，使用默认白色
    }

    canvas.DanmakuItemType itemType;
    switch (type) {
      case 'top':
        itemType = canvas.DanmakuItemType.top;
        break;
      case 'bottom':
        itemType = canvas.DanmakuItemType.bottom;
        break;
      case 'scroll':
      default:
        itemType = canvas.DanmakuItemType.scroll;
    }

    return canvas.DanmakuContentItem(
      content,
      id: id, // 🔥 传递ID
      color: color,
      type: itemType,
      timeOffset: timeOffsetMs, // 🔥 关键修复：使用传入的时间偏移量
      trackIndex: trackIndex, //  不指定轨道编号，让轨道管理器重新分配
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
    // 使用安全检查，确保组件仍然挂载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _syncDanmaku();
      }
    });
  }

  @override
  void dispose() {
    // 🔥 修复：在 dispose 时不要调用可能触发 setState 的方法
    // 清理所有可能导致异步回调的资源
    _controller = null; // 直接置空，不调用任何方法
    _addedDanmaku.clear();
    // 🔥 移除：状态列表已删除
    // _savedDanmakuStates.clear();
    _isRestoring = false;
    _lastSyncTime = -1;
    super.dispose();
  }

  void _syncDanmaku() {
    // 安全检查：确保组件仍然挂载且控制器存在
    if (!mounted || _controller == null || !context.mounted) return;
    
    final currentTimeSeconds = widget.currentPosition / 1000;
    final videoState = context.read<VideoPlayerState>();
    final tracks = videoState.danmakuTracks;
    final trackEnabled = videoState.danmakuTrackEnabled;
    
    // 检查是否是时间轴切换后的首次同步
    bool isAfterTimeJump = _lastSyncTime == 0.0 || (currentTimeSeconds - _lastSyncTime).abs() > 2.0;
    
    if (isAfterTimeJump) {
      // ---------------------------------------------------
      // 时间轴跳转逻辑：使用完整的弹幕数据
      // ---------------------------------------------------
      _controller!.clear();
      _addedDanmaku.clear();

      final allDanmakuFromTracks = <Map<String, dynamic>>[];
      for (final trackId in tracks.keys) {
        if (trackEnabled[trackId] == true) {
          final trackData = tracks[trackId]!;
          allDanmakuFromTracks.addAll(trackData['danmakuList'] as List<Map<String, dynamic>>);
        }
      }

      var danmakuToDisplay = DanmakuTimelineManager.getDanmakuForTimeJump(
        allDanmaku: allDanmakuFromTracks,
        currentTimeSeconds: currentTimeSeconds,
      );
      
      _controller!.setTimeJumpOrRestoring(true);

      for (final danmaku in danmakuToDisplay) {
        if (!mounted || _controller == null) break;
        
        final danmakuTime = (danmaku['time'] ?? 0.0) as double;
        final content = danmaku['content']?.toString() ?? '';
        final id = '${danmakuTime}_$content';

        if (!_shouldFilterDanmaku(danmaku, videoState)) {
          final timeOffset = currentTimeSeconds - danmakuTime;
          // 🔥 关键修复：从原始数据中读取轨道信息
          final int? trackIndex = danmaku['trackIndex'] as int?; 

          // 🔥 恢复记忆：查找已保存的轨道号
          final int? rememberedTrack = _danmakuTrackMap[id]; 
          final convertedDanmaku = _convertWithTimeOffset(
            danmaku, 
            timeOffset,
            rememberedTrack, // 🔥 强制使用记住的轨道号
          );

          _controller!.addDanmaku(convertedDanmaku);
          _addedDanmaku.add(id);
        }
      }
      
      _controller!.setTimeJumpOrRestoring(false);

    } else {
      // ---------------------------------------------------
      // 正常播放逻辑：只添加即将出现的弹幕
      // ---------------------------------------------------
      final upcomingDanmaku = <Map<String, dynamic>>[];
      for (final trackId in tracks.keys) {
        if (trackEnabled[trackId] == true) {
          final trackData = tracks[trackId]!;
          final trackDanmaku = trackData['danmakuList'] as List<Map<String, dynamic>>;
          
          upcomingDanmaku.addAll(trackDanmaku.where((d) {
            final t = d['time'] as double? ?? 0.0;
            // 只获取未来一小段时间内的弹幕
            return t > currentTimeSeconds && t <= currentTimeSeconds + 1.0;
          }));
        }
      }

      for (final danmaku in upcomingDanmaku) {
        final danmakuTime = (danmaku['time'] ?? 0.0) as double;
        final content = danmaku['content']?.toString() ?? '';
        final key = '${danmakuTime.toStringAsFixed(3)}_$content';

        if (!_addedDanmaku.contains(key) && !_shouldFilterDanmaku(danmaku, videoState)) {
          final int? trackIndex = danmaku['trackIndex'] as int?;
          final danmakuContent = _convert(danmaku, trackIndex);
          _controller!.addDanmaku(danmakuContent);
          _addedDanmaku.add(key);

          // 🔥 获取并记忆轨道号
          if (_danmakuTrackMap[key] == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _controller == null) return;
              final states = _controller!.getDanmakuStates();
              final newDanmakuState = states.firstWhere(
                (s) => s.id == key,
                orElse: () => states.last, // Fallback
              );
              if (newDanmakuState.id == key) {
                _danmakuTrackMap[key] = newDanmakuState.trackIndex;
              }
            });
          }
        }
      }
    }

    _lastSyncTime = currentTimeSeconds;

    // 清理过期的已添加记录（超过60秒的）
    _addedDanmaku.removeWhere((key) {
      final timeStr = key.split('_')[0];
      final time = double.tryParse(timeStr) ?? 0.0;
      return (currentTimeSeconds - time).abs() > 60;
    });

    // 播放状态下继续调度
    if (mounted && widget.isPlaying) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _syncDanmaku();
        }
      });
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

  /// 🔥 移除：不再需要 _saveDanmakuStates 和 _restoreDanmakuStates 方法

  /// 🔥 关键修复：处理暂停状态下的弹幕显示
  /// Canvas_Danmaku在暂停状态下不会渲染新添加的弹幕，需要特殊处理
  void _handlePausedDanmakuDisplay() {
    // 安全检查：确保组件仍然挂载且控制器存在
    if (_controller == null || !mounted) return;
    
    // 🔥 修复：在暂停状态下，需要特殊处理来确保弹幕能够显示
    if (!widget.isPlaying && mounted) {
      try {
        // 保存当前控制器的状态
        final currentTick = _controller!.getCurrentTick();
        final states = _controller!.getDanmakuStates();
        
        // 🔥 关键修复：先清空，然后重新添加所有弹幕，确保它们能够显示
        if (mounted && _controller != null) {
          _controller!.clear();
        }
        
        // 短暂恢复动画，使弹幕能够正确初始化
        if (mounted && _controller != null) {
          _controller!.resume();
        }
        
        // 重新添加所有弹幕，使用当前时间作为基准
        if (mounted && _controller != null) {
          for (final state in states) {
            try {
              final totalDuration = state.type == canvas.DanmakuItemType.scroll ? 10000 : 5000; // 毫秒
              final elapsedTime = (state.normalizedProgress * totalDuration).toInt();
              
              final danmakuItem = canvas.DanmakuContentItem(
                state.content,
                color: state.color,
                type: state.type,
                timeOffset: elapsedTime,
                // 🔥 关键修改：添加轨道索引，确保弹幕使用原来的轨道
                trackIndex: state.trackIndex
              );
              
              _controller!.addDanmaku(danmakuItem);
            } catch (e) {
              debugPrint('重新添加弹幕出错: $e');
            }
          }
        }
        
        // 立即在下一帧暂停，确保弹幕位置不会发生偏移
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _controller != null && !widget.isPlaying) {
              _controller!.pause();
              
              // 恢复原始时间戳
              _controller!.setCurrentTick(currentTick);
            }
          });
        }
      } catch (e) {
        // 捕获所有可能的异常，避免崩溃
        debugPrint('处理暂停状态下的弹幕显示出错: $e');
      }
    }
  }
} 
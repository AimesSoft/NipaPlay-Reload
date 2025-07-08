import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/video_player_state.dart';
import '../danmaku/lib/canvas_danmaku.dart' as canvas;
import '../danmaku_abstraction/danmaku_kernel_factory.dart';

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
      
      // 🔥 关键修复：当弹幕从隐藏变为显示时，立即同步弹幕
      if (widget.isVisible && !oldWidget.isVisible) {

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
      }
      
      // 🔥 新增：当弹幕从显示变为隐藏时，清空画布
      if (!widget.isVisible && oldWidget.isVisible && _controller != null) {

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
        _controller!.clear();
      }
      _lastSyncTime = 0.0;
    }
  }

  void _updateOption() {
    if (!mounted) return;
    
    final videoState = context.read<VideoPlayerState>();
    final updated = _option.copyWith(
      fontSize: widget.fontSize,
      opacity: widget.isVisible ? widget.opacity : 0.0,
      hideTop: videoState.blockTopDanmaku,
      hideBottom: videoState.blockBottomDanmaku,
      hideScroll: videoState.blockScrollDanmaku,
      showStroke: true,
      massiveMode: videoState.danmakuStacking,
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
      
      // 如果弹幕类型过滤或轨道堆叠发生变化，立即重新同步弹幕
      if ((filterChanged || stackingChanged) && widget.isVisible) {
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
    
    return canvas.DanmakuContentItem(
      content, 
      color: color, 
      type: itemType,
      timeOffset: timeOffsetMs, // 设置时间偏移
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

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(builder: (context, videoState, child) {
      // 🔥 检测屏蔽词变化
      final currentBlockWords = List<String>.from(videoState.danmakuBlockWords);
      final blockWordsChanged = !_listEquals(_lastBlockWords, currentBlockWords);
      
      // 🔥 检测弹幕类型过滤设置变化
      final currentFilterSettings = '${videoState.blockTopDanmaku}-${videoState.blockBottomDanmaku}-${videoState.blockScrollDanmaku}';
      final filterSettingsChanged = _lastFilterSettings != currentFilterSettings;
      
      // 🔥 检测弹幕轨道堆叠设置变化
      final stackingSettingsChanged = _lastStackingSettings != videoState.danmakuStacking;
      
      if (blockWordsChanged || filterSettingsChanged || stackingSettingsChanged) {
        _lastBlockWords = currentBlockWords;
        _lastFilterSettings = currentFilterSettings;
        _lastStackingSettings = videoState.danmakuStacking;
        
        // 设置变化时，立即重新同步弹幕
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
      

      
      // 🔥 使用 Visibility 而不是 Opacity，确保隐藏时完全不渲染
      return Visibility(
        visible: widget.isVisible,
        child: Opacity(
          opacity: widget.opacity,
          child: canvas.DanmakuScreen(
            createdController: (ctrl) {
              _controller = ctrl;

              // 延迟调用 _updateOption，确保 DanmakuScreen 完全初始化
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _controller != null) {
                  _updateOption();
                  // 🔥 修复：Canvas_Danmaku始终保持运行状态，通过时间暂停来控制弹幕
                  _controller!.resume(); // 始终保持运行
                  
                  // 🔥 根据播放状态设置时间暂停状态
                  if (!widget.isPlaying) {
                    _controller!.pause(); // 这会设置_timePaused=true，但不停止动画循环
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
              opacity: widget.isVisible ? widget.opacity : 0.0,
              hideTop: videoState.blockTopDanmaku,
              hideBottom: videoState.blockBottomDanmaku,
              hideScroll: videoState.blockScrollDanmaku,
              showStroke: true,
              massiveMode: videoState.danmakuStacking,
            ),
          ),
        ),
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

    // 获取当前活跃弹幕列表
    final activeList = videoState.getActiveDanmakuList(currentTimeSeconds);

    // 如果是时间轴切换后的首次同步，需要预加载更大范围的弹幕
    double timeWindow = isAfterTimeJump ? 1.0 : 0.2; // 时间轴切换后扩大到1秒窗口
    
    if (isAfterTimeJump) {

      
      // 🔥 重大改进：时间轴切换后，加载所有应该在当前时间显示的弹幕（包括运动中途的）
      // 滚动弹幕：10秒运动时间，顶部/底部弹幕：5秒显示时间
      final allCurrentDanmaku = activeList.where((danmaku) {
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
      

      
      // 立即添加这些应该显示的弹幕
      for (final danmaku in allCurrentDanmaku) {
        final danmakuTime = (danmaku['time'] ?? 0.0) as double;
        final content = danmaku['content']?.toString() ?? '';
        final key = '${danmakuTime.toStringAsFixed(3)}_$content';
        
        if (!_addedDanmaku.contains(key) && !_shouldFilterDanmaku(danmaku, videoState)) {
          // 🔥 关键：为Canvas_Danmaku创建运动中途的弹幕
          final convertedDanmaku = _convertWithTimeOffset(danmaku, currentTimeSeconds);
          _controller!.addDanmaku(convertedDanmaku);
          _addedDanmaku.add(key);
        }
      }
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

  /// 🔥 关键修复：处理暂停状态下的弹幕显示
  /// Canvas_Danmaku在暂停状态下不会渲染新添加的弹幕，需要特殊处理
  void _handlePausedDanmakuDisplay() {
    if (_controller == null || !mounted) return;
    
    // 🔥 简化方案：在暂停状态下，让Canvas_Danmaku继续运行动画循环，但不更新弹幕时间
    // 这样可以确保弹幕始终显示在画布上，不会因为UI重绘而消失
    if (!widget.isPlaying) {
      // 确保动画循环继续运行，这样弹幕就不会消失
      _controller!.resume();
      
      // 短暂延迟后设置为"暂停"状态，但不停止动画循环
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null && !widget.isPlaying) {
          // 不调用pause()，让动画循环继续运行以保持弹幕显示
          // Canvas_Danmaku会根据时间变化来决定是否更新弹幕位置
          // 在暂停状态下时间不变，所以弹幕位置也不会变化，但会保持显示
        }
      });
    }
  }
} 
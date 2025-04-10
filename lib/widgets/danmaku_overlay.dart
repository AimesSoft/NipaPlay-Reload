import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku/lib/danmaku_screen.dart';
import 'package:nipaplay/danmaku/lib/danmaku_controller.dart';
import 'package:nipaplay/danmaku/lib/danmaku_option.dart';
import 'package:nipaplay/danmaku/lib/danmaku_content_item.dart';
import 'dart:async';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';

double getFontSize() {
  if (globals.isPhone) {
    return 20.0;
  } else {
    return 30.0;
  }
}

class DanmakuOverlay extends StatefulWidget {
  final List<Map<String, dynamic>> danmakuList;
  final bool isPlaying;
  final int currentPosition;

  const DanmakuOverlay({
    super.key,
    required this.danmakuList,
    required this.isPlaying,
    required this.currentPosition,
  });

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay> {
  late DanmakuController _danmakuController;
  final Set<String> _displayedDanmaku = {};
  Timer? _danmakuTimer;
  int? _lastPosition;
  final int _timeWindow = 1000; // 时间窗口大小（毫秒）
  final int _updateInterval = 0; // 更新间隔（毫秒）
  int _lastWindowStart = 0; // 记录上一个时间窗口的起始时间

  @override
  void initState() {
    super.initState();
    _danmakuController = DanmakuController(
      onAddDanmaku: _addDanmaku,
      onUpdateOption: _updateDanmakuOption,
      onPause: _pauseDanmaku,
      onResume: _resumeDanmaku,
      onClear: _clearDanmakus,
    );
    _startDanmakuTimer();
  }

  @override
  void dispose() {
    _danmakuTimer?.cancel();
    super.dispose();
  }

  void _startDanmakuTimer() {
    _danmakuTimer?.cancel();
    _danmakuTimer = Timer.periodic(Duration(milliseconds: _updateInterval), (timer) {
      if (widget.isPlaying) {
        _updateDanmakuDisplay();
      }
    });
  }

  @override
  void didUpdateWidget(DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 检测时间轴变化
    if (_lastPosition != null) {
      int timeDiff = (widget.currentPosition - _lastPosition!).abs();
      if (timeDiff > _timeWindow) { // 如果时间差超过时间窗口，认为是时间轴跳转
        _clearDanmakus();
        _displayedDanmaku.clear();
        _lastWindowStart = widget.currentPosition - _timeWindow;
      }
    }
    _lastPosition = widget.currentPosition;

    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _resumeDanmaku();
        _startDanmakuTimer();
      } else {
        _pauseDanmaku();
        _danmakuTimer?.cancel();
      }
    }
  }

  void _updateDanmakuDisplay() {
    if (!mounted) return;
    
    // 获取当前时间窗口
    final currentTime = widget.currentPosition;
    final windowStart = currentTime - _timeWindow;
    final windowEnd = currentTime + _timeWindow;
    
    // 如果时间窗口没有移动，不需要更新
    if (windowStart == _lastWindowStart) {
      return;
    }
    
    // 更新窗口起始时间
    _lastWindowStart = windowStart;
    
    // 清理已经不在时间窗口内的弹幕ID
    _displayedDanmaku.removeWhere((id) {
      final time = int.parse(id.split('-')[0]);
      return time < windowStart || time > windowEnd;
    });
    
    // 处理时间窗口内的弹幕
    for (var danmaku in widget.danmakuList) {
      final time = ((danmaku['time'] as double) * 1000).toInt(); // 转换为毫秒
      
      // 只处理时间窗口内的弹幕
      if (time >= windowStart && time <= windowEnd) {
        final content = danmaku['content'] as String;
        final type = danmaku['type'] as String;
        final colorStr = danmaku['color'] as String;
        
        // 生成唯一标识
        final danmakuId = '$time-$type-$colorStr-$content';
        
        // 如果这个弹幕还没有显示过
        if (!_displayedDanmaku.contains(danmakuId)) {
          _displayedDanmaku.add(danmakuId);
          
          // 解析颜色
          final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
          final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
          
          // 创建弹幕内容项
          final danmakuItem = DanmakuContentItem(
            content,
            type: type == 'scroll' 
                ? DanmakuItemType.scroll 
                : type == 'top' 
                    ? DanmakuItemType.top 
                    : DanmakuItemType.bottom,
            color: color,
          );
          
          // 添加弹幕
          _addDanmaku(danmakuItem);
        }
      }
    }
  }

  void _addDanmaku(DanmakuContentItem content) {
    if (!mounted) return;
    _danmakuController.addDanmaku(content);
  }

  void _updateDanmakuOption(DanmakuOption option) {
    if (!mounted) return;
    _danmakuController.option = option;
  }

  void _pauseDanmaku() {
    if (!mounted) return;
    _danmakuController.pause();
  }

  void _resumeDanmaku() {
    if (!mounted) return;
    _danmakuController.resume();
  }

  void _clearDanmakus() {
    if (!mounted) return;
    _danmakuController.clear();
    _displayedDanmaku.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        if (!videoState.danmakuVisible) {
          return const SizedBox.shrink();
        }
        return Opacity(
          opacity: videoState.danmakuOpacity,
          child: DanmakuScreen(
            createdController: (controller) {
              _danmakuController = controller;
            },
            option: DanmakuOption(
              fontSize: getFontSize(),
              opacity: 1.0, // 设置弹幕本身的透明度为1.0，因为外层已经有Opacity控件了
            ),
          ),
        );
      },
    );
  }
} 
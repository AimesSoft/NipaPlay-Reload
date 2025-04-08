import 'package:flutter/material.dart';
import 'package:nipaplay/danmaku/lib/danmaku_screen.dart';
import 'package:nipaplay/danmaku/lib/danmaku_controller.dart';
import 'package:nipaplay/danmaku/lib/danmaku_option.dart';
import 'package:nipaplay/danmaku/lib/danmaku_content_item.dart';
import 'dart:async';
import 'package:nipaplay/utils/globals.dart';
double getFontSize() {
  if (isPhone) {
    return 20.0; // 如果是iOS或Android设备
  } else {
    return 30.0; // 其他平台，例如Web、桌面
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
    _danmakuTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
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
      if (timeDiff > 1000) { // 如果时间差超过1秒，认为是时间轴跳转
        _clearDanmakus();
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
    
    // 预处理：按时间轴对弹幕进行分组，每个时间点只保留一个弹幕
    final Map<double, Map<String, dynamic>> timeGroupedDanmaku = {};
    for (var danmaku in widget.danmakuList) {
      final time = danmaku['time'] as double;
      // 如果这个时间点已经有弹幕了，就跳过
      if (!timeGroupedDanmaku.containsKey(time)) {
        timeGroupedDanmaku[time] = danmaku;
      }
    }
    
    // 使用去重后的弹幕列表进行显示
    for (var danmaku in timeGroupedDanmaku.values) {
      final time = danmaku['time'] as double;
      final content = danmaku['content'] as String;
      final type = danmaku['type'] as String;
      final colorStr = danmaku['color'] as String;
      
      // 解析颜色
      final colorValues = colorStr.replaceAll('rgb(', '').replaceAll(')', '').split(',').map((s) => int.parse(s)).toList();
      final color = Color.fromARGB(255, colorValues[0], colorValues[1], colorValues[2]);
      
      // 修改弹幕ID的生成方式，加入更多唯一性标识
      final danmakuId = '$time-$type-$colorStr-$content';

      // 修改时间窗口判断逻辑，使用更精确的时间范围
      final currentTime = widget.currentPosition;
      final danmakuTime = (time * 1000).toInt();
      final timeDiff = (currentTime - danmakuTime).abs();

      if (!_displayedDanmaku.contains(danmakuId) && 
          widget.currentPosition >= (time * 1000) - 25 && 
          widget.currentPosition <= (time * 1000) + 25) {
        _displayedDanmaku.add(danmakuId);
        _addDanmaku(DanmakuContentItem(
          content,
          type: type == 'scroll' 
              ? DanmakuItemType.scroll 
              : type == 'top' 
                  ? DanmakuItemType.top 
                  : DanmakuItemType.bottom,
          color: color,
        ));
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
    return DanmakuScreen(
      createdController: (controller) {
        _danmakuController = controller;
      },
      option: DanmakuOption(
        fontSize: getFontSize(),
      ),
    );
  }
} 
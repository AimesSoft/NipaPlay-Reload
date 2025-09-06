import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'lib/danmaku_screen.dart';
import 'lib/danmaku_controller.dart';
import 'lib/models/danmaku_option.dart';
import 'lib/models/danmaku_content_item.dart' as canvas_models;

// Canvas弹幕渲染管理器
class CanvasDanmakuManager {
  // 创建Canvas弹幕渲染器
  static Widget createRenderer({
    required double fontSize,
    required double opacity,
    required double displayArea,
    required bool visible,
    required bool stacking,
    required bool mergeDanmaku,
    required bool blockTopDanmaku,
    required bool blockBottomDanmaku,
    required bool blockScrollDanmaku,
    required List<String> blockWords,
    required double currentTime,
    required bool isPlaying,
    required double playbackRate,
  }) {
    return CanvasDanmakuRenderer(
      fontSize: fontSize,
      opacity: opacity,
      displayArea: displayArea,
      visible: visible,
      stacking: stacking,
      mergeDanmaku: mergeDanmaku,
      blockTopDanmaku: blockTopDanmaku,
      blockBottomDanmaku: blockBottomDanmaku,
      blockScrollDanmaku: blockScrollDanmaku,
      blockWords: blockWords,
      currentTime: currentTime,
      isPlaying: isPlaying,
      playbackRate: playbackRate,
    );
  }
}

// Canvas弹幕渲染器Widget
class CanvasDanmakuRenderer extends StatefulWidget {
  final double fontSize;
  final double opacity;
  final double displayArea;
  final bool visible;
  final bool stacking;
  final bool mergeDanmaku;
  final bool blockTopDanmaku;
  final bool blockBottomDanmaku;
  final bool blockScrollDanmaku;
  final List<String> blockWords;
  final double currentTime;
  final bool isPlaying;
  final double playbackRate;

  const CanvasDanmakuRenderer({
    super.key,
    required this.fontSize,
    required this.opacity,
    required this.displayArea,
    required this.visible,
    required this.stacking,
    required this.mergeDanmaku,
    required this.blockTopDanmaku,
    required this.blockBottomDanmaku,
    required this.blockScrollDanmaku,
    required this.blockWords,
    required this.currentTime,
    required this.isPlaying,
    required this.playbackRate,
  });

  @override
  State<CanvasDanmakuRenderer> createState() => _CanvasDanmakuRendererState();
}

class _CanvasDanmakuRendererState extends State<CanvasDanmakuRenderer> {
  DanmakuController? _controller;
  List<Map<String, dynamic>> _lastProcessedDanmakuList = [];
  double _lastCurrentTime = 0;
  DanmakuScreen? _danmakuScreen;
  DanmakuOption? _currentOption;
  
  // 添加已添加弹幕的跟踪集合，避免重复添加
  final Set<String> _addedDanmakuKeys = {};

  @override
  void initState() {
    super.initState();
    _initializeDanmakuScreen();
    
    // 初始化时处理弹幕
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      _processAndAddDanmaku(videoState.danmakuList, widget.currentTime);
    });
  }

  void _initializeDanmakuScreen() {
    _currentOption = DanmakuOption(
      fontSize: widget.fontSize,
      opacity: widget.opacity,
      area: widget.displayArea,
      duration: 10, // 默认10秒滚动时间
      hideTop: widget.blockTopDanmaku,
      hideBottom: widget.blockBottomDanmaku,
      hideScroll: widget.blockScrollDanmaku,
      showStroke: true, // 默认显示描边
      massiveMode: widget.stacking,
      safeArea: true, // 为字幕预留空间
      playbackRate: widget.playbackRate,
    );

    _danmakuScreen = DanmakuScreen(
      key: ValueKey(_currentOption.hashCode),
      option: _currentOption!,
      createdController: (controller) {
        //print('Canvas弹幕: DanmakuController已创建');
        _controller = controller;
      },
    );
  }

  bool _needsScreenRecreation() {
    if (_currentOption == null) return true;
    
    return _currentOption!.fontSize != widget.fontSize ||
           _currentOption!.opacity != widget.opacity ||
           _currentOption!.area != widget.displayArea ||
           _currentOption!.hideTop != widget.blockTopDanmaku ||
           _currentOption!.hideBottom != widget.blockBottomDanmaku ||
           _currentOption!.hideScroll != widget.blockScrollDanmaku ||
           _currentOption!.massiveMode != widget.stacking ||
           _currentOption!.playbackRate != widget.playbackRate;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) {
      return const SizedBox.shrink();
    }

    // 如果配置发生变化，重新创建DanmakuScreen
    if (_needsScreenRecreation()) {
      _initializeDanmakuScreen();
    }

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 确保弹幕播放状态与视频播放状态同步
        if (_controller != null) {
          if (widget.isPlaying && !_controller!.running) {
            //print('Canvas弹幕: Consumer检测到需要恢复播放');
            _controller!.resume();
          } else if (!widget.isPlaying && _controller!.running) {
            //print('Canvas弹幕: Consumer检测到需要暂停播放');
            _controller!.pause();
          }
        }
        
        return _danmakuScreen!;
      },
    );
  }

  @override
  void dispose() {
    _controller?.clear();
    _controller = null;
    _addedDanmakuKeys.clear(); // 清理弹幕键值缓存
    super.dispose();
  }

  @override
  void didUpdateWidget(CanvasDanmakuRenderer oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 处理播放/暂停状态变化
    if (widget.isPlaying != oldWidget.isPlaying && _controller != null) {
      //print('Canvas弹幕: 播放状态变化 ${oldWidget.isPlaying} -> ${widget.isPlaying}');
      if (widget.isPlaying) {
        _controller!.resume();
      } else {
        _controller!.pause();
      }
    }
    
    // 检测时间轴大幅变化（用户拖拽进度条）
    double timeDiff = (widget.currentTime - oldWidget.currentTime).abs();
    if (timeDiff > 2.0 && _controller != null) {
      //print('Canvas弹幕: didUpdateWidget检测到时间跳跃 ${timeDiff}秒，强制重新处理弹幕');
      // 重置时间记录，确保下次_processAndAddDanmaku能检测到变化
      _lastCurrentTime = widget.currentTime - 10.0; // 设置一个明显不同的值
    }

    // 只在时间变化、播放状态变化或其他重要属性变化时处理弹幕
    bool shouldProcessDanmaku = widget.currentTime != oldWidget.currentTime ||
                                widget.isPlaying != oldWidget.isPlaying ||
                                widget.fontSize != oldWidget.fontSize ||
                                widget.opacity != oldWidget.opacity ||
                                widget.displayArea != oldWidget.displayArea ||
                                widget.visible != oldWidget.visible;

    if (shouldProcessDanmaku) {
      // 获取最新的弹幕列表并处理
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        _processAndAddDanmaku(videoState.danmakuList, widget.currentTime);
      });
    }
  }

  // 处理并添加弹幕到Canvas渲染器
  void _processAndAddDanmaku(List<Map<String, dynamic>> danmakuList, double currentTime) {
    if (_controller == null) return;

    //print('Canvas弹幕: _processAndAddDanmaku 被调用, 当前时间=$currentTime, 弹幕总数=${danmakuList.length}');

    // 检查是否需要重新处理弹幕列表  
    double timeDiff = (currentTime - _lastCurrentTime).abs();
    bool timeChanged = timeDiff > 0.1; // 普通时间变化阈值
    bool timeJumped = timeDiff > 2.0; // 时间跳跃阈值（切换时间轴）
    bool dataChanged = _lastProcessedDanmakuList.length != danmakuList.length;
    bool forceProcess = _lastProcessedDanmakuList.isEmpty; // 第一次强制处理
    
    // 如果发生时间跳跃，清空当前弹幕并强制重新处理
    if (timeJumped) {
      //print('Canvas弹幕: 检测到时间跳跃 ${timeDiff}秒，清空当前弹幕并重新处理');
      _controller!.clear();
      _addedDanmakuKeys.clear(); // 清空已添加弹幕的跟踪
      forceProcess = true;
    }
    
    if (!timeChanged && !dataChanged && !forceProcess) {
      //print('Canvas弹幕: 跳过处理，时间变化=${timeDiff}, 数据变化=$dataChanged');
      return;
    }

    //print('Canvas弹幕: 开始处理弹幕，时间变化=${timeDiff}, 数据变化=$dataChanged, 强制处理=$forceProcess, 时间跳跃=$timeJumped');

    _lastProcessedDanmakuList = List.from(danmakuList);
    _lastCurrentTime = currentTime;

    // 获取弹幕显示的时间窗口
    // 如果发生时间跳跃，使用较小的前置窗口以快速响应
    final windowStart = timeJumped ? currentTime - 1.0 : currentTime - 5.0;
    final windowEnd = currentTime + 15.0;

    //print('Canvas弹幕: 时间窗口 $windowStart ~ $windowEnd (时间跳跃: $timeJumped)');

    int processedCount = 0;
    int addedCount = 0;
    
    for (var danmakuData in danmakuList) {
      final time = (danmakuData['time'] as num?)?.toDouble() ?? 0.0;
      processedCount++;
      
      // 处理时间窗口内的弹幕
      if (time < windowStart || time > windowEnd) {
        if (processedCount <= 3) { // 只打印前3条的详细信息
          //print('Canvas弹幕: 跳过弹幕 时间=$time (超出窗口)');
        }
        continue;
      }

      // 正确的弹幕文本字段是'content'
      final text = danmakuData['content']?.toString() ?? '';
                   
      if (processedCount <= 5) {
        //print('Canvas弹幕: 弹幕数据 时间=$time, 内容="$text", 类型=${danmakuData['type']}');
      }
      
      if (text.isEmpty) {
        if (processedCount <= 10) {
          //print('Canvas弹幕: 跳过空文本弹幕 (所有字段都为空)');
        }
        continue;
      }

      if (_shouldBlockDanmaku(text)) {
        //print('Canvas弹幕: 跳过被屏蔽弹幕: "$text"');
        continue;
      }

      // 创建弹幕唯一标识符，用于去重
      final danmakuKey = '${time.toStringAsFixed(1)}_${text}_${danmakuData['type']}';
      if (_addedDanmakuKeys.contains(danmakuKey)) {
        //print('Canvas弹幕: 跳过重复弹幕: "$text" 时间=$time');
        continue;
      }

      // 将抽象弹幕模型转换为Canvas弹幕模型
      final canvasDanmaku = _convertToCanvasDanmaku(danmakuData, text);
      if (canvasDanmaku != null) {
        //print('Canvas弹幕: 准备添加弹幕 "$text" 时间=$time 类型=${canvasDanmaku.type}');
        _controller!.addDanmaku(canvasDanmaku);
        _addedDanmakuKeys.add(danmakuKey); // 记录已添加的弹幕
        addedCount++;
      } else {
        //print('Canvas弹幕: 转换失败的弹幕: "$text"');
      }
      
      // 限制添加数量，避免一次添加太多
      // 如果发生时间跳跃，允许添加更多弹幕以快速显示内容
      if (addedCount >= (timeJumped ? 20 : 10)) {
        //print('Canvas弹幕: 达到单次添加上限，停止处理 (时间跳跃模式: $timeJumped)');
        break;
      }
    }
    
    //print('Canvas弹幕: 处理完成，处理了 $processedCount 条，添加了 $addedCount 条弹幕');
    
    // 定期清理过期的弹幕键值（超过30秒的弹幕键值），避免内存泄漏
    if (_addedDanmakuKeys.length > 1000) {
      _addedDanmakuKeys.clear();
      //print('Canvas弹幕: 清理弹幕键值缓存，避免内存泄漏');
    }
  }

  // 检查弹幕是否应该被屏蔽
  bool _shouldBlockDanmaku(String text) {
    for (String blockWord in widget.blockWords) {
      if (text.contains(blockWord)) {
        return true;
      }
    }
    return false;
  }

  // 将抽象弹幕模型转换为Canvas弹幕模型
  canvas_models.DanmakuContentItem? _convertToCanvasDanmaku(Map<String, dynamic> danmakuData, String text) {
    try {
      if (text.isEmpty) {
        //print('Canvas弹幕: 转换失败 - 空文本');
        return null;
      }

      // 解析弹幕类型 - 处理字符串类型
      final typeValue = danmakuData['type'];
      canvas_models.DanmakuItemType type;
      if (typeValue is String) {
        switch (typeValue.toLowerCase()) {
          case 'top':
            type = canvas_models.DanmakuItemType.top;
            break;
          case 'bottom':
            type = canvas_models.DanmakuItemType.bottom;
            break;
          case 'scroll':
          default:
            type = canvas_models.DanmakuItemType.scroll;
            break;
        }
      } else {
        // 处理数字类型（向后兼容）
        final intType = typeValue as int? ?? 1;
        switch (intType) {
          case 4:
            type = canvas_models.DanmakuItemType.bottom;
            break;
          case 5:
            type = canvas_models.DanmakuItemType.top;
            break;
          default:
            type = canvas_models.DanmakuItemType.scroll;
            break;
        }
      }

      // 解析颜色 - 处理RGB字符串格式
      Color color = Colors.white;
      final colorValue = danmakuData['color'];
      if (colorValue is String) {
        // 解析 "rgb(255,255,255)" 格式
        final rgbMatch = RegExp(r'rgb\((\d+),\s*(\d+),\s*(\d+)\)').firstMatch(colorValue);
        if (rgbMatch != null) {
          final r = int.parse(rgbMatch.group(1)!);
          final g = int.parse(rgbMatch.group(2)!);
          final b = int.parse(rgbMatch.group(3)!);
          color = Color.fromRGBO(r, g, b, 1.0);
        }
      } else if (colorValue is int) {
        // 处理整数颜色值（向后兼容）
        color = Color(0xFF000000 | colorValue);
      }

      // 检查是否自己发送
      final isMe = danmakuData['isMe'] as bool? ?? false;

      //print('Canvas弹幕: 转换成功 - 文本="$text", 类型=$typeValue->$type, 颜色=${color.value.toRadixString(16)}, 自己发送=$isMe');

      return canvas_models.DanmakuContentItem(
        text,
        color: color,
        type: type,
        selfSend: isMe,
      );
    } catch (e) {
      //print('Canvas弹幕: 转换异常 - $e, 数据: $danmakuData');
      return null;
    }
  }
}
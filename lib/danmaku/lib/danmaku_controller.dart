import 'package:flutter/material.dart';
import 'danmaku_option.dart';
import 'danmaku_content_item.dart';

/// 🔥 新增：弹幕状态数据类
class DanmakuItemState {
  final String content;
  final Color color;
  final DanmakuItemType type;
  final double normalizedProgress; // 归一化进度 (0.0-1.0)
  final int originalCreationTime; // 原始创建时间
  final int remainingTime; // 剩余显示时间（毫秒）
  final double yPosition; // Y轴位置
  final int trackIndex; // 🔥 新增：轨道编号
  
  DanmakuItemState({
    required this.content,
    required this.color,
    required this.type,
    required this.normalizedProgress,
    required this.originalCreationTime,
    required this.remainingTime,
    required this.yPosition,
    required this.trackIndex, // 🔥 新增：轨道编号
  });
}

class DanmakuController {
  final Function(DanmakuContentItem) onAddDanmaku;
  final Function(DanmakuOption) onUpdateOption;
  final Function onPause;
  final Function onResume;
  final Function onClear;
  final Function onResetAll; // 🔥 新增：彻底重置回调
  final int Function() onGetCurrentTick; // 🔥 新增：获取当前时间tick
  final Function(int) onSetCurrentTick; // 🔥 新增：设置当前时间tick
  final List<DanmakuItemState> Function() onGetDanmakuStates; // 🔥 新增：获取弹幕状态的回调
  final Function(bool) onSetTimeJumpOrRestoring; // 🔥 新增：设置时间跳转或状态恢复标记的回调
  
  DanmakuController({
    required this.onAddDanmaku,
    required this.onUpdateOption,
    required this.onPause,
    required this.onResume,
    required this.onClear,
    required this.onResetAll, // 🔥 新增
    required this.onGetCurrentTick, // 🔥 新增
    required this.onSetCurrentTick, // 🔥 新增
    required this.onGetDanmakuStates, // 🔥 新增
    required this.onSetTimeJumpOrRestoring, // 🔥 新增
  });

  bool _running = true;

  /// 是否运行中
  /// 可以调用pause()暂停弹幕
  bool get running => _running;
  set running(e) {
    _running = e;
  }

  DanmakuOption _option = DanmakuOption();
  DanmakuOption get option => _option;
  set option(e) {
    _option = e;
  }

  /// 暂停弹幕
  void pause() {
    onPause.call();
  }

  /// 继续弹幕
  void resume() {
    onResume.call();
  }

  /// 清空弹幕
  void clear() {
    onClear.call();
  }

  /// 🔥 新增：彻底重置所有状态
  void resetAll() {
    onResetAll.call();
  }

  /// 🔥 新增：获取当前时间tick
  int getCurrentTick() {
    return onGetCurrentTick.call();
  }

  /// 🔥 新增：设置当前时间tick
  void setCurrentTick(int tick) {
    onSetCurrentTick.call(tick);
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem item) {
    onAddDanmaku.call(item);
  }

  /// 更新弹幕配置
  void updateOption(DanmakuOption option) {
    onUpdateOption.call(option);
  }

  /// 🔥 新增：获取当前弹幕状态
  List<DanmakuItemState> getDanmakuStates() {
    return onGetDanmakuStates.call();
  }
  
  /// 🔥 新增：设置时间跳转或状态恢复标记
  void setTimeJumpOrRestoring(bool value) {
    onSetTimeJumpOrRestoring.call(value);
  }
}

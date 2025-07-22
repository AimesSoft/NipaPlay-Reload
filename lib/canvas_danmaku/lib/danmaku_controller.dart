import 'package:flutter/material.dart';
import 'danmaku_option.dart';
import 'danmaku_content_item.dart';

/// 弹幕状态类
class DanmakuState {
  final String? id;
  final String content;
  final DanmakuItemType type;
  final double normalizedProgress;
  final int originalCreationTime;
  final int remainingTime;
  final double yPosition;
  final int trackIndex;
  final Color color;

  DanmakuState({
    this.id,
    required this.content,
    required this.type,
    required this.normalizedProgress,
    required this.originalCreationTime,
    required this.remainingTime,
    required this.yPosition,
    required this.trackIndex,
    required this.color,
  });
}

class DanmakuController {
  final Function(DanmakuContentItem) onAddDanmaku;
  final Function(DanmakuOption) onUpdateOption;
  final Function onPause;
  final Function onResume;
  final Function onClear;
  final Function? onResetAll;
  final Function? onGetCurrentTick;
  final Function? onSetCurrentTick;
  final Function? onGetDanmakuStates;
  final Function? onSetTimeJumpOrRestoring;
  final Function(int)? onUpdateTick; // 新增：更新时间tick的回调，由外部定时器调用

  DanmakuController({
    required this.onAddDanmaku,
    required this.onUpdateOption,
    required this.onPause,
    required this.onResume,
    required this.onClear,
    this.onResetAll,
    this.onGetCurrentTick,
    this.onSetCurrentTick,
    this.onGetDanmakuStates,
    this.onSetTimeJumpOrRestoring,
    this.onUpdateTick,
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

  /// 彻底重置
  void resetAll() {
    if (onResetAll != null) {
      onResetAll!.call();
    } else {
      clear();
    }
  }

  /// 获取当前时间
  int getCurrentTick() {
    if (onGetCurrentTick != null) {
      return onGetCurrentTick!.call();
    }
    return 0;
  }

  /// 设置当前时间
  void setCurrentTick(int tick) {
    if (onSetCurrentTick != null) {
      onSetCurrentTick!.call(tick);
    }
  }

  /// 获取弹幕状态
  List<DanmakuState> getDanmakuStates() {
    if (onGetDanmakuStates != null) {
      return onGetDanmakuStates!.call();
    }
    return [];
  }

  /// 设置时间跳转或恢复标记
  void setTimeJumpOrRestoring(bool value) {
    if (onSetTimeJumpOrRestoring != null) {
      onSetTimeJumpOrRestoring!.call(value);
    }
  }

  /// 添加弹幕
  void addDanmaku(DanmakuContentItem item) {
    try {
      onAddDanmaku.call(item);
    } catch (e) {
      // 安全处理异常，避免添加弹幕时崩溃
      print('添加弹幕时出错: $e');
    }
  }

  /// 更新弹幕配置
  void updateOption(DanmakuOption option) {
    try {
      onUpdateOption.call(option);
    } catch (e) {
      // 安全处理异常，避免更新配置时崩溃
      print('更新弹幕配置时出错: $e');
    }
  }
  
  /// 更新时间戳，由外部定时器调用
  void updateTick(int delta) {
    if (onUpdateTick != null) {
      onUpdateTick!(delta);
    }
  }
}

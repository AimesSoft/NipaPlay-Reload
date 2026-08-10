import 'models/danmaku_option.dart';
import 'models/danmaku_content_item.dart';

typedef AddDanmakuCallback = bool Function(
  DanmakuContentItem item, {
  required double initialProgress,
  required double elapsedSeconds,
});

class DanmakuController {
  final AddDanmakuCallback onAddDanmaku;
  final void Function(DanmakuOption) onUpdateOption;
  final void Function() onPause;
  final void Function() onResume;
  final void Function() onClear;
  DanmakuController({
    required this.onAddDanmaku,
    required this.onUpdateOption,
    required this.onPause,
    required this.onResume,
    required this.onClear,
  });

  bool _running = true;

  /// 是否运行中
  /// 可以调用pause()暂停弹幕
  bool get running => _running;
  set running(bool value) {
    _running = value;
  }

  DanmakuOption _option = DanmakuOption();
  DanmakuOption get option => _option;
  set option(DanmakuOption value) {
    _option = value;
  }

  /// 暂停弹幕
  void pause() {
    if (!_running) return;
    onPause.call();
    _running = false;
  }

  /// 继续弹幕
  void resume() {
    if (_running) return;
    onResume.call();
    _running = true;
  }

  /// 清空弹幕
  void clear() {
    onClear.call();
  }

  /// 添加弹幕
  /// [initialProgress] 用于 seek 后恢复滚动弹幕的水平位置。
  /// [elapsedSeconds] 用于恢复顶部/底部弹幕的剩余生命周期。
  /// 返回是否真正上屏：轨道冲突、被隐藏等情况下返回 false。
  bool addDanmaku(
    DanmakuContentItem item, {
    double initialProgress = 0,
    double elapsedSeconds = 0,
  }) {
    return onAddDanmaku.call(
      item,
      initialProgress: initialProgress,
      elapsedSeconds: elapsedSeconds,
    );
  }

  /// 更新弹幕配置
  void updateOption(DanmakuOption option) {
    onUpdateOption.call(option);
  }
}

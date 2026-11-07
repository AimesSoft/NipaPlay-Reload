import 'dart:async';
import 'foreground.dart';

/// 桌面保持原广播频率；移动设备在后台没有广播计时器。
final class ForegroundBroadcast {
  ForegroundBroadcast(this.send,
      {required this.foregroundOnly,
      this.interval = const Duration(seconds: 30),
      this.sendInitially = true});
  final void Function() send;
  final bool foregroundOnly;
  final Duration interval;
  final bool sendInitially;
  StreamSubscription<bool>? _foreground;
  Timer? _timer;
  bool _started = false;
  void start() {
    if (_started) return;
    _started = true;
    if (foregroundOnly) {
      _foreground = NextForeground.changes.listen((_) => _schedule());
    }
    _schedule(sendNow: sendInitially);
  }

  void _schedule({bool sendNow = true}) {
    _timer?.cancel();
    _timer = null;
    if (!_started || foregroundOnly && !NextForeground.active) return;
    if (sendNow) send();
    _timer = Timer.periodic(interval, (_) => send());
  }

  Future<void> close() async {
    _started = false;
    _timer?.cancel();
    _timer = null;
    await _foreground?.cancel();
    _foreground = null;
  }
}

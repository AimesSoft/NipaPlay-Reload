import 'dart:async';

/// Passes "NipaPlay's recent facts changed" on to the runner, at most once per
/// [window]: the first change is sent at once, and changes inside the window
/// are merged into one more send when it ends.
///
/// Each send makes the runner rebuild its memory block before the next model
/// request, which appends a snapshot of several KB, so a burst of changes must
/// not become a burst of sends.
final class MemoryStaleNotifier {
  MemoryStaleNotifier(this._send,
      {this.window = const Duration(seconds: 2)});

  final void Function() _send;
  final Duration window;
  Timer? _timer;
  bool _pending = false;
  bool _closed = false;

  void changed() {
    if (_closed) return;
    if (_timer != null) {
      _pending = true;
      return;
    }
    _send();
    _timer = Timer(window, () {
      _timer = null;
      if (!_pending || _closed) return;
      _pending = false;
      changed();
    });
  }

  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
  }
}

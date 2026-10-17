import 'dart:async';

import 'package:flutter/foundation.dart';

/// Notes when the main isolate could not run for a while. Everything
/// NipaPlay answers, the agent endpoint included, waits behind it, so a
/// stall here is what Nipa sees as NipaPlay not answering.
final class LoopLag {
  Timer? _timer;

  void start() {
    if (_timer != null) return;
    final clock = Stopwatch()..start();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final late = clock.elapsed - const Duration(seconds: 1);
      clock.reset();
      if (late > const Duration(seconds: 1)) {
        debugPrint('[Next] main isolate blocked ~${late.inMilliseconds} ms');
      }
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

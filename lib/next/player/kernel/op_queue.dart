import 'dart:async';

import 'driver.dart';

/// One kernel instance's operations, one at a time in the order asked (I8),
/// none once the instance is fenced (I2). An operation in flight when the
/// fence goes up finishes its await and must look at [fenced] before it
/// touches the kernel again ([live]).
final class KernelOpQueue {
  Future<void> _tail = Future.value();
  bool _fenced = false;
  int _pending = 0;

  bool get fenced => _fenced;
  int get pending => _pending;

  /// From now on nothing queued runs.
  void fence() => _fenced = true;

  /// Throws [KernelFenced] once the instance is fenced: called after every
  /// await in an operation, before the kernel is touched again.
  void live() {
    if (_fenced) throw const KernelFenced();
  }

  Future<T> run<T>(Future<T> Function() op) {
    if (_fenced) return Future.error(const KernelFenced());
    final done = Completer<T>();
    _pending++;
    _tail = _tail.then((_) async {
      try {
        live();
        done.complete(await op());
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _pending--;
      }
    });
    return done.future;
  }
}

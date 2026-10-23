import 'dart:async';

import 'driver.dart';

/// One kernel instance's operations, one at a time in the order asked (I8),
/// none once the instance is fenced (I2). An operation in flight when the
/// fence goes up finishes its await and must look at [fenced] before it
/// touches the kernel again ([live]).
final class KernelOpQueue {
  Future<void> _tail = Future.value();
  final _alongside = <Future<void>>{};
  bool _fenced = false;
  int _pending = 0;

  bool get fenced => _fenced;
  int get pending => _pending;

  /// Completes once what is queued, and what runs alongside it, has ended.
  Future<void> get drained async {
    await _tail;
    while (_alongside.isNotEmpty) {
      await Future.wait(_alongside.toList());
    }
  }

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

  /// For a call that may take long and that the kernel runs on its own
  /// thread (an mpv command): it does not hold up the transport commands
  /// behind it, but the fence stops it from starting and [drained] waits
  /// for it.
  Future<T> alongside<T>(Future<T> Function() op) {
    if (_fenced) return Future.error(const KernelFenced());
    final done = Completer<T>();
    late final Future<void> mark;
    mark = (() async {
      try {
        done.complete(await Future.sync(op));
      } catch (error, stack) {
        done.completeError(error, stack);
      } finally {
        _alongside.remove(mark);
      }
    })();
    _alongside.add(mark);
    return done.future;
  }
}

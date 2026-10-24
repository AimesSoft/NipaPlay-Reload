import 'dart:async';
import 'package:flutter/widgets.dart';
import '../mesh/runtime.dart';
import '../player/next_playback.dart';

/// What a device that is only a body does when the system moves its
/// application behind another one, locks the screen, or brings it back.
///
/// Behind: the playback is paused (its position is saved with the pause), and
/// the other devices are told, with what was playing, before the system may
/// take the listening socket. Back in front: the listener is opened again on
/// the same port, the addresses are reported afresh and the others are told.
final class BodyLifecycle with WidgetsBindingObserver {
  BodyLifecycle(this.mesh, this.playback);
  final MeshRuntime mesh;
  final NextPlayback playback;
  bool _attached = false;
  bool _behind = false;
  Future<void> _turn = Future.value();

  void attach() {
    if (_attached) return;
    _attached = true;
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _behind = true;
    }
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      // `inactive` is the control centre, a call, the app switcher: still in
      // front for the purpose of being called.
      case AppLifecycleState.inactive:
        return;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        if (_behind) return;
        _behind = true;
        _queue(_goBehind);
      case AppLifecycleState.resumed:
        if (!_behind) return;
        _behind = false;
        _queue(mesh.enterForeground);
      case AppLifecycleState.detached:
        return;
    }
  }

  Future<void> _goBehind() async {
    if (playback.hasVideo && playback.playIntent) {
      try {
        await playback.port.setPaused(true);
      } catch (error, stack) {
        FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack, library: 'Next body lifecycle'));
      }
    }
    await mesh.enterBackground();
  }

  /// One turn at a time, in the order the system gave them.
  void _queue(Future<void> Function() turn) {
    _turn = _turn.then((_) => turn()).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(
          exception: error, stack: stack, library: 'Next body lifecycle'));
    });
  }
}

import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../system/foreground.dart';

/// A mounted page listens only while its TickerMode and app are visible.
/// Returning to it reconciles once, including changes missed while hidden.
mixin VisibleUpdates<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _lifecycle;
  StreamSubscription? _visibleSubscription;
  Stream? _updateStream;
  Future<void> Function()? _readUpdate;
  bool _tickerVisible = false, _enabled = true, _busy = false, _again = false;
  bool get updatesVisible =>
      _tickerVisible &&
      _enabled &&
      (WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onStateChange: (_) => _syncUpdates());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // HarmonyOS builds on Flutter 3.35, where this is the only form.
    // ignore: deprecated_member_use
    _tickerVisible = TickerMode.of(context);
    _syncUpdates();
  }

  void watchUpdates(Stream stream, Future<void> Function() read,
      {bool enabled = true}) {
    if (!identical(stream, _updateStream)) {
      _visibleSubscription?.cancel();
      _visibleSubscription = null;
    }
    _updateStream = stream;
    _readUpdate = read;
    _enabled = enabled;
    _syncUpdates();
  }

  void _syncUpdates() {
    if (!updatesVisible) {
      _visibleSubscription?.cancel();
      _visibleSubscription = null;
      return;
    }
    if (_visibleSubscription != null || _updateStream == null) return;
    _visibleSubscription = _updateStream!.listen((_) => _update());
    _update();
  }

  void _update() {
    _again = true;
    if (_busy) return;
    _busy = true;
    unawaited(() async {
      try {
        while (mounted && updatesVisible && _again) {
          _again = false;
          NextRefreshMetrics.record('ui.visible');
          await _readUpdate?.call();
        }
      } finally {
        _busy = false;
      }
    }());
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    _visibleSubscription?.cancel();
    super.dispose();
  }
}

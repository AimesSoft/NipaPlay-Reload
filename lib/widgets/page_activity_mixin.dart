import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Couples ordinary timers to the same page visibility used by animations,
/// plus application foreground state. It does not suspend business services.
mixin PageActivityMixin<T extends StatefulWidget> on State<T> {
  AppLifecycleListener? _activityLifecycle;
  ValueListenable<bool>? _activityTicker;
  bool _foreground = true;
  bool _pageActive = false;
  bool _activityScheduled = false;
  bool get isPageActive => _pageActive;

  @override
  void initState() {
    super.initState();
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _activityLifecycle = AppLifecycleListener(onStateChange: (state) {
      _foreground = state == AppLifecycleState.resumed;
      if (!_foreground && _pageActive) {
        _pageActive = false;
        onPageActivityChanged(false);
      } else {
        _updatePageActivity();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ticker = TickerMode.getNotifier(context);
    if (!identical(ticker, _activityTicker)) {
      _activityTicker?.removeListener(_updatePageActivity);
      _activityTicker = ticker..addListener(_updatePageActivity);
    }
    _updatePageActivity();
  }

  void _updatePageActivity() {
    // Inherited visibility may change during build. Schedule consumers safely.
    if (_activityScheduled) return;
    _activityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _activityScheduled = false;
      if (!mounted) return;
      final next = _foreground && (_activityTicker?.value ?? false);
      if (next == _pageActive) return;
      _pageActive = next;
      onPageActivityChanged(next);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void onPageActivityChanged(bool active);

  @override
  void dispose() {
    _activityTicker?.removeListener(_updatePageActivity);
    _activityLifecycle?.dispose();
    super.dispose();
  }
}

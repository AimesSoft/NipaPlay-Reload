import 'dart:async';

import 'package:flutter/widgets.dart';

typedef NipaplayRootPopRouteCallback = FutureOr<bool> Function();

/// Keeps tvOS' MENU event inside the application when there is no route left
/// for the root navigator to pop.
///
/// flutter-tvos reports both the Siri Remote MENU button and Simulator Escape
/// key as a `flutter/navigation` `popRoute` message. If every observer returns
/// false at the root route, UIKit handles the event and returns to Apple TV
/// Home. This observer gives the application a final chance to consume it.
class NipaplayTvOSPopRouteGuard extends StatefulWidget {
  const NipaplayTvOSPopRouteGuard({
    super.key,
    required this.enabled,
    required this.onRootPopRoute,
    required this.child,
  });

  final bool enabled;
  final NipaplayRootPopRouteCallback onRootPopRoute;
  final Widget child;

  @override
  State<NipaplayTvOSPopRouteGuard> createState() =>
      _NipaplayTvOSPopRouteGuardState();
}

class _NipaplayTvOSPopRouteGuardState extends State<NipaplayTvOSPopRouteGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!widget.enabled || !mounted) {
      return false;
    }

    final navigator = Navigator.maybeOf(context);
    if (navigator != null && navigator.canPop()) {
      return false;
    }

    return await widget.onRootPopRoute();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

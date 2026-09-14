import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps an Android TV menu/back press inside Flutter for its whole lifetime.
///
/// A route can disappear on key down. Its key up must still be consumed, or
/// Android can redispatch it to Activity.onBackPressed and pop another route.
/// Mount above the Navigator so the handlers survive route/focus changes.
class NipaplayAndroidTvRemoteKeyScope extends StatefulWidget {
  const NipaplayAndroidTvRemoteKeyScope({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<NipaplayAndroidTvRemoteKeyScope> createState() =>
      _NipaplayAndroidTvRemoteKeyScopeState();
}

class _NipaplayAndroidTvRemoteKeyScopeState
    extends State<NipaplayAndroidTvRemoteKeyScope> {
  bool _isPopping = false;

  bool _isBack(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.escape;

  bool _isRemoteNavigationKey(LogicalKeyboardKey key) =>
      _isBack(key) || key == LogicalKeyboardKey.contextMenu;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
    FocusManager.instance.addLateKeyEventHandler(_handleLateKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKeyEvent);
    FocusManager.instance.removeLateKeyEventHandler(_handleLateKeyEvent);
    super.dispose();
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (_isRemoteNavigationKey(event.logicalKey) &&
        (event is KeyUpEvent || event is KeyRepeatEvent || event.synthesized)) {
      return KeyEventResult.handled;
    }
    // Let the focused dialog/panel handle the initial press first.
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleLateKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent || !_isRemoteNavigationKey(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    if (_isBack(event.logicalKey) && !_isPopping) {
      unawaited(_popRoute());
    }
    return KeyEventResult.handled;
  }

  Future<void> _popRoute() async {
    _isPopping = true;
    try {
      final navigator = widget.navigatorKey.currentState;
      if (navigator != null && !await navigator.maybePop() && mounted) {
        await SystemNavigator.pop();
      }
    } finally {
      _isPopping = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

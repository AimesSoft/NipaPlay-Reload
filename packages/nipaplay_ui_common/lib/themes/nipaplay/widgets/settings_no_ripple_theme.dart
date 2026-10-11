import 'package:flutter/material.dart';

class SettingsVisualScope extends InheritedWidget {
  final bool disableBlurEffect;

  const SettingsVisualScope({
    super.key,
    required this.disableBlurEffect,
    required super.child,
  });

  static bool isBlurDisabled(BuildContext context, {bool listen = true}) {
    if (listen) {
      return context
              .dependOnInheritedWidgetOfExactType<SettingsVisualScope>()
              ?.disableBlurEffect ??
          false;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<SettingsVisualScope>();
    final widget = element?.widget;
    if (widget is SettingsVisualScope) {
      return widget.disableBlurEffect;
    }
    return false;
  }

  @override
  bool updateShouldNotify(SettingsVisualScope oldWidget) {
    return disableBlurEffect != oldWidget.disableBlurEffect;
  }
}

class SettingsNoRippleTheme extends StatelessWidget {
  final Widget child;
  final bool disableBlurEffect;

  const SettingsNoRippleTheme({
    super.key,
    required this.child,
    this.disableBlurEffect = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SettingsVisualScope(
      disableBlurEffect: disableBlurEffect,
      child: Theme(
        data: theme.copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}

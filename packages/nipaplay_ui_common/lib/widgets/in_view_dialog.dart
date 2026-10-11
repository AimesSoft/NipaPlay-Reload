import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Shows a Material dialog without letting Flutter Windowing promote it to a
/// separate native window on Windows.
Future<T?> showInViewDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  String? barrierLabel,
  bool useSafeArea = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  bool? requestFocus,
}) {
  // Flutter's experimental desktop windowing promotes showDialog to a
  // separate native view. Keep these dialogs in the current Flutter view so
  // they inherit the existing window metrics and navigator lifecycle.
  final useInViewRoute = defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;
  if (kIsWeb || !useInViewRoute) {
    return showDialog<T>(
      context: context,
      builder: builder,
      barrierDismissible: barrierDismissible,
      barrierColor: barrierColor,
      barrierLabel: barrierLabel,
      useSafeArea: useSafeArea,
      useRootNavigator: useRootNavigator,
      routeSettings: routeSettings,
      anchorPoint: anchorPoint,
      requestFocus: requestFocus,
    );
  }

  final navigator = Navigator.of(
    context,
    rootNavigator: useRootNavigator,
  );
  final themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  final textDirection = Directionality.of(context);
  final themeData = Theme.of(context);
  final mediaQueryData = MediaQuery.of(context);
  final resolvedBarrierColor = barrierColor ??
      DialogTheme.of(context).barrierColor ??
      Theme.of(context).dialogTheme.barrierColor ??
      Colors.black54;
  final resolvedBarrierLabel = barrierLabel ??
      MaterialLocalizations.of(context).modalBarrierDismissLabel;

  return navigator.push<T>(
    RawDialogRoute<T>(
      settings: routeSettings,
      requestFocus: requestFocus,
      anchorPoint: anchorPoint,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
      transitionDuration: const Duration(milliseconds: 150),
      barrierDismissible: barrierDismissible,
      barrierColor: resolvedBarrierColor,
      barrierLabel: resolvedBarrierLabel,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        Widget dialog = themes.wrap(Builder(builder: builder));
        if (useSafeArea) {
          dialog = SafeArea(child: dialog);
        }
        return Directionality(
          textDirection: textDirection,
          child: Theme(
            data: themeData,
            child: MediaQuery(
              data: mediaQueryData,
              child: dialog,
            ),
          ),
        );
      },
    ),
  );
}

import 'package:flutter/widgets.dart';

/// Horizontal size class of the window the phone shell lays out in.
///
/// The iPhone Duo inner display reports a regular width. Apple's guidelines
/// ask apps to use that space for a second column of the same content instead
/// of stretching the compact layout. Defaults to compact.
class AppSizeClassScope extends InheritedWidget {
  const AppSizeClassScope({
    super.key,
    required this.isRegularWidth,
    required super.child,
  });

  final bool isRegularWidth;

  static bool isRegularWidthOf(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<AppSizeClassScope>()
            ?.isRegularWidth ??
        false;
  }

  @override
  bool updateShouldNotify(AppSizeClassScope oldWidget) {
    return isRegularWidth != oldWidget.isRegularWidth;
  }
}

/// Lays out [children] two per row, top-aligned, as the regular-width form of
/// a single stacked column. An odd last child keeps the left column.
List<Widget> buildTwoColumnRows(
  List<Widget> children, {
  double columnSpacing = 0,
}) {
  return [
    for (var index = 0; index < children.length; index += 2)
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: children[index]),
          SizedBox(width: columnSpacing),
          Expanded(
            child: index + 1 < children.length
                ? children[index + 1]
                : const SizedBox.shrink(),
          ),
        ],
      ),
  ];
}

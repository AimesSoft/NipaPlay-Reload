import 'package:flutter/widgets.dart';

class AppNavigationScope extends InheritedWidget {
  const AppNavigationScope({
    super.key,
    required this.selectedPageId,
    required this.pageIds,
    required this.onSelectPage,
    required super.child,
  });

  final String selectedPageId;
  final List<String> pageIds;
  final ValueChanged<String> onSelectPage;

  static AppNavigationScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AppNavigationScope>();
  }

  static AppNavigationScope of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No AppNavigationScope found in context.');
    return scope!;
  }

  @override
  bool updateShouldNotify(AppNavigationScope oldWidget) {
    return selectedPageId != oldWidget.selectedPageId ||
        pageIds != oldWidget.pageIds ||
        onSelectPage != oldWidget.onSelectPage;
  }
}

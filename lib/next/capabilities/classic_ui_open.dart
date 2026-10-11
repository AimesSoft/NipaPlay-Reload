import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// Observes the existing visible Classic widgets after dispatching navigation.
final class ClassicUiOpen {
  Element? _findElement<T extends Widget>(bool Function(T) matches,
      {Element? root}) {
    Element? found;
    void visit(Element element) {
      if (found != null) return;
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is T && matches(widget)) found = element;
      element.visitChildren(visit);
    }

    (root ?? WidgetsBinding.instance.rootElement)?.visitChildren(visit);
    return found;
  }

  T? _find<T extends Widget>(bool Function(T) matches) =>
      _findElement(matches)?.widget as T?;

  Future<bool> page(String page) async {
    final scope =
        _find<AppNavigationScope>((scope) => scope.pageIds.contains(page));
    if (scope == null) return false;
    AnimeDetailPage.popIfOpen();
    scope.onSelectPage(page);
    final controller = _find<CustomScaffold>(
        (widget) => widget.pageIsHome && widget.pageIds.contains(page))?.tabController;
    if (controller != null && controller.indexIsChanging) {
      final settled = Completer<bool>();
      void observe() {
        if (!controller.indexIsChanging && !settled.isCompleted) settled.complete(true);
      }
      controller.addListener(observe);
      try {
        if (!await settled.future.timeout(const Duration(seconds: 2),
            onTimeout: () => false)) {
          return false;
        }
      } finally {
        controller.removeListener(observe);
      }
    }
    await WidgetsBinding.instance.endOfFrame;
    final scaffold = _findElement<CustomScaffold>(
        (widget) => widget.pageIsHome && widget.pageIds.contains(page));
    if (scaffold != null) {
      final targetIndex = (scaffold.widget as CustomScaffold).pageIds.indexOf(page);
      // The ancestor scope can retain its old selectedPageId while the
      // scaffold rebuilds from its TabController. Observe the rendered body.
      final body = _findElement<SwitchableView>((_) => true, root: scaffold);
      return (body?.widget as SwitchableView?)?.currentIndex == targetIndex;
    }
    return _find<AppNavigationScope>((scope) => scope.selectedPageId == page) !=
        null;
  }

  Future<bool> detail(int animeId) async {
    final context = globals.navigatorKey.currentState?.overlay?.context;
    if (context == null) return false;
    AnimeDetailPage.popIfOpen();
    unawaited(ThemedAnimeDetail.show(context, animeId));
    await WidgetsBinding.instance.endOfFrame;
    return _find<AnimeDetailPage>((page) => page.animeId == animeId) != null;
  }
}

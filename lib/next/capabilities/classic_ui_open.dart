import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// Observes the existing visible Classic widgets after dispatching navigation.
final class ClassicUiOpen {
  T? _find<T extends Widget>(bool Function(T) matches) {
    T? found;
    void visit(Element element) {
      final widget = element.widget;
      if (widget is Offstage && widget.offstage) return;
      if (widget is T && matches(widget)) found = widget;
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return found;
  }

  Future<bool> page(String page) async {
    final scope =
        _find<AppNavigationScope>((scope) => scope.pageIds.contains(page));
    if (scope == null) return false;
    AnimeDetailPage.popIfOpen();
    scope.onSelectPage(page);
    await WidgetsBinding.instance.endOfFrame;
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

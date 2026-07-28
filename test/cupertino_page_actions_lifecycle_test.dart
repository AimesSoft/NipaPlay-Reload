import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/downloads/unified_torrent_page_model.dart';
import 'package:nipaplay/pages/torrent_download_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_page_actions_scope.dart';

void main() {
  testWidgets('torrent page clears actions after the tree is unlocked',
      (tester) async {
    final actionsController = CupertinoPageActionsController();
    final searchController = TextEditingController();
    addTearDown(actionsController.dispose);
    addTearDown(searchController.dispose);

    final data = UnifiedTorrentPageViewModel(
      isLoading: true,
      isBusy: false,
      tasks: const [],
      visibleTasks: const [],
      searchController: searchController,
      sort: UnifiedTorrentTaskSort.latest,
      viewMode: UnifiedTorrentTaskViewMode.cards,
      onSearchChanged: (_) {},
      onClearSearch: () {},
      onSortChanged: (_) {},
      onToggleViewMode: () {},
      onRefresh: () {},
      onAddMagnet: () {},
      onPickTorrent: () {},
    );

    Widget buildApp(Widget child) {
      return MaterialApp(
        home: CupertinoPageActionsScope(
          controller: actionsController,
          child: child,
        ),
      );
    }

    await tester.pumpWidget(
      buildApp(CupertinoTorrentDownloadView(data: data)),
    );
    await tester.pump();
    expect(actionsController.actions, hasLength(1));

    await tester.pumpWidget(buildApp(const SizedBox()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(actionsController.actions, isEmpty);
  });
}

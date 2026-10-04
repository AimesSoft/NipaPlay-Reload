import 'package:flutter/material.dart' show Material;
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/search/tag_search_controller.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_tag_search_view.dart';

void main() {
  testWidgets(
      '1000 loaded tag results mount only viewport rows and remain reachable',
      (tester) async {
    final controller = TagSearchController()..mode = TagSearchMode.text;
    controller.displayedTextResults = List.generate(
        1000,
        (i) => SearchResultAnime(
            animeId: i,
            animeTitle: 'Result $i',
            type: 'TV',
            episodeCount: 12,
            rating: 8,
            isFavorited: false));
    controller.textSearchResults = controller.displayedTextResults;
    int? selected;
    await tester.pumpWidget(CupertinoApp(
        home: Material(
            child: CupertinoTagSearchView(
      controller: controller,
      onOpenAnimeDetail: (id) => selected = id,
      onMessage: (_) {},
    ))));
    await tester.pump();
    expect(find.text('Result 999'), findsNothing);
    final scroll =
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    // Move progressively; lazy slivers refine their extent estimate as they lay out.
    for (var i = 0; i < 5; i++) {
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();
    }
    expect(find.text('Result 999'), findsOneWidget);
    expect(
        find
            .byWidgetPredicate(
                (w) => w is Text && (w.data?.startsWith('Result ') ?? false))
            .evaluate()
            .length,
        lessThan(30));
    await tester.tap(find.text('Result 999'));
    expect(selected, 999);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
}

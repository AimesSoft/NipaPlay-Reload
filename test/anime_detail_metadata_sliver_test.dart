import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/quarterly_review_cache.dart';
import 'package:nipaplay/themes/nipaplay/widgets/anime_detail_metadata_sliver.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_comments_widget.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('legacy detail keeps comments mounted when switching tabs',
      (tester) async {
    final anime = BangumiAnime(
      id: 0,
      name: 'Test title',
      nameCn: 'Test title',
      imageUrl: '',
      summary: 'Summary',
      tags: ['tag'],
      language: 'zh',
      metadata: List.generate(1000, (i) => 'Credit $i: Person $i'),
      titles: [
        {'title': 'Last title'}
      ],
    );
    SharedPreferences.setMockInitialValues({
      'bangumi_detail_0': jsonEncode({
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'animeDetail': anime.toJson(),
      }),
    });
    final appearance = _TestAppearance();
    await tester
        .pumpWidget(ChangeNotifierProvider<AppearanceSettingsProvider>.value(
      value: appearance,
      child: AppDisplaySurfaceScope(
        surface: AppDisplaySurface.phone,
        child: MaterialApp(
          home: Scaffold(
              body: AnimeDetailPage(
            animeId: 0,
            renderInWindowScaffold: false,
            sharedSummary: SharedRemoteAnimeSummary(
              animeId: 0,
              name: 'Test title',
              nameCn: 'Test title',
              summary: 'Summary',
              imageUrl: '',
              lastWatchTime: DateTime(2026),
              episodeCount: 0,
              hasMissingFiles: false,
            ),
          )),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(AnimeDetailMetadataSliver), findsOneWidget);
    expect(find.text('Last title'), findsNothing);
    expect(find.byType(BangumiCommentsWidget), findsNothing);
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    final comments = tester.state(find.byType(BangumiCommentsWidget));
    await tester.tap(find.text('详情'));
    await tester.pumpAndSettle();
    expect(
        tester.state(find.byType(BangumiCommentsWidget, skipOffstage: false)),
        same(comments));
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(BangumiCommentsWidget)), same(comments));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    QuarterlyReviewCache.instance.dispose();
    appearance.dispose();
  });

  testWidgets('long credits build by viewport and retain the final titles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverMainAxisGroup(slivers: [
                const SliverToBoxAdapter(child: SizedBox(height: 200)),
                AnimeDetailMetadataSliver(
                  metadata: List.generate(1000, (i) => 'Credit $i: Person $i'),
                  titles: List.generate(50, (i) => {'title': 'Title $i'}),
                  valueStyle: const TextStyle(fontSize: 13),
                  keyStyle: const TextStyle(fontWeight: FontWeight.w600),
                  sectionTitleStyle: const TextStyle(fontSize: 16),
                  secondaryTextColor: Colors.grey,
                ),
                const SliverToBoxAdapter(child: Text('Tags footer')),
              ]),
            ),
          ],
        ),
      ),
    ));
    expect(find.text('制作信息:'), findsOneWidget);
    expect(find.text('Title 49'), findsNothing);
    // Counts rendered text objects, not a source-code or delegate assertion.
    expect(find.byType(RichText).evaluate().length, lessThan(100));
    await tester.scrollUntilVisible(find.text('Title 49'), 500,
        maxScrolls: 100);
    expect(find.text('Title 49'), findsOneWidget);
    expect(find.byType(RichText).evaluate().length, lessThan(100));
    await tester.scrollUntilVisible(find.text('Tags footer'), 300);
    expect(find.text('Tags footer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('metadata formatting, alias filtering and languages survive',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: CustomScrollView(slivers: [
        AnimeDetailMetadataSliver(
          metadata: [
            'Director：Person',
            'Site: https://example.com',
            ' 别名:skip'
          ],
          titles: [
            {'title': 'Title', 'language': 'en'},
            {},
          ],
          valueStyle: TextStyle(fontSize: 13),
          keyStyle: TextStyle(fontWeight: FontWeight.w600),
          sectionTitleStyle: TextStyle(fontSize: 16),
          secondaryTextColor: Colors.grey,
        ),
      ]),
    ));
    expect(find.text('Director: Person', findRichText: true), findsOneWidget);
    expect(find.text('Site: https://example.com'), findsOneWidget);
    expect(find.textContaining('skip', findRichText: true), findsNothing);
    expect(find.text('Title (en)'), findsOneWidget);
    expect(find.text('未知标题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestAppearance extends ChangeNotifier
    implements AppearanceSettingsProvider {
  @override
  AnimeCardAction get animeCardAction => AnimeCardAction.synopsis;

  @override
  bool get enablePageAnimation => false;

  @override
  bool get enableWidgetBlurEffect => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

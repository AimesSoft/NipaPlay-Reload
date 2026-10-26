import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/detail/detail_page.dart';
import 'package:nipaplay/next/ui/widgets/cards.dart';
import 'package:nipaplay/next/ui/widgets/words.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'found_cards_support.dart';

/// Works the agent presented from outside the library: the cards look like
/// the library's, and open the found page that offers “让 Nipa 准备”.
const changan = UiWork(
  workId: 'found:tmdb:tv:1001',
  title: '长安十二时辰',
  year: 2019,
  episodeCount: 48,
  ratings: [UiRating('TMDB', 8.6)],
  artwork: UiArtwork(tint: 0xff884422),
);
const makeine = UiWork(
  workId: 'found:bangumi:3003',
  title: '败犬女主太多了！',
  year: 2024,
  episodeCount: 12,
  artwork: UiArtwork(tint: 0xff448822),
);
const frieren = UiWork(
  workId: 'w1',
  title: '葬送的芙莉莲',
  year: 2023,
  next: UiEpisode(episodeId: 'e1', workId: 'w1', number: 1, playable: true),
);

void main() {
  testWidgets(
      'found works in cards look like library ones and open their found page',
      (tester) async {
    final discover = FoundDetails({
      changan.workId: {
        'overview': '长安城的一天，十二个时辰。',
        'originalTitle': "The Longest Day in Chang'an",
      }
    });
    final played = <UiWork>[];
    final shell = await pumpFoundCards(
      tester,
      cards: const [
        UiWorkCard(changan),
        UiCandidatesCard([
          UiCandidate(makeine, reason: '轻松，一集二十分钟'),
          UiCandidate(frieren),
        ]),
      ],
      discover: discover,
      onPlay: played.add,
    );
    await tester.pump(const Duration(seconds: 1));

    // The same rows and posters as library works: title, one meta line.
    expect(find.text('长安十二时辰'), findsOneWidget);
    expect(
        find.byWidgetPredicate(
            (w) => w is NumText && w.text == '★ 8.6 · 2019 · 48 集'),
        findsOneWidget);
    expect(find.text('败犬女主太多了！'), findsOneWidget);
    expect(find.text('轻松，一集二十分钟'), findsOneWidget);
    // No words about where they come from.
    for (final word in ['TMDB', 'Bangumi', '媒体库', '1001', '3003']) {
      expect(find.textContaining(word, findRichText: true), findsNothing);
    }
    // Only what the library can play offers to play.
    final posters = tester.widgetList<PosterCard>(find.byType(PosterCard));
    expect([for (final p in posters) p.onPlay != null], [false, true]);

    // Opening the found work: its found page, with what its provider adds.
    await tester.tap(find.text('长安十二时辰'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final page = tester.widget<WorkDetailPage>(find.byType(WorkDetailPage));
    expect(page.work.workId, 'found:tmdb:tv:1001');
    expect(discover.asked, ['found:tmdb:tv:1001']);
    expect(find.text('让梨花准备'), findsOneWidget);
    expect(find.textContaining('长安城的一天'), findsOneWidget);
    expect(played, isEmpty);

    // Back, and the found candidate opens the same kind of page.
    Navigator.of(tester.element(find.byType(WorkDetailPage))).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byType(PosterCard).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<WorkDetailPage>(find.byType(WorkDetailPage)).work,
        same(makeine));
    expect(find.text('让梨花准备'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    shell.dispose();
  });
}

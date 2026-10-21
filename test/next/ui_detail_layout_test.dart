import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/detail/detail_page.dart';
import 'package:nipaplay/next/ui/detail/docking_title.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/work_title.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'found_cards_support.dart';

/// A work's page keeps its words in one column: however many lines the
/// title takes, the meta line, the overview and the buttons start below it,
/// on a work found outside the library and on one in it. A length nobody
/// knows is not said.
const _overview = '佐佐木在宠物店买到的，是从异世界转生而来，大名鼎鼎的贤者大人。'
    '「吾名毕耶尔卡洛，乃异界之徒兼星之贤者。」但还是文鸟。佐佐木替这只文鸟取名为小哔。';

const _titles = {
  'one line': '文鸟小哔',
  'two lines': '佐佐木与文鸟小哔 第二季',
  'longer': '佐佐木与文鸟小哔 第二季 ～在异世界当贤者的文鸟与社畜的悠闲日常～',
};

final class _Library implements NextUiData {
  _Library(this.works, this.seasons);
  final Map<String, UiWork> works;
  final Map<String, List<UiEpisode>> seasons;
  @override
  Future<UiWork?> work(String workId) async => works[workId];
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      seasons[workId] ?? const [];
  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<UiWork>> library() async => works.values.toList();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}

/// Opens [work]'s page from a card, as a viewer would. Close with
/// [_close].
Future<NextShellController> _open(WidgetTester tester, UiWork work,
    {NextUiData? data, Map<String, Object?> record = const {}}) async {
  final shell = await pumpFoundCards(tester,
      cards: [UiWorkCard(work)],
      discover: FoundDetails({work.workId: record}),
      data: data);
  await tester.pump(const Duration(seconds: 1));
  await tester.tap(find.text(work.title));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  expect(find.byType(WorkDetailPage), findsOneWidget);
  return shell;
}

/// The title where it is drawn, and what follows it in the column.
void _expectClear(WidgetTester tester, String label) {
  final title = tester.getRect(find.descendant(
      of: find.byType(DockingTitle), matching: find.byType(WorkTitle)));
  final overview = tester.getRect(find.byType(Overview));
  final buttons = tester.getRect(find.byType(NextButton).first);
  expect(title.height, greaterThan(0), reason: label);
  expect(title.overlaps(overview), isFalse,
      reason: '$label: title $title, overview $overview');
  expect(title.bottom, lessThanOrEqualTo(overview.top), reason: label);
  expect(overview.bottom, lessThanOrEqualTo(buttons.top), reason: label);
}

Future<void> _close(WidgetTester tester, NextShellController shell) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  shell.dispose();
}

void main() {
  for (final MapEntry(key: label, value: title) in _titles.entries) {
    testWidgets('a found work: a title of $label stays above its overview',
        (tester) async {
      final work = UiWork(
          workId: 'found:dandanplay:19003',
          title: title,
          year: 2026,
          episodeCount: 12,
          artwork: const UiArtwork(tint: 0xff446688));
      final shell =
          await _open(tester, work, record: {'overview': _overview});
      expect(find.text('让 Nipa 准备'), findsOneWidget);
      _expectClear(tester, label);
      await _close(tester, shell);
    });

    testWidgets('a library work: a title of $label stays above its overview',
        (tester) async {
      final work = UiWork(
          workId: 'w-buncho',
          title: title,
          year: 2026,
          overview: _overview,
          artwork: const UiArtwork(tint: 0xff446688),
          next: const UiEpisode(
              episodeId: 'e2', workId: 'w-buncho', number: 2, playable: true));
      final shell = await _open(tester, work,
          data: _Library({work.workId: work}, {
            work.workId: const [
              UiEpisode(episodeId: 'e1', workId: 'w-buncho', number: 1),
              UiEpisode(
                  episodeId: 'e2',
                  workId: 'w-buncho',
                  number: 2,
                  runtime: Duration(minutes: 23, seconds: 50),
                  playable: true),
            ]
          }));
      _expectClear(tester, label);
      await _close(tester, shell);
    });
  }

  testWidgets('an episode whose length is not known says none', (tester) async {
    const work = UiWork(
        workId: 'w-smoke',
        title: '躲在超市后门抽烟的两人',
        overview: _overview,
        artwork: UiArtwork(tint: 0xfffdfdfd),
        next: UiEpisode(
            episodeId: 'e2', workId: 'w-smoke', number: 2, playable: true));
    final shell = await _open(tester, work,
        data: _Library({work.workId: work}, {
          work.workId: const [
            // No file any more, and no length.
            UiEpisode(episodeId: 'e1', workId: 'w-smoke', number: 1),
            UiEpisode(
                episodeId: 'e2',
                workId: 'w-smoke',
                number: 2,
                runtime: Duration(minutes: 23, seconds: 50),
                playable: true),
            // On disk, never played: a length of nothing.
            UiEpisode(
                episodeId: 'e4',
                workId: 'w-smoke',
                number: 4,
                runtime: Duration.zero,
                playable: true),
            UiEpisode(
                episodeId: 'e5',
                workId: 'w-smoke',
                number: 5,
                runtime: Duration(seconds: 40),
                playable: true),
          ]
        }));
    expect(find.text('0 分', skipOffstage: false), findsNothing);
    expect(find.text('23 分', skipOffstage: false), findsOneWidget);
    expect(find.text('1 分', skipOffstage: false), findsOneWidget,
        reason: 'under a minute, but known');
    await _close(tester, shell);
  });
}

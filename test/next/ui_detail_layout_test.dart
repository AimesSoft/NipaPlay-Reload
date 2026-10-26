import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/detail_page.dart';
import 'package:nipaplay/next/ui/detail/docking_title.dart';
import 'package:nipaplay/next/ui/detail/episodes.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/words.dart';
import 'package:nipaplay/next/ui/widgets/work_title.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'found_cards_support.dart';

/// A work's page keeps its words in one column: however many lines the
/// title takes, the meta line, the overview and the buttons start below it,
/// on a work found outside the library and on one in it. A length nobody
/// knows is not said. A film says its length instead of its episodes, and
/// its page has no row of them.
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

/// Plays what it is asked to; nothing else is asked of it here.
final class _Plays implements NextUiActions {
  final played = <String?>[];
  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async =>
      played.add(episode?.episodeId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Managing is offered; no sheet opens here.
final class _Manage implements NextWorkManage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Opens [work]'s page from a card, as a viewer would. Close with
/// [_close].
Future<NextShellController> _open(WidgetTester tester, UiWork work,
    {NextUiData? data,
    NextUiActions? actions,
    NextWorkManage? manage,
    Map<String, Object?> record = const {}}) async {
  final shell = await pumpFoundCards(tester,
      cards: [UiWorkCard(work)],
      discover: FoundDetails({work.workId: record}),
      data: data,
      actions: actions,
      manage: manage);
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
      expect(find.text('让梨花准备'), findsOneWidget);
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

  group('a film', () {
    const episode = UiEpisode(
        episodeId: 'e-sintel',
        workId: 'w-sintel',
        number: 1,
        season: 1,
        runtime: Duration(minutes: 92),
        playable: true);
    UiWork sintel(
            {String workId = 'w-sintel',
            bool film = true,
            UiEpisode? next = episode,
            Duration? runtime = const Duration(minutes: 92)}) =>
        UiWork(
            workId: workId,
            title: '寻龙记',
            year: 2010,
            episodeCount: 1,
            film: film,
            runtime: runtime,
            ratings: const [UiRating('TMDB', 7.3)],
            overview: _overview,
            artwork: const UiArtwork(tint: 0xff3a4a3a),
            next: next);
    WorkDetailDebug page(WidgetTester tester) =>
        tester.state(find.byType(WorkDetailPage)) as WorkDetailDebug;
    Finder inMeta(Finder finder) =>
        find.descendant(of: find.byType(MetaLine), matching: finder);

    test('its length in words', () {
      expect(Words.length(const Duration(minutes: 92)), '1 小时 32 分');
      expect(Words.length(const Duration(minutes: 52)), '52 分钟');
      expect(Words.length(const Duration(hours: 2)), '2 小时');
      expect(Words.length(const Duration(minutes: 59, seconds: 40)), '1 小时');
      expect(Words.length(const Duration(seconds: 40)), '1 分钟');
      expect(Words.length(Duration.zero), isNull);
      expect(Words.length(null), isNull);
      // The hero plays a film without an episode's number.
      expect(Words.play(sintel()), '播放');
      expect(Words.play(sintel(film: false)), '播放 第 1 集');
    });

    testWidgets('its card says its length, never episodes', (tester) async {
      final shell = await pumpFoundCards(tester,
          cards: [
            UiWorkCard(sintel()),
            UiWorkCard(sintel(workId: 'w-unknown-length', runtime: null)),
            UiWorkCard(sintel(workId: 'w-unknown-kind', film: false)),
          ],
          discover: FoundDetails());
      await tester.pump(const Duration(seconds: 1));
      Finder meta(String text) =>
          find.byWidgetPredicate((w) => w is NumText && w.text == text);
      expect(meta('★ 7.3 · 2010 · 1 小时 32 分'), findsOneWidget);
      // Nobody knows its length: nothing is said in its place.
      expect(meta('★ 7.3 · 2010'), findsOneWidget);
      // Not known as a film: as before.
      expect(meta('★ 7.3 · 2010 · 1 集'), findsOneWidget);
      await _close(tester, shell);
    });

    testWidgets('its page has no row of episodes, and 播放 plays it',
        (tester) async {
      final plays = _Plays();
      final work = sintel();
      final shell = await _open(tester, work,
          data: _Library({work.workId: work}, {
            work.workId: const [episode]
          }),
          actions: plays,
          manage: _Manage());
      expect(find.byType(EpisodeRow), findsNothing);
      expect(find.byType(SeasonHeader), findsNothing);
      expect(inMeta(find.text('1 小时 32 分')), findsOneWidget);
      expect(inMeta(find.textContaining('集')), findsNothing);
      expect(tester.widget<PlayButton>(find.byType(PlayButton)).label, '播放');
      await tester.tap(find.byType(PlayButton));
      await tester.pump();
      expect(plays.played, ['e-sintel']);
      // Its one episode's sheets, which no tile offers, are in ⋯.
      expect(page(tester).debugStatus()['menuItems'], [
        '看过了',
        '弹幕…',
        '字幕…',
        '文件…',
        '匹配作品…',
        '编辑资料…',
        '剧集与文件…',
      ]);
      await _close(tester, shell);
    });

    testWidgets('seen to the end it plays again; half seen it goes on',
        (tester) async {
      final plays = _Plays();
      const seen = UiEpisode(
          episodeId: 'e-sintel',
          workId: 'w-sintel',
          number: 1,
          season: 1,
          progress: 1,
          playable: true);
      var work = sintel(next: null);
      var shell = await _open(tester, work,
          data: _Library({work.workId: work}, {
            work.workId: const [seen]
          }),
          actions: plays);
      expect(tester.widget<PlayButton>(find.byType(PlayButton)).label, '播放');
      await tester.tap(find.byType(PlayButton));
      await tester.pump();
      expect(plays.played, ['e-sintel']);
      expect(page(tester).debugStatus()['menuItems'], ['标成没看过']);
      await _close(tester, shell);

      const half = UiEpisode(
          episodeId: 'e-sintel',
          workId: 'w-sintel',
          number: 1,
          season: 1,
          progress: 0.4,
          playable: true);
      work = sintel(next: half);
      shell = await _open(tester, work,
          data: _Library({work.workId: work}, {
            work.workId: const [half]
          }),
          actions: plays);
      expect(
          tester.widget<PlayButton>(find.byType(PlayButton)).label, '继续播放');
      await _close(tester, shell);
    });

    testWidgets('one nobody knows as a film keeps its season and episodes',
        (tester) async {
      final work = sintel(film: false);
      final shell = await _open(tester, work,
          data: _Library({work.workId: work}, {
            work.workId: const [episode]
          }),
          manage: _Manage());
      expect(find.byType(EpisodeRow), findsOneWidget);
      expect(find.byType(SeasonHeader), findsOneWidget);
      expect(inMeta(find.text(' 集')), findsOneWidget);
      expect(inMeta(find.text('1 小时 32 分')), findsNothing);
      expect(tester.widget<PlayButton>(find.byType(PlayButton)).label, '播放');
      expect(page(tester).debugStatus()['menuItems'],
          ['第 1 集看过了', '匹配作品…', '编辑资料…', '剧集与文件…']);
      await _close(tester, shell);
    });
  });
}

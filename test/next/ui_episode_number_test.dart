import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show Material, MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' show ObjectSchema, TaskEngine;
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/next/ui/cards/card_views.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/detail/detail_page.dart';
import 'package:nipaplay/next/ui/detail/episodes.dart';
import 'package:nipaplay/next/ui/player/player_menus.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/words.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'found_cards_support.dart';
import 'media_test_support.dart';

/// An episode's number is the one stored for it, or none: never read out
/// of its title, never 0. One without a number shows no number anywhere,
/// and follows the numbered ones of its season in the order it came.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the library', () {
    late Directory root;
    late SqliteJobStore store;
    late TaskEngine engine;
    late UiDataService service;
    setUp(() async {
      sqfliteFfiInit();
      root = await Directory.systemTemp.createTemp('episode-number-');
      store = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
      engine =
          TaskEngine(store: store, ownerDeviceId: 'fixture', executors: []);
      await engine.start();
      final media = MediaService(
          store: IdentityStore(store.database, 'fixture'),
          providers: [],
          classic: MemoryClassic(),
          authorizedRoots: () => [root.path]);
      service = UiDataService(
          media,
          engine,
          StateCapability([
            StateView(
                name: 'library.files',
                description: 'fixture',
                fields: const ObjectSchema({}),
                read: (offset, limit) async => [])
          ]),
          StateSources(),
          root,
          MemoryVault());
      Future<void> entity(String id, String kind, String? parent, Map attrs) =>
          store.database.insert('media_entities', {
            'id': id,
            'kind': kind,
            'parent_id': parent,
            'attributes': jsonEncode(attrs)
          });
      await entity('w1', 'work', null, {'title': '葬送的芙莉莲', 'localOnly': true});
      await entity('r1', 'release', 'w1', {'season': 1});
      await entity('r2', 'release', 'w1', {'season': 2});
      // Created in this order; the ids sort otherwise.
      await entity('ep-z', 'episode', 'r1', {'title': '第3话 小芙莉莲'});
      await entity('ep-2', 'episode', 'r1', {'number': '2', 'title': '不错的魔法'});
      await entity('ep-s2', 'episode', 'r2', {'number': '1', 'title': '旅途'});
      await entity('ep-a', 'episode', 'r1', {'title': '总集篇'});
      await entity('ep-1', 'episode', 'r1', {'number': '1', 'title': '冒险的结束'});
    });
    tearDown(() async {
      await service.close();
      await engine.close();
      await root.delete(recursive: true);
    });

    test('numbers only what is stored, and puts the rest after', () async {
      final episodes = await service.episodes('w1');
      expect([for (final e in episodes) (e.episodeId, e.season, e.number)], [
        ('ep-1', 1, 1),
        ('ep-2', 1, 2),
        ('ep-z', 1, null),
        ('ep-a', 1, null),
        ('ep-s2', 2, 1),
      ]);
      expect(episodes[2].title, '第3话 小芙莉莲');
      final second = await service.episodes('w1', season: 2);
      expect(second.map((e) => e.episodeId), ['ep-s2']);
    });
  });

  group('sortEpisodes', () {
    UiEpisode e(String id, int? number, {int? season}) =>
        UiEpisode(episodeId: id, workId: 'w', number: number, season: season);
    List<String> ids(List<UiEpisode> list) =>
        [for (final e in list) e.episodeId];

    test('by season, then number; unnumbered after, as they came', () {
      final list = [
        e('x', null, season: 1),
        e('s2', 1, season: 2),
        e('b', 2, season: 1),
        e('y', null, season: 1),
        e('a', 1, season: 1),
        e('w', null, season: 1),
        e('none', null),
      ];
      sortEpisodes(list);
      expect(ids(list), ['none', 'a', 'b', 'x', 'y', 'w', 's2']);
    });

    test('an episode without a season counts as the one asked', () {
      final list = [e('s2', 1, season: 2), e('n', 3), e('s1', 1, season: 1)];
      sortEpisodes(list, seasonless: 1);
      expect(ids(list), ['s1', 'n', 's2']);
    });

    test('the same number keeps the order it came in', () {
      final list = [e('later', 1), e('two', 2), e('first', 1)];
      sortEpisodes(list);
      expect(ids(list), ['later', 'first', 'two']);
    });
  });

  test('words say no number for an episode without one', () {
    expect(Words.episode(3), '第 3 集');
    expect(Words.episode(null), isNull);
    const unnumbered = UiEpisode(
        episodeId: 'e', workId: 'w', number: null, title: '第3话 小芙莉莲');
    expect(
        Words.play(
            const UiWork(workId: 'w', title: '芙莉莲', next: unnumbered)),
        '播放');
    expect(
        Words.play(const UiWork(
            workId: 'w',
            title: '芙莉莲',
            next: UiEpisode(episodeId: 'e', workId: 'w', number: 5))),
        '播放 第 5 集');
  });

  group('on screen', () {
    const work = UiWork(workId: 'w', title: '葬送的芙莉莲');
    const unnumbered = UiEpisode(
        episodeId: 'e-z',
        workId: 'w',
        number: null,
        title: '第3话 小芙莉莲',
        playable: true);
    const numbered = UiEpisode(
        episodeId: 'e-5',
        workId: 'w',
        number: 5,
        title: '死者的幻影',
        playable: true);

    /// No number of its own, nor one read out of its title.
    void expectNoNumber() {
      for (final text in ['0', '00', '3', '03']) {
        expect(find.text(text), findsNothing, reason: text);
      }
      for (final text in ['第 0 集', '第 3 集']) {
        expect(find.textContaining(text), findsNothing, reason: text);
      }
    }

    Widget host(Widget child) => MaterialApp(
        home: Material(
            child: Center(child: SizedBox(width: 400, child: child))));

    for (final showWork in [true, false]) {
      testWidgets('an episode card, showWork $showWork', (tester) async {
        await tester.pumpWidget(host(EpisodeCardView(
            work: work,
            episode: unnumbered,
            callbacks: const CardCallbacks(),
            showWork: showWork)));
        expect(find.text('第3话 小芙莉莲'), findsOneWidget);
        expectNoNumber();

        await tester.pumpWidget(host(EpisodeCardView(
            work: work,
            episode: numbered,
            callbacks: const CardCallbacks(),
            showWork: showWork)));
        expect(find.text('05'), findsOneWidget);
        expect(find.text('第 5 集 · 死者的幻影'),
            showWork ? findsOneWidget : findsNothing);
      });
    }

    testWidgets('an episode tile on the work page', (tester) async {
      Widget tile(UiEpisode e) => host(EpisodeTile(
          work: work, episode: e, current: false, onPlay: () {}));
      await tester.pumpWidget(tile(unnumbered));
      expect(find.text('第3话 小芙莉莲'), findsOneWidget);
      expectNoNumber();
      await tester.pumpWidget(tile(numbered));
      expect(find.text('05'), findsOneWidget);
    });

    testWidgets('the work page goes on without a number', (tester) async {
      const started = UiEpisode(
          episodeId: 'e-z',
          workId: 'w-z',
          number: null,
          title: '第3话 小芙莉莲',
          progress: 0.4,
          playable: true);
      const page = UiWork(
          workId: 'w-z',
          title: '葬送的芙莉莲',
          artwork: UiArtwork(tint: 0xff3c5a6e),
          next: started);
      final shell = await pumpFoundCards(tester,
          cards: [const UiWorkCard(page)],
          discover: FoundDetails(),
          data: _Library(page, [
            const UiEpisode(
                episodeId: 'e-1', workId: 'w-z', number: 1, progress: 1),
            started,
          ]),
          actions: _Plays());
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text(page.title));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(WorkDetailPage), findsOneWidget);
      expect(
          tester.widget<PlayButton>(find.byType(PlayButton)).label, '继续播放');
      final debug =
          tester.state(find.byType(WorkDetailPage)) as WorkDetailDebug;
      expect(debug.debugStatus()['menuItems'], contains('看过了'));
      expect(find.text('01', skipOffstage: false), findsOneWidget);
      expect(find.text('第3话 小芙莉莲', skipOffstage: false), findsOneWidget);
      for (final text in ['0', '00', '3', '03']) {
        expect(find.text(text, skipOffstage: false), findsNothing,
            reason: text);
      }
      expect(find.textContaining('第 0 集', skipOffstage: false), findsNothing);
      expect(find.textContaining('第 3 集', skipOffstage: false), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      shell.dispose();
    });
  });

  group('下一集', () {
    const work = UiWork(workId: 'w', title: '葬送的芙莉莲');
    UiEpisode e(String id, int? number) => UiEpisode(
        episodeId: id, workId: 'w', number: number, season: 1, playable: true);
    final episodes = [e('e1', 1), e('e2', 2), e('x', null), e('e3', 3)];

    test('follows the numbers, past one without a number', () {
      expect(PlayingWork(work, episodes, episodes[1]).next?.episodeId, 'e3');
      expect(PlayingWork(work, episodes, episodes[3]).next, isNull);
    });

    test('none after an episode without a number', () {
      expect(PlayingWork(work, episodes, episodes[2]).next, isNull);
    });
  });
}

/// One work and its episodes.
final class _Library implements NextUiData {
  _Library(this.only, this.list);
  final UiWork only;
  final List<UiEpisode> list;
  @override
  Future<UiWork?> work(String workId) async =>
      workId == only.workId ? only : null;
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      workId == only.workId ? list : const [];
  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<List<UiWork>> library() async => [only];
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
}

final class _Plays implements NextUiActions {
  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

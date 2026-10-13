import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Material, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/media/provider_transport.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/search/recent_searches.dart';
import 'package:nipaplay/next/ui/search/search_controller.dart';
import 'package:nipaplay/next/ui/search/search_overlay.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/library_search.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The search panel: typing waits and an older answer never replaces a
/// newer one; each group, and each source, answers or fails on its own;
/// nothing found is one quiet line; a work found online that the library
/// has opens its library page, once; the keyboard chooses and opens; recent
/// terms come back and clear, across restarts; ⌘F opens it, an episode
/// plays, a share's file plays from the share, and Nipa gets the words in
/// the input, unsaid.
void main() {
  UiWork work(String id, String title) => UiWork(workId: id, title: title);
  const jellyfin = UiSearchSource(
      sourceId: 'jf-1', name: '客厅 Jellyfin', kind: UiSourceKind.jellyfin);
  const nas = UiSearchSource(
      sourceId: 'smb-1', name: '家里的 NAS', kind: UiSourceKind.smb);
  const emby = UiSearchSource(
      sourceId: 'emby-1', name: '书房 Emby', kind: UiSourceKind.emby);
  UiSourceHit file(String name, {UiSearchSource source = nas}) => UiSourceHit(
      source: source,
      itemId: '/下载/$name',
      kind: UiSourceHitKind.file,
      title: name);

  test('typing waits; an older answer never replaces a newer one', () async {
    final asked = <String>[];
    final answers = <String, Completer<UiLibraryHits>>{};
    final data = _Search(library: (q) {
      asked.add(q);
      return (answers[q] = Completer()).future;
    });
    final search = NextSearch(data, debounce: const Duration(milliseconds: 40));
    search.show();
    search.text.text = '芙';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    search.text.text = '芙莉';
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(asked, ['芙莉'], reason: 'the debounce skips what was typed past');

    search.text.text = '芙莉莲';
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(asked, ['芙莉', '芙莉莲']);
    answers['芙莉莲']!.complete(UiLibraryHits(works: [work('a', '葬送的芙莉莲')]));
    await Future<void>.delayed(Duration.zero);
    answers['芙莉']!.complete(UiLibraryHits(works: [work('b', '旧的答案')]));
    await Future<void>.delayed(Duration.zero);

    final rows = search.shown(SearchGroupKind.library);
    expect([for (final r in rows) (r as WorkEntry).work.title], ['葬送的芙莉莲']);
    expect(search.entries.last, isA<NipaEntry>());
    search.dispose();
  });

  test('a failing group leaves the others; no sources, no sources group',
      () async {
    final data = _Search(
      library: (q) async => UiLibraryHits(works: [work('a', '迷宫饭')]),
      online: (q) async => throw StateError('offline'),
    );
    final search = NextSearch(data, debounce: Duration.zero);
    search.text.text = '迷宫';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(search.groups.keys, isNot(contains(SearchGroupKind.sources)));
    expect(
        search.groups[SearchGroupKind.library]!.state, SearchGroupState.done);
    expect(search.groups[SearchGroupKind.online]!.failed, isTrue);
    expect(search.entries.length, 2);
    expect(search.nothingFound, isFalse);
    search.dispose();
  });

  test('every source answers on its own; one that cannot is not “nothing”',
      () async {
    var lists = 0;
    final answers = <String, Completer<UiSourceAnswer>>{};
    final data = _Search(
      sources: () async {
        lists++;
        return const [jellyfin, nas, emby];
      },
      searchSource: (source, q) =>
          (answers['${source.sourceId} $q'] = Completer()).future,
    );
    final search = NextSearch(data, debounce: Duration.zero);
    search.show();
    expect(lists, 1, reason: 'the sources are read as the panel opens');
    search.text.text = '未知';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(answers.keys, ['jf-1 未知', 'smb-1 未知', 'emby-1 未知']);

    // The share answers first: its rows show while the others search.
    answers['smb-1 未知']!
        .complete(UiSourceAnswer([file('[字幕组] 未知作品 - 01.mkv')]));
    await Future<void>.delayed(Duration.zero);
    var group = search.groups[SearchGroupKind.sources]!;
    expect(group.loading, isTrue);
    expect(
        search.shown(SearchGroupKind.sources).single,
        isA<SourceEntry>()
            .having((e) => e.hit.title, 'title', '[字幕组] 未知作品 - 01.mkv'));

    answers['emby-1 未知']!.completeError(StateError('unreachable'));
    answers['jf-1 未知']!.complete(const UiSourceAnswer([]));
    await Future<void>.delayed(Duration.zero);
    group = search.groups[SearchGroupKind.sources]!;
    expect(group.state, SearchGroupState.done);
    expect(group.unanswered, ['书房 Emby']);

    // Nothing anywhere, but one source could not say: not “nothing found”.
    search.text.text = '无';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    answers['smb-1 无']!.complete(const UiSourceAnswer([]));
    answers['jf-1 无']!.complete(const UiSourceAnswer([]));
    // A source that failed (no total) answers without throwing.
    answers['emby-1 无']!.complete(const UiSourceAnswer([], failed: true));
    await Future<void>.delayed(Duration.zero);
    expect(search.groups[SearchGroupKind.sources]!.unanswered, ['书房 Emby']);
    expect(search.entries.single, isA<NipaEntry>());
    expect(search.nothingFound, isFalse);

    // A share out of reach still tells what it held; it is shown, not
    // called unanswered.
    search.text.text = '下载';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    answers['smb-1 下载']!.complete(const UiSourceAnswer([
      UiSourceHit(
          source: nas,
          itemId: '/下载/b.mkv',
          kind: UiSourceHitKind.file,
          title: 'b.mkv',
          reachable: false)
    ], failed: true));
    answers['jf-1 下载']!.complete(const UiSourceAnswer([]));
    answers['emby-1 下载']!.complete(const UiSourceAnswer([]));
    await Future<void>.delayed(Duration.zero);
    expect(search.groups[SearchGroupKind.sources]!.unanswered, isEmpty);
    expect(
        (search.shown(SearchGroupKind.sources).single as SourceEntry)
            .hit
            .reachable,
        isFalse);

    // An answer to an older query never lands.
    search.text.text = '迟';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    search.text.text = '迟到';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    answers['smb-1 迟']!.complete(UiSourceAnswer([file('迟.mkv')]));
    await Future<void>.delayed(Duration.zero);
    expect(search.shown(SearchGroupKind.sources), isEmpty);

    // Opened again: the sources are read again.
    search.hide();
    search.show();
    expect(lists, 2);
    search.dispose();

    // No sources: no group. A list that cannot be read fails the group,
    // and is read again with the next query.
    var fail = true;
    final none = NextSearch(
        _Search(sources: () async => fail ? throw StateError('x') : const []),
        debounce: Duration.zero);
    none.text.text = '迷宫';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(none.groups[SearchGroupKind.sources]!.failed, isTrue);
    expect(none.nothingFound, isFalse);
    fail = false;
    none.text.text = '迷宫饭';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(none.groups.keys, isNot(contains(SearchGroupKind.sources)));
    expect(none.nothingFound, isTrue);
    none.dispose();
  });

  test('online, a work the library shows is not repeated, by its ID', () async {
    final data = _Search(
      library: (q) async =>
          UiLibraryHits(works: q == '无' ? const [] : [work('a', '迷宫饭')]),
      online: (q) async => q == '无'
          ? const []
          : [
              // The library's own, by another name: shown there already.
              work('a', '迷宫美食'),
              // Called the same, but another work.
              work(Found.id('dandanplay', '1'), '迷宫饭'),
              // The library has it, though its row is not here.
              work('b', '迷宫饭 第二季'),
              // Two results, one work of the library.
              work('b', 'Dungeon Meshi 2'),
            ],
    );
    final search = NextSearch(data, debounce: Duration.zero);
    search.text.text = '迷宫';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final online = search.shown(SearchGroupKind.online).cast<WorkEntry>();
    expect([
      for (final e in online) (e.work.title, e.inLibrary)
    ], [
      ('迷宫饭', false),
      ('迷宫饭 第二季', true),
    ]);
    expect({for (final e in online) e.key}, hasLength(2));

    search.text.text = '无';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(search.nothingFound, isTrue);
    expect(search.entries.single, isA<NipaEntry>());
    search.dispose();
  });

  test('the real searches ask the harness as the interface, read only',
      () async {
    final calls = <h.InvocationRecord>[];
    const frieren = UiWork(
        workId: 'mesh-work:1',
        title: '葬送的芙莉莲',
        originalTitle: '葬送のフリーレン',
        year: 2023,
        episodeCount: 28,
        artwork: UiArtwork(poster: '/library/frieren.jpg'),
        devices: [UiDevice(name: '工作站', online: true)]);
    const third = UiEpisode(
        episodeId: 'mesh-episode:1:3',
        workId: 'mesh-work:1',
        number: 3,
        title: '杀人魔法',
        playable: true,
        device: UiDevice(name: '工作站', online: true));
    // The merged catalogue's own index, over rows as the library writes them
    // (its 28 episodes are not all in the projection: the count is the
    // catalogue's, not estimated).
    final index = LibrarySearchIndex()
      ..replace([
        {
          'id': frieren.workId,
          'added': 1,
          'payload': workJson(frieren),
          'facts': {
            'searchTitles': ['Frieren'],
            'searchYears': [2023],
            'searchEpisodes': [
              {'episode': episodeJson(third), 'titles': <String>[]}
            ],
            'identityKeys': <String>[],
          },
        },
      ]);
    final harness = h.Harness([
      _Merged(index),
      _Metadata(const DandanplayMetadataProvider(_Dandanplay())),
      _Sources(),
    ], observers: [
      _Calls(calls)
    ]);
    final search = CoreSearch(() => harness);

    final hits = await search.library('芙莉');
    final found = hits.works.single;
    expect(found.workId, 'mesh-work:1');
    expect(found.year, 2023);
    expect(found.originalTitle, '葬送のフリーレン');
    expect(found.episodeCount, 28);
    expect(found.artwork.poster, '/library/frieren.jpg');
    expect(found.devices.single.name, '工作站');
    final (of, episode) = (await search.library('杀人')).episodes.single;
    expect(of.workId, 'mesh-work:1');
    expect(episode.episodeId, 'mesh-episode:1:3');
    expect(episode.playable, isTrue);
    expect(episode.device?.name, '工作站');

    // In the library: its library page; otherwise the found one.
    final online = await search.online('芙莉莲');
    expect([
      for (final w in online) (w.workId, w.title)
    ], [
      ('mesh-work:1', '葬送的芙莉莲'),
      (Found.id('dandanplay', '18002'), '葬送的芙莉莲 第二季'),
    ]);
    expect(online.first.artwork.poster, 'https://img.example/18001.jpg');

    final sources = await search.sources();
    expect([
      for (final s in sources) (s.name, s.kind)
    ], [
      ('客厅 Jellyfin', UiSourceKind.jellyfin),
      ('家里的 NAS', UiSourceKind.smb),
      ('书房 Emby', UiSourceKind.emby),
    ]);

    final server = await search.searchSource(sources[0], '芙莉莲', limit: 3);
    expect(server.failed, isFalse);
    final [series, ep] = server.hits;
    expect(series.kind, UiSourceHitKind.work);
    expect(series.work?.workId, 'mesh-work:1', reason: 'bound: the library');
    expect(series.work?.year, 2023);
    expect(ep.kind, UiSourceHitKind.episode);
    expect(ep.work?.workId, 'source-work:series');
    expect(ep.work?.title, '葬送的芙莉莲');
    expect(ep.episode?.episodeId, 'source-episode:e3');
    expect(ep.episode?.number, 3);
    expect(ep.playable, isTrue);

    final share = await search.searchSource(sources[1], '芙莉莲', limit: 3);
    expect(share.failed, isFalse);
    final [loose, bound] = share.hits;
    expect(loose.kind, UiSourceHitKind.file);
    expect(loose.work, isNull, reason: 'no work: it plays from the share');
    expect(loose.episode, isNull);
    expect(loose.itemId, '/下载/芙莉莲 OVA.mkv');
    expect(loose.playable, isFalse);
    expect(loose.reachable, isTrue, reason: 'unverified is unknown');
    expect(bound.work?.workId, 'mesh-work:1');
    expect(bound.episode?.episodeId, 'mesh-episode:1:3');
    expect(bound.title, '葬送的芙莉莲 03.mkv');

    final failed = await search.searchSource(sources[2], '芙莉莲', limit: 3);
    expect(failed.failed, isTrue);
    expect(failed.hits, isEmpty);

    for (final hit in [...server.hits, ...share.hits]) {
      expect(hit.work?.workId, isNot(hit.itemId));
      expect(hit.episode?.episodeId, isNot(hit.itemId));
    }
    expect([
      for (final c in calls) (c.actionId, c.origin, c.effect)
    ], [
      ('media.library.search_merged', 'gui', h.Effect.read),
      ('media.library.search_merged', 'gui', h.Effect.read),
      ('media.metadata.search', 'gui', h.Effect.read),
      ('media.sources.list', 'gui', h.Effect.read),
      ('media.sources.search', 'gui', h.Effect.read),
      ('media.sources.search', 'gui', h.Effect.read),
      ('media.sources.search', 'gui', h.Effect.read),
    ]);
    expect(calls[4].input, {
      'query': '芙莉莲',
      'sourceIds': ['jf-1'],
      'limit': 3
    });
  });

  test('recent terms: latest first, ten at most, kept, cleared for good',
      () async {
    final store = _Store();
    final search = NextSearch(_Search(), store: store, debounce: Duration.zero);
    for (final term in [...'abcdefghijkl'.split(''), 'b']) {
      search.text.text = term;
      search.remember();
    }
    search.text.text = '';
    const kept = ['b', 'l', 'k', 'j', 'i', 'h', 'g', 'f', 'e', 'd'];
    expect(search.recent, kept);
    expect(search.entries.first,
        isA<RecentEntry>().having((e) => e.text, 'text', 'b'));
    await Future<void>.delayed(Duration.zero);
    expect(store.terms, kept);
    search.dispose();

    // The next start reads them back.
    final again = NextSearch(_Search(), store: store);
    await Future<void>.delayed(Duration.zero);
    expect(again.recent, kept);
    again.clearRecent();
    expect(again.entries, isEmpty);
    await Future<void>.delayed(Duration.zero);
    expect(store.terms, isNull, reason: 'the record itself is gone');
    again.dispose();
  });

  test('recent terms live in this device\'s preferences', () async {
    SharedPreferences.setMockInitialValues({});
    const store = PreferenceRecentSearches();
    final search = NextSearch(_Search(), store: store);
    search.text.text = '迷宫饭';
    search.remember();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(PreferenceRecentSearches.key), ['迷宫饭']);
    search.dispose();

    final again = NextSearch(_Search(), store: store);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(again.recent, ['迷宫饭']);
    again.clearRecent();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(prefs.containsKey(PreferenceRecentSearches.key), isFalse);
    again.dispose();
  });

  Widget host(Widget child) => MaterialApp(
        home: Material(
          child: SizedBox(width: 1200, height: 800, child: child),
        ),
      );

  testWidgets(
      'the keyboard chooses and opens; failures and emptiness stay quiet',
      (tester) async {
    final opened = <SearchEntry>[];
    var closed = 0;
    final data = _Search(
      library: (q) async => q == '无'
          ? const UiLibraryHits()
          : UiLibraryHits(works: [
              work('a', '葬送的芙莉莲'),
              work('b', '葬送的芙莉莲 第二季'),
            ], episodes: [
              (
                work('a', '葬送的芙莉莲'),
                const UiEpisode(
                    episodeId: 'e3',
                    workId: 'a',
                    number: 3,
                    title: '杀人魔法',
                    playable: true)
              )
            ]),
      online: (q) async => throw StateError('offline'),
    );
    final search = NextSearch(data, debounce: const Duration(milliseconds: 50));
    await tester.pumpWidget(host(SearchLayer(
      search: search,
      onOpen: opened.add,
      onClose: () {
        closed++;
        search.hide();
      },
    )));
    expect(find.byType(TextField), findsNothing);

    search.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(search.focus.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), '芙莉莲');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('片库'), findsOneWidget);
    expect(find.text('葬送的芙莉莲 第二季'), findsOneWidget);
    expect(find.text('第 3 集 · 杀人魔法'), findsOneWidget);
    expect(find.text('在线'), findsOneWidget);
    expect(find.text('暂时搜不了'), findsOneWidget);
    expect(find.text('没有找到'), findsNothing);
    expect(find.textContaining('让 Nipa 找', findRichText: true), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened.single,
        isA<WorkEntry>().having((e) => e.work.title, 'title', '葬送的芙莉莲 第二季'));

    await tester.enterText(find.byType(TextField), '无');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('没有找到'), findsNothing,
        reason: 'a group failed: it is not that nothing is there');
    expect(find.text('暂时搜不了'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(closed, 1);
    expect(find.byType(TextField), findsNothing);
    search.dispose();
  });

  testWidgets(
      'sources show their works, episodes and files; one that cannot answer '
      'says so alone; a found work the library has is marked', (tester) async {
    final search = NextSearch(
        _Search(
          library: (q) async => UiLibraryHits(works: [work('a', '间谍过家家')]),
          online: (q) async => [
            work('a', '间谍过家家'),
            work('b', '间谍家家酒 剧场版'),
            work(Found.id('dandanplay', '7'), '间谍家家酒 第二季'),
          ],
          sources: () async => const [jellyfin, nas, emby],
          searchSource: (source, q) async => switch (source.sourceId) {
            'jf-1' => const UiSourceAnswer([
                UiSourceHit(
                    source: jellyfin,
                    itemId: 'series',
                    kind: UiSourceHitKind.work,
                    title: '间谍过家家',
                    work: UiWork(
                        workId: 'source-work:s', title: '间谍过家家', year: 2022)),
                UiSourceHit(
                  source: jellyfin,
                  itemId: 'e2',
                  kind: UiSourceHitKind.episode,
                  title: '守护妻子的秘密',
                  work: UiWork(workId: 'source-work:s', title: '间谍过家家'),
                  episode: UiEpisode(
                      episodeId: 'source-episode:e2',
                      workId: 'source-work:s',
                      number: 2,
                      title: '守护妻子的秘密',
                      playable: true),
                  playable: true,
                ),
              ]),
            'smb-1' => UiSourceAnswer([file('间谍 花絮.mkv')]),
            _ => throw StateError('unreachable'),
          },
        ),
        debounce: Duration.zero);
    await tester.pumpWidget(host(
        SearchLayer(search: search, onOpen: (_) {}, onClose: search.hide)));
    search.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), '间谍');
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('间谍家家酒 剧场版'), findsOneWidget);
    expect(find.text('已入库'), findsOneWidget, reason: 'only the library\'s');
    expect(find.text('间谍家家酒 第二季'), findsOneWidget);
    expect(find.text('来源'), findsOneWidget);
    expect(find.text('客厅 Jellyfin · 2022'), findsOneWidget);
    expect(find.text('第 2 集 · 守护妻子的秘密'), findsOneWidget);
    expect(find.text('间谍过家家 · 客厅 Jellyfin'), findsOneWidget);
    expect(find.text('间谍 花絮.mkv'), findsOneWidget);
    expect(find.text('家里的 NAS'), findsOneWidget);
    expect(find.textContaining('书房 Emby', findRichText: true), findsOneWidget);
    expect(find.textContaining('暂时搜不了', findRichText: true), findsOneWidget);
    expect(find.text('没有找到'), findsNothing);
    expect(find.textContaining('/下载/', findRichText: true), findsNothing,
        reason: 'no IDs shown');
    search.dispose();
  });

  testWidgets('recent terms show when nothing is typed, and clear',
      (tester) async {
    final search = NextSearch(
        _Search(library: (q) async => const UiLibraryHits()),
        debounce: Duration.zero);
    search.text.text = '迷宫饭';
    search.remember();
    search.text.text = '';
    await tester.pumpWidget(host(
        SearchLayer(search: search, onOpen: (_) {}, onClose: search.hide)));
    search.show();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('最近'), findsOneWidget);
    expect(find.text('迷宫饭'), findsOneWidget);
    await tester.tap(find.text('清除'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('最近'), findsNothing);
    expect(find.text('迷宫饭'), findsNothing);
    search.dispose();
  });

  testWidgets('⌘F opens search; an episode plays; Nipa gets the words, unsaid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final actions = _Actions();
    final shell = NextShellController(
        _services(_Search(library: (q) async => const UiLibraryHits()),
            actions: actions),
        onLeave: () {});
    await tester.pumpWidget(host(NextShellScope(
      controller: shell,
      child: CallbackShortcuts(
        bindings: nextShellShortcuts(shell),
        child: Focus(
          autofocus: true,
          child: SearchLayer(
              search: shell.search,
              onOpen: shell.openSearchEntry,
              onClose: shell.closeSearch),
        ),
      ),
    )));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(shell.search.isOpen, isTrue);
    expect(shell.search.focus.hasFocus, isTrue);

    await tester.enterText(find.byType(TextField), '冷门老番');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('没有找到'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(shell.search.isOpen, isFalse);
    expect(shell.askText.text, '帮我找「冷门老番」');
    expect(shell.homeChatOpen.value, isTrue);
    expect(shell.chat.turns, isEmpty, reason: 'nothing is said for the user');
    expect(shell.search.recent, ['冷门老番']);

    // An episode plays through the actions, even one not on this device.
    const frieren = UiWork(workId: 'w', title: '葬送的芙莉莲');
    const third =
        UiEpisode(episodeId: 'e3', workId: 'w', number: 3, playable: true);
    shell.openSearch();
    shell.search.text.text = '杀人魔法';
    shell.openSearchEntry(const EpisodeEntry(frieren, third));
    expect(actions.played, [('葬送的芙莉莲', 3)]);
    expect(shell.search.isOpen, isFalse);
    expect(shell.search.recent, ['杀人魔法', '冷门老番']);
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    expect(
        (await tester.runAsync(SharedPreferences.getInstance))!
            .getStringList(PreferenceRecentSearches.key),
        ['杀人魔法', '冷门老番']);

    // A source's episode plays as the library's; a share's file no work
    // holds plays from the share, by its item.
    shell.openSearch();
    shell.search.text.text = '芙莉莲';
    shell.openSearchEntry(const SourceEntry(UiSourceHit(
        source: jellyfin,
        itemId: 'e3',
        kind: UiSourceHitKind.episode,
        title: '杀人魔法',
        work: frieren,
        episode: third,
        playable: true)));
    expect(actions.played.last, ('葬送的芙莉莲', 3));
    shell.openSearch();
    shell.openSearchEntry(SourceEntry(file('芙莉莲 OVA.mkv')));
    expect(actions.fromSource, [('smb-1', '/下载/芙莉莲 OVA.mkv')]);
    expect(actions.played, hasLength(2));
    expect(shell.search.isOpen, isFalse);

    shell.openSearch();
    expect(shell.escape(), isTrue);
    expect(shell.search.isOpen, isFalse);

    await tester.pumpWidget(const SizedBox());
    shell.dispose();
  });
}

final class _Search implements NextSearchData {
  _Search({
    Future<UiLibraryHits> Function(String)? library,
    Future<List<UiWork>> Function(String)? online,
    Future<List<UiSearchSource>> Function()? sources,
    Future<UiSourceAnswer> Function(UiSearchSource, String)? searchSource,
  })  : libraryFor = library ?? ((_) async => const UiLibraryHits()),
        onlineFor = online ?? ((_) async => const []),
        sourcesFor = sources ?? (() async => const []),
        sourceFor = searchSource ?? ((_, __) async => const UiSourceAnswer([]));

  final Future<UiLibraryHits> Function(String) libraryFor;
  final Future<List<UiWork>> Function(String) onlineFor;
  final Future<List<UiSearchSource>> Function() sourcesFor;
  final Future<UiSourceAnswer> Function(UiSearchSource, String) sourceFor;

  @override
  Future<UiLibraryHits> library(String query) => libraryFor(query);

  @override
  Future<List<UiWork>> online(String query) => onlineFor(query);

  @override
  Future<List<UiSearchSource>> sources() => sourcesFor();

  @override
  Future<UiSourceAnswer> searchSource(UiSearchSource source, String query,
          {int limit = 6}) =>
      sourceFor(source, query);
}

NextUiServices _services(NextSearchData search, {NextUiActions? actions}) {
  final lib = _Unused();
  return NextUiServices(
    data: _Data(),
    actions: actions ?? _Unused(),
    chat: _Port(),
    discover: _Unused(),
    library: lib,
    libraryActions: lib,
    search: search,
    settings: FakeSettings(),
  );
}

final class _Data implements NextUiData {
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);

  @override
  Stream<void> get changes => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Port implements ChatPort {
  @override
  bool get available => false;

  @override
  bool get busy => false;

  @override
  Stream<ChatEvent> get display => const Stream.empty();

  @override
  Stream<ChatEvent> get questions => const Stream.empty();

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Unused
    implements
        NextUiActions,
        NextDiscoverData,
        NextLibraryData,
        NextLibraryActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Store implements RecentSearchStore {
  List<String>? terms;

  @override
  Future<List<String>> load() async => terms ?? const [];

  @override
  Future<void> save(List<String> terms) async => this.terms = terms;

  @override
  Future<void> clear() async => terms = null;
}

final class _Actions implements NextUiActions {
  final played = <(String, int?)>[];
  final fromSource = <(String, String)>[];

  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async =>
      played.add((work.title, episode?.number));

  @override
  Future<void> playFromSource(
          {required String sourceId, required String itemId}) async =>
      fromSource.add((sourceId, itemId));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Calls implements h.InvocationObserver {
  _Calls(this.calls);
  final List<h.InvocationRecord> calls;
  @override
  void onInvocation(h.InvocationRecord record) => calls.add(record);
}

/// 弹弹play's search answer, as its API gives it.
final class _Dandanplay implements MetadataTransport {
  const _Dandanplay();
  @override
  Future<h.JsonMap> request(String path,
          {Map<String, String> query = const {}, h.JsonMap? body}) async =>
      {
        'animes': [
          {
            'animeId': 18001,
            'animeTitle': '葬送的芙莉莲',
            'imageUrl': 'https://img.example/18001.jpg',
          },
          {
            'animeId': 18002,
            'animeTitle': '葬送的芙莉莲 第二季',
            'imageUrl': 'https://img.example/18002.jpg',
          }
        ]
      };
}

/// `media.library.search_merged` as MeshLibraryCapability declares it
/// (MeshLibrary is final), answering from the real index.
final class _Merged implements h.Capability {
  _Merged(this.index);
  final LibrarySearchIndex index;
  @override
  late final List<h.Action> actions = [_MergedSearch(index)];
}

final class _MergedSearch extends h.Action<_Json, _Json> {
  const _MergedSearch(this.index);
  final LibrarySearchIndex index;

  @override
  h.ActionSpec get spec => const h.ActionSpec(
        id: 'media.library.search_merged',
        title: '搜索合并片库',
        description: 'Read the merged library index.',
        effect: h.Effect.read,
        input: h.ObjectSchema({
          'query': h.StringSchema(minLength: 1),
          'limit': h.IntegerSchema(minimum: 1, maximum: 100),
          'episodeLimit': h.IntegerSchema(minimum: 1, maximum: 100),
        }, required: [
          'query'
        ]),
        output: h.ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(h.JsonMap json) => _Json(json);

  @override
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) async =>
      h.Completed(_Json(index.search(input.value['query'] as String,
          limit: input.value['limit'] as int? ?? 12,
          episodeLimit: input.value['episodeLimit'] as int?)));
}

/// `media.sources.list` and `media.sources.search`, answering as
/// MediaSourcesCapability does: a Jellyfin (a bound series and an episode
/// of its own), a NipaPlay remote (not searched), a share whose state is
/// unknown (a loose file and a bound one) and an Emby that failed.
final class _Sources implements h.Capability {
  @override
  late final List<h.Action> actions = [
    _SourceAction(
        'media.sources.list',
        (_) => {
              'sources': [
                {'sourceId': 'jf-1', 'type': 'jellyfin', 'name': '客厅 Jellyfin'},
                {'sourceId': 'dr-1', 'type': 'dandanplay_remote', 'name': '远程'},
                {'sourceId': 'smb-1', 'type': 'smb', 'name': '家里的 NAS'},
                {'sourceId': 'emby-1', 'type': 'emby', 'name': '书房 Emby'},
              ]
            }),
    _SourceAction('media.sources.search', (input) {
      final id = (input['sourceIds'] as List).single;
      return {
        'sources': [
          switch (id) {
            'jf-1' => {
                'sourceId': id,
                'name': '客厅 Jellyfin',
                'type': 'jellyfin',
                'basis': 'server',
                'connectionState': 'connected',
                'total': 2,
                'entries': [
                  {
                    'itemId': 'series',
                    'title': '葬送的芙莉莲',
                    'kind': 'Series',
                    'year': 2023,
                    'metadata': {'Name': '葬送的芙莉莲'},
                    'workId': 'mesh-work:1',
                    'episodeId': null,
                    'sourceWorkId': 'source-work:series',
                    'sourceEpisodeId': null,
                    'playable': false,
                  },
                  {
                    'itemId': 'e3',
                    'title': '杀人魔法',
                    'kind': 'Episode',
                    'year': 2023,
                    'metadata': {
                      'Name': '杀人魔法',
                      'SeriesName': '葬送的芙莉莲',
                      'IndexNumber': 3,
                      'ParentIndexNumber': 1,
                    },
                    'workId': null,
                    'episodeId': null,
                    'sourceWorkId': 'source-work:series',
                    'sourceEpisodeId': 'source-episode:e3',
                    'playable': true,
                  },
                ],
              },
            'smb-1' => {
                'sourceId': id,
                'name': '家里的 NAS',
                'type': 'smb',
                'basis': 'indexed',
                'connectionState': 'unverified',
                'total': 2,
                'entries': [
                  {
                    'itemId': '/下载/芙莉莲 OVA.mkv',
                    'title': '芙莉莲 OVA.mkv',
                    'kind': 'File',
                    'fileId': 'file-1',
                    'year': null,
                    'workId': null,
                    'episodeId': null,
                    'playable': false,
                  },
                  {
                    'itemId': '/动画/葬送的芙莉莲 03.mkv',
                    'title': '葬送的芙莉莲 03.mkv',
                    'kind': 'File',
                    'fileId': 'file-2',
                    'year': null,
                    'workId': 'mesh-work:1',
                    'episodeId': 'mesh-episode:1:3',
                    'playable': false,
                  },
                ],
              },
            _ => {
                'sourceId': id,
                'name': '书房 Emby',
                'type': 'emby',
                'basis': 'server',
                'connectionState': 'failed',
                'entries': <Object>[],
                'total': null,
                'error': {
                  'code': 'unavailable',
                  'message': 'Source search could not connect or authenticate.'
                },
              },
          }
        ]
      };
    }),
  ];
}

final class _SourceAction extends h.Action<_Json, _Json> {
  const _SourceAction(this.id, this.answer);
  final String id;
  final h.JsonMap Function(h.JsonMap input) answer;

  @override
  h.ActionSpec get spec => h.ActionSpec(
        id: id,
        title: id,
        description: 'A media source, read.',
        effect: h.Effect.read,
        input: id == 'media.sources.list'
            ? const h.ObjectSchema({})
            : const h.ObjectSchema({
                'query': h.StringSchema(minLength: 1),
                'sourceIds': h.ArraySchema(h.StringSchema(minLength: 1)),
                'limit': h.IntegerSchema(minimum: 1, maximum: 100),
              }, required: [
                'query'
              ]),
        output: const h.ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(h.JsonMap json) => _Json(json);

  @override
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) async =>
      h.Completed(_Json(answer(input.value)));
}

/// `media.metadata.search` over a real provider, answering as
/// MediaCapability does.
final class _Metadata implements h.Capability {
  _Metadata(this.provider);
  final DandanplayMetadataProvider provider;
  @override
  late final List<h.Action> actions = [_MetadataSearch(provider)];
}

final class _Json implements h.JsonEncodable {
  const _Json(this.value);
  final h.JsonMap value;
  @override
  h.JsonMap toJson() => value;
}

final class _MetadataSearch extends h.Action<_Json, _Json> {
  const _MetadataSearch(this.provider);
  final DandanplayMetadataProvider provider;

  @override
  h.ActionSpec get spec => const h.ActionSpec(
        id: 'media.metadata.search',
        title: 'media.metadata.search',
        description: 'Search a metadata source.',
        effect: h.Effect.read,
        input: h.ObjectSchema({
          'provider': h.StringSchema(minLength: 1),
          'query': h.StringSchema(minLength: 1),
        }, required: [
          'provider',
          'query'
        ]),
        output: h.ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(h.JsonMap json) => _Json(json);

  @override
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) async {
    expect(input.value['provider'], 'dandanplay');
    final records = await provider.search(input.value['query'] as String);
    // As MediaService adds it: the accepted identity's library work.
    return h.Completed(_Json({
      'results': [
        for (final r in records)
          {
            ...r.toJson(),
            'workId': r.ref.externalId == '18001' ? 'mesh-work:1' : null,
          }
      ]
    }));
  }
}

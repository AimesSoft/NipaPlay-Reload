import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Material, TextField;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/media/provider_transport.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/mesh/library_codec.dart';
import 'package:nipaplay/next/state/query.dart';
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
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The search panel: typing waits and an older answer never replaces a
/// newer one; each group answers or fails on its own; nothing found is one
/// quiet line; the keyboard chooses and opens; recent terms come back and
/// clear, across restarts; ⌘F opens it, an episode plays, and Nipa gets
/// the words in the input, unsaid.
void main() {
  UiWork work(String id, String title) => UiWork(workId: id, title: title);

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

  test('a failing group leaves the others; sources only where searchable',
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

    final withSources = NextSearch(
        _Search(
            sources: (q) async => [
                  UiSourceHit(work('j', '迷宫饭'),
                      source: '客厅 Jellyfin', kind: UiSourceKind.jellyfin)
                ]),
        debounce: Duration.zero);
    withSources.text.text = '迷宫';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(withSources.shown(SearchGroupKind.sources).single,
        isA<WorkEntry>().having((e) => e.source, 'source', '客厅 Jellyfin'));
    withSources.dispose();
  });

  test('works the library has are not repeated online; nothing found',
      () async {
    final data = _Search(
      library: (q) async =>
          UiLibraryHits(works: q == '无' ? const [] : [work('a', '迷宫饭')]),
      online: (q) async => q == '无'
          ? const []
          : [work('found:x', '迷宫饭'), work('found:y', '迷宫饭 第二季')],
    );
    final search = NextSearch(data, debounce: Duration.zero);
    search.text.text = '迷宫';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect([
      for (final e in search.shown(SearchGroupKind.online))
        (e as WorkEntry).work.title
    ], [
      '迷宫饭 第二季'
    ]);

    search.text.text = '无';
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(search.nothingFound, isTrue);
    expect(search.entries.single, isA<NipaEntry>());
    search.dispose();
  });

  test('the real searches ask the harness as the interface, read only',
      () async {
    final calls = <h.InvocationRecord>[];
    final works = [
      const UiWork(
          workId: 'mesh-work:1',
          title: '葬送的芙莉莲',
          year: 2023,
          episodeCount: 28,
          artwork: UiArtwork(poster: '/library/frieren.jpg'),
          devices: [UiDevice(name: '工作站', online: true)]),
      const UiWork(workId: 'mesh-work:2', title: '迷宫饭'),
    ];
    // `library.merged` as registerMergedLibrary declares it (MeshLibrary is
    // final): its rows are workJson with the episodes.
    final merged = StateView(
      name: 'library.merged',
      description: 'The viewer library.',
      fields: const h.ObjectSchema({
        'id': h.StringSchema(),
        'workId': h.StringSchema(),
        'title': h.StringSchema(),
        'devices':
            h.ArraySchema(h.ObjectSchema({}, additionalProperties: true)),
        'episodes':
            h.ArraySchema(h.ObjectSchema({}, additionalProperties: true)),
        'next': h.ObjectSchema({}, additionalProperties: true, nullable: true),
        'artwork': h.ObjectSchema({}, additionalProperties: true),
      }, additionalProperties: true),
      read: (offset, limit) async => [
        for (final w in works.skip(offset).take(limit))
          {
            'id': w.workId,
            ...workJson(w),
            'episodes': [
              for (var n = 1; n <= (w.episodeCount ?? 0); n++)
                {'episodeId': '${w.workId}:$n', 'number': n}
            ],
          }
      ],
    );
    final harness = h.Harness([
      StateCapability([merged]),
      _Metadata(const DandanplayMetadataProvider(_Dandanplay())),
    ], observers: [
      _Calls(calls)
    ]);
    final search = CoreSearch(() => harness);

    final hits = await search.library('芙莉');
    final frieren = hits.works.single;
    expect(frieren.workId, 'mesh-work:1');
    // Only what the view declares is public: no year.
    expect(frieren.year, isNull);
    expect(frieren.episodeCount, 28);
    expect(frieren.artwork.poster, '/library/frieren.jpg');
    expect(frieren.devices.single.name, '工作站');
    expect(hits.episodes, isEmpty);

    final online = await search.online('芙莉莲');
    expect(online.single.workId, Found.id('dandanplay', '18001'));
    expect(Found.isFound(online.single), isTrue);
    expect(online.single.title, '葬送的芙莉莲');
    expect(online.single.artwork.poster, 'https://img.example/18001.jpg');

    expect(search.sources('芙莉莲'), isNull);
    expect([
      for (final c in calls) (c.actionId, c.origin, c.effect)
    ], [
      ('state.query', 'gui', h.Effect.read),
      ('media.metadata.search', 'gui', h.Effect.read),
    ]);
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
    Future<List<UiSourceHit>> Function(String)? sources,
  })  : libraryFor = library ?? ((_) async => const UiLibraryHits()),
        onlineFor = online ?? ((_) async => const []),
        sourcesFor = sources;

  final Future<UiLibraryHits> Function(String) libraryFor;
  final Future<List<UiWork>> Function(String) onlineFor;
  final Future<List<UiSourceHit>> Function(String)? sourcesFor;

  @override
  Future<UiLibraryHits> library(String query) => libraryFor(query);

  @override
  Future<List<UiWork>> online(String query) => onlineFor(query);

  @override
  Future<List<UiSourceHit>>? sources(String query) => sourcesFor?.call(query);
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

  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async =>
      played.add((work.title, episode?.number));

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
          }
        ]
      };
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
    return h.Completed(_Json({
      'results': [for (final r in records) r.toJson()]
    }));
  }
}

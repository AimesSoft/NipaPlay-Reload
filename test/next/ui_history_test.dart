import 'package:flutter/widgets.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipa_harness/nipa_harness.dart' as h show Invocation;
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/history.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/pages/history_view.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/sheet.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('an entry reads its row: names, progress, time, pictures and where it is',
      () {
    final at = DateTime.utc(2026, 10, 12, 13, 40);
    final e = UiHistoryEntry.from({
      'entryId': 'h1',
      'fileId': 'f1',
      'workId': 'w1',
      'libraryEpisodeId': 'e3',
      'poster': '/cache/w1/poster.jpg',
      'still': null,
      'locator': '/v/Frieren/Frieren - 03.mkv',
      'animeId': 17003,
      'episodeId': 170030003,
      'title': '  葬送的芙莉莲 ',
      'episodeTitle': ' 第3话 ',
      'positionMs': 600000,
      'durationMs': 1440000,
      'progress': 0.42,
      'lastWatchedAt': at.toIso8601String(),
    });
    expect(e.entryId, 'h1');
    expect(e.workId, 'w1');
    expect(e.libraryEpisodeId, 'e3');
    expect(e.poster, '/cache/w1/poster.jpg');
    expect(e.still, isNull);
    expect(e.title, '葬送的芙莉莲');
    expect(e.episode, '第3话');
    expect(e.animeId, 17003);
    expect(e.progress, 0.42);
    expect(e.position, const Duration(minutes: 10));
    expect(e.duration, const Duration(minutes: 24));
    expect(e.at, at.toLocal());
    expect(e.at!.isUtc, isFalse);
    expect(e.playable, isTrue);

    final bare = UiHistoryEntry.from({
      'entryId': 7,
      'locator': '/v/%E7%AC%AC01%E8%AF%9D.mp4',
      'title': ' ',
      'durationMs': 0,
      'lastWatchedAt': null,
    });
    expect(bare.entryId, '7');
    expect(bare.title, '第01话');
    expect(bare.duration, isNull);
    expect(bare.at, isNull);

    final unseen = UiHistoryEntry.from({'entryId': 'h2', 'title': '别处'});
    expect(unseen.playable, isFalse);
    expect(unseen.title, '别处');

    final elsewhere = UiHistoryEntry.from({
      'entryId': 'h3',
      'title': '别处',
      'workId': 'w1',
      'libraryEpisodeId': 'e3',
    });
    expect(elsewhere.playable, isTrue,
        reason: 'the library may have the episode on another device');
  });

  test('pages follow the cursor; clearing gathers every page in one call',
      () async {
    final world = _World([
      for (var i = 0; i < 170; i++)
        _row(i,
            at: DateTime(2026, 10, 13).subtract(Duration(hours: i)),
            locator: i % 50 == 1 ? null : '/v/$i.mkv',
            animeId: 100 + i % 3),
    ]);
    final history = NextHistory(world.calls);

    final first = await history.page();
    expect(first.entries, hasLength(80));
    expect(first.cursor, 'h79');
    expect(world.queries.single, {'view': 'history.entries', 'limit': 80});
    final second = await history.page(cursor: first.cursor);
    expect(world.queries.last,
        {'view': 'history.entries', 'limit': 80, 'cursor': 'h79'});
    final last = await history.page(cursor: second.cursor);
    expect(last.entries, hasLength(10));
    expect(last.cursor, isNull);

    await history.clear();
    final removed = world.removed.single;
    expect(removed.keys.toSet(), {'entryIds', 'animeIds'});
    expect((removed['entryIds'] as List).toSet(),
        {for (var i = 0; i < 170; i++) 'h$i'},
        reason: 'entries with no place too');
    expect((removed['animeIds'] as List).toSet(), {100, 101, 102});
    expect(world.rows, isEmpty);

    await history.clear();
    expect(world.removed, hasLength(1), reason: 'nothing left to forget');
  });

  test('removing names the entries, with a place or not', () async {
    final world = _World([
      _row(0, locator: '/v/a.mkv'),
      _row(1, locator: null),
    ]);
    final history = NextHistory(world.calls);
    final entries = (await history.page()).entries;

    await history.remove(const []);
    expect(world.removed, isEmpty);
    await history.remove([entries[1]]);
    await history.remove(entries);
    expect(world.removed, [
      {
        'entryIds': ['h1']
      },
      {
        'entryIds': ['h0', 'h1']
      },
    ]);
  });

  test('days: today, yesterday, weekdays within the week, then dates', () {
    // A Tuesday evening.
    final now = DateTime(2026, 10, 13, 22);
    UiHistoryEntry at(DateTime? t, String id) =>
        UiHistoryEntry(entryId: id, title: id, at: t);
    final groups = groupHistory([
      at(DateTime(2026, 10, 13, 21, 40), 'a'),
      at(DateTime(2026, 10, 13, 0, 5), 'b'),
      at(DateTime(2026, 10, 12, 23, 59), 'c'),
      at(DateTime(2026, 10, 11, 20), 'd'),
      at(DateTime(2026, 10, 7, 9), 'e'),
      at(DateTime(2026, 10, 6, 23), 'f'),
      at(DateTime(2026, 10, 3, 8), 'g'),
      at(DateTime(2025, 12, 31, 23), 'h'),
      at(null, 'i'),
    ], now: now);
    expect([for (final g in groups) g.label],
        ['今天', '昨天', '周日', '周三', '10月6日', '10月3日', '2025年12月31日', '更早']);
    expect([for (final g in groups) g.entries.map((e) => e.entryId).join()],
        ['ab', 'c', 'd', 'e', 'f', 'g', 'h', 'i']);
    expect(historyDay(DateTime(2026, 10, 14, 1), now: now), '今天',
        reason: 'a clock ahead is still today');
  });

  testWidgets(
      'the list reads on at the end, forgets a row, asks which copy, clears',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime.now();
    final world = _World([
      for (var i = 0; i < 100; i++)
        _row(i,
            at: now.subtract(Duration(minutes: 20 * i)),
            locator: i == 1 ? null : '/v/$i.mkv'),
    ])
      ..asks = '/v/0.mkv';
    final shell = NextShellController(_services(world.calls), onLeave: () {});
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(800, 600)),
        child: NextShellScope(
          controller: shell,
          child: const Stack(children: [
            Positioned.fill(child: HistoryView(top: 40)),
            Positioned.fill(child: NextSheetLayer()),
          ]),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    final view = tester.state(find.byType(HistoryView)) as HistoryDebug;
    expect(view.debugStatus()['entries'], 80);
    expect(view.debugStatus()['more'], isTrue);
    expect(find.text('作品 0'), findsOneWidget);

    // The entry with no place cannot go on, but can be forgotten.
    await view.debug({'hover': '1'});
    await tester.pumpAndSettle();
    expect(_button('继续'), findsNothing);
    expect(_button('删除'), findsOneWidget);

    // Forgotten: the row fades, and reading on still misses nothing.
    await view.debug({'hover': '2'});
    await tester.pumpAndSettle();
    await tester.tap(_button('删除'));
    await tester.pumpAndSettle();
    expect(world.removed.single, {
      'entryIds': ['h2']
    });
    expect(find.text('作品 2'), findsNothing);
    expect(view.debugStatus()['entries'], 79);

    final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first);
    for (var i = 0; i < 4 && view.debugStatus()['more'] == true; i++) {
      scroll.position.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
    }
    expect(view.debugStatus()['entries'], 99);
    expect(view.debugStatus()['distinct'], 99);
    expect(view.debugStatus()['more'], isFalse);

    // Two copies: the question is put, and the one chosen plays.
    scroll.position.jumpTo(0);
    await view.debug({'hover': '0'});
    await tester.pumpAndSettle();
    await tester.tap(_button('继续'));
    await tester.pumpAndSettle();
    expect(find.text('播放哪一个？'), findsOneWidget);
    await tester.tap(find.text('2160p'));
    await tester.pumpAndSettle();
    expect(world.opened, ['/v/0.mkv', '/v/0.mkv#nas']);

    // A failure is a short word on the row.
    world.failing = true;
    await view.debug({'resume': '3'});
    await tester.pumpAndSettle();
    expect(view.debugStatus()['notes'], {'h4': '现在做不了'});
    world.failing = false;

    await view.debug({'clear': 'ask'});
    await tester.pumpAndSettle();
    expect(find.text('清空观看记录？'), findsOneWidget);
    await tester.tap(find.text('清空').last);
    await tester.pumpAndSettle();
    expect(world.rows, isEmpty);
    expect(find.text('没有观看记录'), findsOneWidget);
    expect(view.debugStatus()['entries'], 0);

    await tester.pumpWidget(const SizedBox());
    shell.dispose();
  });
}

/// A row's action that can be pressed now (hidden ones let the pointer
/// through).
Finder _button(String label) => find
    .byWidgetPredicate(
        (w) => w is NextIconButton && w.label == label && w.onTap != null)
    .hitTestable();

JsonMap _row(int i, {DateTime? at, String? locator, int? animeId}) => {
      'entryId': 'h$i',
      'locator': locator,
      'animeId': animeId ?? 100 + i,
      'title': '作品 $i',
      'episodeTitle': '第${i % 12 + 1}话',
      'positionMs': 60000 * (i % 24),
      'durationMs': 1440000,
      'progress': i % 4 == 0 ? 1.0 : (i % 24) / 24,
      'lastWatchedAt': (at ?? DateTime(2026, 10, 13)).toUtc().toIso8601String(),
    };

/// A record read latest first, its cursor the last row read (as
/// `state.query` keeps the last row's place), and what was asked of it.
final class _World {
  _World(this.rows);
  final List<JsonMap> rows;
  final queries = <JsonMap>[];
  final removed = <JsonMap>[];
  final opened = <String>[];

  /// The path that has two copies to choose from.
  String? asks;
  bool failing = false;

  late final harness = Harness([
    _Capability([
      _Action('state.query', (input) async {
        queries.add(input);
        final after = input['cursor'] == null
            ? 0
            : int.parse('${input['cursor']}'.substring(1)) + 1;
        final rest = [
          for (final r in rows)
            if (int.parse('${r['entryId']}'.substring(1)) >= after) r
        ];
        final page = rest.take(input['limit'] as int).toList();
        return Completed(_Json({
          'rows': page,
          'nextCursor': rest.length > page.length ? page.last['entryId'] : null,
        }));
      }),
      _Action('history.remove', (input) async {
        removed.add(input);
        final ids = ((input['entryIds'] as List?) ?? const []).toSet();
        final works = ((input['animeIds'] as List?) ?? const []).toSet();
        rows.removeWhere(
            (r) => ids.contains(r['entryId']) || works.contains(r['animeId']));
        return const Completed(_Json({}));
      }),
      _Action('playback.open', (input) async {
        if (failing) {
          return const Failed(Failure(FailureCode.unavailable, 'Busy.'));
        }
        final path = input['path'] as String;
        opened.add(path);
        if (path == asks) {
          return NeedsDecision(Decision(prompt: '播放哪一个？', options: [
            for (final (label, copy) in const [
              ('1080p', 'local'),
              ('2160p', 'nas'),
            ])
              DecisionOption(
                  label: label,
                  call: ActionCall('playback.open', {'path': '$path#$copy'})),
          ]));
        }
        return const Completed(_Json({'state': 'playing'}));
      }),
    ]),
  ]);

  GuiCalls get calls => GuiCalls(() async => harness);
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Action extends Action<_Json, _Json> {
  _Action(this.id, this.execute);
  final String id;
  final Future<Outcome<_Json>> Function(JsonMap) execute;

  @override
  ActionSpec get spec => ActionSpec(
        id: id,
        title: id,
        description: 'Test.',
        effect: Effect.write,
        input: const ObjectSchema({}, additionalProperties: true),
        output: const ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(JsonMap json) => _Json(json);

  @override
  Future<Outcome<_Json>> run(_Json input, h.Invocation invocation) =>
      execute(input.value);
}

final class _Capability implements Capability {
  _Capability(this.actions);
  @override
  final List<Action> actions;
}

NextUiServices _services(GuiCalls calls) {
  final unused = _Unused();
  return NextUiServices(
    data: _Data(),
    actions: unused,
    chat: _Port(),
    discover: unused,
    library: unused,
    libraryActions: unused,
    search: _Search(),
    settings: FakeSettings(),
    calls: calls,
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

final class _Search implements NextSearchData {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

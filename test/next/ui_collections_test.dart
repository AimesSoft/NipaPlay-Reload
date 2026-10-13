import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipa_harness/nipa_harness.dart' as h show Invocation;
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/collections.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/detail/collection.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Act extends Action<_Json, _Json> {
  _Act(this.id, this.body);
  final String id;
  final FutureOr<JsonMap> Function(JsonMap input) body;

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
  Future<Outcome<_Json>> run(_Json input, h.Invocation invocation) async {
    try {
      return Completed(_Json(await body(input.value)));
    } on Failure catch (f) {
      return Failed(f);
    }
  }
}

final class _Cap implements Capability {
  _Cap(this.actions);
  @override
  final List<Action> actions;
}

/// Accounts, a work's identities and what each account holds, as small as
/// the tests need.
final class _World {
  final signedIn = {'bangumi': true, 'dandanplay': true};
  final bindings = <JsonMap>[];

  /// provider → workId → the account's `result`, or a [Failure] to fail.
  final held = <String, Map<int, Object>>{'bangumi': {}, 'dandanplay': {}};

  /// provider → the batch row for an update, when it is not completed.
  final refuse = <String, Object>{};

  /// provider → items, when `accounts.collections.list` exists.
  Map<String, List<JsonMap>>? listed;
  final calls = <(String, JsonMap)>[];

  void bind(String entityId, String provider, Object externalId,
          {String status = 'accepted'}) =>
      bindings.add({
        'entityId': entityId,
        'provider': provider,
        'externalId': '$externalId',
        'status': status,
      });

  JsonMap _query(JsonMap input) {
    final filter = input['filter'] as Map;
    bool matches(JsonMap row) => filter.entries.every((e) {
          final p = e.value as Map;
          final v = '${row[e.key]}';
          if (p.containsKey('eq')) return v == '${p['eq']}';
          return (p['in'] as List).map((x) => '$x').contains(v);
        });
    return {'rows': bindings.where(matches).toList()};
  }

  GuiCalls get gui => GuiCalls(() async => Harness([
        _Cap([
          _Act('accounts.status', (input) {
            calls.add(('accounts.status', input));
            return {
              'accounts': [
                for (final e in signedIn.entries)
                  {'provider': e.key, 'loggedIn': e.value}
              ]
            };
          }),
          _Act('state.query', (input) {
            calls.add(('state.query', input));
            return _query(input);
          }),
          _Act('accounts.collections.get', (input) {
            calls.add(('accounts.collections.get', input));
            final provider = input['provider'] as String;
            final id = (input['workIds'] as List).single as int;
            final value = held[provider]![id];
            if (value is Failure) throw value;
            if (value == 'failed') {
              return {
                'results': [
                  {
                    'index': 0,
                    'status': 'failed',
                    'error': {'code': 'unavailable', 'message': 'down'}
                  }
                ]
              };
            }
            return {
              'results': [
                {
                  'index': 0,
                  'status': 'completed',
                  'result': value ?? {'collection': null}
                }
              ]
            };
          }),
          _Act('accounts.collections.update', (input) {
            calls.add(('accounts.collections.update', input));
            final refused = refuse[input['provider']];
            if (refused is Failure) throw refused;
            return {
              'results': [
                {
                  'index': 0,
                  'status': refused == null ? 'completed' : 'failed',
                }
              ]
            };
          }),
          if (listed case final listed?)
            _Act('accounts.collections.list', (input) {
              calls.add(('accounts.collections.list', input));
              final provider = input['provider'] as String;
              final wanted = (input['statuses'] as List).cast<String>();
              return {
                'items': [
                  for (final item in listed[provider] ?? const <JsonMap>[])
                    if (wanted.contains(item['status'])) item
                ]
              };
            }),
        ])
      ]));

  List<JsonMap> updates() => [
        for (final (action, input) in calls)
          if (action == 'accounts.collections.update') input
      ];
}

void main() {
  group('UiWatchStatus', () {
    test('reads both accounts’ words and numbers', () {
      expect(UiWatchStatus.read('bangumi', 1), UiWatchStatus.wish);
      expect(UiWatchStatus.read('bangumi', 2), UiWatchStatus.done);
      expect(UiWatchStatus.read('bangumi', 3), UiWatchStatus.doing);
      expect(UiWatchStatus.read('bangumi', 4), UiWatchStatus.onHold);
      expect(UiWatchStatus.read('bangumi', 5), UiWatchStatus.dropped);
      for (final s in UiWatchStatus.values) {
        expect(UiWatchStatus.read('bangumi', s.name), s);
      }
      expect(UiWatchStatus.read('bangumi', 6), isNull);
      expect(
          UiWatchStatus.read('dandanplay', 'favorited'), UiWatchStatus.doing);
      expect(UiWatchStatus.read('dandanplay', 'finished'), UiWatchStatus.done);
      expect(
          UiWatchStatus.read('dandanplay', 'abandoned'), UiWatchStatus.dropped);
      expect(UiWatchStatus.read('dandanplay', 'wish'), isNull);
      expect(UiWatchStatus.read('dandanplay', null), isNull);
    });

    test('writes 弹弹play’s three, Bangumi’s five', () {
      for (final s in UiWatchStatus.values) {
        expect(s.on('bangumi'), s.name);
      }
      expect({
        for (final s in UiWatchStatus.values) s: s.on('dandanplay')
      }, {
        UiWatchStatus.doing: 'favorited',
        UiWatchStatus.wish: 'favorited',
        UiWatchStatus.done: 'finished',
        UiWatchStatus.onHold: 'favorited',
        UiWatchStatus.dropped: 'abandoned',
      });
      // What is written reads back as itself on Bangumi, and as one of the
      // three on 弹弹play.
      for (final s in UiWatchStatus.values) {
        expect(UiWatchStatus.read('bangumi', s.on('bangumi')), s);
        expect(
            UiWatchStatus.read('dandanplay', s.on('dandanplay')),
            isIn([
              UiWatchStatus.doing,
              UiWatchStatus.done,
              UiWatchStatus.dropped
            ]));
      }
    });

    test('lists only what reads as itself', () {
      for (final s in UiWatchStatus.values) {
        expect(s.all('bangumi'), [s.name]);
      }
      expect(UiWatchStatus.doing.all('dandanplay'), ['favorited']);
      expect(UiWatchStatus.done.all('dandanplay'), ['finished']);
      expect(UiWatchStatus.dropped.all('dandanplay'), ['abandoned']);
      expect(UiWatchStatus.wish.all('dandanplay'), isEmpty);
      expect(UiWatchStatus.onHold.all('dandanplay'), isEmpty);
      for (final s in UiWatchStatus.values) {
        for (final value in s.all('dandanplay')) {
          expect(UiWatchStatus.read('dandanplay', value), s);
        }
      }
    });
  });

  group('NextCollections.of', () {
    test('reads signed-in accounts and leaves the others unread', () async {
      final w = _World()
        ..signedIn['bangumi'] = false
        ..bind('w', 'bangumi', 400)
        ..bind('w', 'dandanplay', 17)
        ..bind('w', 'dandanplay', 18, status: 'rejected');
      w.held['dandanplay']![17] = {
        'collection': {'animeId': 17, 'favoriteStatus': 'finished'},
        'rating': 8,
      };
      final c = await NextCollections(w.gui).of('w');
      final bangumi = c.links.singleWhere((l) => l.provider == 'bangumi');
      final dandan = c.links.singleWhere((l) => l.provider == 'dandanplay');
      expect((bangumi.id, bangumi.loggedIn, bangumi.status, bangumi.failed),
          (400, false, null, false));
      expect((dandan.id, dandan.loggedIn, dandan.status, dandan.rating),
          (17, true, UiWatchStatus.done, 8));
      expect(c.signedIn, isTrue);
      expect(c.status, UiWatchStatus.done);
      expect(c.rating, 8);
      final gets = [
        for (final (action, input) in w.calls)
          if (action == 'accounts.collections.get') input['provider']
      ];
      expect(gets, ['dandanplay']);
    });

    test('Bangumi’s standing and score come first', () async {
      final w = _World()
        ..bind('w', 'bangumi', 400)
        ..bind('w', 'dandanplay', 17);
      w.held['bangumi']![400] = {
        'collection': {'subject_id': 400, 'type': 1, 'rate': 7},
      };
      w.held['dandanplay']![17] = {
        'collection': {'animeId': 17, 'favoriteStatus': 'favorited'},
        'rating': 9,
      };
      final c = await NextCollections(w.gui).of('w');
      expect(c.status, UiWatchStatus.wish);
      expect(c.rating, 7);
    });

    test('an account that cannot be read is marked, not dropped', () async {
      final w = _World()
        ..bind('w', 'bangumi', 400)
        ..bind('w', 'dandanplay', 17);
      w.held['bangumi']![400] =
          const Failure(FailureCode.unavailable, 'Bangumi is down.');
      w.held['dandanplay']![17] = 'failed';
      final c = await NextCollections(w.gui).of('w');
      expect([for (final l in c.links) (l.provider, l.loggedIn, l.failed)],
          [('bangumi', true, true), ('dandanplay', true, true)]);
      expect(c.status, isNull);
    });

    test('a work no account knows has no links', () async {
      final w = _World()..bind('w', 'bangumi', 'not-a-number');
      final c = await NextCollections(w.gui).of('w');
      expect(c.links, isEmpty);
      expect(c.signedIn, isFalse);
    });
  });

  group('NextCollections.set', () {
    test('writes only signed-in accounts that know the work', () async {
      final w = _World()
        ..signedIn['dandanplay'] = false
        ..bind('w', 'bangumi', 400)
        ..bind('w', 'dandanplay', 17)
        ..bind('other', 'bangumi', 401);
      final collections = NextCollections(w.gui);
      final c = await collections.of('w');
      final changed = collections.changes.first;
      final failed =
          await collections.set(c, status: UiWatchStatus.onHold, rating: 7);
      await changed;
      expect(failed, isEmpty);
      expect(w.updates(), [
        {
          'provider': 'bangumi',
          'items': [
            {'workId': 400, 'status': 'onHold', 'rating': 7}
          ]
        }
      ]);
    });

    test('maps the standing for 弹弹play and keeps the one it had for a score',
        () async {
      final w = _World()..bind('w', 'dandanplay', 17);
      w.held['dandanplay']![17] = {
        'collection': {'animeId': 17, 'favoriteStatus': 'finished'},
        'rating': 0,
      };
      final collections = NextCollections(w.gui);
      final c = await collections.of('w');
      expect(await collections.set(c, status: UiWatchStatus.wish), isEmpty);
      expect(await collections.set(c, rating: 6), isEmpty);
      expect([
        for (final u in w.updates()) (u['items'] as List).single
      ], [
        {'workId': 17, 'status': 'favorited'},
        {'workId': 17, 'status': 'finished', 'rating': 6},
      ]);
    });

    test('says which accounts did not take it', () async {
      final w = _World()
        ..bind('w', 'bangumi', 400)
        ..bind('w', 'dandanplay', 17);
      w.refuse['bangumi'] = 'failed';
      w.refuse['dandanplay'] =
          const Failure(FailureCode.unavailable, '弹弹play is down.');
      final collections = NextCollections(w.gui);
      final c = await collections.of('w');
      expect(await collections.set(c, status: UiWatchStatus.doing),
          ['bangumi', 'dandanplay']);
      w.refuse.remove('bangumi');
      expect(await collections.set(c, status: UiWatchStatus.doing),
          ['dandanplay']);
    });

    test('a score without any standing is written without one', () async {
      final w = _World()..bind('w', 'bangumi', 400);
      final collections = NextCollections(w.gui);
      final c = await collections.of('w');
      await collections.set(c, rating: 9);
      expect((w.updates().single['items'] as List).single,
          {'workId': 400, 'rating': 9});
    });
  });

  group('NextCollections.works', () {
    test('is null where the accounts cannot list', () async {
      final w = _World()..bind('w', 'bangumi', 400);
      final collections = NextCollections(w.gui);
      expect(await collections.lists(), isFalse);
      expect(await collections.works(UiWatchStatus.doing), isNull);
      expect(w.calls, isEmpty);
    });

    test('lists the library’s works of a standing, in the accounts’ order',
        () async {
      final w = _World()
        ..bind('a', 'bangumi', 400)
        ..bind('b', 'bangumi', 401)
        ..bind('b', 'dandanplay', 17)
        ..bind('c', 'dandanplay', 18)
        ..listed = {
          'bangumi': [
            {'workId': 401, 'status': 'doing'},
            {'workId': 400, 'status': 'doing'},
            {'workId': 999, 'status': 'doing'},
            {'workId': 402, 'status': 'wish'},
          ],
          'dandanplay': [
            {'workId': 17, 'status': 'favorited'},
            {'workId': 18, 'status': 'favorited'},
          ],
        };
      final collections = NextCollections(w.gui);
      expect(await collections.lists(), isTrue);
      // Bangumi, signed in, decides alone: 弹弹play's “following” would
      // bring 想看 and 搁置 into 在看.
      expect(await collections.works(UiWatchStatus.doing), ['b', 'a']);
      w.calls.clear();
      expect(await collections.works(UiWatchStatus.wish), isEmpty);
      expect([
        for (final (action, input) in w.calls)
          if (action == 'accounts.collections.list') input['provider']
      ], [
        'bangumi'
      ]);
      // Without Bangumi, 弹弹play's list is the one.
      w.signedIn['bangumi'] = false;
      expect(await collections.works(UiWatchStatus.doing), ['b', 'c']);
      w.calls.clear();
      expect(await collections.works(UiWatchStatus.wish), isEmpty);
      expect(w.calls.where((c) => c.$1 == 'accounts.collections.list'),
          isEmpty);
    });
  });

  testWidgets(
      'the button shows the standing; a choice is written at once, and an '
      'account that refuses it goes back and turns red', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final w = _World()
      ..bind('w', 'bangumi', 400)
      ..bind('w', 'dandanplay', 17)
      ..bind('none', 'bangumi', 'x');
    w.held['bangumi']![400] = {
      'collection': {'subject_id': 400, 'type': 3, 'rate': 9},
    };
    final settings = FakeSettings();
    final shell =
        NextShellController(_services(w.gui, settings), onLeave: () {});
    Future<CollectionDebug> pump(String workId) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(800, 600)),
          child: NextShellScope(
            controller: shell,
            child: Overlay(key: ValueKey(workId), initialEntries: [
              OverlayEntry(
                builder: (_) => Align(
                  alignment: Alignment.topLeft,
                  child: CollectionButton(
                      work: UiWork(workId: workId, title: workId)),
                ),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return tester.state(find.byType(CollectionButton)) as CollectionDebug;
    }

    // No account knows it: nothing shows.
    var button = await pump('none');
    expect(button.debugStatus()['shown'], isFalse);
    expect(find.byType(OverlayPortal), findsNothing);

    button = await pump('w');
    expect(find.text('在看'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);

    await tester.tap(find.text('在看'));
    await tester.pumpAndSettle();
    expect(button.debugStatus()['open'], isTrue);
    expect(find.text('弹弹play'), findsOneWidget);
    expect(find.text('Bangumi'), findsOneWidget);

    // Shown before the accounts answer, written to both.
    await tester.tap(find.text('看过'));
    await tester.pump();
    expect(button.debugStatus()['status'], 'done');
    await tester.pumpAndSettle();
    expect([
      for (final u in w.updates()) (u['items'] as List).single
    ], [
      {'workId': 400, 'status': 'done'},
      {'workId': 17, 'status': 'finished'},
    ]);

    // 弹弹play does not take it: it goes back, red; Bangumi keeps it.
    w.calls.clear();
    w.refuse['dandanplay'] = 'failed';
    await button.debug({'rating': '6'});
    await tester.pumpAndSettle();
    expect([
      for (final u in w.updates()) (u['items'] as List).single
    ], [
      {'workId': 400, 'status': 'done', 'rating': 6},
      {'workId': 17, 'status': 'finished', 'rating': 6},
    ]);
    expect(button.debugStatus()['links'], [
      {
        'provider': 'bangumi',
        'loggedIn': true,
        'status': 'done',
        'rating': 6,
        'failed': false
      },
      {
        'provider': 'dandanplay',
        'loggedIn': true,
        'status': 'done',
        'rating': null,
        'failed': true
      },
    ]);
    expect(button.debugStatus()['rating'], 6);

    // Esc puts the panel away.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(button.debugStatus()['open'], isFalse);

    // Signed out of Bangumi: its mark offers the login window, and the
    // work is read again once signed in.
    w.signedIn['bangumi'] = false;
    await settings.logout('bangumi');
    await tester.pumpAndSettle();
    await button.debug({'open': 'true'});
    await tester.pumpAndSettle();
    expect(find.text('登录'), findsOneWidget);
    w.signedIn['bangumi'] = true;
    await tester.tap(find.text('登录'));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(button.debugStatus()['signing'], isEmpty);
    expect(button.debugStatus()['links'],
        everyElement(containsPair('loggedIn', true)));

    await tester.pumpWidget(const SizedBox());
    shell.dispose();
  });
}

NextUiServices _services(GuiCalls calls, FakeSettings settings) {
  final unused = _Unused();
  return NextUiServices(
    data: _Data(),
    actions: unused,
    chat: _Port(),
    discover: unused,
    library: unused,
    libraryActions: unused,
    search: _Search(),
    settings: settings,
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

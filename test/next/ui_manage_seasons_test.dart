import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Material, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/ui/data/batch_manage.dart';
import 'package:nipaplay/next/ui/data/core_manage.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/data/work_owners.dart';
import 'package:nipaplay/next/ui/detail/manage_work.dart';
import 'package:nipaplay/next/ui/settings/controls.dart' show PillButton;
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'media_test_support.dart';

/// A TMDB series lists its seasons without their episodes: matching reads
/// every season as the agent does (`media.metadata.get_batch`), and pairs a
/// file with an episode only by the season and number recorded for it — an
/// episode without a season as of season 1, a special (season 0) never with
/// the regular episode of its number. What nothing fits is the viewer's.
/// A season that cannot be read is said so. A work made its own keeps its
/// episodes as they are.
void main() {
  JsonMapLike season(int n) => {
        'provider': 'tmdb',
        'objectType': 'season',
        'externalId': '${9100 + n}',
        'scope': 'tv/9001/season/$n'
      };
  JsonMapLike episodeRef(int s, int n, int id) => {
        'provider': 'tmdb',
        'objectType': 'episode',
        'externalId': '$id',
        'scope': 'tv/9001/season/$s/episode/$n'
      };
  const series = UiMatchCandidate(
      provider: UiProvider.tmdb, title: '长安十二时辰', ref: mediaWorkRef);

  /// TMDB as it answers: the series with specials, season 1 and season 2;
  /// season 1 as recorded in the fixture.
  Future<MediaFixture> tmdb({bool secondFails = false}) async {
    final f = MediaFixture();
    await f.open();
    f.tmdb.handlers['/3/tv/9001'] = (_) => {
          'id': 9001,
          'name': '长安十二时辰',
          'original_name': '长安十二时辰',
          'first_air_date': '2019-06-27',
          'seasons': [
            for (final n in [0, 1, 2])
              {
                'id': 9100 + n,
                'name': n == 0 ? '特别篇' : '第 $n 季',
                'season_number': n,
                'air_date': '2019-06-27'
              }
          ]
        };
    f.tmdb.handlers['/3/tv/9001/season/0'] = (_) => {
          'id': 9100,
          'name': '特别篇',
          'season_number': 0,
          'episodes': [
            {
              'id': 9501,
              'name': '幕后',
              'season_number': 0,
              'episode_number': 1
            }
          ]
        };
    f.tmdb.handlers['/3/tv/9001/season/2'] = (_) {
      if (secondFails) {
        throw const h.Failure(h.FailureCode.unavailable, 'TMDB is busy.');
      }
      return {
        'id': 9102,
        'name': '第 2 季',
        'season_number': 2,
        'episodes': [
          for (final n in [1, 2])
            {
              'id': 9600 + n,
              'name': '续$n',
              'season_number': 2,
              'episode_number': n
            }
        ]
      };
    };
    return f;
  }

  group('catalogue', () {
    test('a TMDB series\' episodes are read season by season, in one call',
        () async {
      final f = await tmdb();
      addTearDown(f.close);
      final manage = CoreWorkManage(() => f.harness, _Data(const []));

      final episodes = await manage.candidateEpisodes(series);
      expect([for (final e in episodes) e.label], [
        '第 1 季 第 1 集  第一集',
        '第 1 季 第 2 集  第二集',
        '第 2 季 第 1 集  续1',
        '第 2 季 第 2 集  续2',
        '特别篇 1  幕后',
      ]);
      expect([for (final e in episodes) (e.season, e.number)],
          [(1, '1'), (1, '2'), (2, '1'), (2, '2'), (0, '1')]);
      expect([for (final e in episodes) e.release], [
        season(1),
        season(1),
        season(2),
        season(2),
        season(0),
      ]);
      expect(episodes[2].ref, episodeRef(2, 1, 9601));
      expect([for (final r in f.tmdb.requests) r['path']], [
        '/3/tv/9001',
        '/3/tv/9001/season/0',
        '/3/tv/9001/season/1',
        '/3/tv/9001/season/2',
      ]);
    });

    test('of one season, the season goes unsaid', () async {
      final f = MediaFixture();
      await f.open();
      addTearDown(f.close);
      final manage = CoreWorkManage(() => f.harness, _Data(const []));
      final episodes = await manage.candidateEpisodes(series);
      expect([for (final e in episodes) e.label],
          ['第 1 集  第一集', '第 2 集  第二集']);
      expect(episodes.first.release, mediaReleaseRef);
    });

    test('a season that cannot be read fails the whole, not shown as empty',
        () async {
      final f = await tmdb(secondFails: true);
      addTearDown(f.close);
      final manage = CoreWorkManage(() => f.harness, _Data(const []));
      await expectLater(
          manage.candidateEpisodes(series), throwsA(isA<UiManageError>()));
    });

    test('a file is matched to an episode of another season, as previewed',
        () async {
      final f = await tmdb();
      addTearDown(f.close);
      final file = await f.file('s2e1.mkv');
      final taken = (await f.call('media.identity.bind_batch', {
        'requestId': 'taken-as-season-1',
        'entries': [tmdbBinding(file)]
      }))['entries'] as List;
      final workId = (taken.single as Map)['workId'] as String;
      final episodeId =
          ((taken.single as Map)['episodeIds'] as List).single as String;
      final harness = h.Harness([
        MediaCapability(f.service),
        _Cap({
          'media.management.targets': (_) => {
                'entries': [
                  {
                    'workId': workId,
                    'targets': [
                      {
                        'deviceId': 'fixture-device',
                        'workId': workId,
                        'local': true,
                        'online': true,
                        'episodes': [
                          {'episodeId': episodeId, 'mergedEpisodeId': episodeId}
                        ],
                      }
                    ],
                  }
                ]
              },
          'media.metadata.ui_facts': (_) => {
                'fields': {
                  'title': {'value': '长安十二时辰'}
                },
                'episodes': {
                  'items': [
                    {'episodeId': episodeId, 'number': 1, 'season': 1}
                  ]
                },
              },
        }, []),
      ]);
      final manage = CoreWorkManage(() => harness, _Data(const []));
      final work = await manage.work(UiWork(workId: workId, title: '长安十二时辰'));
      final to = (await manage.candidateEpisodes(series))
          .singleWhere((e) => e.season == 2 && e.number == '1');

      final plan = await manage.previewMatch(work, series, {work.files.single: to});
      expect(plan.files, 1);
      await plan.apply();
      final identity = (await f.call('media.identity.get', {'entityId': file}))[
          'identity'] as Map;
      expect([
        for (final b in (identity['bindings'] as List).cast<Map>())
          if (b['status'] == 'accepted') b['ref']
      ], [
        episodeRef(2, 1, 9601)
      ]);
    });
  });

  group('pairing', () {
    UiCandidateEpisode c(int? s, String n) => UiCandidateEpisode(
        number: n, season: s, ref: {'s': s, 'n': n}, seasons: s != null);
    final catalogue = [
      for (final n in ['1', '2', '3']) c(1, n),
      for (final n in ['1', '2']) c(2, n),
      c(0, '1'),
      c(0, '3'),
    ];
    String? pair(int? s, String n, [List<UiCandidateEpisode>? from]) {
      final e = uiPairEpisode(from ?? catalogue, s, n);
      return e == null ? null : '${e.season}/${e.number}';
    }

    test('by season and number together', () {
      expect(pair(1, '3'), '1/3');
      expect(pair(2, '1'), '2/1');
      expect(pair(2, '02'), '2/2');
    });

    test('a special and the episode of its number are never confused', () {
      expect(pair(0, '3'), '0/3');
      expect(pair(1, '3'), '1/3');
      expect(pair(0, '2'), isNull);
    });

    test('a number without a season is of season 1', () {
      expect(pair(null, '2'), '1/2');
      expect(pair(null, '3'), '1/3');
    });

    test('what nothing fits, or more than one could, is not paired', () {
      expect(pair(3, '1'), isNull);
      expect(pair(2, '3'), isNull);
      expect(pair(1, ''), isNull);
      expect(pair(null, ''), isNull);
      final plain = [c(null, '1'), c(null, '2'), c(null, 'SP1')];
      expect(pair(null, '1', plain), 'null/1');
      expect(pair(2, '2', plain), 'null/2');
      expect(pair(null, 'SP1', plain), 'null/SP1');
      // A catalogue without seasons cannot say which of its own is special.
      expect(pair(0, '1', plain), isNull);
      expect(pair(null, '1', [c(null, '1'), c(null, '01')]), isNull);
      expect(
          pair(null, '1',
              [const UiCandidateEpisode.film({'film': true})]),
          isNull);
    });

    test('labels say the season only among several', () {
      expect(c(2, '3').label, '第 2 季 第 3 集');
      expect(c(0, '3').label, '特别篇 3');
      expect(
          const UiCandidateEpisode(
                  number: '3', season: 1, title: '苍月草', ref: {})
              .label,
          '第 3 集  苍月草');
      expect(const UiCandidateEpisode.film({}).label, '正片');
    });
  });

  group('sheet', () {
    const a = UiFile(path: '/m/a.mkv'),
        b = UiFile(path: '/m/b.mkv'),
        c = UiFile(path: '/m/c.mkv'),
        d = UiFile(path: '/m/d.mkv'),
        e = UiFile(path: '/m/e.mkv'),
        f = UiFile(path: '/m/f.mkv');
    final episodes = [
      const UiManagedEpisode(number: '1', season: 1, files: [a]),
      const UiManagedEpisode(number: '1', season: 0, files: [b]),
      const UiManagedEpisode(number: '1', season: 2, files: [c]),
      const UiManagedEpisode(number: '2', files: [d]),
      const UiManagedEpisode(number: '', season: 1, files: [e]),
      const UiManagedEpisode(number: '1', season: 3, files: [f]),
    ];

    Future<_Seasons> open(WidgetTester tester, _Seasons manage,
        {WorkSection section = WorkSection.match, bool film = false}) async {
      tester.view
        ..physicalSize = const Size(900, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(WorkManageSheet(
        work: UiWork(workId: 'w', title: '作品', film: film),
        manage: manage,
        section: section,
        onClose: () {},
        onChanged: () {},
        onReplaced: (_) {},
        onRemoved: (_) {},
      )));
      await tester.pumpAndSettle();
      if (section != WorkSection.match) return manage;
      await tester.enterText(find.byType(TextField), 'query');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('长安十二时辰'));
      await tester.pumpAndSettle();
      return manage;
    }

    Finder pill(String label) =>
        find.byWidgetPredicate((w) => w is PillButton && w.label == label);
    VoidCallback? onTap(WidgetTester tester) =>
        tester.widget<PillButton>(pill('匹配')).onTap;

    testWidgets(
        'each file is the episode of its season and number; '
        'what nothing fits is chosen', (tester) async {
      final manage = await open(tester, _Seasons(episodes));
      expect(find.text('第 1 季 第 1 集  一'), findsOneWidget);
      expect(find.text('特别篇 1  特一'), findsOneWidget);
      expect(find.text('第 2 季 第 1 集  甲'), findsOneWidget);
      expect(find.text('第 1 季 第 2 集  二'), findsOneWidget);
      expect(find.text('选择'), findsNWidgets(2));
      expect(onTap(tester), isNull);

      await tester.tap(find.text('选择').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 2 季 第 2 集  乙'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('特别篇 2  特二'));
      await tester.pumpAndSettle();
      expect(find.text('选择'), findsNothing);
      expect(onTap(tester), isNotNull);

      await tester.tap(pill('匹配'));
      await tester.pumpAndSettle();
      expect({
        for (final MapEntry(key: f, value: e) in manage.previewed!.entries)
          f.name: (e.season, e.number, e.release?['scope'])
      }, {
        'a.mkv': (1, '1', 'tv/9001/season/1'),
        'b.mkv': (0, '1', 'tv/9001/season/0'),
        'c.mkv': (2, '1', 'tv/9001/season/2'),
        'd.mkv': (1, '2', 'tv/9001/season/1'),
        'e.mkv': (2, '2', 'tv/9001/season/2'),
        'f.mkv': (0, '2', 'tv/9001/season/0'),
      });
    });

    testWidgets('episodes that cannot be read are said so', (tester) async {
      await open(tester, _Seasons(episodes)..fails = true);
      expect(find.text('暂时读不到'), findsOneWidget);
      expect(find.text('选择'), findsNothing);
      expect(pill('匹配'), findsNothing);
    });

    testWidgets('a matched episode shows which of the seasons it is',
        (tester) async {
      await open(tester, _Seasons(episodes.sublist(0, 3), matched: true),
          section: WorkSection.episodes);
      expect(find.text('第 1 季 第 1 集'), findsOneWidget);
      expect(find.text('特别篇 1'), findsOneWidget);
      expect(find.text('第 2 季 第 1 集'), findsOneWidget);
      expect(find.text('01'), findsNWidgets(3));
    });

    testWidgets('a film\'s one episode goes without a number', (tester) async {
      await open(
          tester,
          _Seasons(const [
            UiManagedEpisode(number: '1', title: '数字 86', files: [a])
          ], matched: true, film: true),
          section: WorkSection.episodes,
          film: true);
      expect(find.text('01'), findsNothing);
      expect(find.text('第 1 集'), findsNothing);
    });
  });

  group('batch', () {
    final record = {
      'ref': mediaWorkRef,
      'kind': 'tv',
      'episodes': [
        for (final n in [0, 1, 2])
          {'ref': season(n), 'season': n, 'episodes': const []}
      ],
    };
    JsonMapLike seasonRecord(int s) => {
          'ref': season(s),
          'kind': 'season',
          'season': s,
          'episodes': [
            for (final n in [1, 2])
              {
                'ref': episodeRef(s, n, 9000 + s * 10 + n),
                'number': '$n',
                'season': s
              }
          ],
        };
    JsonMapLike file(String id, String episode) => {
          'fileId': id,
          'path': '/v/$id.mkv',
          'bindings': const [],
          'episodes': [
            {'episodeId': episode, 'relation': 'primary', 'ordinal': 0}
          ],
        };
    JsonMapLike preview(JsonMapLike input) => input['expectedPlan'] != null
        ? {'entries': const []}
        : {
            'expectedPlan': 'plan',
            'preview': {
              'diskFilesDeleted': false,
              'progressChanged': false,
              'entities': const [],
            },
          };
    final owner = WorkOwner({
      'deviceId': 'here',
      'workId': 'w',
      'local': true,
      'online': true,
      'episodes': [
        for (final n in [1, 2, 3, 4, 5]) {'episodeId': 'e$n', 'mergedEpisodeId': 'm$n'}
      ],
    }, null);
    final data = _Data(const [
      UiEpisode(episodeId: 'm1', workId: 'w', number: 1, season: 1),
      UiEpisode(episodeId: 'm2', workId: 'w', number: 1, season: 0),
      UiEpisode(episodeId: 'm3', workId: 'w', number: 2),
      UiEpisode(episodeId: 'm4', workId: 'w', number: 1, season: 2),
      UiEpisode(episodeId: 'm5', workId: 'w', number: 1, season: 3),
    ]);
    const candidate = UiBatchCandidate(title: '长安十二时辰', ref: mediaWorkRef);

    test('pairs by season and number as the sheet does; the rest stay',
        () async {
      final calls = <(String, JsonMapLike)>[];
      final batch = NextBatch(
          GuiCalls(() async => h.Harness([
                _Cap({
                  'media.metadata.get': (_) => {'record': record},
                  'media.metadata.get_batch': (input) => {
                        'results': [
                          for (final (i, ref) in (input['refs'] as List).indexed)
                            {
                              'index': i,
                              'record': seasonRecord(
                                  int.parse('${(ref as Map)['externalId']}') -
                                      9100)
                            }
                        ]
                      },
                  'media.files.list': (_) => {
                        'files': [
                          for (final n in [1, 2, 3, 4, 5]) file('f$n', 'e$n')
                        ]
                      },
                  'media.management.bind_batch': preview,
                }, calls)
              ])),
          data);
      final result = await batch.previewMatch([
        (UiBatchWork(const UiWork(workId: 'w', title: '长安'), owners: [owner]),
            candidate)
      ]);
      expect([for (final c in calls) c.$1], [
        'media.metadata.get',
        'media.metadata.get_batch',
        'media.files.list',
        'media.management.bind_batch',
      ]);
      expect(calls[1].$2['refs'], [season(0), season(1), season(2)]);
      expect([
        for (final e in (calls.last.$2['entries'] as List).cast<Map>())
          (e['entityId'], (e['releaseRef'] as Map)['scope'],
              ((e['episodeRefs'] as List).single as Map)['scope'])
      ], [
        ('f1', 'tv/9001/season/1', 'tv/9001/season/1/episode/1'),
        ('f2', 'tv/9001/season/0', 'tv/9001/season/0/episode/1'),
        ('f3', 'tv/9001/season/1', 'tv/9001/season/1/episode/2'),
        ('f4', 'tv/9001/season/2', 'tv/9001/season/2/episode/1'),
      ]);
      expect([for (final g in result.groups) (g.fitted, g.missed)], [(4, 1)]);
    });

    test('a season that cannot be read fails the preview', () async {
      final batch = NextBatch(
          GuiCalls(() async => h.Harness([
                _Cap({
                  'media.metadata.get': (_) => {'record': record},
                  'media.metadata.get_batch': (input) => {
                        'results': [
                          for (final (i, ref) in (input['refs'] as List).indexed)
                            if ((ref as Map)['externalId'] == '9102')
                              {
                                'index': i,
                                'error': const h.Failure(
                                        h.FailureCode.unavailable, 'busy')
                                    .toJson()
                              }
                            else
                              {
                                'index': i,
                                'record': seasonRecord(
                                    int.parse('${ref['externalId']}') - 9100)
                              }
                        ]
                      },
                }, [])
              ])),
          data);
      await expectLater(
          batch.previewMatch([
            (
              UiBatchWork(const UiWork(workId: 'w', title: '长安'),
                  owners: [owner]),
              candidate
            )
          ]),
          throwsA(isA<h.Failure>()
              .having((f) => f.code, 'code', h.FailureCode.unavailable)));
    });
  });

  group('a work of its own', () {
    test(
        'keeps each episode\'s number, season and title, its files together; '
        'another device\'s files stay there', () async {
      final calls = <(String, JsonMapLike)>[];
      JsonMapLike row(String fileId, String path, String episode) => {
            'fileId': fileId,
            'path': path,
            'bindings': const [],
            'episodes': [
              {'episodeId': episode, 'relation': 'primary'}
            ],
          };
      late final h.Harness harness;
      harness = h.Harness([
        _Cap({
          'media.management.targets': (_) => {
                'entries': [
                  {
                    'workId': 'w',
                    'targets': [
                      {
                        'deviceId': 'this-mac',
                        'workId': 'local-work',
                        'local': true,
                        'online': true,
                        'episodes': [
                          for (final e in ['3', 'sp', 'x'])
                            {'episodeId': 'local-$e', 'mergedEpisodeId': 'm:$e'}
                        ],
                      },
                      {
                        'deviceId': 'study',
                        'workId': 'their-work',
                        'local': false,
                        'online': true,
                        'episodes': [
                          for (final e in ['3', 'there'])
                            {'episodeId': 'their-$e', 'mergedEpisodeId': 'm:$e'}
                        ],
                      },
                    ],
                  }
                ]
              },
          'state.query': (_) => {
                'rows': [
                  {'deviceId': 'study', 'name': '书房的 Mac'}
                ]
              },
          'media.metadata.ui_facts': (_) => {
                'fields': const {},
                'episodes': {
                  'items': [
                    {
                      'episodeId': 'm:3',
                      'number': 3,
                      'season': 1,
                      'title': {'value': '苍月草'}
                    },
                    {'episodeId': 'm:sp', 'number': 1, 'season': 0},
                    {'episodeId': 'm:x'},
                    {'episodeId': 'm:there', 'number': 4, 'season': 1},
                  ]
                },
              },
          'media.identity.get': (input) => switch (input['entityId']) {
                'local-work' => {
                    'identity': {'id': 'local-work', 'bindings': const []}
                  },
                'f-3a' => {
                    'identity': {
                      'id': 'f-3a',
                      'bindings': [
                        {
                          'bindingId': 'b-3a',
                          'status': 'accepted',
                          'ref': mediaEpisodeRef(3)
                        }
                      ]
                    }
                  },
                _ => throw const h.Failure(h.FailureCode.notFound, 'none'),
              },
          'media.entities.remove_batch': (_) =>
              throw const h.Failure(h.FailureCode.invalidInput, 'not local'),
          'media.files.list': (_) => {
                'files': [
                  row('f-3a', '/m/03.mkv', 'local-3'),
                  row('f-3a', '/backup/03.mkv', 'local-3'),
                  row('f-3b', '/m/03 v2.mkv', 'local-3'),
                  row('f-sp', '/m/sp01.mkv', 'local-sp'),
                  row('f-x', '/m/extra.mkv', 'local-x'),
                ]
              },
          'study.media.identity.get': (input) => {
                'identity': {'id': input['entityId'], 'bindings': const []}
              },
          'study.media.files.list': (_) => {
                'files': [
                  row('their-3', r'D:\m\03.mkv', 'their-3'),
                  row('their-4', r'D:\m\04.mkv', 'their-there'),
                ]
              },
          'media.identity.unbind_batch': (_) => {'entries': const []},
          'media.entities.put_batch': (_) => {'entries': const []},
          'mesh.invoke': (input) async => switch (await harness.invokeJson(
                  '${input['deviceId']}.${input['action']}',
                  Map<String, Object?>.from(input['input'] as Map),
                  h.Invocation(origin: 'mesh'))) {
                h.Completed(:final value) => value.toJson(),
                h.Failed(:final failure) => throw failure,
                h.NeedsDecision() => throw StateError('decision'),
              },
        }, calls)
      ]);
      final manage = CoreWorkManage(() => harness, _Data(const []));
      final work = await manage.work(const UiWork(workId: 'w', title: '芙莉莲'));
      expect(work.kind, UiWorkKind.loose);
      calls.clear();

      await manage.createLocal(work, '芙莉莲');
      JsonMapLike sent(String action) =>
          calls.singleWhere((c) => c.$1 == action).$2;
      expect(sent('media.identity.unbind_batch')['entries'], [
        {
          'entityId': 'f-3a',
          'reason': isA<String>(),
          'bindingIds': ['b-3a']
        }
      ]);
      final entries =
          (sent('media.entities.put_batch')['entries'] as List).cast<Map>();
      expect([for (final e in entries) e['kind']],
          ['work', 'release', 'episode', 'episode', 'episode']);
      expect([
        for (final e in entries.skip(2))
          {for (final k in e.keys) if (k != 'entityId' && k != 'parentId') k: e[k]}
      ], [
        {
          'kind': 'episode',
          'title': '苍月草',
          'number': '3',
          'season': 1,
          'fileIds': ['f-3a', 'f-3b'],
        },
        {
          'kind': 'episode',
          'title': 'sp01',
          'number': '1',
          'season': 0,
          'fileIds': ['f-sp'],
        },
        {
          'kind': 'episode',
          'title': 'extra',
          'fileIds': ['f-x'],
        },
      ]);
      expect({for (final e in entries.skip(2)) e['parentId']},
          {entries[1]['entityId']});
      expect(calls.where((c) => c.$1 == 'mesh.invoke'), isEmpty);
    });
  });
}

typedef JsonMapLike = Map<String, Object?>;

Widget _app(Widget child) => MaterialApp(
      home: Material(
        color: const Color(0xFF08080B),
        child: Center(child: SizedBox(width: 468, height: 760, child: child)),
      ),
    );

final class _Data implements NextUiData {
  _Data(this.shown);
  final List<UiEpisode> shown;

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      shown;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The sheet's NipaPlay: a work of [episodes], a series of two seasons and
/// specials as `media.metadata.get_batch` would give them, and what was
/// previewed.
final class _Seasons implements NextWorkManage {
  _Seasons(this.episodes, {this.matched = false, this.film = false});
  final List<UiManagedEpisode> episodes;
  final bool matched;

  /// Matched to a film: its one episode is the film itself.
  final bool film;
  bool fails = false;
  Map<UiFile, UiCandidateEpisode>? previewed;

  static const _series = UiMatchCandidate(
      provider: UiProvider.tmdb, title: '长安十二时辰', ref: mediaWorkRef);

  @override
  Future<UiManagedWork> work(UiWork work) async => UiManagedWork(
      work: work,
      kind: matched ? UiWorkKind.matched : UiWorkKind.loose,
      match: matched
          ? const UiMatch(
              provider: UiProvider.tmdb, title: '长安十二时辰', candidate: _series)
          : null,
      episodes: episodes);

  @override
  Future<List<UiMatchCandidate>> search(
          UiProvider provider, String query) async =>
      const [_series];

  @override
  Future<List<UiCandidateEpisode>> candidateEpisodes(
      UiMatchCandidate candidate) async {
    if (fails) throw const UiManageError(message: 'busy');
    if (film) return [UiCandidateEpisode.film(candidate.ref)];
    const titles = {
      0: ['特一', '特二'],
      1: ['一', '二'],
      2: ['甲', '乙'],
    };
    return candidateEpisodesOf({
      'ref': candidate.ref,
      'kind': 'tv',
      'episodes': [
        for (final MapEntry(key: s, value: names) in titles.entries)
          {
            'ref': {
              'provider': 'tmdb',
              'objectType': 'season',
              'externalId': '${9100 + s}',
              'scope': 'tv/9001/season/$s'
            },
            'season': s,
            'episodes': [
              for (final (i, name) in names.indexed)
                {
                  'ref': {
                    'provider': 'tmdb',
                    'objectType': 'episode',
                    'externalId': '$s-${i + 1}',
                    'scope': 'tv/9001/season/$s/episode/${i + 1}'
                  },
                  'number': '${i + 1}',
                  'season': s,
                  'title': name
                }
            ]
          }
      ]
    });
  }

  @override
  Future<UiAssociation> previewMatch(UiManagedWork work,
      UiMatchCandidate candidate, Map<UiFile, UiCandidateEpisode> files) async {
    previewed = files;
    return UiAssociation(
        works: [candidate.title], files: files.length, apply: () async {});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Json implements h.JsonEncodable {
  const _Json(this.value);
  final h.JsonMap value;
  @override
  h.JsonMap toJson() => value;
}

final class _Act extends h.Action<_Json, _Json> {
  _Act(this.id, this.calls, this.body);
  final String id;
  final List<(String, JsonMapLike)> calls;
  final FutureOr<JsonMapLike> Function(JsonMapLike input) body;

  @override
  h.ActionSpec get spec => h.ActionSpec(
        id: id,
        title: id,
        description: id,
        effect: h.Effect.write,
        input: const h.ObjectSchema({}, additionalProperties: true),
        output: const h.ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(h.JsonMap json) => _Json(json);

  @override
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) async {
    calls.add((id, input.value));
    try {
      return h.Completed(_Json(await body(input.value)));
    } on h.Failure catch (f) {
      return h.Failed(f);
    }
  }
}

/// Actions answering as their contracts read, each call kept.
final class _Cap implements h.Capability {
  _Cap(Map<String, FutureOr<JsonMapLike> Function(JsonMapLike)> answers,
      List<(String, JsonMapLike)> calls)
      : actions = [
          for (final MapEntry(key: id, value: body) in answers.entries)
            _Act(id, calls, body)
        ];

  @override
  final List<h.Action> actions;
}

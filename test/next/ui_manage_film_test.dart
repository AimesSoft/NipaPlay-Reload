import 'package:flutter/material.dart' show MaterialApp, Material, TextField;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/ui/data/core_manage.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/manage_sheet.dart' show ImpactCard;
import 'package:nipaplay/next/ui/detail/manage_work.dart';
import 'package:nipaplay/next/ui/settings/controls.dart' show PillButton;
import 'package:nipaplay/next/ui_data/ui_data.dart';

import 'media_test_support.dart';

/// A film has no episodes: in the work sheet it is its own one, 正片, and
/// matching a file to it sends the film's ref as the episode with no
/// release, as `media.management.bind_batch` takes it. A work of one
/// episode is the film at once; of several, which file is the film is the
/// viewer's to say. A series is matched as before.
void main() {
  const filmRef = {
    'provider': 'tmdb',
    'objectType': 'movie',
    'externalId': '9301',
    'scope': ''
  };
  const film = UiMatchCandidate(
      provider: UiProvider.tmdb, title: '数字 86', movie: true, ref: filmRef);

  group('catalogue', () {
    test('a film is its own one episode; a series\' are within its seasons',
        () {
      final [one] = candidateEpisodesOf(
          {'ref': filmRef, 'kind': 'movie', 'episodes': const []});
      expect((one.movie, one.label, one.release), (true, '正片', null));
      expect(one.ref, filmRef);

      const season = {
        'provider': 'tmdb',
        'objectType': 'season',
        'externalId': '9101',
        'scope': 'tv/9001/season/1'
      };
      final episodes = candidateEpisodesOf({
        'ref': mediaWorkRef,
        'kind': 'tv',
        'episodes': [
          {
            'ref': season,
            'number': '1',
            'episodes': [
              for (final n in [1, 2])
                {'ref': mediaEpisodeRef(n), 'number': '$n', 'title': '第$n时'}
            ]
          }
        ]
      });
      expect([for (final e in episodes) (e.movie, e.label, e.season)], [
        (false, '第 1 集  第1时', 1),
        (false, '第 2 集  第2时', 1),
      ]);
      expect([for (final e in episodes) e.release], [season, season]);
      expect([for (final e in episodes) e.ref],
          [mediaEpisodeRef(1), mediaEpisodeRef(2)]);
    });

    test(
        'a file taken for a series is matched to a film from the sheet: '
        'previewed, then applied', () async {
      final f = MediaFixture();
      await f.open();
      addTearDown(f.close);
      final file = await f.file('86.mkv');
      final taken = (await f.call('media.identity.bind_batch', {
        'requestId': 'taken-for-a-series',
        'entries': [tmdbBinding(file)]
      }))['entries'] as List;
      final workId = (taken.single as Map)['workId'] as String;
      final episodeId =
          ((taken.single as Map)['episodeIds'] as List).single as String;
      final harness = h.Harness([
        MediaCapability(f.service),
        _Where(workId: workId, episodeId: episodeId, fileId: file),
      ]);
      final manage = CoreWorkManage(
          () => harness,
          _Data([
            UiEpisode(episodeId: episodeId, workId: workId, number: 1),
          ]));

      final work = await manage.work(UiWork(workId: workId, title: '长安十二时辰'));
      expect(work.kind, UiWorkKind.matched);
      expect(work.files, hasLength(1));

      final [episode] = await manage.candidateEpisodes(film);
      expect((episode.movie, episode.label, episode.release), (true, '正片', null));

      final plan =
          await manage.previewMatch(work, film, {work.files.single: episode});
      expect(plan.files, 1);
      await plan.apply();

      final identity = (await f.call('media.identity.get', {'entityId': file}))[
          'identity'] as Map;
      expect([
        for (final b in (identity['bindings'] as List).cast<Map>())
          if (b['status'] == 'accepted') b['ref']
      ], [
        filmRef
      ]);
    });
  });

  group('sheet', () {
    const series = UiMatchCandidate(
        provider: UiProvider.tmdb,
        title: '长安十二时辰',
        ref: {
          'provider': 'tmdb',
          'objectType': 'tv',
          'externalId': '9001',
          'scope': ''
        });
    const a = UiFile(path: '/media/films/86.mkv');
    const b = UiFile(path: '/media/films/86 extras.mkv');
    const c = UiFile(path: '/backup/films/86.mkv');

    Future<_Films> open(WidgetTester tester, String pick,
        List<UiManagedEpisode> episodes) async {
      final manage = _Films(episodes, [film, series]);
      await tester.pumpWidget(_app(WorkManageSheet(
        work: const UiWork(workId: 'w', title: 'steel tears'),
        manage: manage,
        section: WorkSection.match,
        onClose: () {},
        onChanged: () {},
        onReplaced: (_) {},
        onRemoved: (_) {},
      )));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'query');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text(pick));
      await tester.pumpAndSettle();
      return manage;
    }

    Finder pill(String label) =>
        find.byWidgetPredicate((w) => w is PillButton && w.label == label);
    VoidCallback? onTap(WidgetTester tester) =>
        tester.widget<PillButton>(pill('匹配')).onTap;

    testWidgets('a work of one episode is the film at once', (tester) async {
      final manage = await open(tester, '数字 86', [
        const UiManagedEpisode(number: '1', files: [a, c]),
      ]);
      expect(find.text('文件'), findsOneWidget);
      expect(find.text('正片'), findsNWidgets(2));
      expect(onTap(tester), isNotNull);

      await tester.tap(pill('匹配'));
      await tester.pumpAndSettle();
      expect(manage.previewed!.keys, [a, c]);
      for (final e in manage.previewed!.values) {
        expect((e.movie, e.release), (true, null));
        expect(e.ref, filmRef);
      }

      await tester.tap(find.descendant(
          of: find.byType(ImpactCard), matching: pill('匹配')));
      await tester.pumpAndSettle();
      expect(manage.applied, 1);
      expect(find.text('已匹配'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('of several episodes, which file is the film is the viewer\'s',
        (tester) async {
      final manage = await open(tester, '数字 86', [
        const UiManagedEpisode(number: '1', files: [a]),
        const UiManagedEpisode(number: '2', files: [b]),
      ]);
      expect(find.text('正片'), findsNothing);
      expect(find.text('跳过'), findsNWidgets(2));
      expect(onTap(tester), isNull);

      await tester.tap(find.text('跳过').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('正片'));
      await tester.pumpAndSettle();
      expect(find.text('正片'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(onTap(tester), isNotNull);

      await tester.tap(pill('匹配'));
      await tester.pumpAndSettle();
      expect(manage.previewed!.keys, [a]);
      expect(manage.previewed![a]!.movie, isTrue);
    });

    testWidgets('a series: each file the episode of its number, as before',
        (tester) async {
      final manage = await open(tester, '长安十二时辰', [
        const UiManagedEpisode(number: '1', files: [a]),
        const UiManagedEpisode(number: '2', files: [b]),
      ]);
      expect(find.text('跳过'), findsNothing);
      expect(find.text('第 1 集  第1时'), findsOneWidget);
      expect(find.text('第 2 集  第2时'), findsOneWidget);
      expect(onTap(tester), isNotNull);

      await tester.tap(pill('匹配'));
      await tester.pumpAndSettle();
      expect({
        for (final MapEntry(key: f, value: e) in manage.previewed!.entries)
          f.name: (e.number, e.release?['objectType'])
      }, {
        '86.mkv': ('1', 'season'),
        '86 extras.mkv': ('2', 'season'),
      });
    });
  });
}

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

/// The sheet's NipaPlay: a loose work of [episodes], the candidates'
/// records as `media.metadata.get` gives them, and what was previewed.
final class _Films implements NextWorkManage {
  _Films(this.episodes, this.found);
  final List<UiManagedEpisode> episodes;
  final List<UiMatchCandidate> found;
  Map<UiFile, UiCandidateEpisode>? previewed;
  int applied = 0;

  @override
  Future<UiManagedWork> work(UiWork work) async =>
      UiManagedWork(work: work, kind: UiWorkKind.loose, episodes: episodes);

  @override
  Future<List<UiMatchCandidate>> search(
          UiProvider provider, String query) async =>
      found;

  @override
  Future<List<UiCandidateEpisode>> candidateEpisodes(
          UiMatchCandidate candidate) async =>
      candidateEpisodesOf(candidate.movie
          ? {'ref': candidate.ref, 'kind': 'movie', 'episodes': const []}
          : {
              'ref': candidate.ref,
              'kind': 'tv',
              'episodes': [
                {
                  'ref': mediaReleaseRef,
                  'number': '1',
                  'episodes': [
                    for (final n in [1, 2])
                      {
                        'ref': mediaEpisodeRef(n),
                        'number': '$n',
                        'title': '第$n时'
                      }
                  ]
                }
              ]
            });

  @override
  Future<UiAssociation> previewMatch(UiManagedWork work,
      UiMatchCandidate candidate, Map<UiFile, UiCandidateEpisode> files) async {
    previewed = files;
    return UiAssociation(
        works: [candidate.title],
        files: files.length,
        apply: () async => applied++);
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

final class _Action extends h.Action<_Json, _Json> {
  _Action(this.id, this.answer);
  final String id;
  final h.JsonMap Function(h.JsonMap input) answer;

  @override
  h.ActionSpec get spec => h.ActionSpec(
        id: id,
        title: id,
        description: id,
        effect: h.Effect.read,
        input: const h.ObjectSchema({}, additionalProperties: true),
        output: const h.ObjectSchema({}, additionalProperties: true),
      );

  @override
  _Json decodeInput(h.JsonMap json) => _Json(json);

  @override
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) async =>
      h.Completed(_Json(answer(input.value)));
}

/// What the merged library would say of the work: this device has it, its
/// episode is its own, and the episode's number.
final class _Where implements h.Capability {
  _Where(
      {required this.workId, required this.episodeId, required this.fileId});
  final String workId, episodeId, fileId;

  @override
  late final List<h.Action> actions = [
    _Action(
        'media.management.targets',
        (input) => {
              'entries': [
                {
                  'workId': workId,
                  'targets': [
                    {
                      'deviceId': 'fixture-device',
                      'workId': workId,
                      'local': true,
                      'online': true,
                      'reason': null,
                      'episodes': [
                        {
                          'episodeId': episodeId,
                          'mergedEpisodeId': episodeId,
                          'fileIds': [fileId]
                        }
                      ],
                    }
                  ],
                }
              ]
            }),
    _Action(
        'media.metadata.ui_facts',
        (input) => {
              'workId': workId,
              'fields': {
                'title': {'value': '长安十二时辰'}
              },
              'episodes': {
                'items': [
                  {
                    'episodeId': episodeId,
                    'number': 1,
                    'season': 1,
                    'title': {'value': '巳正'}
                  }
                ]
              },
            }),
  ];
}

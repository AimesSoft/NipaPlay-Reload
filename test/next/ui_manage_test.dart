import 'package:flutter/material.dart' show MaterialApp, Material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/ui/data/core_manage.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/manage_episode.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// The management sheets ask NipaPlay through the same Actions as the
/// agent, as the person (`gui`), on the device that has the work (its own
/// IDs, through `mesh.invoke` when it is another), and never delete before
/// the viewer said so: a NeedsDecision becomes a question; only its answer
/// runs the option NipaPlay offered. Matches change only as previewed.
void main() {
  const work = UiWork(workId: 'mesh-work:1', title: '葬送的芙莉莲');
  const episode = UiEpisode(
      episodeId: 'mesh-episode:3',
      workId: 'mesh-work:1',
      number: 3,
      playable: true);

  group('CoreWorkManage', () {
    test('a file is deleted only by the option of NipaPlay’s question',
        () async {
      final world = _World(elsewhere: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final places = (await manage.episode(work, episode)).locations;
      world.calls.clear();

      final confirm = await manage.deleteFile(places.first);
      expect(confirm.items, ['03.mkv']);
      expect(world.ids, ['media.mesh_files.delete']);
      expect(world.calls.single.$2, {
        'paths': ['/media/frieren/03.mkv']
      });
      await confirm.run();
      expect(world.ids, ['media.mesh_files.delete', 'media.mesh_files.confirm']);
      expect(world.calls.last.$2, {'decisionId': 'decision-1'});

      await manage.deleteFile(places.last);
      expect(world.calls.last.$2, {
        'paths': [r'D:\Anime\03.mkv'],
        'deviceId': 'study-mac'
      });
      expect(world.origins, everyElement('gui'));
    });

    test('a changed file refuses the answer as a conflict', () async {
      final world = _World()..confirmFails = true;
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.episode(work, episode);
      final confirm = await manage.deleteFile(managed.locations.first);
      await expectLater(
          confirm.run(),
          throwsA(isA<UiManageError>()
              .having((e) => e.conflict, 'conflict', isTrue)));
    });

    test('subtitle copies: the question, then its own call', () async {
      final world = _World();
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.episode(work, episode);
      world.calls.clear();
      final confirm =
          await manage.deleteSubtitleCopies(managed.subtitles.single);
      expect(confirm.items, ['a.ass']);
      expect(world.ids, ['subtitle.copy_delete']);
      await confirm.run();
      expect(world.calls.last.$2, containsPair('confirm', true));
      expect(world.calls.last.$2, containsPair('expectedFingerprint', 'fp'));
    });

    test('an episode is read on each device with its own IDs', () async {
      final world = _World(elsewhere: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.episode(work, episode);

      expect(world.calls.first.$2, {
        'workIds': ['mesh-work:1']
      });
      expect(world.remote, [
        ['study-mac', 'media.files.list', {'workId': 'their-work'}]
      ]);
      expect([for (final f in managed.locations) (f.device, f.path)], [
        (null, '/media/frieren/03.mkv'),
        (null, '/backup/frieren/03.mkv'),
        ('书房的 Mac', r'D:\Anime\03.mkv'),
      ]);
      expect(managed.locations.last.manager, UiFileManager.explorer);
      expect(managed.files.single.size, 1200);
      expect(managed.device, isNull);
      expect([for (final t in managed.danmaku) t.source], ['弹弹play', 'B 站']);
      expect(managed.subtitles.single.tracks.single.language, 'zh-Hans');

      await manage.setDanmaku(managed.danmaku.first, enabled: false);
      expect(world.calls.last.$2, {
        'changes': [
          {'bindingId': 'b-1', 'expectedRevision': 4, 'enabled': false}
        ]
      });
      await manage.setDanmaku(managed.danmaku.last,
          offset: const Duration(milliseconds: 1500));
      expect(world.calls.last.$2, {
        'changes': [
          {'trackId': 'next:bilibili', 'offsetMs': 1500}
        ]
      });
    });

    test('files are shown by the file manager of the device they are on',
        () async {
      final world = _World(elsewhere: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final places = (await manage.episode(work, episode)).locations;
      world.calls.clear();

      await manage.reveal(places.first);
      expect(world.calls.single.$1, 'media.files.reveal');
      expect(world.calls.single.$2, {
        'paths': ['/media/frieren/03.mkv']
      });
      await manage.reveal(places.last);
      expect(world.remote.last, [
        'study-mac',
        'media.files.reveal',
        {
          'paths': [r'D:\Anime\03.mkv']
        }
      ]);

      world.revealRefused = true;
      await expectLater(
          manage.reveal(places.first), throwsA(isA<UiManageError>()));
    });

    test('a device that does not answer is said so, and not asked',
        () async {
      final world = _World(elsewhere: true, here: false, online: false);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.work(work);
      expect(managed.editable, isFalse);
      expect(managed.unavailable, '书房的 Mac 不在线');
      expect(world.remote, isEmpty);

      final one = await manage.episode(work, episode);
      expect(one.unavailable, '书房的 Mac 不在线');
      expect(one.locations, isEmpty);
      expect(world.remote, isEmpty);
    });

    test('a match is previewed, then applied with its plans', () async {
      final world = _World(matched: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.work(work);
      expect(managed.kind, UiWorkKind.matched);
      world.calls.clear();

      const candidate = UiMatchCandidate(
          provider: UiProvider.tmdb,
          title: '葬送的芙莉莲',
          ref: {
            'provider': 'tmdb',
            'objectType': 'tv',
            'externalId': '209867',
            'scope': ''
          });
      const to = UiCandidateEpisode(number: '3', ref: {
        'provider': 'tmdb',
        'objectType': 'episode',
        'externalId': '209867-3',
        'scope': 'tv/209867/season/1/episode/3'
      }, release: {
        'provider': 'tmdb',
        'objectType': 'season',
        'externalId': '209867',
        'scope': 'tv/209867/season/1'
      });
      final plan = await manage
          .previewMatch(managed, candidate, {managed.files.single: to});
      expect(world.ids, [
        'media.identity.get',
        'media.management.unbind_batch',
        'media.management.bind_batch'
      ]);
      expect(world.calls.where((c) => c.$2.containsKey('expectedPlan')),
          isEmpty);
      final unbind = world.calls[1].$2, bind = world.calls[2].$2;
      expect(unbind['entries'], [
        {
          'entityId': 'file-1',
          'reason': 'Viewer matched the work in its sheet.',
          'bindingIds': ['b-file']
        }
      ]);
      expect(bind['entries'], [
        {
          'kind': 'file',
          'reason': 'Viewer matched the work in its sheet.',
          'entityId': 'file-1',
          'workRef': candidate.ref,
          'releaseRef': to.release,
          'episodeRefs': [to.ref],
        }
      ]);
      expect([plan.works, plan.episodes, plan.files, plan.watched, plan.sources],
          [['葬送的芙莉莲'], 1, 1, 1, ['TMDB']]);

      world.calls.clear();
      await plan.apply();
      expect(world.ids, [
        'media.management.unbind_batch',
        'media.management.bind_batch',
        'media.management.bind_batch'
      ]);
      expect(world.calls[0].$2, {...unbind, 'expectedPlan': 'plan-1'});
      expect(world.calls[1].$2, bind);
      expect(world.calls[2].$2, {...bind, 'expectedPlan': 'plan-3'});
      expect(world.origins, everyElement('gui'));
    });

    test('letting go of a match that changed since its preview conflicts',
        () async {
      final world = _World(matched: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.work(work);
      world.calls.clear();
      final plan = await manage.previewUnmatch(managed);
      expect(world.calls.single.$1, 'media.management.unbind_batch');
      expect(world.calls.single.$2['entries'], [
        {
          'entityId': 'local-work',
          'reason': 'Viewer let go of the match in the work sheet.',
          'bindingIds': ['b-work']
        }
      ]);
      world.stale = true;
      await expectLater(
          plan.apply(),
          throwsA(isA<UiManageError>()
              .having((e) => e.conflict, 'conflict', isTrue)));
    });

    test('an episode title is cleared on every device that has it',
        () async {
      final world = _World(elsewhere: true);
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.work(work);
      final e = managed.episodes.single;
      expect(e.titleEdited, isTrue);
      expect([for (final f in e.files) f.device], [null, '书房的 Mac']);
      world.calls.clear();

      await manage.clearEpisodeTitle(e);
      expect(world.calls.first.$1, 'media.metadata.override_batch');
      expect(world.calls.first.$2, {
        'entries': [
          {
            'entityId': 'local-episode',
            'field': 'title',
            'value': null,
            'mode': 'clear'
          }
        ]
      });
      expect(world.remote, [
        [
          'study-mac',
          'media.metadata.override_batch',
          {
            'entries': [
              {
                'entityId': 'their-episode',
                'field': 'title',
                'value': null,
                'mode': 'clear'
              }
            ]
          }
        ]
      ]);
      expect(world.ids.last, 'media.library.refresh');
    });

    test('a work of its own: words in one batch, removal previewed, undone',
        () async {
      final world = _World();
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.work(work);
      expect(managed.kind, UiWorkKind.local);
      expect(managed.text[UiTextField.title]!.edited, isTrue);
      expect(managed.episodes.single.files.single.path, '/media/frieren/03.mkv');

      await manage.editText(managed, {
        UiTextField.title: '芙莉莲',
        UiTextField.overview: null,
      });
      expect(world.ids.where((id) => id == 'media.metadata.override_batch'),
          hasLength(1));
      expect(world.calls.last.$2, {
        'entries': [
          {'entityId': 'local-work', 'field': 'title', 'value': '芙莉莲'},
          {'entityId': 'local-work', 'field': 'overview', 'value': null},
        ]
      });

      world.calls.clear();
      final undo = await manage.removeLocal(managed);
      expect(world.ids,
          ['media.entities.remove_batch', 'media.entities.remove_batch']);
      expect(world.calls.first.$2['preview'], isTrue);
      expect(world.calls.last.$2['preview'], isFalse);
      expect(world.calls.last.$2['expectedPlan'], 'plan-1');
      await manage.restore(undo);
      expect(world.ids.last, 'media.entities.restore');
      expect(world.calls.last.$2, {'undoId': 'undo-1'});
    });
  });

  group('sheet', () {
    testWidgets('deleting a file asks first; cancelling deletes nothing',
        (tester) async {
      final manage = _Sheet();
      await tester.pumpWidget(_app(EpisodeManageSheet(
        work: work,
        episode: episode,
        manage: manage,
        section: EpisodeSection.files,
        onClose: () {},
        onChanged: () {},
        onBlockWords: () {},
        onEpisodes: () {},
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      expect(find.text('从磁盘删除？'), findsOneWidget);
      expect(find.text('03.mkv'), findsWidgets);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('从磁盘删除？'), findsNothing);
      expect(manage.deleted, 0);

      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(manage.deleted, 1);
      expect(find.text('从磁盘删除？'), findsNothing);
      expect(find.text('已删除'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a refusal is said in a word', (tester) async {
      final manage = _Sheet()..refuse = true;
      await tester.pumpWidget(_app(EpisodeManageSheet(
        work: work,
        episode: episode,
        manage: manage,
        section: EpisodeSection.files,
        onClose: () {},
        onChanged: () {},
        onBlockWords: () {},
        onEpisodes: () {},
      )));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除文件'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(manage.deleted, 0);
      expect(find.text('刚刚有了变化，再试一次'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
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
  _Data({this.shown = const []});
  final List<UiEpisode> shown;

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async =>
      shown;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A sheet's NipaPlay: one file, its deletion asked about.
final class _Sheet implements NextWorkManage {
  int deleted = 0;
  bool refuse = false;
  static const _file = UiFile(path: '/media/frieren/03.mkv', size: 1200);

  @override
  Future<UiManagedEpisode> episode(UiWork work, UiEpisode episode) async =>
      UiManagedEpisode(
          number: '3',
          episode: episode,
          files: const [_file],
          locations: const [_file]);

  @override
  Future<UiConfirm> deleteFile(UiFile file) async => UiConfirm(
        items: [file.name],
        run: () async {
          if (refuse) throw const UiManageError(conflict: true);
          deleted++;
        },
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Json implements h.JsonEncodable {
  const _Json(this.value);
  final h.JsonMap value;
  @override
  h.JsonMap toJson() => value;
}

typedef _Answer = Future<h.Outcome<_Json>> Function(h.JsonMap input);

final class _Action extends h.Action<_Json, _Json> {
  _Action(this.id, this.answer);
  final String id;
  final _Answer answer;

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
  Future<h.Outcome<_Json>> run(_Json input, h.Invocation invocation) =>
      answer(input.value);
}

/// NipaPlay's Actions as their contracts read, for one work with one
/// episode: here (one file in two places) and, with [elsewhere], on the
/// study's Mac too (another file), answering through `mesh.invoke`.
final class _World implements h.Capability {
  _World(
      {this.elsewhere = false,
      this.here = true,
      this.online = true,
      this.matched = false});
  final bool elsewhere, here, online, matched;
  final calls = <(String, h.JsonMap, String)>[];
  bool confirmFails = false;
  bool stale = false;
  bool revealRefused = false;
  int _plans = 0;
  late final harness = h.Harness([this], observers: [_Origins(this)]);

  List<String> get ids => [for (final c in calls) c.$1];
  List<String> get origins => [for (final c in calls) c.$3];

  /// What was asked of the other device: where, which Action, its input.
  List<List<Object?>> get remote => [
        for (final c in calls)
          if (c.$1.startsWith('mesh.invoke'))
            [c.$2['deviceId'], c.$2['action'], c.$2['input']]
      ];

  static h.Outcome<_Json> _done(h.JsonMap value) => h.Completed(_Json(value));

  static const _ref = {
    'provider': 'tmdb',
    'objectType': 'tv',
    'externalId': '209867',
    'scope': ''
  };

  late final _entities = {
    'local-episode': {'id': 'local-episode', 'kind': 'episode', 'parentId': 'local-release', 'revision': 2},
    'local-release': {'id': 'local-release', 'kind': 'release', 'parentId': 'local-work', 'revision': 1},
    'local-work': {
      'id': 'local-work',
      'kind': 'work',
      'parentId': null,
      'revision': 3,
      'bindings': [
        if (matched)
          {'bindingId': 'b-work', 'status': 'accepted', 'ref': _ref}
      ]
    },
    'file-1': {
      'id': 'file-1',
      'kind': 'file',
      'bindings': [
        {'bindingId': 'b-file', 'status': 'accepted', 'ref': _ref}
      ]
    },
    'their-work': {'id': 'their-work', 'kind': 'work', 'bindings': const []},
  };

  static h.JsonMap _row(String fileId, String path, String episode) => {
        'fileId': fileId,
        'path': path,
        'size': 1200,
        'durationMs': 1440000,
        'modifiedAt': null,
        'bindings': const [],
        'episodes': [
          {'episodeId': episode, 'relation': 'exact'}
        ],
      };

  static const _impact = {
    'entities': [
      {
        'entity': {
          'id': 'local-work',
          'kind': 'work',
          'attributes': {'title': '葬送的芙莉莲'}
        },
        'associations': [],
        'sources': [
          {'provider': 'tmdb', 'status': 'accepted'}
        ],
        'locations': [],
        'progress': [],
      },
      {
        'entity': {'id': 'local-episode', 'kind': 'episode', 'attributes': {}},
        'associations': [],
        'sources': [],
        'locations': [],
        'progress': [],
      },
      {
        'entity': {'id': 'file-1', 'kind': 'file', 'attributes': {}},
        'associations': [],
        'sources': [
          {'provider': 'tmdb', 'status': 'withdrawn'}
        ],
        'locations': [
          {'locator': '/media/frieren/03.mkv'}
        ],
        'progress': [
          {'watchProgress': 0.4, 'lastPosition': 580000}
        ],
      },
    ],
    'diskFilesDeleted': false,
    'progressChanged': false,
  };

  late final Map<String, _Answer> _answers = {
    'media.management.targets': (input) async => _done({
          'entries': [
            {
              'workId': (input['workIds'] as List).single,
              'targets': [
                if (here)
                  {
                    'deviceId': 'this-mac',
                    'workId': 'local-work',
                    'local': true,
                    'online': true,
                    'reason': null,
                    'episodes': [
                      {
                        'episodeId': 'local-episode',
                        'mergedEpisodeId': 'mesh-episode:3',
                        'fileIds': ['file-1']
                      }
                    ],
                  },
                if (elsewhere)
                  {
                    'deviceId': 'study-mac',
                    'workId': 'their-work',
                    'local': false,
                    'online': online,
                    'reason': online ? null : 'source_device_offline',
                    'episodes': [
                      {
                        'episodeId': 'their-episode',
                        'mergedEpisodeId': 'mesh-episode:3',
                        'fileIds': ['their-file']
                      }
                    ],
                  },
              ],
            }
          ]
        }),
    'state.query': (input) async => _done({
          'rows': [
            {'deviceId': 'study-mac', 'name': '书房的 Mac', 'platform': 'windows'}
          ]
        }),
    'media.files.list': (input) async => _done({
          'files': input['workId'] == 'their-work'
              ? [_row('their-file', r'D:\Anime\03.mkv', 'their-episode')]
              : [
                  _row('file-1', '/media/frieren/03.mkv', 'local-episode'),
                  _row('file-1', '/backup/frieren/03.mkv', 'local-episode'),
                ]
        }),
    'media.files.reveal': (input) async => _done({
          'results': [
            revealRefused
                ? {
                    'index': 0,
                    'requested': false,
                    'error': {'code': 'unavailable', 'message': 'rejected'}
                  }
                : {'index': 0, 'requested': true, 'mode': 'select_file'}
          ]
        }),
    for (final op in ['bind', 'unbind'])
      'media.management.${op}_batch': (input) async {
        if (input['expectedPlan'] == null) {
          return _done({'preview': _impact, 'expectedPlan': 'plan-${++_plans}'});
        }
        return stale
            ? const h.Failed(h.Failure(h.FailureCode.conflict,
                'Association preview is stale; preview again.'))
            : _done({'entries': const []});
      },
    'media.mesh_files.delete': (input) async => h.NeedsDecision(h.Decision(
            prompt: '确认删除或覆盖这些文件',
            options: [
              h.DecisionOption(
                  label: '确认',
                  call: h.ActionCall('media.mesh_files.confirm', {
                    'decisionId': 'decision-1',
                    if (input['deviceId'] != null) 'deviceId': input['deviceId']
                  }))
            ])),
    'media.mesh_files.confirm': (input) async => confirmFails
        ? const h.Failed(h.Failure(h.FailureCode.conflict, 'changed'))
        : _done({'updated': 1}),
    'subtitle.copy_delete': (input) async => input['confirm'] == true
        ? _done({'deleted': input['paths']})
        : h.NeedsDecision(h.Decision(prompt: 'Delete', options: [
            h.DecisionOption(
                label: 'Delete copies',
                call: h.ActionCall('subtitle.copy_delete', {
                  'paths': input['paths'],
                  'confirm': true,
                  'expectedFingerprint': 'fp'
                }))
          ])),
    'media.metadata.ui_facts': (input) async => _done({
          'workId': input['workId'],
          'fields': {
            'title': {
              'value': '葬送的芙莉莲',
              'source': {'mode': 'persistent'}
            },
            'overview': {'value': null},
          },
          'episodes': {
            'items': [
              {
                'episodeId': 'mesh-episode:3',
                'number': 3,
                'season': 1,
                'title': {
                  'value': '苍月草',
                  'source': {'mode': 'persistent'}
                }
              }
            ]
          },
        }),
    'media.identity.get': (input) async {
      final entity = _entities[input['entityId']];
      return entity == null
          ? const h.Failed(h.Failure(h.FailureCode.notFound, 'Unknown entity.'))
          : _done({
              'identity': {'bindings': const [], ...entity}
            });
    },
    'media.entities.remove_batch': (input) async => input['preview'] == false
        ? _done({'undoId': 'undo-1'})
        : _done({'preview': const [], 'expectedPlan': 'plan-1'}),
    'media.entities.restore': (input) async => _done({'restored': true}),
    'media.metadata.override_batch': (input) async => _done({'atomic': true}),
    'media.library.refresh': (input) async => _done({'works': 1}),
    'danmaku.tracks': (input) async => _done({
          'tracks': input['entityId'] == 'local-episode'
              ? [
                  {'bindingId': 'b-1', 'revision': 4, 'platform': 'dandanplay', 'origin': 'binding', 'count': 3200, 'enabled': true, 'offsetMs': 0},
                ]
              : [
                  {'bindingId': null, 'trackId': 'next:bilibili', 'platform': 'bilibili', 'origin': 'playback', 'count': 900, 'enabled': true},
                ]
        }),
    'subtitle.tracks': (input) async => _done({
          'files': [
            {
              'fileId': 'file-1',
              'revision': 5,
              'tracks': [
                {'id': 'sidecar:1', 'origin': 'sidecar', 'language': 'zh-Hans', 'format': 'ass', 'available': true}
              ],
              'selection': null,
              'detachedPaths': ['/data/subtitles/a.ass'],
            }
          ]
        }),
    'danmaku.update': (input) async => _done({
          'results': [
            {'index': 0, 'status': 'completed', 'result': const {}}
          ]
        }),
  };

  /// Another device's Actions answer as this one's would.
  Future<h.Outcome<_Json>> _mesh(h.JsonMap input) => _answers[input['action']]!(
      Map<String, Object?>.from(input['input'] as Map));

  @override
  late final List<h.Action> actions = [
    for (final MapEntry(key: id, value: answer) in _answers.entries)
      _Action(id, answer),
    _Action('mesh.invoke', _mesh),
    _Action('mesh.invoke_destructive', _mesh),
  ];
}

final class _Origins implements h.InvocationObserver {
  _Origins(this.world);
  final _World world;
  @override
  void onInvocation(h.InvocationRecord record) => world.calls.add((
        record.actionId,
        Map<String, Object?>.from(record.input as Map),
        record.origin
      ));
}

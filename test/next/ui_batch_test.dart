import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' hide Invocation;
import 'package:nipa_harness/nipa_harness.dart' as h show Invocation;
import 'package:nipaplay/next/ui/data/batch_manage.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart' show UiProvider;
import 'package:nipaplay/next/ui/data/work_owners.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Act extends Action<_Json, _Json> {
  _Act(this.id, this.calls, this.body);
  final String id;
  final List<(String, JsonMap, String)> calls;
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
    calls.add((id, input.value, invocation.origin));
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

/// The library's episodes, by number.
final class _Data implements NextUiData {
  _Data(this.numbers);
  final Map<String, int> numbers;

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async => [
        for (final MapEntry(key: id, value: n) in numbers.entries)
          UiEpisode(episodeId: id, workId: workId, number: n)
      ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NextBatch _batch(List<(String, JsonMap, String)> calls,
    Map<String, FutureOr<JsonMap> Function(JsonMap)> actions,
    {Map<String, int> numbers = const {}}) {
  late final Harness harness;
  harness = Harness([
    _Cap([
      for (final MapEntry(key: id, value: body) in actions.entries)
        _Act(id, calls, body),
      // Another device's part, run against the same actions.
      _Act('mesh.invoke', calls, (input) async {
        final action = '${input['deviceId']}.${input['action']}';
        return switch (await harness.invokeJson(
            action,
            Map<String, Object?>.from(input['input'] as Map),
            h.Invocation(origin: 'mesh'))) {
          Completed(:final value) => value.toJson(),
          Failed(:final failure) => throw failure,
          NeedsDecision() => throw StateError('decision'),
        };
      }),
    ])
  ]);
  return NextBatch(GuiCalls(() async => harness), _Data(numbers));
}

JsonMap _ref(String id, [String type = 'anime']) => {
      'provider': 'dandanplay',
      'objectType': type,
      'externalId': id,
      'scope': type == 'episode' ? 'anime/7' : ''
    };

UiWork _work(String id) => UiWork(workId: id, title: '作品 $id');

/// [device]'s own [workId], with its own episodes to the merged ones.
WorkOwner _on(String device, String workId,
        [Map<String, String> episodes = const {}]) =>
    WorkOwner({
      'deviceId': device,
      'workId': workId,
      'local': device == 'here',
      'online': true,
      'episodes': [
        for (final MapEntry(key: own, value: merged) in episodes.entries)
          {'episodeId': own, 'mergedEpisodeId': merged}
      ],
    }, device == 'here' ? null : {'name': device});

UiBatchWork _picked(String id, Map<WorkOwner, List<JsonMap>> owners) =>
    UiBatchWork(_work(id), owners: owners.keys.toList(), matches: owners);

JsonMap _row(String id, String kind,
        {String? parent,
        String? title,
        List<JsonMap> associations = const [],
        List<JsonMap> sources = const [],
        List<JsonMap> progress = const []}) =>
    {
      'entity': {
        'id': id,
        'kind': kind,
        'parent_id': parent,
        'revision': 0,
        'attributes': {'title': title},
      },
      'associations': associations,
      'sources': sources,
      'locations': const [],
      'progress': progress,
    };

JsonMap _identity(String id, String kind, List<JsonMap> refs) => {
      'identity': {
        'id': id,
        'kind': kind,
        'bindings': [
          for (final ref in refs) {'status': 'accepted', 'ref': ref},
          {'status': 'revoked', 'ref': _ref('old')},
        ],
      }
    };

JsonMap _file(String id, String episode, [List<String> bindings = const []]) =>
    {
      'fileId': id,
      'path': '/v/$id.mkv',
      'bindings': [
        for (final b in bindings) {'bindingId': b, 'ref': _ref(b, 'episode')}
      ],
      'episodes': [
        {'episodeId': episode, 'relation': 'primary', 'ordinal': 0}
      ],
    };

void main() {
  test('works are read where each device has them, by its own IDs', () async {
    final calls = <(String, JsonMap, String)>[];
    final batch = _batch(calls, {
      'media.management.targets': (input) => {
            'entries': [
              for (final id in (input['workIds'] as List).cast<String>())
                switch (id) {
                  'w1' => {
                      'workId': 'w1',
                      'targets': [
                        {
                          'deviceId': 'here',
                          'workId': 'w1',
                          'local': true,
                          'online': true,
                          'episodes': const []
                        },
                        {
                          'deviceId': 'd2',
                          'workId': 'own-w1',
                          'local': false,
                          'online': true,
                          'episodes': const []
                        },
                        {
                          'deviceId': 'd3',
                          'workId': 'x',
                          'local': false,
                          'online': false,
                          'reason': 'source_device_offline',
                          'episodes': const []
                        },
                      ],
                    },
                  'e1' => {
                      'workId': 'e1',
                      'targets': [
                        {
                          'deviceId': 'here',
                          'workId': 'e1',
                          'local': true,
                          'online': true,
                          'episodes': const []
                        },
                      ],
                    },
                  _ => {
                      'workId': id,
                      'targets': const [],
                      'error': const Failure(
                              FailureCode.notFound, 'Unknown merged work.')
                          .toJson(),
                    },
                }
            ]
          },
      'state.query': (_) => {
            'rows': [
              {'deviceId': 'd2', 'name': '工作站'},
              {'deviceId': 'd3', 'name': '旧笔记本'},
            ]
          },
      'media.identity.get': (input) => switch (input['entityId']) {
            'w1' => _identity('w1', 'work', [_ref('1')]),
            _ => _identity('e1', 'episode', const []),
          },
      'd2.media.identity.get': (input) =>
          _identity(input['entityId'] as String, 'work', [_ref('2')]),
    });
    final works = await batch.read([
      _work('w1'),
      _work('e1'),
      _work('source-work:jf:1'),
      _work('gone'),
    ]);
    expect(calls.every((c) => c.$3 == (c.$1.startsWith('d') ? 'mesh' : 'gui')),
        isTrue);
    expect(calls.first.$2, {
      'workIds': ['w1', 'e1', 'gone']
    });
    expect((calls[1].$2['filter'] as Map)['deviceId'], {
      'in': ['d2', 'd3']
    });
    expect(calls.where((c) => c.$1 == 'mesh.invoke').single.$2, {
      'deviceId': 'd2',
      'action': 'media.identity.get',
      'input': {'entityId': 'own-w1'},
    });
    final [w1, e1, shared, gone] = works;
    expect([for (final o in w1.owners) (o.deviceId, o.workId, o.local, o.name)],
        [('here', 'w1', true, null), ('d2', 'own-w1', false, '工作站')]);
    expect([
      for (final o in w1.owners) w1.matches[o]
    ], [
      [_ref('1')],
      [_ref('2')],
    ]);
    expect(w1.away, ['旧笔记本不在线']);
    expect([e1, shared, gone].map((w) => w.reachable), everyElement(isFalse));
    expect([
      e1.away,
      shared.away,
      gone.away
    ], [
      isEmpty,
      ['在共享来源里'],
      ['已经不在了'],
    ]);
  });

  test('refresh asks each device for its own refs, a hundred a call', () async {
    final calls = <(String, JsonMap, String)>[];
    JsonMap refresh(JsonMap input) => {
          'atomic': false,
          'entries': [
            for (final (i, e) in (input['entries'] as List).indexed)
              if ((e as Map)['ref']['externalId'] == 'bad')
                {
                  'index': i,
                  'status': 'failed',
                  'error':
                      const Failure(FailureCode.unavailable, 'later').toJson(),
                }
              else
                {
                  'index': i,
                  'status': 'completed',
                  'result': {
                    'job': {'jobId': 'job-${e['ref']['externalId']}'}
                  },
                }
          ],
        };
    final batch = _batch(calls, {
      'media.metadata.refresh_batch': refresh,
      'd2.media.metadata.refresh_batch': refresh,
      'd3.media.metadata.refresh_batch': (_) =>
          throw const Failure(FailureCode.unavailable, 'unreachable'),
      'd2.task.get': (input) => {
            'job': {'jobId': input['jobId'], 'state': 'succeeded'}
          },
    });
    final started = await batch.refresh([
      _picked('a', {
        _on('here', 'a'): [_ref('a1'), _ref('bad')]
      }),
      for (var i = 0; i < 99; i++)
        _picked('m$i', {
          _on('here', 'm$i'): [_ref('$i')]
        }),
      _picked('r', {
        _on('d2', 'own-r'): [_ref('r1')]
      }),
      _picked('z', {
        _on('d3', 'own-z'): [_ref('z1')]
      }),
      _picked('loose', {_on('here', 'loose'): const []}),
    ]);
    List<int> sizes(String action) => [
          for (final c in calls)
            if (c.$1 == action) (c.$2['entries'] as List).length
        ];
    expect(sizes('media.metadata.refresh_batch'), [100, 1]);
    expect(sizes('d2.media.metadata.refresh_batch'), [1]);
    final entries = [
      for (final c in calls)
        if (c.$1.contains('media.metadata.refresh_batch'))
          ...(c.$2['entries'] as List).cast<Map>()
    ];
    expect(entries.first.keys, unorderedEquals(['ref', 'requestId']));
    expect(
        entries.map((e) => e['requestId']).toSet(), hasLength(entries.length));
    expect(started.keys, isNot(contains('loose')));
    expect(started['a']!.jobs.map((j) => j.jobId), ['job-a1']);
    expect(started['a']!.failure!.code, FailureCode.unavailable);
    expect(started['z']!.failure!.message, 'unreachable');
    final remote = started['r']!.jobs.single;
    expect((remote.owner.deviceId, remote.jobId), ('d2', 'job-r1'));
    expect((await batch.job(remote)).step, UiJobStep.done);
    expect(calls.lastWhere((c) => c.$1 == 'mesh.invoke').$2, {
      'deviceId': 'd2',
      'action': 'task.get',
      'input': {'jobId': 'job-r1'},
    });
  });

  test('a job reads as waiting, done or failed with its error', () async {
    final batch = _batch([], {
      'task.get': (input) => {
            'job': switch (input['jobId']) {
              'a' => {'jobId': 'a', 'state': 'running'},
              'b' => {'jobId': 'b', 'state': 'succeeded'},
              _ => {
                  'jobId': 'c',
                  'state': 'failed',
                  'error': const Failure(FailureCode.notFound, 'gone').toJson(),
                },
            }
          },
    });
    final here = _on('here', 'w');
    expect((await batch.job(UiBatchJob(here, 'a'))).step, UiJobStep.waiting);
    expect((await batch.job(UiBatchJob(here, 'b'))).step, UiJobStep.done);
    final failed = await batch.job(UiBatchJob(here, 'c'));
    expect(failed.step, UiJobStep.failed);
    expect(failed.failure!.code, FailureCode.notFound);
  });

  test('search asks the provider by name and keeps refs as they came',
      () async {
    final calls = <(String, JsonMap, String)>[];
    final batch = _batch(calls, {
      'media.metadata.search': (_) => {
            'results': [
              {
                'ref': _ref('9'),
                'workId': 'w9',
                'title': '九',
                'kind': 'tv',
                'year': 2023,
                'imageUrl': 'https://img/9.jpg',
              },
              {'ref': _ref('8'), 'workId': null, 'title': '八', 'kind': 'movie'},
            ]
          },
    });
    final found = await batch.search(UiProvider.bangumi, '九');
    expect(calls.single.$2, {'provider': 'bangumi', 'query': '九'});
    expect(calls.single.$3, 'gui');
    expect(found.first.ref, _ref('9'));
    expect((found.first.inLibrary, found.first.movie), (true, false));
    expect((found.last.inLibrary, found.last.movie), (false, true));
  });

  test(
      'a match puts each file on the candidate episode of its number, '
      'previewed per device and sent unchanged with its plan', () async {
    final calls = <(String, JsonMap, String)>[];
    final revision = {'here': 0, 'd2': 0};
    var released = false;
    JsonMap Function(JsonMap) manage(String device, List<JsonMap> rows,
            {bool release = false}) =>
        (input) {
          final at =
              '$device-${revision[device]}${device == 'here' && released ? '+' : ''}';
          if (input['expectedPlan'] case final plan?) {
            if (plan != at) throw const Failure(FailureCode.conflict, 'stale');
            if (release) released = true;
            return {'entries': const []};
          }
          return {
            'expectedPlan': at,
            'preview': {
              'diskFilesDeleted': false,
              'progressChanged': false,
              'entities': rows,
            },
          };
        };
    final work = [
      _row('w1', 'work', title: '一', sources: [
        {'status': 'accepted', 'provider': 'dandanplay'},
      ]),
      _row('r1', 'release', parent: 'w1'),
      _row('e1', 'episode', parent: 'r1'),
      _row('e2', 'episode', parent: 'r1'),
      _row('f1', 'file', associations: [
        {'file_id': 'f1', 'episode_id': 'e1'}
      ], progress: [
        {'lastPosition': 1200, 'watchProgress': 0.4},
      ]),
      _row('f2', 'file', associations: [
        {'file_id': 'f2', 'episode_id': 'e2'}
      ], progress: [
        {'lastPosition': null, 'watchProgress': null},
      ]),
    ];
    final batch = _batch(calls, numbers: {
      'm1': 1,
      'm2': 2,
      'm4': 4
    }, {
      'media.metadata.get': (_) => {
            'record': {
              'episodes': [
                for (final n in [1, 2])
                  {'ref': _ref('ep$n', 'episode'), 'number': '$n'}
              ]
            }
          },
      'media.files.list': (_) => {
            'files': [
              _file('f1', 'e1', ['b1']),
              _file('f1', 'e1', ['b1']),
              _file('f2', 'e2'),
            ]
          },
      'd2.media.files.list': (_) => {
            'files': [_file('g2', 'x2'), _file('g4', 'x4')]
          },
      'media.management.unbind_batch': manage('here', work, release: true),
      'media.management.bind_batch': manage('here', [
        ...work,
        _row('w7', 'work', title: '已有'),
        _row('e7', 'episode', parent: 'w7'),
      ]),
      'd2.media.management.bind_batch': manage('d2', [
        _row('own-w1', 'work', title: '一'),
        _row('x2', 'episode', parent: 'own-w1'),
      ]),
      'media.library.refresh': (_) => {'works': 2},
    });
    const candidate = UiBatchCandidate(title: '候选', ref: {
      'provider': 'dandanplay',
      'objectType': 'anime',
      'externalId': '7',
      'scope': ''
    });
    final preview = await batch.previewMatch([
      (
        _picked('w1', {
          _on('here', 'w1', {'e1': 'm1', 'e2': 'm2'}): [_ref('7')],
          _on('d2', 'own-w1', {'x2': 'm2', 'x4': 'm4'}): const [],
        }),
        candidate
      ),
    ]);
    List<JsonMap> sent(String action) => [
          for (final c in calls)
            if (c.$1 == action) c.$2
        ];
    expect(sent('media.metadata.get').single, {'ref': candidate.ref});
    JsonMap file(String id, String episode) => {
          'kind': 'file',
          'reason': isA<String>(),
          'entityId': id,
          'workRef': candidate.ref,
          'episodeRefs': [_ref(episode, 'episode')],
        };
    final release = sent('media.management.unbind_batch').single;
    final here = sent('media.management.bind_batch').single;
    final there = sent('d2.media.management.bind_batch').single;
    expect(release['entries'], [
      {
        'entityId': 'f1',
        'reason': isA<String>(),
        'bindingIds': ['b1']
      }
    ]);
    expect(here['entries'], [file('f1', 'ep1'), file('f2', 'ep2')]);
    expect(there['entries'], [file('g2', 'ep2')]);
    expect({release['requestId'], here['requestId'], there['requestId']},
        hasLength(3));
    expect(sent('mesh.invoke').map((c) => (c['deviceId'], c['action'])), [
      ('d2', 'media.files.list'),
      ('d2', 'media.management.bind_batch'),
    ]);
    expect(calls.every((c) => c.$3 == (c.$1.startsWith('d') ? 'mesh' : 'gui')),
        isTrue);

    expect((preview.episodes, preview.files, preview.progress), (4, 2, 1));
    expect((preview.keeps, preview.empty), (true, false));
    final [mine, other] = preview.groups;
    expect(
        (mine.id, mine.episodes, mine.files, mine.progress), ('w1', 3, 2, 1));
    expect((mine.fitted, mine.missed), (2, 1));
    expect(mine.providers, ['dandanplay']);
    expect((other.work, other.title, other.episodes, other.fitted),
        (null, '已有', 1, null));

    revision['d2'] = 1;
    await expectLater(
        batch.apply(preview),
        throwsA(isA<Failure>()
            .having((f) => f.code, 'code', FailureCode.conflict)));
    expect(sent('media.management.unbind_batch')[1],
        {...release, 'expectedPlan': 'here-0'});
    expect(sent('media.management.bind_batch').sublist(1), [
      here,
      {...here, 'expectedPlan': 'here-0+'},
    ]);
    expect(sent('d2.media.management.bind_batch')[1],
        {...there, 'expectedPlan': 'd2-0'});

    final again = await batch.again(preview);
    expect(sent('d2.media.management.bind_batch')[2], there);
    await batch.apply(again);
    expect(sent('d2.media.management.bind_batch')[3],
        {...there, 'expectedPlan': 'd2-1'});
    expect(sent('media.management.unbind_batch'), hasLength(2));
    expect(sent('media.management.bind_batch'), hasLength(3));
    expect(calls.last.$1, 'media.library.refresh');
  });

  test('letting go previews each device whose own work is matched', () async {
    final calls = <(String, JsonMap, String)>[];
    final batch = _batch(calls, {
      'media.management.unbind_batch': (input) => {
            'expectedPlan': 'p',
            'preview': {
              'diskFilesDeleted': false,
              'progressChanged': false,
              'entities': [_row('w1', 'work', title: '一')],
            },
          },
    });
    await batch.previewUnmatch([
      _picked('w1', {
        _on('here', 'w1'): [_ref('1')],
        _on('d2', 'own-w1'): const [],
      })
    ]);
    expect(calls.single.$1, 'media.management.unbind_batch');
    expect(calls.single.$2['entries'], [
      {'entityId': 'w1', 'reason': isA<String>()}
    ]);
    expect(calls.single.$2.containsKey('expectedPlan'), isFalse);
  });
}

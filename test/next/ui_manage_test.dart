import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp, Material;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as h;
import 'package:nipaplay/next/ui/data/core_manage.dart';
import 'package:nipaplay/next/ui/data/work_manage.dart';
import 'package:nipaplay/next/ui/detail/manage_episode.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';

/// The management sheets ask NipaPlay through the same Actions as the
/// agent, as the person (`gui`), and never delete before the viewer said
/// so: a NeedsDecision becomes a question; only its answer runs the
/// option NipaPlay offered.
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
      final world = _World();
      final manage = CoreWorkManage(() => world.harness, _Data());
      final confirm = await manage.deleteFile(
          const UiFile(path: '/media/frieren/03.mkv'));
      expect(confirm.items, ['03.mkv']);
      expect(world.ids, ['media.mesh_files.delete']);
      expect(world.calls.single.$2, {
        'paths': ['/media/frieren/03.mkv']
      });

      await confirm.run();
      expect(world.ids, ['media.mesh_files.delete', 'media.mesh_files.confirm']);
      expect(world.calls.last.$2, {'decisionId': 'decision-1'});
      expect(world.origins, everyElement('gui'));
    });

    test('a changed file refuses the answer as a conflict', () async {
      final world = _World()..confirmFails = true;
      final manage = CoreWorkManage(() => world.harness, _Data());
      final confirm =
          await manage.deleteFile(const UiFile(path: '/media/a.mkv'));
      await expectLater(
          confirm.run(),
          throwsA(isA<UiManageError>()
              .having((e) => e.conflict, 'conflict', isTrue)));
    });

    test('subtitle copies: the question, then its own call', () async {
      final world = _World();
      final manage = CoreWorkManage(() => world.harness, _Data());
      final confirm = await manage.deleteSubtitleCopies(const UiSubtitles(
          file: UiFile(path: '/media/a.mkv'),
          detached: ['/data/subtitles/a.ass'],
          handle: null));
      expect(confirm.items, ['a.ass']);
      expect(world.ids, ['subtitle.copy_delete']);
      await confirm.run();
      expect(world.calls.last.$2,
          containsPair('confirm', true));
      expect(world.calls.last.$2,
          containsPair('expectedFingerprint', 'fp'));
    });

    test('an episode is read through its local IDs; tracks keep revisions',
        () async {
      final world = _World();
      final manage =
          CoreWorkManage(() => world.harness, _Data(shown: [episode]));
      final managed = await manage.episode(work, episode);

      expect(managed.files.single.name, '03.mkv');
      expect(managed.files.single.size, 1200);
      expect([for (final t in managed.danmaku) t.source], ['弹弹play', 'B 站']);
      expect(managed.danmaku.first.count, 3200);
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
      UiManagedEpisode(number: '3', episode: episode, files: const [_file]);

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

final class _Action extends h.Action<_Json, _Json> {
  _Action(this.id, this.answer);
  final String id;
  final Future<h.Outcome<_Json>> Function(h.JsonMap input) answer;

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

/// NipaPlay's media, danmaku and subtitle Actions as their contracts read,
/// for one local work with one episode and one file.
final class _World implements h.Capability {
  final calls = <(String, h.JsonMap, String)>[];
  bool confirmFails = false;
  late final harness = h.Harness([this], observers: [_Origins(this)]);

  List<String> get ids => [for (final c in calls) c.$1];
  List<String> get origins => [for (final c in calls) c.$3];

  static h.Outcome<_Json> _done(h.JsonMap value) => h.Completed(_Json(value));

  static const _entities = {
    'local-episode': {'id': 'local-episode', 'kind': 'episode', 'parentId': 'local-release', 'revision': 2},
    'local-release': {'id': 'local-release', 'kind': 'release', 'parentId': 'local-work', 'revision': 1},
    'local-work': {'id': 'local-work', 'kind': 'work', 'parentId': null, 'revision': 3, 'bindings': []},
  };

  @override
  late final List<h.Action> actions = [
    for (final (id, answer) in <(String, Future<h.Outcome<_Json>> Function(h.JsonMap))>[
      ('media.mesh_files.delete', (input) async => h.NeedsDecision(h.Decision(
          prompt: '确认删除或覆盖这些文件',
          options: [
            h.DecisionOption(
                label: '确认',
                call: h.ActionCall(
                    'media.mesh_files.confirm', {'decisionId': 'decision-1'}))
          ]))),
      ('media.mesh_files.confirm', (input) async => confirmFails
          ? const h.Failed(h.Failure(h.FailureCode.conflict, 'changed'))
          : _done({'updated': 1})),
      ('subtitle.copy_delete', (input) async => input['confirm'] == true
          ? _done({'deleted': input['paths']})
          : h.NeedsDecision(h.Decision(prompt: 'Delete', options: [
              h.DecisionOption(
                  label: 'Delete copies',
                  call: h.ActionCall('subtitle.copy_delete', {
                    'paths': input['paths'],
                    'confirm': true,
                    'expectedFingerprint': 'fp'
                  }))
            ]))),
      ('media.metadata.ui_facts', (input) async => _done({
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
                {'episodeId': 'mesh-episode:3', 'number': 3, 'season': 1, 'title': {'value': '苍月草'}}
              ]
            },
          })),
      ('media.library.readable', (input) async => _done({
            'entries': [
              {
                'episodeId': 'mesh-episode:3',
                'path': '/media/frieren/03.mkv',
                'fileId': 'file-1',
                'sourceEpisodeId': 'local-episode',
                'local': true,
              }
            ]
          })),
      ('media.identity.get', (input) async {
        final entity = _entities[input['entityId']];
        return entity == null
            ? const h.Failed(h.Failure(h.FailureCode.notFound, 'Unknown entity.'))
            : _done({'identity': {'bindings': const [], ...entity}});
      }),
      ('media.files.list', (input) async => _done({
            'files': [
              {'fileId': 'file-1', 'path': '/media/frieren/03.mkv', 'size': 1200, 'durationMs': 1440000}
            ]
          })),
      ('media.entities.remove_batch', (input) async => input['preview'] == false
          ? _done({'undoId': 'undo-1'})
          : _done({'preview': const [], 'expectedPlan': 'plan-1'})),
      ('media.entities.restore', (input) async => _done({'restored': true})),
      ('media.metadata.override_batch', (input) async => _done({'atomic': true})),
      ('danmaku.tracks', (input) async => _done({
            'tracks': input['entityId'] == 'local-episode'
                ? [
                    {'bindingId': 'b-1', 'revision': 4, 'platform': 'dandanplay', 'origin': 'binding', 'count': 3200, 'enabled': true, 'offsetMs': 0},
                  ]
                : [
                    {'bindingId': null, 'trackId': 'next:bilibili', 'platform': 'bilibili', 'origin': 'playback', 'count': 900, 'enabled': true},
                  ]
          })),
      ('subtitle.tracks', (input) async => _done({
            'files': [
              {
                'fileId': 'file-1',
                'revision': 5,
                'tracks': [
                  {'id': 'sidecar:1', 'origin': 'sidecar', 'language': 'zh-Hans', 'format': 'ass', 'available': true}
                ],
                'selection': null,
              }
            ]
          })),
      ('danmaku.update', (input) async => _done({
            'results': [
              {'index': 0, 'status': 'completed', 'result': const {}}
            ]
          })),
    ])
      _Action(id, answer)
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

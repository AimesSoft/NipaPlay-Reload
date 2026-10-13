import 'dart:core' as core;
import 'dart:core';

import 'package:flutter/widgets.dart' hide Action;
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/background.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/next/ui/data/downloads.dart';
import 'package:nipaplay/next/ui/data/gui_calls.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/downloads/download_sheet.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/sheet.dart';

/// Scripted Actions: each answers from [answers]; every call is kept.
final class _Script {
  _Script(this.answers);
  final Map<String, Object Function(JsonMap input)> answers;
  final calls = <(String, JsonMap)>[];

  GuiCalls get gui => GuiCalls(() async => Harness([
        _Capability([
          for (final id in answers.keys)
            _Action(id, (input) {
              calls.add((id, input));
              return answers[id]!(input);
            })
        ])
      ]));
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Action extends Action<_Json, _Json> {
  _Action(this.id, this.answer);
  final String id;
  final Object Function(JsonMap) answer;
  @override
  ActionSpec get spec => ActionSpec(
      id: id,
      title: id,
      description: '',
      effect: Effect.write,
      input: const ObjectSchema({}, additionalProperties: true),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    try {
      return Completed(
          _Json(Map<String, Object?>.from(answer(input.value) as Map)));
    } on Failure catch (f) {
      return Failed(f);
    }
  }
}

final class _Capability implements Capability {
  _Capability(this.actions);
  @override
  final List<Action> actions;
}

JsonMap _job(String id, String state, {String created = '2026-10-01'}) => {
      'jobId': id,
      'type': 'download',
      'title': '下载',
      'state': state,
      'progress': {'completed': 1, 'total': 4},
      'createdAt': created,
    };

JsonMap _task({bool paused = false, bool finished = false, String? error}) => {
      'title': 'Frieren [1080p]',
      'outputDirectory': '/m/NipaPlay',
      'completedBytes': 300,
      'totalBytes': 1000,
      'finished': finished,
      'paused': paused,
      'error': error,
      'downloadSpeedBytesPerSecond': 100,
      'uploadSpeedBytesPerSecond': 5,
      'health': {'connectedPeers': 7, 'seenPeers': 30},
      'disk': {'availableBytes': 9000},
      'files': [
        {
          'index': 0,
          'path': '/m/NipaPlay/Frieren/01.mkv',
          'expectedSize': 600,
          'included': true,
          'isVideo': true,
          'completedBytes': 300,
          'complete': false,
          'playable': false,
          'streamable': true,
        },
        {
          'index': 1,
          'path': '/m/NipaPlay/Frieren/Fonts.7z',
          'expectedSize': 400,
          'included': false,
          'isVideo': false,
          'completedBytes': 0,
          'complete': false,
        },
      ],
    };

void main() {
  group('downloads, as the pages read them', () {
    test('a download’s state, rates, peers and files', () {
      final d = UiDownload.from(_job('a', 'running'), _task());
      expect(d.state, UiDownloadState.downloading);
      expect(d.progress, 0.3);
      expect(d.peers, 7);
      expect(d.free, 9000);
      expect(d.remaining, const Duration(seconds: 7));
      expect(d.files.first.name, '01.mkv');
      expect(d.files.first.folder, isNull);
      expect(d.files.first.progress, 0.5);
      expect(d.files.last.included, isFalse);

      expect(UiDownload.from(_job('a', 'paused'), _task(paused: true)).state,
          UiDownloadState.paused);
      expect(
          UiDownload.from(_job('a', 'succeeded'), _task(finished: true)).state,
          UiDownloadState.finished);
      expect(
          UiDownload.from(_job('a', 'running'), _task(error: 'No space left'))
              .state,
          UiDownloadState.failed);
      // Without a session only the task's own facts remain.
      final gone = UiDownload.from(_job('a', 'queued'), null);
      expect(gone.live, isFalse);
      expect(gone.state, UiDownloadState.queued);
      expect(gone.progress, 0.25);
    });

    test('the list: newest first, removed ones left out, a missing session kept',
        () async {
      final script = _Script({
        'task.list': (_) => {
              'jobs': [
                _job('old', 'succeeded', created: '2026-09-01'),
                _job('gone', 'cancelled'),
                _job('new', 'running', created: '2026-10-02'),
              ]
            },
        'download.read': (input) {
          expect(input['jobIds'], ['new', 'old']);
          return {
            'results': [
              {'index': 0, 'status': 'completed', 'job': _job('new', 'running'), 'task': _task()},
              {
                'index': 1,
                'status': 'failed',
                'error': const Failure(FailureCode.notFound, 'gone').toJson()
              },
            ]
          };
        },
      });
      final list = await NextDownloads(script.gui).list();
      expect([for (final d in list) d.jobId], ['new', 'old']);
      expect(list.first.live, isTrue);
      expect(list.last.live, isFalse);
    });

    test('a batch failure is not taken for success', () async {
      final script = _Script({
        'download.set_paused': (_) => {
              'results': [
                {
                  'index': 0,
                  'status': 'failed',
                  'error':
                      const Failure(FailureCode.conflict, 'busy').toJson()
                }
              ]
            },
      });
      await expectLater(NextDownloads(script.gui).setPaused(['a'], true),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.conflict)));
    });

    test('limits read back what the downloader does', () async {
      final script = _Script({
        'download.limits.get': (_) => {
              'supported': true,
              'sessionInitialized': false,
              'applied': false,
              'actual': null
            },
        'download.limits.set': (input) => {
              'supported': true,
              'sessionInitialized': true,
              'applied': true,
              'actual': {
                'downloadBytesPerSecond': input['downloadBytesPerSecond'],
                'uploadBytesPerSecond': 0
              }
            },
      });
      final downloads = NextDownloads(script.gui);
      final now = await downloads.limits();
      expect(now.supported, isTrue);
      expect(now.running, isFalse);
      final set = await downloads.setLimits(down: 1 << 20);
      expect(set.down, 1 << 20);
      expect(script.calls.last.$2, {'downloadBytesPerSecond': 1 << 20});
    });
  });

  group('background work', () {
    test('Classic and Next scanning are one 扫描; Next’s capacity is shown',
        () async {
      final script = _Script({
        'task.resources': (_) => {
              'pools': [
                {'type': 'media.scan', 'capacity': 2, 'active': 1, 'queued': 0},
                {'type': 'media.scan_classic', 'capacity': 1, 'active': 1, 'queued': 3},
                {'type': 'media.metadata.refresh', 'capacity': 4, 'active': 0, 'queued': 0},
                {'type': 'agent.helper', 'capacity': 2, 'active': 1, 'queued': 0},
              ]
            },
        'settings.set': (input) => input,
      });
      final background = NextBackground(script.gui);
      final pools = await background.pools();
      expect([for (final p in pools) p.kind], ['scan', 'metadata', 'helper']);
      expect(pools.first.capacity, 2);
      expect(pools.first.active, 2);
      expect(pools.first.queued, 3);
      await background.setCapacity('metadata', 6);
      expect(script.calls.last.$2,
          {'key': 'tasks.metadataConcurrency', 'value': 6});
    });

    test('control reports each task’s answer', () async {
      final script = _Script({
        'task.control': (input) => {
              'results': [
                for (final (i, e) in (input['entries'] as List).cast<Map>().indexed)
                  {
                    'index': i,
                    'jobId': e['jobId'],
                    'accepted': e['jobId'] != 'helper',
                    'controlSupported': e['jobId'] != 'helper',
                  }
              ]
            },
      });
      final results =
          await NextBackground(script.gui).control(['scan', 'helper'], 'pause');
      expect([for (final r in results) r.accepted], [true, false]);
      expect(results.last.supported, isFalse);
    });

    test('a waiting task’s question comes back with its executable options',
        () async {
      final script = _Script({
        'task.get': (_) => {
              'job': {
                'jobId': 'd',
                'decision': {
                  'prompt': '删除 3 个文件？',
                  'options': [
                    {
                      'label': '删除',
                      'call': {
                        'action': 'media.mesh_files.delete',
                        'input': {'token': 't'}
                      }
                    }
                  ]
                }
              }
            },
      });
      final decision = await NextBackground(script.gui).question('d');
      expect(decision!.prompt, '删除 3 个文件？');
      expect(decision.options.single.call.actionId, 'media.mesh_files.delete');
      expect(decision.options.single.call.input, {'token': 't'});
    });
  });

  testWidgets('the sheet: choosing files, then deleting with the files',
      (tester) async {
    var task = _task();
    final script = _Script({
      'download.read': (_) => {'job': _job('a', 'running'), 'task': task},
      'download.select_files': (input) {
        task = {
          ...task,
          'files': [
            for (final f in (task['files'] as List).cast<Map>())
              {
                ...f,
                'included':
                    (input['fileIndices'] as List).contains(f['index'])
              }
          ]
        };
        return {'job': _job('a', 'running'), 'task': task};
      },
      'download.delete': (_) => {'job': _job('a', 'cancelled')},
    });
    final services = NextUiServices(
      data: _Stub(),
      actions: _Stub(),
      chat: _Stub(),
      discover: _Stub(),
      library: _Library(),
      libraryActions: _Stub(),
      search: _Search(),
      settings: FakeSettings(),
      calls: script.gui,
    );
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: MediaQueryData(size: Size(1200, 900)),
        child: NextSheetLayer(),
      ),
    ));
    final shown = openDownload(services, 'a');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Frieren [1080p]'), findsOneWidget);
    expect(find.textContaining('01.mkv', findRichText: true), findsOneWidget);

    await tester.tap(_pressable('选择 Fonts.7z'));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 100));
    expect(script.calls.where((c) => c.$1 == 'download.select_files').single.$2,
        {'jobId': 'a', 'fileIndices': [0, 1]});

    await tester.tap(_pressable('删除'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('连同文件删除'), findsOneWidget);
    await tester.tap(find.text('连同文件删除'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(script.calls.map((c) => c.$1), contains('download.delete'));
    expect(script.calls.map((c) => c.$1), isNot(contains('download.remove')));
    await shown;
    expect(NextSheetLayer.open, 0);
    await tester.pumpWidget(const SizedBox());
  });
}

Finder _pressable(String label) => find
    .byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label)
    .first;

/// The parts of the shell the sheet never touches.
final class _Stub
    implements
        NextUiData,
        NextUiActions,
        ChatPort,
        NextDiscoverData,
        NextLibraryActions {
  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Library implements NextLibraryData {
  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _Search implements NextSearchData {
  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/chat_line_reader.dart';
import 'package:nipaplay/next/memory/recent.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';
import 'package:nipaplay/next/state/calendar_material.dart';
import 'package:nipaplay/next/settings/classic_settings.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/developer_options_provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';
import 'support/big_profile.dart';
import 'support/cpu_budget_probe.dart';

/// The performance line for Next on the main isolate, over a large profile:
/// no single stretch of Next's own work holds the isolate for more than 4 ms,
/// and while nothing changes nothing runs. CPU time rather than wall time is
/// used, so descheduling and other processes do not consume this budget.
///
/// The test isolate stands for the UI isolate: everything Next runs here
/// directly is what the app runs on its main isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Next's own main-isolate work, measured as thread CPU time.
  const nextBudgetMs = 4.0;

  /// While nothing changes, Next does (almost) nothing: this much over the
  /// machine's own unrest.
  const idleSlackMs = 60.0;

  late Directory temp;
  late BigProfile profile;
  late NextCore core;

  setUpAll(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({'plugin_enabled_ids': <String>[]});
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    temp = await Directory.systemTemp.createTemp('next-main-thread-');
    PackageInfo.setMockInitialValues(
        appName: 'NipaPlay',
        packageName: 'nipa.perf',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => temp.path);
    final settings = ClassicSettings(
        appearance: AppearanceSettingsProvider(automaticUiScale: 1.3),
        language: AppLanguageProvider(),
        home: HomeSectionsSettingsProvider(),
        theme: ThemeNotifier(),
        developer: DeveloperOptionsProvider(),
        labs: LabsSettingsProvider(sandboxStatus: () async => false),
        webdav: WebDAVQuickAccessProvider(),
        plugins: PluginService());
    ClassicSettings.attached = settings;
    await settings.ready;
    await settings.plugins.ready;
    // NEXT_PERF_SCALE shrinks the profile (e.g. 0.25) for a quick look.
    final scale =
        double.tryParse(const String.fromEnvironment('NEXT_PERF_SCALE')) ?? 1.0;
    profile = await buildBigProfile(Directory('${temp.path}/next'),
        spec: BigProfileSpec(
            works: (120 * scale).ceil(),
            jobs: (1500 * scale).ceil(),
            followups: (1200 * scale).ceil(),
            hookEvents: (4000 * scale).ceil(),
            journalBytes: ((40 << 20) * scale).ceil(),
            danmakuEpisodes: (40 * scale).ceil().clamp(4, 40)));
  });
  tearDownAll(() async {
    await temp.delete(recursive: true);
  });

  // On Windows a test attempt is repeated (retry:) when one thread-CPU reading
  // spikes: a real regression fails every attempt, a spike does not.
  test('a large profile keeps the main isolate free', () async {
    NextCore newCore(Directory root, {void Function(String)? startupPhase}) =>
        NextCore(
          root: root,
          databaseFactory: databaseFactoryFfi,
          downloadBackend: FakeDownloadBackend(root),
          downloadLibrary: FakeDownloadLibrary(),
          isDownloaderEnabled: () async => true,
          loadImportedKeys: () async => {},
          classic: MemoryClassic(),
          authorizedRoots: () => [profile.media.path],
          mediaDurationProbe: (_) async => 1440000,
          mediaSubtitleProbe: (_) async => {'subtitles': <Object?>[]},
          mediaProviders: const [],
          startupPhase: startupPhase,
        );

    // The app ships AOT; this test normally runs as JIT. Exercise the startup,
    // memory and first-composition paths once before taking the CPU clock, so
    // the budget measures recurring work rather than first-call compilation.
    final warm = newCore(profile.root);
    await warm.ready;
    await warm.startNipa();
    await warm.uiData.home();
    final warmLibrary = await warm.uiData.library();
    for (final work in warmLibrary.take(3)) {
      await warm.uiData.work(work.workId);
      await warm.uiData.episodes(work.workId);
    }
    warm.memory.recent = (current) async {
      final activity = await warm.state.views['activity']!.readPage!(0, 5);
      return recentMemoryFacts(
          _History(profile),
          await activeJobFacts(warm.engine),
          await warm.followups.activeList(),
          activity.rows,
          current,
          activityTotal: activity.total,
          redact: warm.uiData.meshLibrary!.worker.redactText);
    };
    await warm.memory.context(null);
    final warmHarness = Harness(warm.capabilities, observers: [
      nextJournal(profile.journal),
      warm.activityInvocations,
    ]);
    for (var i = 0; i < 3; i++) {
      final warmActivity = await warmHarness.invokeJson(
          'state.query',
          {'view': 'activity', 'limit': 20},
          Invocation(origin: 'perf:warm:activity:$i'));
      expect(warmActivity, isA<Completed>());
    }
    for (var i = 0; i < 3; i++) {
      final warmResources = await warmHarness.invokeJson(
          'task.resources', {}, Invocation(origin: 'perf:warm:resources:$i'));
      expect(warmResources, isA<Completed>());
    }
    // A change to the library (she renames a work) is a first-use path too:
    // the first rename of a process compiles the override, change-announcing
    // and recomposition code, which showed as the one round that held the
    // isolate for 2-4 ms while the later rounds stayed under 1.2 ms.
    {
      final work = profile.workIds[30];
      const name = 'warm-up name';
      final changed = warm.uiData.changes.first;
      final renamed = await warmHarness.invokeJson(
          'media.metadata.override_batch',
          {
            'entries': [
              {
                'entityId': work,
                'field': 'title',
                'value': name,
                'mode': 'persistent'
              }
            ]
          },
          Invocation(origin: 'perf:warm:rename'));
      expect(renamed, isA<Completed>());
      await changed.timeout(const Duration(seconds: 10));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while ((await warm.uiData.work(work))?.title != name) {
        if (DateTime.now().isAfter(deadline)) fail('the warm-up rename never arrived');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await warm.uiData.home();
    }
    await encodeReply({'warm': true});
    await warm.close();

    final probe = CpuBudgetProbe()..verbose = true;
    final turnOutput = _chatOutputBytes(profile);
    // The runtime output reader spawns its isolate and first reaches the
    // transfer callbacks here; like the other first-use paths above, compile
    // them before the recurring-work budget starts.
    await _chatOutput(turnOutput);
    final replyPayload = {
      'rows': [
        for (var i = 0; i < 400; i++) {'id': 'perf-$i', 'text': '回答 $i ' * 500}
      ]
    };
    final hookPayload = {'text': 'hook output ' * 12000};
    await probe.run(() async {
      // What the machine does to an empty process, for the idle limits.
      await Future<void>.delayed(const Duration(seconds: 5));
      probe.mark('baseline');
      // The library announces its own steps through the same callback while it
      // is rebuilt after a change; those belong to that change's round (the
      // best of three, below), not to startup.
      int? changeRound;
      core = newCore(profile.root,
          startupPhase: (name) => probe.mark(
              changeRound == null ? name : 'library change $changeRound: $name'));
      probe.mark('startup: core constructed');
      // What the GUI supplies from Classic: its watch history, and the
      // calendar it keeps encoded in its preferences.
      core.stateSources.history = () =>
          [for (final row in profile.history) Map<String, Object?>.of(row)];
      core.stateSources.continueWatching = () => [
            for (final row in profile.history.take(40))
              Map<String, Object?>.of(row)
          ];
      core.stateSources.calendar =
          () async => CalendarMaterial.encoded(profile.calendarJson);
      addTearDown(() => core.close());
      await core.ready;
      probe.mark('startup: core ready');
      // Next's interface is open: Nipa's services run (NextRuntime starts them
      // when it opens, D1).
      await core.startNipa();
      probe.mark('startup: Nipa services');
      final history = _History(profile);
      core.memory.recent = (current) async {
        final activity = await core.state.views['activity']!.readPage!(0, 5);
        return recentMemoryFacts(history, await activeJobFacts(core.engine),
            await core.followups.activeList(), activity.rows, current,
            activityTotal: activity.total,
            redact: core.uiData.meshLibrary!.worker.redactText);
      };
      final harness = Harness(core.capabilities, observers: [
        nextJournal(profile.journal),
        core.activityInvocations,
      ]);
      probe.mark('startup');

      final data = core.uiData;
      var homeCalls = 0;
      Future<void> home() async {
        final first = homeCalls++ == 0;
        final shown = await data.home();
        if (first) probe.mark('first home: home');
        final works = await data.library();
        if (first) probe.mark('first home: library');
        for (final work in works.take(3)) {
          await data.work(work.workId);
          if (first) probe.mark('first home: work');
          await data.episodes(work.workId);
          if (first) probe.mark('first home: episodes');
        }

        expect(shown.shelves, isNotNull);
      }

      // The first composition of everything (the app does it once).
      final library = core.uiData.meshLibrary!;
      await library.prepareIndex();
      probe.mark('first home: prepare index');
      await home();
      probe.mark('first home');

      // Nothing changes: the body must not keep working, and the library is
      // not built again.
      final built = library.builds;
      await Future<void>.delayed(const Duration(seconds: 8));
      probe.mark('idle');

      // The home page reloads as it does on a change.
      for (var i = 0; i < 3; i++) {
        await home();
      }
      const regressionMs = int.fromEnvironment('NEXT_PERF_INJECT_BLOCK_MS');
      if (regressionMs > 0)
        probe.injectBlock(Duration(milliseconds: regressionMs));
      probe.mark('home refresh x3');

      // A Nipa turn: the runtime's output read in, her calls answered, her
      // memory for the turn put together.
      await _chatOutput(turnOutput);
      probe.mark('turn: runtime output');
      await core.memory.rememberThread('thread-perf-0');
      probe.mark('turn: memory remember');
      await core.memory.changesFor('thread-perf-0');
      probe.mark('turn: memory changes');
      await core.memory.changesFor('thread-perf-0');
      probe.mark('turn: memory unchanged');
      final encoded = await encodeReply(replyPayload);
      expect(encoded.length, greaterThan(500000));
      probe.mark('turn: encode reply');
      await core.hooks.emit('network.state_changed', 'perf-hook', hookPayload);
      probe.mark('turn: hook redaction');
      Future<JsonMap> call(String action, JsonMap input,
          {String origin = 'harness_cli:chat:perf'}) async {
        final outcome =
            await harness.invokeJson(action, input, Invocation(origin: origin));
        expect(outcome, isA<Completed>(),
            reason: outcome is Completed
                ? null
                : '$action ${outcome.toEnvelope()}');
        return (outcome as Completed).value.toJson();
      }

      await core.memory.context(null);
      probe.mark('turn: memory context');
      final queries = [
        {'view': 'activity', 'limit': 20},
        {
          'view': 'tasks',
          'limit': 20,
          'orderBy': [
            {'field': 'updatedAt', 'direction': 'desc'}
          ]
        },
        {
          'view': 'task_events',
          'filter': {
            'jobId': {'eq': profile.jobIds[profile.jobIds.length ~/ 2]}
          }
        },
        {
          'view': 'library.files',
          'limit': 50,
          'filter': {
            'workId': {'eq': profile.workIds[3]}
          }
        },
        {'view': 'followups', 'limit': 20},
        {'view': 'library.works', 'limit': 20},
      ];
      for (var i = 0; i < queries.length; i++) {
        final query = queries[i];
        await call('state.query', query);
        probe.mark('turn: state.query ${query['view']}');
      }
      await call('task.list', {});
      probe.mark('turn: task.list');
      await call('db.query', {
        'sql': 'SELECT id, kind FROM media_entities WHERE kind=?',
        'params': ['work'],
        'limit': 200
      });
      probe.mark('turn: db.query');
      // Her opening-skip hook asks the player every two seconds while she
      // works; any cheap read stands for it here.
      for (var i = 0; i < 20; i++) {
        await call('task.resources', {}, origin: 'hook:job-perf-1');
      }
      probe.mark('turn: task.resources');

      // Writes to tables the library is not made of (a task's progress, an
      // audit row) do not build it again either.
      await core.uiData.db.insert('body_changes', {
        'at': DateTime.now().toUtc().toIso8601String(),
        'type': 'perf.unrelated',
        'subject_id': 's',
        'actor': 'a',
        'origin': 'o',
        'facts': '{}'
      });
      await Future<void>.delayed(const Duration(seconds: 1));
      await data.library();
      expect(library.builds, built,
          reason: 'an unrelated write built the library');
      probe.mark('unrelated write');

      // The library changes: she renames a work, three times over. The new
      // title reaches the library without anyone asking for a refresh.
      for (var round = 0; round < 3; round++) {
        changeRound = round;
        final work = profile.workIds[5 + round];
        final name = '改过的名字 $round';
        final changed = data.changes.first;
        final beforeChange = library.builds;
        await call('media.metadata.override_batch', {
          'entries': [
            {
              'entityId': work,
              'field': 'title',
              'value': name,
              'mode': 'persistent'
            }
          ]
        });
        await changed.timeout(const Duration(seconds: 10));
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while ((await data.work(work))?.title != name) {
          if (DateTime.now().isAfter(deadline))
            fail('the rename never reached the library');
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        await home();
        probe.mark('library change $round');
        expect(library.builds,
            inInclusiveRange(beforeChange + 1, beforeChange + 3),
            reason:
                'a change to the library builds it once (or again for what the build wrote)');
      }

      changeRound = null;
      await Future<void>.delayed(const Duration(seconds: 6));
      probe.mark('idle after');
    });
    probe.stop();
    // NEXT_PERF_HOLD keeps the process for a profiler to read afterwards.
    final hold =
        int.tryParse(const String.fromEnvironment('NEXT_PERF_HOLD')) ?? 0;
    if (hold > 0) await Future<void>.delayed(Duration(seconds: hold));
    // ignore: avoid_print
    print(probe);

    final phases = {
      for (final (name, longest, held) in probe.phases) name: (longest, held)
    };
    double longestOf(String name) => probe.phases
        .where((phase) => phase.$1 == name)
        .fold(0.0, (longest, phase) => phase.$2 > longest ? phase.$2 : longest);

    // The first indexer pass is catalogue work, not UI work. Keep its own
    // target separate from the general 4 ms ceiling so growing profiles cannot
    // quietly consume almost the whole budget again.
    expect(phases['startup: Nipa indexers']!.$1, lessThanOrEqualTo(1.0),
        reason: 'startup: Nipa indexers held the main isolate '
            '${phases['startup: Nipa indexers']!.$1.toStringAsFixed(3)} ms of CPU at once');

    // Everything Next does on the main isolate has the same hard ceiling.
    for (final MapEntry(key: name, value: (longest, _)) in phases.entries) {
      if (name == 'baseline' ||
          name.startsWith('library change') ||
          name.startsWith('idle')) continue;
      expect(longest, lessThanOrEqualTo(nextBudgetMs),
          reason:
              '$name held the main isolate ${longest.toStringAsFixed(3)} ms of CPU at once');
    }
    // These paths used to sit on the 4 ms ceiling. They carry the first home
    // page and Nipa's recurring turns, so they keep the tighter PERF5 budget
    // even while the rest of startup still has its older 4 ms limit.
    const perfBudgetMs = 2.0;
    for (final name in [
      'startup: Nipa mesh received',
      'startup: Nipa mesh published',
      'startup: Nipa mesh prepared',
      'first home: home',
      'home refresh x3',
      'turn: runtime output',
      'turn: state.query activity',
      'turn: task.resources',
    ]) {
      final longest = longestOf(name);
      expect(longest, lessThanOrEqualTo(perfBudgetMs),
          reason:
              '$name held the main isolate ${longest.toStringAsFixed(3)} ms of CPU at once');
    }
    // Library changes repeat: other work can overlap one round, so the best
    // complete round must still fit. A real regression is present in all three.
    final changes = [
      for (var i = 0; i < 3; i++)
        probe.phases
            .where((phase) =>
                phase.$1 == 'library change $i' ||
                phase.$1.startsWith('library change $i: '))
            .fold(0.0, (longest, phase) => phase.$2 > longest ? phase.$2 : longest)
    ].reduce((a, b) => a < b ? a : b);
    expect(changes, lessThanOrEqualTo(perfBudgetMs),
        reason:
            'a library change held the main isolate ${changes.toStringAsFixed(3)} ms of CPU at once (best of 3)');

    // While nothing changes nothing runs: no more than the machine's own
    // unrest, which an empty stretch at the start measured.
    final noisePerSecond = phases['baseline']!.$2 / 5;
    for (final (name, seconds) in [('idle', 8), ('idle after', 6)]) {
      final limit = idleSlackMs + 3 * noisePerSecond * seconds;
      expect(phases[name]!.$2, lessThan(limit),
          reason: '$name, Next still held the main isolate '
              '${phases[name]!.$2.toStringAsFixed(1)} ms (limit ${limit.toStringAsFixed(1)})');
    }
  }, timeout: const Timeout(Duration(minutes: 5)), retry: Platform.isWindows ? 2 : null);
}

/// The conversation runtime's side of [ConversationHistory]: a long thread.
final class _History implements ConversationHistory {
  _History(this.profile);
  final BigProfile profile;
  @override
  String? get mainThreadId => 'thread-perf-0';
  @override
  Map<String, String> get threadOrigins => const {};
  @override
  Future<ChatMessage> listThreads(
          {String? cursor,
          int limit = 30,
          List<String>? sourceKinds,
          String? sortKey}) async =>
      {
        'data': [
          for (var i = 0; i < 7; i++) {'id': 'thread-perf-$i'}
        ],
        'nextCursor': null
      };
  @override
  Future<ChatMessage> readThread(String id, {bool withProcess = true}) async =>
      {
        'id': id,
        'turns': [
          for (var t = 0; t < 60; t++)
            {
              'id': 'turn-$t',
              'status': 'completed',
              'items': [
                {
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': '第 $t 句话'}
                  ]
                },
                for (var c = 0; c < 6; c++)
                  {
                    'id': 'cmd-$t-$c',
                    'type': 'commandExecution',
                    'command': 'nipa call state.query',
                    'aggregatedOutput': 'x' * 4000,
                    'status': 'completed'
                  },
                {'type': 'agentMessage', 'text': '回答 $t ' * 40},
              ]
            }
        ]
      };
}

/// The runtime's output for one turn as the host reads it: stream deltas,
/// commands with long output, and a thread read back.
List<int> _chatOutputBytes(BigProfile profile) {
  final lines = <String>[];
  for (var i = 0; i < 400; i++) {
    lines.add(jsonEncode({
      'method': 'item/agentMessage/delta',
      'params': {
        'threadId': 'thread-perf-0',
        'turnId': 'turn-x',
        'itemId': 'm',
        'delta': '这是第 $i 段回答。'
      }
    }));
  }
  for (var i = 0; i < 40; i++) {
    lines.add(jsonEncode({
      'method': 'item/completed',
      'params': {
        'threadId': 'thread-perf-0',
        'turnId': 'turn-x',
        'item': {
          'id': 'cmd-$i',
          'type': 'commandExecution',
          'command': 'nipa call state.query',
          'aggregatedOutput': 'line of output $i\n' * 2000,
          'exitCode': 0,
          'status': 'completed'
        }
      }
    }));
  }
  lines.add(jsonEncode({
    'id': 7,
    'result': {
      'thread': {
        'id': 'thread-perf-0',
        'turns': [
          for (var t = 0; t < 40; t++)
            {
              'id': 'turn-$t',
              'items': [
                {'type': 'agentMessage', 'text': '回答' * 2000}
              ]
            }
        ]
      }
    }
  }));
  return utf8.encode('${lines.join('\n')}\n');
}

Future<void> _chatOutput(List<int> bytes) async {
  final output = Stream<List<int>>.fromIterable([
    for (var i = 0; i < bytes.length; i += 65536)
      bytes.sublist(i, i + 65536 > bytes.length ? bytes.length : i + 65536)
  ]);
  final reader = ChatLineReader.start(output,
      rpc: true, streamDeltaMethods: const {'item/agentMessage/delta'});
  await reader.lines.length;
}

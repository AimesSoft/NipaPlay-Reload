import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/chat_line_reader.dart';
import 'package:nipaplay/next/memory/recent.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';
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
import 'support/main_thread_probe.dart';

/// The performance line for Next on the main isolate, over a large profile:
/// no single stretch of Next's own work holds the isolate long, and while
/// nothing changes nothing runs. The thresholds leave room for a loaded CI
/// machine; the measured values are printed for comparison.
///
/// The test isolate stands for the UI isolate: everything Next runs here
/// directly is what the app runs on its main isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Hard line: no task of Next's on the main isolate takes 100 ms or more.
  const hardLineMs = 100.0;

  /// A task that runs once has no second round to be judged by, and a busy
  /// machine can stall any process for a moment: it gets this much more.
  const loadSlackMs = 50.0;

  /// The first composition of everything, in a process that has not run the
  /// code before.
  const coldLineMs = 500.0;

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
        appName: 'NipaPlay', packageName: 'nipa.perf', version: '1.0.0',
        buildNumber: '1', buildSignature: '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'),
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
    final scale = double.tryParse(const String.fromEnvironment('NEXT_PERF_SCALE')) ?? 1.0;
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

  test('a large profile keeps the main isolate free', () async {
    final backend = FakeDownloadBackend(profile.root);
    final probe = MainThreadProbe.start()..verbose = true;
    // What the machine does to an empty process, for the idle limits.
    await Future<void>.delayed(const Duration(seconds: 5));
    probe.mark('baseline');
    core = NextCore(
      root: profile.root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: backend,
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => true,
      loadImportedKeys: () async => {},
      classic: MemoryClassic(),
      authorizedRoots: () => [profile.media.path],
      mediaDurationProbe: (_) async => 1440000,
      mediaSubtitleProbe: (_) async => {'subtitles': <Object?>[]},
      mediaProviders: const [],
    );
    // What the GUI supplies from Classic: its watch history, and the
    // calendar it keeps encoded in its preferences.
    core.stateSources.history = () => [
          for (final row in profile.history) Map<String, Object?>.of(row)
        ];
    core.stateSources.continueWatching = () => [
          for (final row in profile.history.take(40)) Map<String, Object?>.of(row)
        ];
    core.stateSources.calendar = () async =>
        (jsonDecode(profile.calendarJson) as List).cast<Map<String, Object?>>();
    addTearDown(() => core.close());
    await core.ready;
    // Next's interface is open: Nipa's services run (NextRuntime starts them
    // when it opens, D1).
    await core.startNipa();
    final history = _History(profile);
    core.memory.recent = (current) async => recentMemoryFacts(
        history,
        [
          for (final job in await core.engine.list())
            if (!job.state.isTerminal) job.toJson()
        ],
        (await core.followups.list())
            .where((r) => !const {'completed', 'cancelled'}.contains(r['state']))
            .toList(),
        (await core.state.views['activity']!.readAll!()).rows,
        current);
    final harness = Harness(core.capabilities, observers: [
      nextJournal(profile.journal),
      core.activityInvocations,
    ]);
    probe.mark('startup');

    final data = core.uiData;
    Future<void> home() async {
      final shown = await data.home();
      final works = await data.library();
      for (final work in works.take(3)) {
        await data.work(work.workId);
        await data.episodes(work.workId);
      }

      expect(shown.shelves, isNotNull);
    }

    // The first composition of everything (the app does it once).
    await home();
    probe.mark('first home');

    // Nothing changes: the body must not keep working, and the library is
    // not built again.
    final library = core.uiData.meshLibrary!;
    final built = library.builds;
    await Future<void>.delayed(const Duration(seconds: 8));
    probe.mark('idle');

    // The home page reloads as it does on a change.
    for (var i = 0; i < 3; i++) {
      await home();
    }
    probe.mark('home refresh x3');

    // A Nipa turn: the runtime's output read in, her calls answered, her
    // memory for the turn put together.
    await _chatOutput(profile);
    probe.mark('turn: runtime output');
    Future<JsonMap> call(String action, JsonMap input,
        {String origin = 'harness_cli:chat:perf'}) async {
      final outcome =
          await harness.invokeJson(action, input, Invocation(origin: origin));
      expect(outcome, isA<Completed>(), reason: '$action ${outcome.toEnvelope()}');
      return (outcome as Completed).value.toJson();
    }

    await core.memory.context(null);
    probe.mark('turn: memory context');
    for (final query in [
      {'view': 'activity', 'limit': 20},
      {'view': 'tasks', 'limit': 20, 'orderBy': [{'field': 'updatedAt', 'direction': 'desc'}]},
      {'view': 'task_events', 'filter': {'jobId': {'eq': profile.jobIds[profile.jobIds.length ~/ 2]}}},
      {'view': 'library.files', 'limit': 50, 'filter': {'workId': {'eq': profile.workIds[3]}}},
      {'view': 'followups', 'limit': 20},
      {'view': 'library.works', 'limit': 20},
    ]) {
      await call('state.query', query);
    }
    probe.mark('turn: state.query');
    await call('task.list', {});
    await call('db.query', {'sql': 'SELECT id, kind FROM media_entities WHERE kind=?', 'params': ['work'], 'limit': 200});
    // Her opening-skip hook asks the player every two seconds while she
    // works; any cheap read stands for it here.
    for (var i = 0; i < 20; i++) {
      await call('task.resources', {}, origin: 'hook:job-perf-1');
    }
    probe.mark('turn: calls');

    // Writes to tables the library is not made of (a task's progress, an
    // audit row) do not build it again either.
    await core.uiData.db.insert('body_changes', {
      'at': DateTime.now().toUtc().toIso8601String(), 'type': 'perf.unrelated',
      'subject_id': 's', 'actor': 'a', 'origin': 'o', 'facts': '{}'});
    await Future<void>.delayed(const Duration(seconds: 1));
    await data.library();
    expect(library.builds, built, reason: 'an unrelated write built the library');
    probe.mark('unrelated write');

    // The library changes: she renames a work, three times over. The new
    // title reaches the library without anyone asking for a refresh.
    for (var round = 0; round < 3; round++) {
      final work = profile.workIds[5 + round];
      final name = '改过的名字 $round';
      final changed = data.changes.first;
      final beforeChange = library.builds;
      await call('media.metadata.override_batch', {
        'entries': [
          {'entityId': work, 'field': 'title', 'value': name, 'mode': 'persistent'}
        ]
      });
      await changed.timeout(const Duration(seconds: 10));
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while ((await data.work(work))?.title != name) {
        if (DateTime.now().isAfter(deadline)) fail('the rename never reached the library');
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await home();
      probe.mark('library change $round');
      expect(library.builds, inInclusiveRange(beforeChange + 1, beforeChange + 3),
          reason: 'a change to the library builds it once (or again for what the build wrote)');
    }

    await Future<void>.delayed(const Duration(seconds: 6));
    probe.mark('idle after');
    probe.stop();
    // NEXT_PERF_HOLD keeps the process for a profiler to read afterwards.
    final hold = int.tryParse(const String.fromEnvironment('NEXT_PERF_HOLD')) ?? 0;
    if (hold > 0) await Future<void>.delayed(Duration(seconds: hold));
    // ignore: avoid_print
    print(probe);

    final phases = {for (final (name, longest, held) in probe.phases) name: (longest, held)};

    // The first composition of everything is the one cold start: the code is
    // run for the first time too, so it gets more room.
    expect(phases['first home']!.$1, lessThan(coldLineMs),
        reason: 'first home held the main isolate ${phases['first home']!.$1.toStringAsFixed(1)} ms at once');
    // Every other task is under the hard line. A machine can stall a process
    // now and then whatever it does (an empty test shows it, and a busy
    // machine more), so a phase that repeats is judged by its best round: a
    // task that is too long is too long every time.
    for (final MapEntry(key: name, value: (longest, _)) in phases.entries) {
      if (name == 'startup' || name == 'baseline' || name == 'first home' || name.startsWith('library change') || name.startsWith('idle')) continue;
      expect(longest, lessThan(hardLineMs + loadSlackMs),
          reason: '$name held the main isolate ${longest.toStringAsFixed(1)} ms at once');
    }
    final changes = [for (var i = 0; i < 3; i++) phases['library change $i']!.$1]
        .reduce((a, b) => a < b ? a : b);
    expect(changes, lessThan(hardLineMs),
        reason: 'a library change held the main isolate ${changes.toStringAsFixed(1)} ms at once (best of 3)');

    // While nothing changes nothing runs: no more than the machine's own
    // unrest, which an empty stretch at the start measured.
    final noisePerSecond = phases['baseline']!.$2 / 5;
    for (final (name, seconds) in [('idle', 8), ('idle after', 6)]) {
      final limit = idleSlackMs + 3 * noisePerSecond * seconds;
      expect(phases[name]!.$2, lessThan(limit),
          reason: '$name, Next still held the main isolate '
              '${phases[name]!.$2.toStringAsFixed(1)} ms (limit ${limit.toStringAsFixed(1)})');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
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
          {String? cursor, int limit = 30, List<String>? sourceKinds, String? sortKey}) async =>
      {
        'data': [
          for (var i = 0; i < 7; i++) {'id': 'thread-perf-$i'}
        ],
        'nextCursor': null
      };
  @override
  Future<ChatMessage> readThread(String id, {bool withProcess = true}) async => {
        'id': id,
        'turns': [
          for (var t = 0; t < 60; t++)
            {
              'id': 'turn-$t',
              'status': 'completed',
              'items': [
                {'type': 'userMessage', 'content': [{'type': 'text', 'text': '第 $t 句话'}]},
                for (var c = 0; c < 6; c++)
                  {'id': 'cmd-$t-$c', 'type': 'commandExecution', 'command': 'nipa call state.query',
                    'aggregatedOutput': 'x' * 4000, 'status': 'completed'},
                {'type': 'agentMessage', 'text': '回答 $t ' * 40},
              ]
            }
        ]
      };
}

/// The runtime's output for one turn as the host reads it: stream deltas,
/// commands with long output, and a thread read back.
Future<void> _chatOutput(BigProfile profile) async {
  final lines = <String>[];
  for (var i = 0; i < 400; i++) {
    lines.add(jsonEncode({'method': 'item/agentMessage/delta',
      'params': {'threadId': 'thread-perf-0', 'turnId': 'turn-x', 'itemId': 'm', 'delta': '这是第 $i 段回答。'}}));
  }
  for (var i = 0; i < 40; i++) {
    lines.add(jsonEncode({'method': 'item/completed', 'params': {'threadId': 'thread-perf-0', 'turnId': 'turn-x',
      'item': {'id': 'cmd-$i', 'type': 'commandExecution', 'command': 'nipa call state.query',
        'aggregatedOutput': 'line of output $i\n' * 2000, 'exitCode': 0, 'status': 'completed'}}}));
  }
  lines.add(jsonEncode({'id': 7, 'result': {'thread': {'id': 'thread-perf-0', 'turns': [
    for (var t = 0; t < 40; t++)
      {'id': 'turn-$t', 'items': [{'type': 'agentMessage', 'text': '回答' * 2000}]}
  ]}}}));
  final bytes = utf8.encode('${lines.join('\n')}\n');
  final output = Stream<List<int>>.fromIterable([
    for (var i = 0; i < bytes.length; i += 65536)
      bytes.sublist(i, i + 65536 > bytes.length ? bytes.length : i + 65536)
  ]);
  final reader = ChatLineReader.start(output,
      rpc: true, streamDeltaMethods: const {'item/agentMessage/delta'});
  await reader.lines.length;
}

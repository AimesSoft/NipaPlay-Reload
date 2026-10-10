// Run: ~/development/flutter-3.44.6/bin/flutter test --no-pub
//      scripts/next/x4_experiment.dart --reporter expanded
// All application state, credentials, seed history and harnesses are temporary.
// This script is run by flutter test and initializes isolated preferences.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/harness_repository.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test/next/download_test_support.dart';
import '../../test/next/media_test_support.dart';
import 'x3_experiment.dart' show snapshot;

Future<ProcessResult> command(String executable, List<String> args,
    {String? cwd, Map<String, String>? environment}) async {
  final result = await Process.run(executable, args,
      workingDirectory: cwd, environment: environment);
  if (result.exitCode != 0) {
    throw StateError(
        '$executable ${args.join(' ')}: ${result.stderr} ${result.stdout}');
  }
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('X4 output, pagination and seed upgrade experiment', () async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final baselineRef = Platform.environment['NIPAPLAY_X4_BASE'] ??
        'f5a08af5862a45e62f665462e5b686edc0e0e1fe';
    final root = await Directory.systemTemp.createTemp('nipa-x4-');
    final repository = Directory(p.join(root.path, 'harness'));
    final credentials = File(p.join(root.path, 'private', 'endpoint.json'));
    final upstream = Directory(p.join(root.path, 'seed'));
    final core = NextCore(
        root: Directory(p.join(root.path, 'state')),
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        mediaProviders: []);
    await core.ready;
    AgentEndpoint? endpoint;
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      final history = <JsonMap>[];
      for (var i = 0; i < 367; i++) {
        final locator = i < 107
            ? p.join(
                root.path, 'videos', 'Series $i', 'Episode $i 2160p WEB-DL.mkv')
            : 'https://example.test/Series%20$i/episode$i.mkv?token=fixture-private';
        if (i < 107) {
          final file = File(locator);
          await file.parent.create(recursive: true);
          await file.writeAsString('offline video fixture $i');
        }
        await core.media.service.store.ensureFile(locator);
        history.add({
          'filePath': locator,
          'lastPosition': 10000,
          'duration': 20000,
          'watchProgress': 0.5,
          'lastWatchTime': '2026-10-11T00:00:00Z'
        });
      }
      core.stateSources.history = () => history;
      core.stateSources.continueWatching = () => history;
      core.stateSources.classicLibrary = classicLibraryStateViews(
          history: () => [], seriesDetail: (_) => null);
      final fileView = core.state.views['library.files']!;
      final sorted = await fileView.read(0, 500);
      final badLocator = sorted[137]['locator'];
      final invalidHistory =
          history.singleWhere((r) => r['filePath'] == badLocator);
      invalidHistory['duration'] = 0;
      invalidHistory['watchProgress'] = double.infinity;

      // Reproduce with the recorded base revision and synthetic production rows.
      final oldQuery = (await command(
              'git', ['show', '$baselineRef:lib/next/state/query.dart']))
          .stdout as String;
      await File(p.join(root.path, 'old_query.dart')).writeAsString(oldQuery);
      final raw = await fileView.read(0, 500);
      final jsonRows = [
        for (final row in raw)
          {
            ...row,
            'progress': {
              ...(row['progress'] as Map),
              if ((row['progress'] as Map)['progress'] == double.infinity)
                'progress': 'Infinity'
            }
          }
      ];
      await File(p.join(root.path, 'rows.json'))
          .writeAsString(jsonEncode(jsonRows));
      await File(p.join(root.path, 'baseline.dart')).writeAsString('''
import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'old_query.dart';
Future<void> main() async {
  final rows = (jsonDecode(await File('rows.json').readAsString()) as List).cast<JsonMap>();
  for (final r in rows) {if ((r['progress'] as Map)['progress']=='Infinity') (r['progress'] as Map)['progress']=double.infinity;}
  final capability = StateCapability([StateView(name:'library.files',description:'production synthetic records',fields:const ObjectSchema({
    'fileId':StringSchema(),'locator':StringSchema(nullable:true),
    'progress':ObjectSchema({'progress':NumberSchema(nullable:true),'durationMs':IntegerSchema(nullable:true)})
  }),read:(offset,limit) async=>rows.skip(offset).take(limit).toList())]);
  final api=Harness([capability]);
  for(final limit in [100,200]) {
    final r=await api.invokeJson('state.query',{'view':'library.files','limit':limit},Invocation(origin:'experiment'));
    stdout.writeln('baseline query limit=\$limit: \${r is Completed ? "rows=" + ((r.value.toJson()['rows'] as List).length.toString()) : jsonEncode(r.toEnvelope())}');
  }
}
''');
      // flutter_tester lives in bin/cache/artifacts/engine/...; use the SDK
      // selected by flutter rather than the shell's unrelated Dart version.
      final sdkDart = Platform.environment['FLUTTER_ROOT'] != null
          ? p.join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'dart')
          : p.join(Platform.environment['HOME']!, 'development',
              'flutter-3.44.6', 'bin', 'dart');
      final baseline = await command(
          sdkDart,
          [
            '--packages=${p.absolute('.dart_tool/package_config.json')}',
            'baseline.dart'
          ],
          cwd: root.path);
      stdout.writeln(baseline.stdout);
      expect(baseline.stdout, contains('state_read_failed'));
      expect(baseline.stdout, contains('limit=100: rows=100'));

      final store =
          SqliteJobStore.fromDatabase(core.media.service.store.database);
      for (var i = 0; i < 71; i++) {
        final now = DateTime.utc(2026, 10, 11).add(Duration(seconds: i));
        final state = i < 50
            ? JobState.succeeded
            : i < 67
                ? JobState.failed
                : i < 69
                    ? JobState.running
                    : JobState.paused;
        final job = Job(
            jobId: 'fixture-$i',
            type: 'fixture',
            title: 'Episode $i download',
            state: state,
            phase: 'download',
            progress: JobProgress(completed: 10, total: 20, unit: 'bytes'),
            createdAt: now,
            updatedAt: now,
            ownerDeviceId: core.deviceId,
            revision: 0,
            error: state == JobState.failed
                ? const Failure(
                    FailureCode.unavailable, 'fixture source unavailable')
                : null,
            receipt: state.isTerminal
                ? JobReceipt(
                    verification: state == JobState.succeeded
                        ? VerificationLevel.verified
                        : VerificationLevel.unverified,
                    details: {
                        'downloadComplete': state == JobState.succeeded,
                        'observation': 'fixture ' * 60,
                        'files': [
                          for (var f = 0; f < 2; f++)
                            {
                              'relativePath':
                                  'Season $i/Episode $f 2160p WEB-DL.mkv',
                              'path': p.join(root.path, 'videos', 'Season $i',
                                  'Episode $f.mkv'),
                              'size': 1024,
                              'verified': true
                            }
                        ]
                      })
                : null);
        await store.commit(
            job,
            JobEvent(
                jobId: job.jobId,
                revision: 0,
                kind: 'fixture',
                at: now,
                snapshot: job.toJson()),
            expectedRevision: null);
      }
      final seed = <String, List<int>>{};
      final source = Directory(p.absolute('assets/next/harness'));
      await for (final file in source.list(recursive: true)) {
        if (file is File) {
          seed[p.relative(file.path, from: source.path)] =
              await file.readAsBytes();
        }
      }
      endpoint = AgentEndpoint(
          harness: Harness([
            ...core.capabilities,
            LibraryCapability(history: () => [], seriesDetail: (_) => null)
          ]),
          seed: seed,
          appVersion: 'x4-experiment',
          credentialFile: credentials,
          seedRepository: upstream,
          port: 0);
      final started = await endpoint.start(repository);
      expect(started, isA<AgentEndpointRunning>());
      final connection = jsonDecode(await credentials.readAsString()) as Map;
      final url = Uri.parse(connection['url'] as String);
      final token = connection['token'] as String;
      final environment = {'NIPAPLAY_ENDPOINT_FILE': credentials.path};
      Future<ProcessResult> cli(List<String> args, {bool old = false}) =>
          command('/usr/bin/python3',
              [old ? p.join(root.path, 'old_nipa') : './nipa', ...args],
              cwd: repository.path, environment: environment);
      final oldNipa = (await command(
              'git', ['show', '$baselineRef:assets/next/harness/nipa']))
          .stdout as String;
      await File(p.join(root.path, 'old_nipa')).writeAsString(oldNipa);
      stdout.writeln(
          'Fixture: files=${raw.length}, tasks=71; production Core, SQLite, /harness, HTTP_PROXY bypass');
      for (final verb in ['list', 'status']) {
        final before = await cli([verb], old: true);
        final after = await cli([verb]);
        final full = await cli([verb, '--full']);
        final beforeBytes = utf8.encode(before.stdout as String).length;
        final afterBytes = utf8.encode(after.stdout as String).length;
        stdout.writeln(
            '$verb: before=$beforeBytes B, after=$afterBytes B, full=${utf8.encode(full.stdout as String).length} B, reduction=${(100 * (1 - afterBytes / beforeBytes)).toStringAsFixed(2)}%');
        expect(afterBytes, lessThan(beforeBytes ~/ 4));
        expect(jsonDecode(full.stdout as String),
            jsonDecode(before.stdout as String));
        if (verb == 'status') {
          stdout.writeln('\$ ./nipa status\n${after.stdout}');
        }
        if (verb == 'list') {
          final actions =
              (jsonDecode(after.stdout as String) as Map)['actions'] as List;
          stdout.writeln(
              'list sample (${actions.length} actions): ${jsonEncode(actions.take(4).toList())}');
        }
      }
      final described =
          jsonDecode((await cli(['describe', 'state.query'])).stdout as String)
              as Map;
      expect(described['inputSchema'], isA<Map>());
      final pageCli = jsonDecode(
          (await cli(['query', 'library.files', '{"limit":500}'])).stdout
              as String) as Map;
      expect(((pageCli['result'] as Map)['rows'] as List), hasLength(367));
      expect(
          ((pageCli['result'] as Map)['rows'] as List)
              .where((r) => (r as Map)['fileId'] == sorted[137]['fileId'])
              .single['progress']['progress'],
          null);
      expect(invalidHistory['watchProgress'], double.infinity);
      stdout.writeln(
          'CLI query limit=500: rows=367, warnings=[], nonfinite progress=null; source remains Infinity');

      Future<JsonMap> request(JsonMap input) async {
        final outgoing = await client.postUrl(url);
        outgoing.headers.set('Authorization', 'Bearer $token');
        outgoing.headers.contentType = ContentType.json;
        outgoing.write(jsonEncode(
            {'operation': 'call', 'action': 'state.query', 'input': input}));
        final response = await outgoing.close();
        expect(response.statusCode, 200);
        final envelope =
            jsonDecode(await utf8.decoder.bind(response).join()) as JsonMap;
        expect(envelope['status'], 'completed', reason: jsonEncode(envelope));
        return envelope['result'] as JsonMap;
      }

      Future<void> sweep(int run) async {
        final timer = Stopwatch()..start();
        String? cursor;
        final ids = <String>[];
        var pages = 0;
        do {
          final result = await request({
            'view': 'library.files',
            'limit': 50,
            if (cursor != null) 'cursor': cursor
          });
          expect(result['warnings'], isEmpty);
          ids.addAll((result['rows'] as List)
              .map((r) => (r as Map)['fileId'] as String));
          cursor = result['nextCursor'] as String?;
          pages++;
        } while (cursor != null);
        expect(ids, hasLength(367));
        expect(ids.toSet(), hasLength(367));
        stdout.writeln(
            'sweep $run: pages=$pages, rows=${ids.length}, unique=${ids.toSet().length}, failures=0, retries=0, elapsed=${timer.elapsedMilliseconds} ms');
      }

      for (var run = 1; run <= 5; run++) {
        await sweep(run);
      }
      await Future.wait([for (var run = 6; run <= 9; run++) sweep(run)]);
      final slow = StateCapability([
        StateView(
            name: 'slow',
            description: 'explicit slow source',
            fields: const ObjectSchema({'id': IntegerSchema()}),
            read: (offset, limit) async {
              await Future<void>.delayed(const Duration(milliseconds: 1200));
              return offset == 0
                  ? [
                      {'id': 1}
                    ]
                  : [];
            })
      ]);
      final timer = Stopwatch()..start();
      final slowResult = await slow.query({'view': 'slow'});
      expect(slowResult['rows'], hasLength(1));
      expect(slowResult['warnings'], isEmpty);
      stdout.writeln(
          'slow default query: rows=1, warnings=[], elapsed=${timer.elapsedMilliseconds} ms (> former 1000 ms budget)');

      stdout.writeln('\$ git remote -v\n${(await command('git', [
            'remote',
            '-v'
          ], cwd: repository.path)).stdout}');
      final initial =
          (await command('git', ['rev-parse', 'HEAD'], cwd: upstream.path))
              .stdout;
      await maintainHarnessSeed(upstream, seed);
      expect(
          (await command('git', ['rev-parse', 'HEAD'], cwd: upstream.path))
              .stdout,
          initial);
      final localNote = File(p.join(repository.path, 'agent-notes.md'));
      await localNote.writeAsString('Agent-owned file\n');
      final before = jsonEncode(await snapshot(repository));
      final next = {...seed, 'seed-upgrade.txt': utf8.encode('version 2\n')};
      await endpoint.stop();
      endpoint = AgentEndpoint(
          harness: Harness(core.capabilities),
          seed: next,
          appVersion: 'x4-upgraded',
          credentialFile: credentials,
          seedRepository: upstream,
          port: 0);
      expect(await endpoint.start(repository), isA<AgentEndpointRunning>());
      expect(jsonEncode(await snapshot(repository)), before);
      stdout.writeln(
          'Upgrade application start: harness bytes, modes and mtimes unchanged=true');
      stdout.writeln('\$ git fetch nipaplay');
      final fetched =
          await command('git', ['fetch', 'nipaplay'], cwd: repository.path);
      stdout.writeln(fetched.stderr);
      stdout.writeln('seed commits=${(await command('git', [
            'rev-list',
            '--count',
            'HEAD'
          ], cwd: upstream.path)).stdout.toString().trim()} (unchanged seed created no commit)');
      expect(
          (await command('git', ['merge-base', 'HEAD', 'nipaplay/main'],
                  cwd: repository.path))
              .stdout,
          initial);
      stdout.writeln(
          '\$ git show nipaplay/main:seed-upgrade.txt\n${(await command('git', [
                'show',
                'nipaplay/main:seed-upgrade.txt'
              ], cwd: repository.path)).stdout}');
      expect(await File(p.join(repository.path, 'seed-upgrade.txt')).exists(),
          false);
      stdout.writeln(
          '\$ git merge --ff-only nipaplay/main\n${(await command('git', [
                'merge',
                '--ff-only',
                'nipaplay/main'
              ], cwd: repository.path)).stdout}');
      expect(await localNote.readAsString(), 'Agent-owned file\n');
      stdout.writeln(
          'Agent merge: upgrade file present=true, local notes retained=true; EXPERIMENT COMPLETE');
    } finally {
      client.close(force: true);
      await endpoint?.stop();
      await core.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

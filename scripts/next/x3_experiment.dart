import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';

// A local file delivery stands in for a download. Transport, task persistence,
// hook execution and the seed CLI are the production implementations.
final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Delivery implements JobExecutor {
  _Delivery(this.target);
  final File target;
  @override
  String get type => 'download';
  @override
  Future<void> execute(JobContext context) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    await target.writeAsString('delivered by harness CLI');
    await context.markSideEffectCommitted();
    await context
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'files': [
        {'path': target.path, 'size': (await target.stat()).size}
      ]
    }));
  }

  @override
  Future<void> recover(JobContext context) => execute(context);
}

final class _Files implements Capability {
  _Files(TaskEngine engine, File target)
      : actions = [
          _FileAction('write', engine, target),
          _FileAction('delete', engine, target)
        ];
  @override
  final List<Action> actions;
}

final class _FileAction extends Action<NoInput, _Json> {
  _FileAction(this.verb, this.engine, this.target);
  final String verb;
  final TaskEngine engine;
  final File target;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'experiment.$verb',
      title: '$verb fixture file',
      description: verb == 'delete'
          ? 'Delete the delivered experiment file.'
          : 'Deliver a fixture file as a persisted task.',
      effect: verb == 'delete' ? Effect.destructive : Effect.write,
      input: const ObjectSchema({}),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  NoInput decodeInput(JsonMap json) => const NoInput();
  @override
  Future<Outcome<_Json>> run(NoInput input, Invocation invocation) async {
    if (verb == 'delete') {
      await target.delete();
      return const Completed(_Json({'deleted': true}));
    }
    final job =
        await engine.submit(type: 'download', title: 'Experiment delivery');
    return Completed(_Json({'job': job.toJson(), 'origin': invocation.origin}));
  }
}

Future<Map<String, Object?>> snapshot(Directory root) async {
  final entries = <String, Object?>{};
  await for (final file in root.list(recursive: true, followLinks: false)) {
    final stat = await file.stat();
    entries[p.relative(file.path, from: root.path)] = {
      'mode': stat.mode,
      'modified': stat.modified.toIso8601String(),
      if (file is File)
        'sha256': sha256.convert(await file.readAsBytes()).toString(),
    };
  }
  return entries;
}

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> main() async {
  sqfliteFfiInit();
  final temporary = await Directory.systemTemp.createTemp('nipa-x3-');
  final repository = Directory(p.join(temporary.path, 'harness'));
  final target = File(p.join(temporary.path, 'delivered.txt'));
  final credentials = File(p.join(temporary.path, 'private', 'endpoint.json'));
  final seed = <String, List<int>>{};
  final source = Directory(p.absolute('assets/next/harness'));
  await for (final file in source.list(recursive: true)) {
    if (file is File) {
      seed[p.relative(file.path, from: source.path)] = await file.readAsBytes();
    }
  }
  final store = await SqliteJobStore.open(
      Directory(p.join(temporary.path, 'state')),
      factory: databaseFactoryFfi);
  final hooks = HarnessHooks();
  final engine = TaskEngine(
      store: store,
      ownerDeviceId: 'x3-local',
      executors: [_Delivery(target), hooks]);
  hooks.engine = engine;
  await engine.start();
  final harness = Harness([TaskCapability(engine), _Files(engine, target)]);
  final endpoint = AgentEndpoint(
      harness: harness,
      seed: seed,
      appVersion: 'x3-experiment',
      credentialFile: credentials,
      port: 0);
  StreamSubscription<Job>? events;
  try {
    await endpoint.start(repository);
    final git = await Process.run('git', ['rev-list', '--count', 'HEAD'],
        workingDirectory: repository.path);
    require(git.exitCode == 0 && git.stdout.toString().trim() == '1',
        'Expected one seed commit.');
    stdout.writeln(
        'Seed repository: initial commits=${git.stdout.toString().trim()}, nipa mode=${(await File(p.join(repository.path, 'nipa')).stat()).mode & 0x1ff}');
    stdout.writeln(
        'Credential mode=${(await credentials.stat()).mode & 0x1ff}; outside repository=true');
    stdout.writeln('CLI interpreter: ${(await Process.run('/usr/bin/python3', [
          '--version'
        ])).stdout.toString().trim()}');
    final hook = File(p.join(repository.path, 'hooks', 'download.completed'));
    await hook.writeAsString('''#!/usr/bin/env python3
import json, os, pathlib, sys, time
event = json.load(sys.stdin)
assert event["event"] == "download.completed"
assert pathlib.Path.cwd().name == "harness"
assert pathlib.Path(os.environ["NIPAPLAY_ENDPOINT_FILE"]).is_file()
time.sleep(0.2)
pathlib.Path("records").mkdir(exist_ok=True)
pathlib.Path("records/hook-event.json").write_text(json.dumps(event))
print(json.dumps({"event": event["event"], "received": True}))
print("cookie=synthetic-secret-for-redaction", file=sys.stderr)
''');
    await Process.run('chmod', ['755', hook.path]);
    hooks.enable(repository, credentials);
    events = engine.changes.listen((job) {
      unawaited(hooks.taskChanged(job));
    });
    Future<JsonMap> nipa(List<String> args) async {
      final result = await Process.run('./nipa', args,
          workingDirectory: repository.path,
          environment: {
            'NIPAPLAY_ENDPOINT_FILE': credentials.path,
            'PATH': '/usr/bin:/bin:/usr/sbin:/sbin'
          });
      stdout.writeln('\$ ./nipa ${args.join(' ')}');
      stdout.writeln(result.stdout);
      require(result.exitCode == 0, 'nipa failed: ${result.stderr}');
      return jsonDecode(result.stdout as String) as JsonMap;
    }

    await nipa(['status']);
    final catalog = await nipa(['list']);
    require((catalog['actions'] as List).length == 6, 'Catalog mismatch');
    final inputFile = File(p.join(temporary.path, 'input.json'));
    await inputFile.writeAsString('{}');
    final written =
        await nipa(['call', 'experiment.write', '@${inputFile.path}']);
    final jobId =
        ((written['result'] as JsonMap)['job'] as JsonMap)['jobId'] as String;
    final watched = await nipa(['watch', jobId, '--seconds', '5']);
    require(
        ((watched['result'] as JsonMap)['job'] as JsonMap)['state'] ==
            'succeeded',
        'Delivery not verified');
    final preview = await nipa(['call', 'experiment.delete', '{}']);
    require(preview['executed'] == false && await target.exists(),
        'Preview changed data');
    List<Job> runs = [];
    final limit = Stopwatch()..start();
    while (runs.isEmpty && limit.elapsed < const Duration(seconds: 5)) {
      runs = await engine.list(type: 'harness.hook');
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    require(runs.length == 1, 'Expected event to submit one hook');
    final receipt = await nipa(['watch', runs.single.jobId, '--seconds', '5']);
    require(
        ((receipt['result'] as JsonMap)['job'] as JsonMap)['state'] ==
            'succeeded',
        'Hook failed');
    require(!jsonEncode(receipt).contains('synthetic-secret-for-redaction'),
        'Hook leaked a secret');
    final event = jsonDecode(
        await File(p.join(repository.path, 'records', 'hook-event.json'))
            .readAsString()) as Map;
    stdout.writeln('Event observed by executable: ${jsonEncode({
          'event': event['event'],
          'objectId': event['objectId'],
          'received': true
        })}');
    await File(p.join(repository.path, 'AGENTS.md'))
        .writeAsString('# Agent-owned instructions\n');
    final before = await snapshot(repository);
    await endpoint.stop();
    await endpoint.start(repository);
    final after = await snapshot(repository);
    require(jsonEncode(before) == jsonEncode(after),
        'Existing harness was modified');
    stdout.writeln(
        'Existing harness: ${before.length} entries; bytes, modes, and mtimes unchanged=true');
    stdout.writeln(
        'Destructive preview: delivered file still exists=${await target.exists()}');
    stdout.writeln('EXPERIMENT COMPLETE');
  } finally {
    await events?.cancel();
    await hooks.disable();
    await endpoint.stop();
    await engine.close();
    await temporary.delete(recursive: true);
  }
}

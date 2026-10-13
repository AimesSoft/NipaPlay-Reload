import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/headless/ports.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/mesh/capability.dart';
import 'package:nipaplay/next/programs/runtime.dart';
import 'package:nipaplay/next/programs/repository.dart';
import 'package:nipaplay/next/settings/denylist.dart';
import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('x46-constraints-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  ProgramRuntime runtime(bool enabled) =>
      ProgramRuntime(enabled: enabled, location: HeadlessRepository(root.path));
  test(
      'host-only permission is absent by default and cannot be set by an Action',
      () async {
    expect(await loadProgramPermission(root), false);
    final disabled = runtime(await loadProgramPermission(root));
    await File('${root.path}/program.json').writeAsString('{"enabled":true}');
    expect(await loadProgramPermission(root), true);
    final result = await Harness([disabled.capability]).invokeJson(
        'program.run',
        {'title': 'probe', 'command': 'echo should-not-run'},
        Invocation(origin: 'mesh:mac'));
    expect(result, isA<Failed>());
    for (final key in [
      'program.enabled',
      'program_enabled',
      'remoteRun.enabled',
      'remote_run_enabled',
      'mesh.coordinator',
      'mesh.issuer',
      'mesh.trust'
    ]) {
      expect(isSettingDenied(key), true, reason: key);
    }
  });
  test(
      'remote catalog includes useful target families and excludes host mutation',
      () {
    for (final id in [
      'subtitle.import',
      'history.mark_watched_batch',
      'settings.describe',
      'followup.register',
      'program.run',
      'ui.capture',
      'sync.run',
      'activity.report'
    ]) {
      expect(meshActionAllowed(id), true, reason: id);
    }
    for (final id in [
      'settings.set',
      'settings.reset',
      'accounts.login',
      'accounts.logout',
      'mesh.invoke',
      'mesh.devices',
      'credentials.set',
      'agent.dispatch',
      'app.quit'
    ]) {
      expect(meshActionAllowed(id), false, reason: id);
    }
  });
  test(
      'bundle chunks are idempotent and cannot replace already received content',
      () async {
    final receiver = ProgramRepository(runtime(true));
    final harness = Harness([receiver]);
    final data = utf8.encode('a committed fixture bundle');
    final digest = sha256.convert(data).toString();
    JsonMap chunk(int offset, List<int> bytes) => {
          'sha256': digest,
          'offset': offset,
          'totalBytes': data.length,
          'data': base64Encode(bytes)
        };
    Future<Outcome> call(JsonMap input) => harness.invokeJson(
        'program.repository.receive', input, Invocation(origin: 'mesh:mac'));
    final first = chunk(0, data.sublist(0, 10));
    expect(await call(first), isA<Completed>());
    expect(await call(first), isA<Completed>());
    expect(await call(chunk(0, utf8.encode('DIFFERENT!'))), isA<Failed>());
    expect(await call(chunk(15, data.sublist(15))), isA<Failed>());
    final complete = await call(chunk(10, data.sublist(10))) as Completed;
    final saved = complete.value.toJson();
    expect(saved['complete'], true);
    expect(await File(saved['path'] as String).readAsBytes(), data);
    expect(await call(first), isA<Completed>());
    expect(await root.list().where((e) => e is File).toList(), isEmpty);
    // A different authenticated sender cannot append to this sender's upload.
    final other = await harness.invokeJson('program.repository.receive',
        chunk(10, data.sublist(10)), Invocation(origin: 'mesh:other'));
    expect(other, isA<Failed>());
  });
  test('invalid digests and disabled receiving leave the harness untouched',
      () async {
    final receiver = ProgramRepository(runtime(false));
    final input = {
      'sha256': '0' * 64,
      'offset': 0,
      'totalBytes': 3,
      'data': 'YWJj'
    };
    expect(
        await Harness([receiver]).invokeJson('program.repository.receive',
            input, Invocation(origin: 'mesh:mac')),
        isA<Failed>());
    expect(await root.list().toList(), isEmpty);
    final enabled = ProgramRepository(runtime(true));
    expect(
        await Harness([enabled]).invokeJson('program.repository.receive',
            {...input, 'sha256': '../escape'}, Invocation(origin: 'mesh:mac')),
        isA<Failed>());
    expect(await root.list().toList(), isEmpty);
  });
  test('command and bundle payloads do not enter the invocation journal',
      () async {
    final journal = File('${root.path}/journal.jsonl');
    final r = runtime(false);
    await Harness([r.capability, ProgramRepository(r)],
            observers: [JsonlJournal(journal)])
        .invokeJson(
            'program.run',
            {
              'title': 'private title',
              'command': 'echo password=fixture-value'
            },
            Invocation(origin: 'mesh:mac'));
    final text = await journal.readAsString();
    expect(text, isNot(contains('fixture-value')));
    expect(text, isNot(contains('private title')));
  });

  test('origin-device Mesh journal does not expose a rejected command or bundle', () async {
    final journal = File('${root.path}/origin-journal.jsonl');
    final mesh = MeshRuntime(root: root, vault: MemoryVault(), token: () async => null);
    final harness = Harness([MeshCapability(mesh)], observers: [JsonlJournal(journal)]);
    await harness.invokeJson('mesh.invoke', {'deviceId': 'offline',
      'action': 'program.run', 'input': {'title': 'fixture', 'command': 'echo token=fixture-private'}},
      Invocation(origin: 'harness_cli'));
    await harness.invokeJson('mesh.invoke', {'deviceId': 'offline',
      'action': 'program.repository.receive', 'input': {'data': 'fixture-private-base64'}},
      Invocation(origin: 'harness_cli'));
    final text = await journal.readAsString();
    expect(text, isNot(contains('fixture-private')));
    await mesh.close();
  });
  test(
      'split output secrets and authenticated URLs stay redacted in bounded tails',
      () {
    final tail = ProgramOutputTail();
    tail.add('password=synthetic-');
    tail.add('fixture\nhttps://example.invalid/api?token=fixture\nnormal\n');
    expect(tail.value, isNot(contains('synthetic-fixture')));
    expect(tail.value, isNot(contains('token=fixture')));
    expect(tail.value, contains('normal'));
    tail.add('token=${'private' * 5000}');
    expect(tail.value.length, lessThanOrEqualTo(8192));
    expect(tail.value, isNot(contains('private')));
  });
  test('interrupted persisted command is failed without replaying its effect',
      () async {
    final store = MemoryJobStore();
    final initial = TaskEngine(
        store: store, ownerDeviceId: 'target', executors: [runtime(true)]);
    final job =
        await initial.submit(type: 'program', title: 'interrupted', input: {
      'command': 'touch replayed',
      'repository': root.path,
      'shell': 'sh',
      'timeoutSeconds': 1
    }, details: {
      'command': 'touch replayed'
    });
    final interrupted = Job.fromJson(
        {...job.toStorageJson(), 'state': 'interrupted', 'revision': 1});
    await store.commit(
        interrupted,
        JobEvent(
            jobId: job.jobId,
            revision: 1,
            kind: 'interrupted',
            at: interrupted.updatedAt,
            snapshot: interrupted.toJson()),
        expectedRevision: 0);
    final r = runtime(true);
    final engine =
        TaskEngine(store: store, ownerDeviceId: 'target', executors: [r]);
    r.engine = engine;
    await engine.start();
    final recovered = await untilState(engine, job.jobId, JobState.failed);
    expect(recovered.receipt!.details['reason'], 'interrupted_no_replay');
    expect(await File('${root.path}/replayed').exists(), false);
    await r.close();
    await engine.close();
  });
}

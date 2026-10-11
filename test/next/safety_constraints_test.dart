import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/settings/denylist.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/full_backup_service.dart';
import 'package:nipaplay/services/remote_control_access_guard_service.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../packages/nipa_harness/test/task_support.dart';
import '../security/memory_vault.dart';

final class _Delete extends Action<_Json, _Json> implements Capability {
  int effects = 0;
  @override
  List<Action> get actions => [this];
  @override
  ActionSpec get spec => const ActionSpec(
      id: 'download.delete',
      title: 'Delete',
      description: 'Delete files',
      effect: Effect.destructive,
      input: ObjectSchema({'jobId': StringSchema()}, required: ['jobId']),
      output: ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    effects++;
    return Completed(_Json({'deleted': true}));
  }
}

final class _Json implements JsonEncodable {
  _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

Future<Job> _terminal(TaskEngine engine, String id) async {
  var job = await engine.get(id);
  while (!job.state.isTerminal) {
    job = await engine.wait(id, afterRevision: job.revision);
  }
  return job;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'only application consent can delete; refusal and cancellation keep files',
      () async {
    final store = MemoryJobStore(), deletion = _Delete();
    var shown = Completer<void>(), answer = Completer<bool>();
    final guard = DiskDeletion(prompt: (title, message, stopped) {
      shown.complete();
      return Future.any([answer.future, stopped.then((_) => false)]);
    });
    final engine =
        TaskEngine(store: store, ownerDeviceId: 'local', executors: [guard]);
    guard.engine = engine;
    final api = Harness(guard.protect([deletion]));
    await engine.start();
    addTearDown(engine.close);
    Future<String> request() async {
      final outcome = await api.invokeJson(
          'download.delete', {'jobId': 'download'}, Invocation(origin: 'mcp'));
      return ((outcome as Completed).value.toJson()['job'] as JsonMap)['jobId']
          as String;
    }

    final id = await request();
    await shown.future;
    expect((await engine.get(id)).state, JobState.waitingUser);
    expect(deletion.effects, 0);
    expect(
        await api.invokeJson('download.delete',
            {'jobId': 'download', 'confirm': true}, Invocation(origin: 'mcp')),
        isA<Failed>());
    await expectLater(engine.resume(id), throwsA(isA<Failure>()));
    answer.complete(false);
    final declined = await _terminal(engine, id);
    expect(declined.state, JobState.failed);
    expect(declined.error!.message, '用户没有同意删除');
    expect(declined.receipt!.details['deleted'], false);
    expect(deletion.effects, 0);
    shown = Completer();
    answer = Completer();
    final cancelId = await request();
    await shown.future;
    await engine.cancel(cancelId);
    expect((await _terminal(engine, cancelId)).state, JobState.cancelled);
    expect(deletion.effects, 0);
    shown = Completer();
    answer = Completer();
    final approvedId = await request();
    await shown.future;
    answer.complete(true);
    expect((await _terminal(engine, approvedId)).receipt!.verification,
        VerificationLevel.verified);
    expect(deletion.effects, 1);
    expect(
        (await store.events(id)).map((e) => e.kind), contains('waiting_user'));
  });

  test('reopening waiting_user prompts again and never reuses an old approval',
      () async {
    final store = MemoryJobStore(), deletion = _Delete();
    var shown = Completer<void>();
    final first = DiskDeletion(prompt: (title, message, stopped) {
      shown.complete();
      return stopped.then((_) => false);
    });
    var engine =
        TaskEngine(store: store, ownerDeviceId: 'local', executors: [first]);
    first.engine = engine;
    final api = Harness(first.protect([deletion]));
    await engine.start();
    final outcome = await api.invokeJson(
        'download.delete', {'jobId': 'download'}, Invocation(origin: 'mcp'));
    final id = ((outcome as Completed).value.toJson()['job']
        as JsonMap)['jobId'] as String;
    await shown.future;
    await engine.close();
    shown = Completer();
    final answer = Completer<bool>();
    final second = DiskDeletion(prompt: (title, message, stopped) {
      shown.complete();
      return Future.any([answer.future, stopped.then((_) => false)]);
    });
    engine =
        TaskEngine(store: store, ownerDeviceId: 'local', executors: [second]);
    second.engine = engine;
    second.protect([deletion]);
    await engine.start();
    await shown.future;
    expect((await engine.get(id)).state, JobState.waitingUser);
    expect(deletion.effects, 0);
    answer.complete(false);
    await _terminal(engine, id);
    await engine.close();
    expect(deletion.effects, 0);
  });

  test(
      'backup preference filter runs before vault hydration; Classic default stays unchanged',
      () async {
    final previous = CredentialStore.instance, vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    addTearDown(() => CredentialStore.instance = previous);
    SharedPreferences.setMockInitialValues(
        {'labs_enable_agent_endpoint': false});
    final data = <String, dynamic>{
      'version': 2,
      'preferences': {
        'settings': {
          'labs_enable_agent_endpoint': true,
          'remote_control_receiver_enabled': true,
          'spoiler_ai_api_key': 'synthetic-secret',
          'danmaku_visible': false,
        }
      }
    };
    final service = FullBackupService();
    final result = await service.restoreFromData(
        backupData: data,
        categories: {BackupCategory.preferences},
        preferenceKeyAllowed: (key) => !isSettingDenied(key));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('labs_enable_agent_endpoint'), false);
    expect(prefs.containsKey('remote_control_receiver_enabled'), false);
    expect(prefs.getBool('danmaku_visible'), false);
    expect(result.preferencesResult!.skippedCount, 3);
    expect(vault.values, isEmpty);
    await service.restoreFromData(backupData: {
      'version': 2,
      'preferences': {
        'settings': {'labs_enable_agent_endpoint': true}
      }
    }, categories: {
      BackupCategory.preferences
    });
    expect(prefs.getBool('labs_enable_agent_endpoint'), true);
  });

  test(
      'Mesh receiver switch and Classic device revocation override Mesh account trust',
      () async {
    SharedPreferences.setMockInitialValues(
        {RemoteControlSettings.receiverEnabledKey: false});
    expect(await authorizeMeshPeer('test-mesh-peer', '测试设备'), isA<Failure>());
    await RemoteControlSettings.setReceiverEnabled(true);
    await RemoteControlSettings.addTrustedDevice(
        {'clientKey': 'id:test-mesh-peer', 'clientId': 'test-mesh-peer'});
    expect(await authorizeMeshPeer('test-mesh-peer', '测试设备'), isNull);
    await RemoteControlSettings.setReceiverEnabled(false);
    expect(await authorizeMeshPeer('test-mesh-peer', '测试设备'), isA<Failure>());
    await RemoteControlAccessGuardService.instance
        .removeTrustedDevice('id:test-mesh-peer');
    await RemoteControlSettings.setReceiverEnabled(true);
    expect(await authorizeMeshPeer('test-mesh-peer', '测试设备'), isA<Failure>());
  });

  test('Next backup cannot replace rejected settings or supply login secrets',
      () async {
    final previous = CredentialStore.instance, vault = MemoryVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    addTearDown(() => CredentialStore.instance = previous);
    SharedPreferences.setMockInitialValues({'timeline_preview_enabled': false});
    final result =
        await FullBackupService(allowInlineCredentials: false).restoreFromData(
            backupData: {
          'version': 2,
          'preferences': {
            'settings': {'timeline_preview_enabled': true}
          },
          'accounts': {
            'dandanplay': {'isLoggedIn': true, 'token': 'fixture-token'}
          },
        },
            categories: {
          BackupCategory.preferences,
          BackupCategory.accounts
        },
            preferenceRestorer: (key, value) async {
              throw const Failure(
                  FailureCode.conflict, 'User declined performance warning.');
            });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('timeline_preview_enabled'), false);
    expect(result.preferencesResult!.restoredCount, 0);
    expect(result.preferencesResult!.skippedItems.single['reason'],
        'setting_rejected');
    expect(result.accountsResult!.skippedItems.single['reason'],
        'forbidden_credential_input');
    expect(prefs.containsKey('dandanplay_logged_in'), false);
    expect(vault.values, isEmpty);
  });
}

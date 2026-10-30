import 'dart:async';
import '../state/change_history.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/services/auto_sync_service.dart';
import 'package:nipaplay/services/backup_category.dart';
import 'package:nipaplay/utils/auto_sync_settings.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import '../settings/registry.dart';
import '../capabilities/user_authorization.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'service.dart';

const syncConfigurationSchema = ObjectSchema({
  'url': StringSchema(),
  'username': StringSchema(),
  'remotePath': StringSchema(minLength: 1),
  'intervalMinutes': IntegerSchema(minimum: 5),
  'categories': ArraySchema(StringSchema(values: [
    'preferences',
    'mediaLibraries',
    'watchHistory',
    'episodeMatches',
    'accounts'
  ])),
  'syncOnRecordChange': BooleanSchema(),
});

final class SyncService {
  SyncService(this.sources);
  final MediaSourcesService sources;
  final classic = AutoSyncService.instance;
  Future<JsonMap> configuration() async => {
        'url': await AutoSyncSettings.getServerUrl(),
        'username': await AutoSyncSettings.getUsername(),
        'remotePath': await AutoSyncSettings.getRemotePath(),
        'intervalMinutes': await AutoSyncSettings.getIntervalMinutes(),
        'categories': (await AutoSyncSettings.getCategories())
            .map((c) => c.name)
            .toList(),
        'syncOnRecordChange': await AutoSyncSettings.getSyncOnRecordChange(),
      };
  Future<JsonMap> status() async => {
        'configuration': await configuration(),
        'enabled': await AutoSyncSettings.isEnabled(),
        'hasPassword': (await AutoSyncSettings.getPassword()).isNotEmpty,
        'syncing': classic.isSyncing,
        'phase': classic.phase.name,
        'completedRunCount': classic.completedRunCount,
        'lastSyncAt':
            (await AutoSyncSettings.getLastSyncAt())?.toIso8601String(),
        'lastError': await AutoSyncSettings.getLastSyncError(),
      };
  List<SettingEntry> settings() => [
        SettingEntry(
            key: 'sync.configuration',
            title: '多端同步',
            description:
                'Classic WebDAV incremental sync configuration. No password in configuration; use sync.login with authorized credentials or its login window. Omitted fields are retained by sync.configure.',
            schema: syncConfigurationSchema,
            defaultValue: {
              'url': '',
              'username': '',
              'remotePath': AutoSyncSettings.defaultRemotePath,
              'intervalMinutes': 30,
              'categories': BackupCategory.values.map((c) => c.name).toList(),
              'syncOnRecordChange': false
            },
            storageKey: '@runtime:sync.configuration',
            reader: 'AutoSyncSettings',
            writer: 'AutoSyncSettings.saveWebDavConfiguration',
            read: configuration,
            write: (v) async {
              await configure(v as JsonMap);
            },
            decodeStorage: (v) => v),
        SettingEntry(
            key: 'sync.enabled',
            title: '自动同步',
            description:
                'Enable or disable Classic incremental synchronization. Enabling immediately synchronizes. Prefer sync.enable to get a task receipt.',
            schema: const BooleanSchema(),
            defaultValue: false,
            storageKey: '@runtime:sync.enabled',
            reader: 'AutoSyncSettings.isEnabled',
            writer: 'AutoSyncService.enable/disable',
            read: AutoSyncSettings.isEnabled,
            write: (v) => enabled(v as bool),
            decodeStorage: (v) => v),
      ];
  Future<void> save(JsonMap value, String password) async {
    await AutoSyncSettings.saveWebDavConfiguration(
        serverUrl: value['url'] as String,
        username: value['username'] as String,
        password: password,
        remotePath: value['remotePath'] as String,
        intervalMinutes: value['intervalMinutes'] as int,
        categories: (value['categories'] as List)
            .map((n) => BackupCategory.values.byName(n as String))
            .toSet(),
        syncOnRecordChange: value['syncOnRecordChange'] as bool);
    await classic.reloadSchedule();
  }

  Future<void> _record(String key, Object? before, Object? after) =>
      runZoned(() => SettingsAccess.recordRegisteredRuntime(key, before, after),
          zoneValues: {
            SettingsAccess.invocationKey:
                BodyChanges.invocation ?? Invocation(origin: 'gui')
          });
  Future<JsonMap> configure(JsonMap input) => sources.serial(() async {
        final before = await configuration();
        final next = {...before, ...input};
        if ((next['categories'] as List).isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'Choose at least one sync category.');
        }
        next['url'] = (next['url'] as String).isEmpty
            ? ''
            : sources.validateUrl(next['url'] as String);
        final previousUrl = (before['url'] as String).isEmpty
            ? ''
            : sources.validateUrl(before['url'] as String);
        final sameAccount = next['url'] == previousUrl &&
            next['username'] == before['username'];
        await save(
            next, sameAccount ? await AutoSyncSettings.getPassword() : '');
        final after = await configuration();
        await _record('sync.configuration', before, after);
        return {'configuration': after};
      });
  Future<void> enabled(bool value) async {
    final before = await AutoSyncSettings.isEnabled();
    try {
      if (value) {
        await classic.enable();
      } else {
        await classic.disable();
      }
    } finally {
      await _record('sync.enabled', before, await AutoSyncSettings.isEnabled());
    }
  }

  Future<JsonMap> test() async {
    final c = await configuration();
    return {
      'connected': await classic.testConnection(
          serverUrl: c['url'] as String,
          username: c['username'] as String,
          password: await AutoSyncSettings.getPassword(),
          remotePath: c['remotePath'] as String)
    };
  }

  Future<JsonMap> submit(String operation, JsonMap input) async {
    if (operation == 'login' && input['password'] != null) {
      requireUserAuthorization(input);
      final password = input['password'] as String;
      SecretRedactor.remember(const CredentialRef('sync', 'login'), password);
      return sources.serial(() async {
        final c = await configuration();
        if ((c['url'] as String).isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'Configure sync.url before connecting.');
        }
        final connected = await classic.testConnection(
            serverUrl: c['url'] as String,
            username: c['username'] as String,
            password: password,
            remotePath: c['remotePath'] as String);
        if (!connected) {
          throw const Failure(FailureCode.unavailable,
              'Sync server did not accept the connection; login was not saved.');
        }
        await save(c, password);
        return {'connected': true, 'method': 'password'};
      });
    }
    final c = await configuration();
    if ((c['url'] as String).isEmpty && operation != 'enable') {
      throw const Failure(
          FailureCode.invalidInput, 'Configure sync.url before connecting.');
    }
    final job = await sources.engine.submit(
        type: 'sync.operation',
        title: operation == 'login'
            ? '登录同步服务器'
            : operation == 'enable'
                ? '设置自动同步'
                : '同步观看记录',
        input: {'operation': operation, ...input, 'configuration': c});
    return {'jobId': job.jobId};
  }

  Future<void> execute(JobContext context) async {
    final op = context.job.input['operation'];
    await context.running(
        phase: op == 'login' ? 'awaiting_password' : 'syncing');
    JsonMap details;
    if (op == 'login') {
      final c = context.job.input['configuration'] as JsonMap;
      final prompt = sources.requestPassword;
      if (prompt == null) {
        throw const Failure(FailureCode.unavailable,
            'The NipaPlay login window is not attached.');
      }
      final password = await prompt({
        'name': '同步服务器',
        'type': 'webdav',
        'url': c['url'],
        'username': c['username']
      }, context.stopRequested);
      if (password == null ||
          (await context.snapshot()).cancelRequestedAt != null) {
        await sources.engine.cancel(context.job.jobId);
        await context.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged,
            details: {'connected': false}));
        return;
      }
      await sources.serial(() async {
        final current = await configuration();
        if (current['url'] != c['url'] ||
            current['username'] != c['username']) {
          throw const Failure(
              FailureCode.conflict, 'Sync account changed during login.');
        }
        await classic.testConnection(
            serverUrl: c['url'] as String,
            username: c['username'] as String,
            password: password,
            remotePath: current['remotePath'] as String);
        await save(current, password);
      });
      details = {'connected': true};
    } else if (op == 'enable') {
      await enabled(context.job.input['enabled'] as bool);
      details = await status();
    } else {
      final result = await classic.manualSync();
      details = {
        'downloadedPatches': result.downloadedPatches,
        'uploadedOperations': result.uploadedOperations,
        'restoredOperations': result.restoredOperations,
        'createdRepository': result.createdRepository,
        ...await status()
      };
    }
    await context.markSideEffectCommitted();
    await context.succeed(JobReceipt(
        verification: VerificationLevel.verified,
        details: SecretRedactor.json(details) as JsonMap));
  }
}

final class SyncCapability implements Capability {
  SyncCapability(SyncService service)
      : actions = [
          for (final op in [
            'status',
            'configure',
            'login',
            'enable',
            'test',
            'run'
          ])
            _SyncAction(op, service)
        ];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _SyncAction extends Action<_Json, _Json> {
  const _SyncAction(this.op, this.service);
  final String op;
  final SyncService service;
  @override
  ActionSpec get spec => ActionSpec(
      id: 'sync.$op',
      title: switch (op) {
        'status' => '查看同步状态',
        'configure' => '设置多端同步',
        'login' => '登录同步服务器',
        'enable' => '设置自动同步',
        'test' => '测试同步连接',
        _ => '同步观看记录',
      },
      description: switch (op) {
        'status' =>
          'Read Classic incremental WebDAV configuration, hasPassword (presence only), enabled state, phase, run count and last success/error without returning secrets.',
        'configure' =>
          'Patch Classic incremental sync configuration. url is HTTP(S), remotePath is a directory on that server, intervalMinutes >= 5, categories is nonempty. Omitted fields stay unchanged. Changing url or username clears the old password; use sync.login. Does not enable synchronization.',
        'login' =>
          'With explicit user authorization, pass password and userAuthorization to test and save the configured sync login directly, returning connected and method without a job. Credentials may be supplied by the user or from a location they authorize. Passwords are never returned or stored in task inputs. Omit password to open the NipaPlay login window; that mode returns jobId for task.wait/cancel.',
        'enable' =>
          'Set enabled true or false. Enable immediately syncs like Classic. Returns jobId; use task.wait for its result. Disabling stops scheduled runs; an already active run completes.',
        'test' =>
          'Test the configured WebDAV repository through Classic using its saved credentials. Classic may create the configured remote directory. Does not enable sync.',
        _ =>
          'Run Classic incremental synchronization now, using the configured categories. Requires enabled. Returns jobId; task.wait returns downloadedPatches, uploadedOperations and restoredOperations. Classic merges concurrent runs; poll sync.status for the live phase.'
      },
      effect: op == 'status' ? Effect.read : Effect.write,
      input: op == 'configure'
          ? ObjectSchema(syncConfigurationSchema.properties)
          : op == 'enable'
              ? const ObjectSchema({'enabled': BooleanSchema()},
                  required: ['enabled'])
              : op == 'login'
                  ? const ObjectSchema({
                      'password': StringSchema(secret: true),
                      'userAuthorization': userAuthorizationSchema,
                    })
                  : const ObjectSchema({}),
      output: const ObjectSchema({}, additionalProperties: true));
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    try {
      final result = switch (op) {
        'status' => await service.status(),
        'configure' => await service.configure(input.value),
        'test' => await service.test(),
        _ => await service.submit(op, input.value)
      };
      return Completed(_Json(SecretRedactor.json(result) as JsonMap));
    } on Failure {
      rethrow;
    } catch (e) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$e'));
    }
  }
}

final class SyncExecutor implements JobExecutor {
  const SyncExecutor(this.service);
  final SyncService service;
  @override
  String get type => 'sync.operation';
  @override
  Future<void> execute(JobContext context) async {
    try {
      await service.execute(context);
    } on Failure {
      rethrow;
    } catch (e) {
      throw Failure(FailureCode.unavailable, SecretRedactor.text('$e'));
    }
  }

  @override
  Future<void> recover(JobContext context) => execute(context);
}

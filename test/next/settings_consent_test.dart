import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/settings/capability.dart';
import 'package:nipaplay/next/settings/consent.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/system_settings.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

SettingEntry _fixed(String key, Object? initial, harness.Schema schema,
    Map<String, Object?> store,
    {Object? fallback = ''}) {
  store[key] = initial;
  return SettingEntry(
      key: key,
      title: key,
      description: 'fixture',
      schema: schema,
      defaultValue: fallback,
      storageKey: 'fixture_$key',
      reader: 'test',
      writer: 'test',
      read: () async => store[key],
      write: (v) async => store[key] = v,
      decodeStorage: (v) => v);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MediaFixture media;
  late SubtitleLibrary subtitles;
  late SettingsRegistry registry;
  late SettingConsent consent;
  late harness.TaskEngine engine;
  late harness.Harness api;
  late SqliteJobStore jobs;
  late Map<String, Object?> store;
  late List<(String, String)> asked;
  var answer = true;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-consent-');
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    media = MediaFixture();
    await media.open();
    subtitles = SubtitleLibrary(media.service, media.root);
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    store = {};
    asked = [];
    answer = true;
    registry = SettingsRegistry(jobs.database, [
      ...SystemSettings(
              SidecarIndexer(DanmakuStore(media.identities), () async {}),
              subtitles)
          .entries(),
      _fixed('danmaku.spoilerAiApiUrl', '', const harness.StringSchema(), store),
      _fixed('network.httpProxy', '', const harness.StringSchema(), store),
      _fixed('plugins.githubProxyUrl', '', const harness.StringSchema(), store),
      _fixed('network.allowInvalidCertificates', false,
          const harness.BooleanSchema(), store,
          fallback: false),
      _fixed('network.fixturePlain', 'a', const harness.StringSchema(), store),
    ]);
    SettingsAccess.registry = registry;
    consent = SettingConsent(registry, prompt: (title, message, stopped) async {
      asked.add((title, message));
      return answer;
    });
    engine = harness.TaskEngine(
        store: jobs, ownerDeviceId: 'fixture-device', executors: [consent]);
    consent.engine = engine;
    api = harness.Harness(
        consent.protect([SettingsCapability(registry)]));
    await engine.start();
  });

  tearDown(() async {
    await registry.drain();
    SettingsAccess.registry = null;
    await engine.close();
    await subtitles.close();
    await media.close();
    await root.delete(recursive: true);
  });

  Future<harness.Outcome> invoke(String action, Map<String, Object?> input,
          {String origin = 'harness_cli'}) =>
      api.invokeJson(action, input, harness.Invocation(origin: origin));

  Future<Map<String, Object?>> completed(harness.Outcome outcome) async {
    expect(outcome, isA<harness.Completed>(), reason: '${outcome.toEnvelope()}');
    return (outcome as harness.Completed).value.toJson();
  }

  Future<harness.Job> finished(String jobId) async {
    for (var i = 0; i < 200; i++) {
      final job = await engine.get(jobId);
      if (job.state.isTerminal) return job;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('The task did not finish.');
  }

  harness.Decision decision(harness.Outcome outcome) {
    expect(outcome, isA<harness.NeedsDecision>(), reason: '${outcome.toEnvelope()}');
    return (outcome as harness.NeedsDecision).decision;
  }

  Future<String> requestJob(harness.Decision decision,
      {String origin = 'harness_cli'}) async {
    final option = decision.options.single;
    expect(option.call.actionId, 'settings.set.request');
    final result = await completed(
        await invoke(option.call.actionId, option.call.input, origin: origin));
    return (result['job'] as Map)['jobId'] as String;
  }

  test(
      'explicit authorization applies settings without a second prompt and keeps validation',
      () async {
    final outcome = await invoke('settings.set', {
      'key': 'network.httpProxy',
      'value': 'http://localhost:8080',
      'userAuthorization':
          'User requested sending application traffic through this proxy',
    });
    await completed(outcome);
    expect(store['network.httpProxy'], 'http://localhost:8080');
    expect(asked, isEmpty);
    final invalid = await invoke('settings.set', {
      'key': 'network.allowInvalidCertificates',
      'value': 'not-a-boolean',
      'userAuthorization': 'User requested changing certificate trust',
    });
    expect(invalid, isA<harness.Failed>());
    expect(store['network.allowInvalidCertificates'], false);
    final missing = await invoke('settings.set', {
      'key': 'network.httpProxy',
      'value': 'http://localhost:9999',
    });
    expect(missing, isA<harness.NeedsDecision>());
    expect(store['network.httpProxy'], 'http://localhost:8080');
  });

  test('an Agent setting an address that receives keys asks first and changes nothing',
      () async {
    final outcome = await invoke('settings.set', {
      'key': 'danmaku.spoilerAiApiUrl',
      'value': 'https://ai.example.org/v1',
      'reason': 'try a mirror'
    });
    final asking = decision(outcome);
    expect(asking.prompt, contains('ai.example.org'));
    expect(store['danmaku.spoilerAiApiUrl'], '');
    expect(asked, isEmpty);
    expect((await registry.get('danmaku.spoilerAiApiUrl'))['revision'], 0);
    expect(api.catalog.map((s) => s.id), contains('settings.set.request'));
    expect(
        api.catalog.firstWhere((s) => s.id == 'settings.set').description,
        contains('NeedsDecision'));
  });

  test('the user agrees: the change is applied with the Agent\'s reason and provenance',
      () async {
    final jobId = await requestJob(decision(await invoke('settings.set', {
      'key': 'network.httpProxy',
      'value': 'http://127.0.0.1:7890',
      'reason': 'use the local proxy'
    })));
    final job = await finished(jobId);
    expect(job.state.name, 'succeeded');
    expect(job.type, 'setting_consent');
    expect(job.receipt!.details['changed'], true);
    expect(store['network.httpProxy'], 'http://127.0.0.1:7890');
    expect(asked.single.$1, '更改HTTP 代理');
    expect(asked.single.$2, contains('http://127.0.0.1:7890'));
    final history = await registry.history(key: 'network.httpProxy');
    expect(history.single['changedBy'], 'agent');
    expect(history.single['reason'], 'use the local proxy');
  });

  test('the user declines: nothing changes and the task says so', () async {
    answer = false;
    final jobId = await requestJob(decision(await invoke('settings.set', {
      'key': 'network.allowInvalidCertificates',
      'value': true
    })));
    final job = await finished(jobId);
    expect(job.state.name, 'failed');
    expect(job.error!.message, '用户没有同意修改设置');
    expect(job.receipt!.details, {'changed': false, 'reason': 'user_declined'});
    expect(store['network.allowInvalidCertificates'], false);
    expect(asked.single.$1, '更改自签名证书');
    expect(await registry.history(key: 'network.allowInvalidCertificates'), isEmpty);
  });

  test('Bangumi\'s server (a real registry entry) needs the same yes', () async {
    final jobId = await requestJob(decision(await invoke('settings.set', {
      'key': 'network.bangumiServerUrl',
      'value': 'https://bgm.example.org'
    })));
    expect((await finished(jobId)).state.name, 'succeeded');
    expect((await registry.get('network.bangumiServerUrl'))['value'],
        'https://bgm.example.org');
  });

  test('safe values, resets, unchanged values and the settings page need no question',
      () async {
    store['plugins.githubProxyUrl'] = 'https://mirror.example/';
    await completed(await invoke('settings.set',
        {'key': 'plugins.githubProxyUrl', 'value': ''}));
    expect(store['plugins.githubProxyUrl'], '');
    store['network.allowInvalidCertificates'] = true;
    await completed(await invoke('settings.set',
        {'key': 'network.allowInvalidCertificates', 'value': false}));
    expect(store['network.allowInvalidCertificates'], false);
    store['network.httpProxy'] = 'http://127.0.0.1:1';
    await completed(await invoke('settings.set',
        {'key': 'network.httpProxy', 'value': 'http://127.0.0.1:1'}));
    await completed(await invoke('settings.reset', {'key': 'network.httpProxy'}));
    expect(store['network.httpProxy'], '');
    // The page is the person: origin gui is not asked.
    await completed(await invoke(
        'settings.set',
        {'key': 'danmaku.spoilerAiApiUrl', 'value': 'https://ai.example.org'},
        origin: 'gui'));
    expect(store['danmaku.spoilerAiApiUrl'], 'https://ai.example.org');
    // An ordinary setting is untouched by the gate.
    await completed(await invoke(
        'settings.set', {'key': 'network.fixturePlain', 'value': 'b'}));
    expect(store['network.fixturePlain'], 'b');
    expect(asked, isEmpty);
    expect(
        (await registry.history(key: 'network.fixturePlain')).single['changedBy'],
        'agent');
  });

  test('a batch with a sensitive change waits whole; approved, all of it is applied',
      () async {
    final outcome = await invoke('settings.set', {
      'changes': [
        {'key': 'network.fixturePlain', 'value': 'z', 'reason': 'with it'},
        {'key': 'network.httpProxy', 'value': 'http://127.0.0.1:9'},
      ]
    });
    final asking = decision(outcome);
    expect(store['network.fixturePlain'], 'a');
    final job = await finished(await requestJob(asking));
    expect(job.state.name, 'succeeded');
    expect(store['network.fixturePlain'], 'z');
    expect(store['network.httpProxy'], 'http://127.0.0.1:9');
    expect(asked.single.$2, contains('另外 1 项设置一并修改'));
  });

  test('an invalid value beside a valid one that needs the question rejects the whole call',
      () async {
    final outcome = await invoke('settings.set', {
      'changes': [
        {'key': 'network.fixturePlain', 'value': 'z'},
        {'key': 'network.httpProxy', 'value': 'http://127.0.0.1:5'},
        {'key': 'network.bangumiServerUrl', 'value': 'https://u:p@bgm.example'},
      ]
    });
    expect(outcome, isA<harness.Failed>(), reason: '${outcome.toEnvelope()}');
    expect(store['network.fixturePlain'], 'a');
    expect(store['network.httpProxy'], '');
    expect(asked, isEmpty);
  });

  test('an invalid sensitive value alone fails by itself and is never applied',
      () async {
    final done = await completed(await invoke('settings.set', {
      'changes': [
        {'key': 'network.fixturePlain', 'value': 'z'},
        {'key': 'network.bangumiServerUrl', 'value': 'https://u:p@bgm.example'},
      ]
    }));
    final results = (done['results'] as List).cast<Map>();
    expect(results.map((r) => r['status']), ['completed', 'failed']);
    expect((await registry.get('network.bangumiServerUrl'))['value'], '');
    expect(asked, isEmpty);
  });

  test('a preview belongs to its caller and is used once', () async {
    final asking = decision(await invoke('settings.set',
        {'key': 'network.httpProxy', 'value': 'http://127.0.0.1:2'}));
    final other = await invoke(asking.options.single.call.actionId,
        asking.options.single.call.input, origin: 'mcp');
    expect(other, isA<harness.Failed>());
    final jobId = await requestJob(asking);
    await finished(jobId);
    final again = await invoke(asking.options.single.call.actionId,
        asking.options.single.call.input);
    expect(again, isA<harness.Failed>());
  });

  test('the question shows addresses without credentials or query', () {
    expect(settingWords('https://user:secret@proxy.example:8080/p?token=abc#f'),
        'https://proxy.example:8080/p');
    expect(settingWords(''), '（空）');
    expect(settingWords(true), '开');
    expect(settingWords('x' * 300).length, lessThan(130));
    final (title, message) = settingConsentWords([
      {
        'key': 'network.allowInvalidCertificates',
        'from': '关',
        'to': '开'
      }
    ]);
    expect(title, '更改自签名证书');
    expect(message, contains('无效或自签名'));
    expect(jsonEncode(settingConsentRules.keys.toList()),
        contains('plugins.githubProxyUrl'));
  });
}

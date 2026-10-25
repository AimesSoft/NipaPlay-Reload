import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'package:nipaplay/next/danmaku/sidecar.dart';
import 'package:nipaplay/next/danmaku/store.dart';
import 'package:nipaplay/next/settings/prefs.dart';
import 'package:nipaplay/next/settings/registry.dart';
import 'package:nipaplay/next/settings/system_settings.dart';
import 'package:nipaplay/next/subtitles/library.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late MediaFixture media;
  late SubtitleLibrary subtitles;
  late SqliteJobStore jobs;
  late SettingsRegistry registry;
  late harness.Harness api;
  late SharedPreferences prefs;

  setUp(() async {
    sqfliteFfiInit();
    root = await Directory.systemTemp.createTemp('nipa-prefs-');
    SharedPreferences.setMockInitialValues({
      'bangumi_server_url': 'https://bgm.example.org',
      'my_notes_v1': 'hello',
      'counter_total': 5,
      'ratio_x': 0.5,
      'flags_list': ['a', 'b'],
      'flag_on': true,
      'dandanplay_token': 'tok-123',
      'web_server_port': 1180,
      'remote_control_trusted_devices': '[{"clientKey":"k1"}]',
      'custom_gateway_url': 'http://gateway.example',
      'trusted_cert_rules_v1': '{"host":"x"}',
      'spoiler_ai_api_key': 'sk-abc',
      'long_text': 'x' * 5000,
      'leaky_note': 'bearer Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => root.path);
    prefs = await SharedPreferences.getInstance();
    media = MediaFixture();
    await media.open();
    subtitles = SubtitleLibrary(media.service, media.root);
    jobs = await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    registry = SettingsRegistry(
        jobs.database,
        SystemSettings(
                SidecarIndexer(DanmakuStore(media.identities), () async {}),
                subtitles)
            .entries());
    SettingsAccess.registry = registry;
    api = harness.Harness([PrefsCapability(PrefsService(registry))]);
  });

  tearDown(() async {
    await registry.drain();
    SettingsAccess.registry = null;
    await subtitles.close();
    await media.close();
    await jobs.database.close();
    await root.delete(recursive: true);
  });

  Future<Map<String, Object?>> call(String action, Map<String, Object?> input,
      {String origin = 'harness_cli'}) async {
    final outcome =
        await api.invokeJson(action, input, harness.Invocation(origin: origin));
    expect(outcome, isA<harness.Completed>(),
        reason: '$action $input: ${outcome.toEnvelope()}');
    final value = (outcome as harness.Completed).value.toJson();
    expect(api.lookup(action)!.spec.output.validate(value), isEmpty);
    return value;
  }

  Future<harness.Failure> refused(String action, Map<String, Object?> input,
      {String origin = 'harness_cli'}) async {
    final outcome =
        await api.invokeJson(action, input, harness.Invocation(origin: origin));
    expect(outcome, isA<harness.Failed>(), reason: '$action $input');
    return (outcome as harness.Failed).failure;
  }

  Map<String, Map> byKey(Map<String, Object?> listed) => {
        for (final row in (listed['prefs'] as List).cast<Map>())
          row['key'] as String: row
      };

  test('the list says which keys a setting claims, which are secret, which are boundaries and which are open',
      () async {
    final listed = await call('settings.prefs.list', {});
    final rows = byKey(listed);
    expect(rows['bangumi_server_url']!['class'], 'claimed');
    expect(rows['bangumi_server_url']!['claimedBy'], ['network.bangumiServerUrl']);
    expect(rows['dandanplay_token']!['class'], 'credential');
    expect(rows['spoiler_ai_api_key']!['class'], 'credential');
    expect(rows['web_server_port']!['class'], 'boundary');
    expect(rows['remote_control_trusted_devices']!['class'], 'boundary');
    expect(rows['custom_gateway_url']!['class'], 'routing');
    expect(rows['trusted_cert_rules_v1']!['class'], 'routing');
    for (final key in ['my_notes_v1', 'counter_total', 'ratio_x', 'flags_list', 'flag_on']) {
      expect(rows[key]!['class'], 'open', reason: key);
      expect(rows[key]!['writable'], true);
    }
    expect(rows['my_notes_v1']!['type'], 'string');
    expect(rows['counter_total']!['type'], 'int');
    expect(rows['ratio_x']!['type'], 'double');
    expect(rows['flags_list']!['type'], 'stringList');
    expect(rows['flags_list']!['size'], 2);
    expect(rows['dandanplay_token']!['readable'], false);
    expect(rows['dandanplay_token']!['writable'], false);
    expect(rows['custom_gateway_url']!['readable'], true);
    expect(rows['custom_gateway_url']!['writable'], false);
    expect(rows['bangumi_server_url']!['writable'], false);
    expect(jsonEncode(listed), isNot(contains('tok-123')));
    expect(jsonEncode(listed), isNot(contains('hello')));
    final counts = listed['counts'] as Map;
    expect(counts['credential'], 2);
    expect(counts['boundary'], 2);
    expect(counts['claimed'], 1);
    expect(listed['total'], prefs.getKeys().length);

    final open = byKey(await call('settings.prefs.list', {'class': 'open'}));
    expect(open.keys, containsAll(['my_notes_v1', 'flag_on']));
    expect(open.values.every((r) => r['class'] == 'open'), isTrue);
    final page = await call('settings.prefs.list', {'limit': 3});
    expect((page['prefs'] as List), hasLength(3));
    expect(page['nextOffset'], 3);
    final found = byKey(await call('settings.prefs.list', {'keyword': 'GATEWAY'}));
    expect(found.keys, ['custom_gateway_url']);
  });

  test('get returns values, masks secrets in text and never returns credentials or boundaries',
      () async {
    final got = (await call('settings.prefs.get', {
      'keys': [
        'my_notes_v1',
        'counter_total',
        'flags_list',
        'bangumi_server_url',
        'dandanplay_token',
        'web_server_port',
        'absent_key',
        'long_text',
        'leaky_note',
      ]
    }))['prefs'] as List;
    final rows = {for (final row in got.cast<Map>()) row['key']: row};
    expect(rows['my_notes_v1']!['value'], 'hello');
    expect(rows['counter_total']!['value'], 5);
    expect(rows['flags_list']!['value'], ['a', 'b']);
    expect(rows['bangumi_server_url']!['value'], 'https://bgm.example.org');
    expect(rows['bangumi_server_url']!['claimedBy'], ['network.bangumiServerUrl']);
    expect(rows['dandanplay_token']!['withheld'], 'credential');
    expect(rows['dandanplay_token']!.containsKey('value'), false);
    expect(rows['web_server_port']!['withheld'], 'authorization_boundary');
    expect(rows['web_server_port']!.containsKey('value'), false);
    expect(rows['absent_key']!['present'], false);
    expect((rows['long_text']!['value'] as Map)['truncated'], true);
    expect((rows['long_text']!['value'] as Map)['length'], 5000);
    expect(jsonEncode(rows['leaky_note']), isNot(contains('abcdefghijklmnopqrstuvwxyz0123456789')));
    expect(jsonEncode(got), isNot(contains('tok-123')));
    expect(jsonEncode(got), isNot(contains('1180')));
  });

  test('set previews first, commits exactly the preview, records it and can be undone',
      () async {
    final preview = await call('settings.prefs.set',
        {'key': 'my_notes_v1', 'value': 'changed', 'reason': 'try'});
    expect(preview['committed'], false);
    expect(prefs.getString('my_notes_v1'), 'hello');
    expect((preview['before'] as Map)['value'], 'hello');
    expect((preview['after'] as Map)['value'], 'changed');

    final commit = await call('settings.prefs.set',
        {'previewId': preview['previewId'], 'reason': 'try'});
    expect(commit['committed'], true);
    expect(commit['commitId'], matches(RegExp(r'^prefs-\d+$')));
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'changed');
    // The preview is single-use.
    final reused = await refused('settings.prefs.set', {'previewId': preview['previewId']});
    expect(reused.code, harness.FailureCode.conflict);

    final history = (await call('settings.prefs.history', {'key': 'my_notes_v1'}))['commits'] as List;
    final row = history.single as Map;
    expect(row['commitId'], commit['commitId']);
    expect(row['changedBy'], 'agent');
    expect(row['origin'], 'harness_cli');
    expect(row['reason'], 'try');
    expect((row['before'] as Map)['value'], 'hello');
    expect((row['after'] as Map)['value'], 'changed');
    // Not part of the registry's own history.
    expect(await registry.history(), isEmpty);

    final dry = await call('settings.prefs.undo',
        {'commitId': commit['commitId'], 'dryRun': true});
    expect(dry['dryRun'], true);
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'changed');

    final undone = await call('settings.prefs.undo',
        {'commitId': commit['commitId'], 'reason': 'wrong key'});
    expect(undone['undoOf'], commit['commitId']);
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'hello');
    final all = (await call('settings.prefs.history', {}))['commits'] as List;
    expect(all.map((c) => (c as Map)['commitId']), [undone['commitId'], commit['commitId']]);
    expect((all.first as Map)['reason'], contains('undo of ${commit['commitId']}'));

    // The undo can be undone too.
    await call('settings.prefs.undo', {'commitId': undone['commitId']});
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'changed');
  });

  test('a new key, a removal and an existing key\'s type', () async {
    Future<Map<String, Object?>> write(Map<String, Object?> input) async {
      final preview = await call('settings.prefs.set', input);
      return call('settings.prefs.set', {'previewId': preview['previewId']});
    }

    await write({'key': 'fresh_flags', 'value': ['x', 'y']});
    await write({'key': 'fresh_count', 'value': 3});
    await write({'key': 'fresh_ratio', 'value': 1.5});
    await prefs.reload();
    expect(prefs.getStringList('fresh_flags'), ['x', 'y']);
    expect(prefs.getInt('fresh_count'), 3);
    expect(prefs.getDouble('fresh_ratio'), 1.5);
    // A double key takes a whole number as a double; an int key refuses 1.5.
    await write({'key': 'ratio_x', 'value': 2});
    await prefs.reload();
    expect(prefs.getDouble('ratio_x'), 2.0);
    expect((await refused('settings.prefs.set', {'key': 'counter_total', 'value': 1.5})).code,
        harness.FailureCode.invalidInput);
    expect((await refused('settings.prefs.set', {'key': 'flag_on', 'value': 'yes'})).code,
        harness.FailureCode.invalidInput);
    expect((await refused('settings.prefs.set', {'key': 'fresh_new', 'value': {'a': 1}})).code,
        harness.FailureCode.invalidInput);

    final removed = await write({'key': 'my_notes_v1', 'remove': true});
    await prefs.reload();
    expect(prefs.containsKey('my_notes_v1'), false);
    expect((removed['after'] as Map)['present'], false);
    await call('settings.prefs.undo', {'commitId': removed['commitId']});
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'hello');
    expect((await refused('settings.prefs.set', {'key': 'nothing_here', 'remove': true})).code,
        harness.FailureCode.invalidInput);
    expect((await refused('settings.prefs.set', {'key': 'flag_on', 'value': true})).message,
        contains('already'));
    expect((await refused('settings.prefs.set', {'key': 'flag_on', 'value': false, 'remove': true})).code,
        harness.FailureCode.invalidInput);
  });

  test('claimed keys, credentials, boundaries and routing keys are never written',
      () async {
    final claimed = await refused('settings.prefs.set',
        {'key': 'bangumi_server_url', 'value': 'https://evil.example'});
    expect(claimed.message, contains('settings.set'));
    expect(claimed.message, contains('network.bangumiServerUrl'));
    for (final key in [
      'dandanplay_token',
      'spoiler_ai_api_key',
      'web_server_port',
      'remote_control_trusted_devices',
      'custom_gateway_url',
      'trusted_cert_rules_v1',
      'brand_new_proxy_address',
    ]) {
      final failure = await refused('settings.prefs.set', {'key': key, 'value': 'x'});
      expect(failure.code, harness.FailureCode.invalidInput, reason: key);
    }
    final removal = await refused('settings.prefs.set', {'key': 'dandanplay_token', 'remove': true});
    expect(removal.code, harness.FailureCode.invalidInput);
    await prefs.reload();
    expect(prefs.getString('bangumi_server_url'), 'https://bgm.example.org');
    expect(prefs.getString('dandanplay_token'), 'tok-123');
    expect(prefs.getInt('web_server_port'), 1180);
    expect(prefs.containsKey('brand_new_proxy_address'), false);
    expect(await registry.database.query('settings_changes', where: "key LIKE 'prefs:%'"), isEmpty);
  });

  test('a value that looks like a credential is not written', () async {
    final failure = await refused('settings.prefs.set', {
      'key': 'notes_free',
      'value': 'Authorization: Bearer abcdefghijklmnopqrstuvwxyz0123456789'
    });
    expect(failure.message, contains('credential'));
    expect(prefs.containsKey('notes_free'), false);
  });

  test('a preview belongs to its caller, and a changed preference is not overwritten',
      () async {
    final preview = await call('settings.prefs.set', {'key': 'my_notes_v1', 'value': 'mine'},
        origin: 'harness_cli');
    final other = await refused('settings.prefs.set', {'previewId': preview['previewId']},
        origin: 'mcp');
    expect(other.code, harness.FailureCode.conflict);
    await prefs.setString('my_notes_v1', 'the user changed it');
    final stale = await refused('settings.prefs.set', {'previewId': preview['previewId']});
    expect(stale.code, harness.FailureCode.conflict);
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'the user changed it');
  });

  test('undo refuses when the preference moved on, and says how', () async {
    final preview = await call('settings.prefs.set', {'key': 'my_notes_v1', 'value': 'b'});
    final commit = await call('settings.prefs.set', {'previewId': preview['previewId']});
    await prefs.setString('my_notes_v1', 'c');
    final failure = await refused('settings.prefs.undo', {'commitId': commit['commitId']});
    expect(failure.code, harness.FailureCode.conflict);
    expect(failure.violations.single.message, contains('now'));
    await prefs.reload();
    expect(prefs.getString('my_notes_v1'), 'c');
    expect((await refused('settings.prefs.undo', {'commitId': 'prefs-99999'})).code,
        harness.FailureCode.notFound);
    expect((await refused('settings.prefs.undo', {'commitId': 'db-1'})).code,
        harness.FailureCode.invalidInput);
  });

  test('the settings page is recorded as the user', () async {
    final preview = await call('settings.prefs.set',
        {'key': 'my_notes_v1', 'value': 'from page'}, origin: 'gui');
    await call('settings.prefs.set', {'previewId': preview['previewId']}, origin: 'gui');
    final history = (await call('settings.prefs.history', {}))['commits'] as List;
    expect((history.single as Map)['changedBy'], 'user');
  });
}

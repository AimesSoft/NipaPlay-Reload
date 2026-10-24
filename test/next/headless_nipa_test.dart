@Timeout(Duration(minutes: 6))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/headless/agent_cli.dart';
import 'package:nipaplay/next/headless/model.dart';
import 'package:nipaplay/next/headless/nipa.dart';
import 'package:nipaplay/next/headless/vault.dart';
import 'package:nipaplay/next/settings/host_settings_service.dart';
import 'package:path/path.dart' as p;

/// What the person at a headless host sets for Nipa: the model and its key,
/// and the agent switch. (`headless_nipa_host_test.dart` runs the host.)
void main() {
  late Directory dir;
  late Directory data;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('headless-nipa-');
    data = Directory(p.join(dir.path, 'data'));
  });
  tearDown(() => dir.delete(recursive: true));

  group('the model and its key', () {
    test('the key goes to the vault, never into model.json, and out of no fact', () async {
      final vault = HeadlessVault(Directory(p.join(data.path, 'vault')));
      final model = HeadlessModel(root: data, vault: vault);
      expect((await model.facts()).missing, ['model', 'key']);
      final facts = await model.save(
          provider: 'Fixture',
          baseUrl: 'https://models.example/v1/',
          model: 'flash',
          key: 'sk-headless-fixture-0001');
      expect(facts.ready, true);
      expect(facts.baseUrl, 'https://models.example/v1');
      expect(jsonEncode(facts.toJson()), isNot(contains('sk-headless')));
      final saved = await File('${data.path}/model.json').readAsString();
      expect(saved, isNot(contains('sk-headless')));
      expect(jsonDecode(saved), containsPair('source', 'nipaplay'));
      // The same reference the desktop settings page uses, so each reads what
      // the other wrote.
      expect(HeadlessModel.keyRef(data, jsonDecode(saved) as Map<String, Object?>),
          HostSettingsService.modelKey(data, jsonDecode(saved) as Map<String, Object?>));
      final launch = await model.launch();
      expect(launch.route!.key, 'sk-headless-fixture-0001');
      expect(launch.route!.baseUrl, 'https://models.example/v1');
      expect(launch.route!.api, 'openai-responses');
      expect(launch.revision, 1);
      // The key is bound to its address: another address has none.
      final moved = await model.save(
          baseUrl: 'https://other.example/v1', model: 'flash', provider: 'Fixture');
      expect(moved.missing, ['key']);
      await expectLater(model.launch(), throwsA(isA<HeadlessModelMissing>()));
      await model.clear();
      expect((await model.facts()).missing, ['model', 'key']);
    });

    test('an address with credentials, a query or no scheme is refused', () async {
      final model = HeadlessModel(
          root: data, vault: HeadlessVault(Directory(p.join(data.path, 'vault'))));
      for (final bad in [
        'https://user:pass@models.example/v1',
        'https://models.example/v1?key=abc',
        'ftp://models.example',
        'models.example'
      ]) {
        await expectLater(
            model.save(baseUrl: bad, model: 'flash'), throwsFormatException,
            reason: bad);
      }
    });
  });

  group('the command line', () {
    test('--model-set reads the key from standard input and prints no secret', () async {
      final lines = <String>[];
      final code = await runHeadlessAgentCommand('model-set', data,
          options: {
            '--provider': 'Fixture',
            '--base-url': 'https://models.example/v1',
            '--model': 'flash',
            '--reasoning': 'low',
          },
          keyStdin: true,
          input: Stream.value(utf8.encode('sk-cli-fixture-0002\n')),
          write: lines.add);
      expect(code, 0);
      expect(lines.join('\n'), isNot(contains('sk-cli-fixture')));
      expect((jsonDecode(lines.first) as Map)['keyConfigured'], true);
      final marker = jsonDecode(await File('${data.path}/headless.json').readAsString());
      expect(marker, containsPair('host', 'nipaplay-headless'));
      final vault = HeadlessVault(Directory(p.join(data.path, 'vault')));
      final launch = await HeadlessModel(root: data, vault: vault).launch();
      expect(launch.route!.key, 'sk-cli-fixture-0002');
      expect(launch.route!.reasoningEffort, 'low');
      // No file under the data directory but the vault holds it.
      await for (final entity in data.list(recursive: true)) {
        if (entity is File && !entity.path.contains('${p.separator}vault${p.separator}')) {
          expect(await entity.readAsString(), isNot(contains('sk-cli-fixture')),
              reason: entity.path);
        }
      }
    });

    test('an empty key and an unknown command fail with a reason, not the key', () async {
      final lines = <String>[];
      var code = await runHeadlessAgentCommand('model-set', data,
          options: {'--base-url': 'https://models.example/v1', '--model': 'flash'},
          keyStdin: true,
          input: Stream.value(utf8.encode('\n')),
          write: lines.add);
      expect(code, 1);
      expect((jsonDecode(lines.single) as Map)['status'], 'failed');
      lines.clear();
      code = await runHeadlessAgentCommand('model-set', data,
          options: {'--model': 'flash'}, write: lines.add);
      expect(code, 1);
      expect(lines.single, contains('--base-url is required'));
    });

    test('the agent switch is on until it is turned off', () async {
      expect(await HeadlessAgentSwitch.enabled(data), true);
      final lines = <String>[];
      expect(await runHeadlessAgentCommand('agent-disable', data, write: lines.add), 0);
      expect(await HeadlessAgentSwitch.enabled(data), false);
      expect(await runHeadlessAgentCommand('agent-enable', data, write: lines.add), 0);
      expect(await HeadlessAgentSwitch.enabled(data), true);
      expect(await runHeadlessAgentCommand('agent-status', data, write: lines.add), 0);
      expect((jsonDecode(lines.last) as Map)['enabled'], true);
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/history_capability.dart';
import 'package:nipaplay/next/capabilities/library_capability.dart';
import 'package:nipaplay/next/capabilities/navigation_capability.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/settings/denylist.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'download_test_support.dart';
import 'media_test_support.dart';
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('runtime capability coverage contains the approved baseline', () async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('nipa-coverage-');
    final core = NextCore(
      root: root,
      databaseFactory: databaseFactoryFfi,
      downloadBackend: FakeDownloadBackend(root),
      downloadLibrary: FakeDownloadLibrary(),
      isDownloaderEnabled: () async => false,
      loadImportedKeys: () async => {},
      classic: MemoryClassic(),
      authorizedRoots: () => [root.path],
      mediaProviders: [],
    );
    await core.ready;
    addTearDown(() async {
      await core.close();
      await root.delete(recursive: true);
    });
    final playback = PlaybackFixture();
    final api = Harness([
      ...core.capabilities,
      LibraryCapability(
          history: () => playback.rows, seriesDetail: (_) => seriesDetail()),
      HistoryCapability(
          continueWatching: () => playback.rows,
          seriesDetail: (_) => seriesDetail()),
      playback.capability,
      NavigationCapability(changePage: (_) {}),
    ]);
    final actions = {for (final spec in api.catalog) spec.id: spec.effect.name};
    final settings = {
      for (final entry in core.settings.entries)
        entry.key: {'effect': 'write', 'scope': entry.scope}
    };
    for (final entry in core.settings.entries) {
      expect(isSettingDenied(entry.key), isFalse);
      expect(isSettingDenied(entry.storageKey), isFalse);
      expect(entry.schema.validate(entry.defaultValue), isEmpty,
          reason: entry.key);
      expect(entry.reader, isNotEmpty);
      expect(entry.writer, isNotEmpty);
    }
    final baselineFile = File('test/next/capability_coverage_baseline.json');
    final baseline = jsonDecode(await baselineFile.readAsString()) as Map;
    if (Platform.environment['NIPA_EXPORT_COVERAGE'] == '1') {
      await File('${Directory.systemTemp.path}/nipa-capability-coverage.json')
          .writeAsString('${const JsonEncoder.withIndent('  ').convert({
            ...Map<String, Object?>.from(baseline),
            'actions': actions,
            'settings': settings,
            'contracts': {
              for (final spec in api.catalog)
                spec.id: {
                  'effect': spec.effect.name,
                  'input': spec.input.toJsonSchema(),
                  'output': spec.output.toJsonSchema(),
                },
            },
          })}\n');
    }
    final expectedActions = baseline['actions'] as Map;
    final expectedSettings = baseline['settings'] as Map;
    final capabilities = baseline['capabilities'] as Map;
    final primary = baseline['primaryActions'] as Map;
    final compatibility = baseline['compatibility'] as Map;
    // Released rows remain the floor; merging tools must retain their abilities.
    for (final entry in expectedActions.entries) {
      expect(capabilities, contains(entry.key));
      expect(compatibility, contains(entry.key));
      final mapping = compatibility[entry.key] as Map;
      final capability = capabilities[entry.key] as Map;
      expect(capability['action'], mapping['action']);
      expect(capability['effect'], entry.value);
      expect(primary, contains(mapping['action']));
      expect(actions[mapping['action']], entry.value,
          reason: 'Missing ability: ${entry.key} → ${mapping['action']}');
    }
    for (final entry in capabilities.entries) {
      final capability = entry.value as Map;
      expect(primary, contains(capability['action']));
      expect(actions[capability['action']], capability['effect'],
          reason: 'Missing capability: ${entry.key}');
    }
    for (final verb in ['pause', 'resume']) {
      final mapping = compatibility['download.$verb'] as Map;
      expect(mapping['action'], 'download.set_paused');
      expect(mapping['inputDefaults'], {'paused': verb == 'pause'});
      expect(
          api.lookup(mapping['action'] as String)!.spec.input.validate({
            'jobId': 'coverage-target',
            ...Map<String, Object?>.from(mapping['inputDefaults'] as Map),
          }),
          isEmpty);
      expect(actions['download.$verb'], 'write');
    }
    for (final entry in primary.entries) {
      final contract = entry.value as Map;
      final spec = api.lookup(entry.key as String)!.spec;
      expect(spec.effect.name, contract['effect'], reason: entry.key as String);
      if (contract.containsKey('input')) {
        expect(spec.input.toJsonSchema(), contract['input'],
            reason: '${entry.key} input contract');
        expect(spec.output.toJsonSchema(),
            (baseline['outputContracts'] as Map)[contract['outputContract']],
            reason: '${entry.key} output contract');
      }
    }
    final scenarios = baseline['behaviorScenarios'] as Map;
    final behaviorTests = Directory('test/next')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('_test.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final entry in scenarios.entries) {
      expect(actions.containsKey(entry.key), isTrue);
      for (final scenario in entry.value as List) {
        expect(behaviorTests, contains(scenario as String),
            reason: 'Missing behavior scenario: $scenario');
      }
    }
    for (final entry in compatibility.entries) {
      final mapping = entry.value as Map;
      if (!mapping.containsKey('mode')) continue;
      expect(expectedActions.containsKey(entry.key), isTrue);
      expect(mapping['mode'], isIn(['alias', 'legacyRecovery']));
      expect(mapping['capability'], isNotEmpty);
      for (final target in mapping['targets'] as List) {
        expect(primary.containsKey(target), isTrue);
        expect(actions[target], (primary[target] as Map)['effect']);
        expect(scenarios[target], isNotEmpty);
      }
      if (mapping['mode'] == 'legacyRecovery') {
        expect(scenarios[entry.key], isNotEmpty);
      }
      if (mapping['action'] == 'state.query') {
        expect(actions[entry.key], 'read',
            reason: 'Legacy getter remains callable: ${entry.key}');
        expect(core.state.views,
            contains((mapping['inputDefaults'] as Map)['view']));
        expect(
            api.lookup('state.query')!.spec.input.validate(
                Map<String, Object?>.from(mapping['inputDefaults'] as Map)),
            isEmpty);
      }
    }
    for (final entry in expectedSettings.entries) {
      expect(settings[entry.key], entry.value,
          reason: 'Missing or changed setting: ${entry.key}');
    }
    debugPrint(
        'Capability coverage: ${capabilities.length} abilities, ${primary.length} primary actions, ${compatibility.length} compatibility mappings; ${actions.length} callable actions, ${settings.length} settings.');
  });
}

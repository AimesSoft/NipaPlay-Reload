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
            'settings': settings
          })}\n');
    }
    final expectedActions = baseline['actions'] as Map;
    final expectedSettings = baseline['settings'] as Map;
    for (final entry in expectedActions.entries) {
      expect(actions[entry.key], entry.value,
          reason: 'Missing or changed Action: ${entry.key}');
    }
    final primaryActions = baseline['primaryActions'] as Map;
    final compatibility = baseline['compatibility'] as Map;
    final scenarios = baseline['behaviorScenarios'] as Map;
    final danmakuTests = Directory('test/next')
        .listSync()
        .whereType<File>()
        .where(
            (f) => f.path.contains('danmaku_') && f.path.endsWith('_test.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');
    for (final entry in scenarios.entries) {
      expect(actions.containsKey(entry.key), isTrue);
      for (final scenario in entry.value as List) {
        expect(danmakuTests, contains(scenario as String),
            reason: 'Missing behavior scenario: $scenario');
      }
    }
    for (final entry in primaryActions.entries) {
      expect(actions[entry.key], entry.value,
          reason: 'Missing or changed primary Action: ${entry.key}');
      expect(scenarios[entry.key], isNotEmpty);
    }
    for (final entry in compatibility.entries) {
      final mapping = entry.value as Map;
      expect(expectedActions.containsKey(entry.key), isTrue);
      expect(mapping['mode'], isIn(['alias', 'legacyRecovery']));
      expect(mapping['capability'], isNotEmpty);
      for (final target in mapping['targets'] as List) {
        expect(primaryActions.containsKey(target), isTrue);
        expect(actions[target], primaryActions[target]);
        expect(scenarios[target], isNotEmpty);
      }
      if (mapping['mode'] == 'legacyRecovery') {
        expect(scenarios[entry.key], isNotEmpty);
      }
    }
    for (final entry in expectedSettings.entries) {
      expect(settings[entry.key], entry.value,
          reason: 'Missing or changed setting: ${entry.key}');
    }
    debugPrint(
        'Capability coverage: ${actions.length} actions, ${settings.length} settings.');
  });
}

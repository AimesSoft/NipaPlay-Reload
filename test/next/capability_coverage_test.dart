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
    if (Platform.environment['NIPA_EXPORT_COVERAGE'] == '1') {
      await File('${Directory.systemTemp.path}/nipa-capability-coverage.json')
          .writeAsString('${const JsonEncoder.withIndent('  ').convert({
            'actions': actions,
            'settings': settings
          })}\n');
    }
    final baseline = jsonDecode(await baselineFile.readAsString()) as Map;
    final expectedActions = baseline['actions'] as Map;
    final expectedSettings = baseline['settings'] as Map;
    for (final entry in expectedActions.entries) {
      expect(actions[entry.key], entry.value,
          reason: 'Missing or changed Action: ${entry.key}');
    }
    for (final entry in expectedSettings.entries) {
      expect(settings[entry.key], entry.value,
          reason: 'Missing or changed setting: ${entry.key}');
    }
    debugPrint(
        'Capability coverage: ${actions.length} actions, ${settings.length} settings.');
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/classic_mode_policy.dart';
import 'package:nipaplay/services/concurrent_video_processor.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LabsSettingsProvider labs;
  late NextUiPreference preference;
  late void Function() unbind;
  late bool Function() supported;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.labsEnableAgentEndpoint: true,
    });
    supported = NextUiPreference.deviceHasNext;
    NextUiPreference.deviceHasNext = () => true;
    labs = LabsSettingsProvider(sandboxStatus: () async => false);
    preference = NextUiPreference();
    unbind = ClassicModePolicy.bind(labs, preference);
    await labs.ready;
    await preference.ready;
  });
  tearDown(() {
    unbind();
    labs.dispose();
    preference.dispose();
    NextUiPreference.deviceHasNext = supported;
  });

  test('returning to Classic does not revive a pre-switch permit', () async {
    final permit = (await ClassicModePolicy.acquire())!;
    expect(permit.isCurrent, isTrue);
    await preference.setEnabled(true);
    expect(ClassicModePolicy.classicActive, isFalse);
    expect(await ClassicModePolicy.acquire(), isNull);
    await preference.setEnabled(false);
    expect(await permit.allowed, isFalse);
    expect(await ClassicModePolicy.acquire(), isNotNull);
  });

  test('Next blocks Classic startup, explicit scans and completed downloads',
      () async {
    await preference.setEnabled(true);
    var started = 0, matched = 0;
    final scan = ScanService.forTesting(startupAction: () async {
      started++;
    }, completedFilesProcessor: (_) async {
      matched++;
      return [];
    });
    addTearDown(scan.dispose);
    await scan.startStartupRefresh();
    await scan.startDirectoryScan('/must-not-touch');
    expect(
        await scan.scanCompletedFiles(['file.mkv'], folderPath: '/'), isFalse);
    final results = await ConcurrentVideoProcessor.processVideoPaths(
        ['file.mkv'], getVideoInfo: (_) async {
      matched++;
      return {};
    });
    expect(results, isEmpty);
    expect(started, 0);
    expect(matched, 0);
  });

  test('an in-flight Classic match cannot publish after a mode round trip',
      () async {
    final entered = Completer<void>();
    final response = Completer<Map<String, dynamic>>();
    var lookups = 0;
    final work = ConcurrentVideoProcessor.processVideoPaths(
        ['one.mkv', 'two.mkv'],
        maxConcurrency: 1, getVideoInfo: (_) {
      lookups++;
      entered.complete();
      return response.future;
    });
    await entered.future;
    await preference.setEnabled(true);
    await preference.setEnabled(false);
    response.complete({
      'isMatched': true,
      'matches': [
        {
          'animeId': 1,
          'episodeId': 2,
          'animeTitle': 'must not save',
        }
      ]
    });
    expect(await work, isEmpty);
    expect(lookups, 1);
  });
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForInitialLoad(ChangeNotifier provider) async {
  final completer = Completer<void>();
  void listener() {
    if (!completer.isCompleted) completer.complete();
  }

  provider.addListener(listener);
  await completer.future.timeout(const Duration(seconds: 2));
  provider.removeListener(listener);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('diffused low-resolution posters default on and persist', () async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppearanceSettingsProvider();
    await _waitForInitialLoad(provider);

    expect(provider.diffuseLowResolutionPosters, isTrue);

    await provider.setDiffuseLowResolutionPosters(false);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool('diffuse_low_resolution_recommendation_posters'),
      isFalse,
    );
  });

  test('fast playback setting loads and persists', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.fastPlaybackStartup: true,
    });
    final provider = SettingsProvider();
    await _waitForInitialLoad(provider);

    expect(provider.fastPlaybackStartup, isTrue);

    await provider.setFastPlaybackStartup(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SettingsKeys.fastPlaybackStartup), isFalse);
  });

  test('fast playback toggle lives in Player settings', () {
    final generalSettings = File(
      'lib/settings/pages/general_settings_content.dart',
    ).readAsStringSync();
    final playerSettings = File(
      'lib/settings/pages/player_settings_content.dart',
    ).readAsStringSync();

    expect(generalSettings, isNot(contains('fastPlaybackStartup')));
    expect(generalSettings, isNot(contains('快速开始播放')));
    expect(playerSettings, contains('快速开始播放'));
    expect(playerSettings, contains('settingsProvider.fastPlaybackStartup'));
    expect(
      playerSettings,
      contains('settingsProvider.setFastPlaybackStartup'),
    );
  });

  test('home recommendations support diffuse and subtle blur strengths', () {
    final source = File(
      'lib/themes/nipaplay/widgets/dashboard_home_page_build_hero.dart',
    ).readAsStringSync();

    expect(source, contains('.diffuseLowResolutionPosters'));
    expect(RegExp(r'\? 40\.0\s*: 3\.0').allMatches(source), hasLength(2));
    expect(
      RegExp(r'lowResBlurSigma: lowResolutionBlurSigma').allMatches(source),
      hasLength(2),
    );
  });

  test('loading overlay resolves a cached cover before its first build', () {
    final overlay = File(
      'lib/themes/nipaplay/widgets/loading_overlay.dart',
    ).readAsStringSync();
    final playerUi = File(
      'lib/themes/nipaplay/widgets/video_player_ui.dart',
    ).readAsStringSync();

    final initState = overlay.substring(
      overlay.indexOf('void initState()'),
      overlay.indexOf('void didUpdateWidget'),
    );
    expect(
        initState, contains('_coverImageUrl = _resolveImmediateCoverUrl();'));
    expect(initState, contains('_updateAnimeCoverUrl();'));
    expect(
      initState.indexOf('_resolveImmediateCoverUrl()'),
      lessThan(initState.indexOf('_updateAnimeCoverUrl()')),
    );
    expect(overlay, contains('getAnimeDetailsFromMemory(animeId)'));
    expect(
        playerUi, contains('coverImageUrl: videoState.loadingCoverImageUrl'));
  });

  test('fast playback defers recognition until playback is active', () {
    final source = File(
      'lib/utils/video_player_state/video_player_state_player_setup.dart',
    ).readAsStringSync();

    expect(source, contains('if (!fastPlaybackStartup)'));
    expect(source, contains('await loadInitialDanmaku();'));
    expect(source, contains('if (fastPlaybackStartup)'));
    expect(source, contains('_startBackgroundDanmakuLoading('));
    expect(source, contains('if (_status == PlayerStatus.playing) break;'));
    expect(source, contains('generation != _playbackGeneration'));

    final playCall = source.indexOf('play(); // Call our central play method');
    final backgroundCall = source.indexOf(
      '_startBackgroundDanmakuLoading(videoPath, loadInitialDanmaku);',
    );
    expect(playCall, greaterThanOrEqualTo(0));
    expect(backgroundCall, greaterThan(playCall));
  });
}

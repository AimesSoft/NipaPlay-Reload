import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/ui_scale_policy.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppearanceSettingsProvider> loadAppearance(
    {double? automaticScale}) async {
  final loaded = Completer<void>();
  final provider = AppearanceSettingsProvider(automaticUiScale: automaticScale);
  void onLoaded() {
    provider.removeListener(onLoaded);
    loaded.complete();
  }

  provider.addListener(onLoaded);
  addTearDown(provider.dispose);
  await loaded.future;
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('TV scale accounts for output resolution and logical density', () {
    for (final (size, dpr, expected) in [
      (const Size(1920, 1080), 2.0, 0.5),
      (const Size(1920, 1080), 1.0, 1.0),
      (const Size(1280, 720), 4 / 3, 0.75),
      (const Size(3840, 2160), 4.0, 0.5),
      (const Size(3840, 2160), 2.0, 1.0),
      (const Size(3840, 2160), 1.0, 1.3),
      (const Size(2160, 3840), 2.0, 1.0),
      (const Size(1920, 1080), 3.0, 0.5),
      (const Size(3840, 2160), 3.5, 0.55),
    ]) {
      expect(
        UiScalePolicy.forTelevisionDisplay(
            physicalSize: size, devicePixelRatio: dpr),
        closeTo(expected, 0.001),
        reason: '$size at DPR $dpr',
      );
    }
  });

  test('unavailable display metrics fall back to a usable scale', () {
    for (final (size, dpr) in [
      (Size.zero, 2.0),
      (const Size(double.infinity, 1080), 2.0),
      (const Size(1920, 1080), 0.0),
      (const Size(1920, 1080), double.nan),
    ]) {
      expect(
        UiScalePolicy.forTelevisionDisplay(
            physicalSize: size, devicePixelRatio: dpr),
        1.0,
      );
    }
  });

  test('new TV installs use the recommendation without storing a manual scale',
      () async {
    final provider = await loadAppearance(automaticScale: 0.5);
    expect(provider.useAutomaticUiScale, isTrue);
    expect(provider.uiScale, 0.5);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('ui_scale_factor'), isFalse);
    final nextLaunch = await loadAppearance(automaticScale: 0.75);
    expect(nextLaunch.uiScale, 0.75);
  });

  test('legacy manual choices survive the automatic scaling upgrade', () async {
    SharedPreferences.setMockInitialValues({'ui_scale_factor': 1.2});
    final provider = await loadAppearance(automaticScale: 0.5);
    expect(provider.useAutomaticUiScale, isFalse);
    expect(provider.uiScale, 1.2);
  });

  test('manual adjustment disables automatic scaling even at the same value',
      () async {
    final provider = await loadAppearance(automaticScale: 0.5);
    await provider.setUiScale(0.5);
    expect(provider.useAutomaticUiScale, isFalse);
    final nextLaunch = await loadAppearance(automaticScale: 0.75);
    expect(nextLaunch.useAutomaticUiScale, isFalse);
    expect(nextLaunch.uiScale, 0.5);
  });

  test('re-enabling automatic scaling recalculates on the next launch',
      () async {
    SharedPreferences.setMockInitialValues({'ui_scale_factor': 0.8});
    final provider = await loadAppearance(automaticScale: 0.5);
    await provider.setAutomaticUiScale(true);
    expect(provider.useAutomaticUiScale, isTrue);
    expect(provider.uiScale, 0.5);
    final nextLaunch = await loadAppearance(automaticScale: 0.75);
    expect(nextLaunch.useAutomaticUiScale, isTrue);
    expect(nextLaunch.uiScale, 0.75);
    await nextLaunch.setAutomaticUiScale(false);
    final manualLaunch = await loadAppearance(automaticScale: 1.0);
    expect(manualLaunch.useAutomaticUiScale, isFalse);
    expect(manualLaunch.uiScale, 0.75);
  });

  test('non-TV platforms keep their existing defaults and manual scaling',
      () async {
    final provider = await loadAppearance();
    expect(provider.supportsAutomaticUiScale, isFalse);
    expect(provider.useAutomaticUiScale, isFalse);
    expect(provider.uiScale, AppearanceSettingsProvider.defaultUiScale);
    await provider.setUiScale(0.8);
    await provider.setAutomaticUiScale(true);
    final nextLaunch = await loadAppearance();
    expect(nextLaunch.uiScale, 0.8);
    expect(nextLaunch.useAutomaticUiScale, isFalse);
  });
}

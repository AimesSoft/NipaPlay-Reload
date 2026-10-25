import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _waitForInitialLoad(AppearanceSettingsProvider provider) async {
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

  test('quarterly review defaults on and remembers the appearance switch',
      () async {
    SharedPreferences.setMockInitialValues({});
    final provider = AppearanceSettingsProvider();
    await _waitForInitialLoad(provider);
    expect(provider.showQuarterlyAnimeReview, isTrue);

    await provider.setShowQuarterlyAnimeReview(false);
    expect(provider.showQuarterlyAnimeReview, isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('show_quarterly_anime_review'), isFalse);

    final reloaded = AppearanceSettingsProvider();
    await _waitForInitialLoad(reloaded);
    expect(reloaded.showQuarterlyAnimeReview, isFalse);

    await reloaded.setShowQuarterlyAnimeReview(true);
    expect(prefs.getBool('show_quarterly_anime_review'), isTrue);
  });
}

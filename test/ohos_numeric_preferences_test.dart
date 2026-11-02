import 'package:flutter_test/flutter_test.dart';
// Use the vendored package's platform interface to simulate a native reload.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

// Exercise the OHOS implementation while the workspace uses mainline deps.
// ignore: avoid_relative_lib_imports
import '../packages/shared_preferences_ohos_compat/lib/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores whole-valued doubles returned as ints after OHOS restart',
      () async {
    // OHOS encodes 2.0 as an integer when its persisted getAll result crosses
    // the platform channel. This outline preference is read before area/speed.
    SharedPreferences.setMockInitialValues({
      'next2_danmaku_outline_width': 2,
      'danmaku_display_area': 0.25,
      'danmaku_speed_multiplier': 1.4,
      'merge_danmaku': true,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('next2_danmaku_outline_width'), 2.0);
    expect(prefs.getDouble('danmaku_display_area'), 0.25);
    expect(prefs.getDouble('danmaku_speed_multiplier'), 1.4);
    expect(prefs.getBool('merge_danmaku'), isTrue);
  });

  test('reload handles persisted whole-valued selections and keeps type checks',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('danmaku_display_area', 1.0);
    await prefs.setDouble('danmaku_speed_multiplier', 2.0);
    // Simulate the native store returning integral numbers as ints on reload.
    SharedPreferencesStorePlatform.instance =
        InMemorySharedPreferencesStore.withData({
      'flutter.danmaku_display_area': 1,
      'flutter.danmaku_speed_multiplier': 2,
      'flutter.invalid': '1.0',
    });
    await prefs.reload();
    expect(prefs.getDouble('danmaku_display_area'), 1.0);
    expect(prefs.getDouble('danmaku_speed_multiplier'), 2.0);
    expect(prefs.getDouble('missing'), isNull);
    expect(() => prefs.getDouble('invalid'), throwsA(isA<TypeError>()));
  });
}

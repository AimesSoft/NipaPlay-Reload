import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/apple_native_media_control.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('media detail glass defaults on and restores an explicit off choice',
      () async {
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceSettingsProvider();
    await appearance.ready;
    expect(appearance.enableMediaDetailLiquidGlass, isTrue);
    await appearance.setEnableMediaDetailLiquidGlass(false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(SettingsKeys.enableMediaDetailLiquidGlass), isFalse);
    final restored = AppearanceSettingsProvider();
    await restored.ready;
    expect(restored.enableMediaDetailLiquidGlass, isFalse);
    await restored.setEnableMediaDetailLiquidGlass(true);
    expect(prefs.getBool(SettingsKeys.enableMediaDetailLiquidGlass), isTrue);
    appearance.dispose();
    restored.dispose();
  });

  testWidgets(
      'disabling glass switches a supported button back without losing its action',
      (tester) async {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.ios,
        iosVersion: 26);
    addTearDown(native.PlatformInfo.clearPlatformOverride);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const capabilities = MethodChannel('nipaplay/native_media_controls');
    messenger.setMockMethodCallHandler(capabilities, (_) async => true);
    messenger.setMockMethodCallHandler(
        SystemChannels.platform_views, (_) async => null);
    await AppleNativeMediaControl.initialize();
    addTearDown(() async {
      messenger.setMockMethodCallHandler(capabilities, null);
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      await AppleNativeMediaControl.initialize();
    });
    SharedPreferences.setMockInitialValues({});
    final appearance = AppearanceSettingsProvider();
    await appearance.ready;
    var pressed = 0;
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: appearance,
      child: MaterialApp(
          home: Scaffold(
              body: Wrap(children: [
        AdaptiveMediaDetailActionButton(
          icon: Icons.chat_bubble_outline,
          label: '评论',
          onPressed: () => pressed++,
        ),
      ]))),
    ));
    expect(find.byType(AppleNativeMediaControl), findsOneWidget);
    await appearance.setEnableMediaDetailLiquidGlass(false);
    await tester.pump();
    expect(find.byType(AppleNativeMediaControl), findsNothing);
    await tester.tap(find.text('评论'));
    expect(pressed, 1);
    await appearance.setEnableMediaDetailLiquidGlass(true);
    await tester.pump();
    expect(find.byType(AppleNativeMediaControl), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    appearance.dispose();
  });
}

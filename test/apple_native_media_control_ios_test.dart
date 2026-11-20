import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/apple_native_media_control.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const capabilities = MethodChannel('nipaplay/native_media_controls');

  setUp(() {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.ios,
        iosVersion: 26);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(capabilities, null);
    await AppleNativeMediaControl.initialize();
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    native.PlatformInfo.clearPlatformOverride();
  });

  test('iOS needs a registered native bridge, not just the OS version',
      () async {
    for (final supported in [true, false]) {
      messenger.setMockMethodCallHandler(capabilities, (_) async => supported);
      await AppleNativeMediaControl.initialize();
      expect(
          AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, supported);
    }
    messenger.setMockMethodCallHandler(capabilities, null);
    await AppleNativeMediaControl.initialize();
    expect(AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, isFalse);
  });

  testWidgets(
      'iOS content and More items reach UIKit without a Flutter label overlay',
      (tester) async {
    messenger.setMockMethodCallHandler(capabilities, (_) async => true);
    await AppleNativeMediaControl.initialize();
    final created = <Map<Object?, Object?>>[];
    final channels = <MethodChannel>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        expect(args['viewType'], 'nipaplay/native_media_control');
        created.add(const StandardMessageCodec().decodeMessage(
                ByteData.sublistView(args['params'] as Uint8List))
            as Map<Object?, Object?>);
        final channel =
            MethodChannel('nipaplay/native_media_control_${args['id']}');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (_) async => null);
      }
      return null;
    });
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    var pressed = 0;
    int? selected;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      AdaptiveMediaDetailActionButton(
          icon: Icons.play_arrow,
          label: '继续观看',
          detail: '第 3 话',
          emphasis: MediaDetailActionEmphasis.primary,
          onPressed: () => pressed++),
      SizedBox(
          width: 100,
          child: AppleNativeMediaControl(
              label: '更多',
              symbol: 'ellipsis',
              items: const [
                {'label': '修改背景图', 'enabled': true}
              ],
              onSelected: (index) => selected = index)),
    ]))));
    await tester.pumpAndSettle();
    expect(find.byType(UiKitView), findsNWidgets(2));
    expect(find.text('继续观看'), findsNothing);
    expect(created.first['detail'], '第 3 话');
    expect(created.first['symbol'], 'play.fill');
    expect(created.first['primary'], isTrue);
    expect(created.last['items'], [
      {'label': '修改背景图', 'enabled': true}
    ]);
    await messenger.handlePlatformMessage(
        channels.first.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('pressed')),
        (_) {});
    await messenger.handlePlatformMessage(
        channels.last.name,
        const StandardMethodCodec()
            .encodeMethodCall(const MethodCall('selected', 0)),
        (_) {});
    expect(pressed, 1);
    expect(selected, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

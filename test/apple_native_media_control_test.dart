import 'package:adaptive_platform_ui/adaptive_platform_ui.dart' as native;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/themes/nipaplay/widgets/apple_native_media_control.dart';
import 'package:nipaplay/themes/nipaplay/widgets/adaptive_media_detail_action.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('nipaplay/native_media_controls');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.macos);
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(channel, null);
    await AppleNativeMediaControl.initialize();
    native.PlatformInfo.clearPlatformOverride();
  });

  test('macOS uses the native capability answer rather than the iOS gate',
      () async {
    for (final supported in [true, false]) {
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'supportsGlass');
        return supported;
      });
      await AppleNativeMediaControl.initialize();
      expect(AppleNativeMediaControl.supported, supported);
      expect(
          AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, supported);
    }
  });

  test('missing or failing native bridge clears support and falls back',
      () async {
    messenger.setMockMethodCallHandler(channel, (_) async => true);
    await AppleNativeMediaControl.initialize();
    expect(AppleNativeMediaControl.supported, isTrue);
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await AppleNativeMediaControl.initialize();
    expect(AdaptiveMediaDetailActionButton.supportsNativeLiquidGlass, isFalse);
    messenger.setMockMethodCallHandler(channel, null);
    await AppleNativeMediaControl.initialize();
    expect(AppleNativeMediaControl.supported, isFalse);
  });

  testWidgets('macOS click and keyboard activation reach Swift once each',
      (tester) async {
    final channels = <MethodChannel>[];
    final commands = <String>[];
    var pressed = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        final control =
            MethodChannel('nipaplay/native_media_control_${args['id']}');
        channels.add(control);
        messenger.setMockMethodCallHandler(control, (call) async {
          commands.add(call.method);
          if (call.method == 'activate') {
            await messenger.handlePlatformMessage(
                control.name,
                const StandardMethodCodec()
                    .encodeMethodCall(const MethodCall('pressed')),
                (_) {});
          }
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: GestureDetector(
      onTap: () => fail('parent must not consume native button clicks'),
      child: SizedBox(
          width: 120,
          child: AppleNativeMediaControl(
            label: '评论',
            symbol: 'bubble.right',
            onPressed: () => pressed++,
          )),
    ))));
    await tester.pumpAndSettle();
    final button = find.byType(AppleNativeMediaControl);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(commands.where((value) => value == 'activate').length, 1);
    expect(pressed, 1);
    // Native views remain visual; Flutter retains pointer and keyboard routing.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(commands.where((value) => value == 'activate').length, 2);
    expect(pressed, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('disabled macOS control does not dispatch activation',
      (tester) async {
    final commands = <String>[];
    MethodChannel? control;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        control = MethodChannel(
            'nipaplay/native_media_control_${(call.arguments as Map)['id']}');
        messenger.setMockMethodCallHandler(control!, (call) async {
          commands.add(call.method);
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      if (control != null) messenger.setMockMethodCallHandler(control!, null);
    });
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SizedBox(
      width: 120,
      child: AppleNativeMediaControl(label: '观看', symbol: 'play.fill'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppleNativeMediaControl));
    await tester.pumpAndSettle();
    expect(commands, isNot(contains('activate')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'native hover, press, keyboard release and cancellation stay synchronized',
      (tester) async {
    final interaction = <Map<Object?, Object?>>[];
    final channels = <MethodChannel>[];
    var activated = 0;
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'];
        final channel = MethodChannel('nipaplay/native_media_control_$id');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setInteraction') {
            interaction.add(Map<Object?, Object?>.from(call.arguments as Map));
          }
          if (call.method == 'activate') activated++;
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
          width: 120,
          child: AppleNativeMediaControl(
            label: '评论',
            symbol: 'bubble.right',
            onPressed: () {},
          )),
    ))));
    await tester.pumpAndSettle();
    final button = find.byType(AppleNativeMediaControl);
    final center = tester.getCenter(button);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(400, 400));
    await mouse.moveTo(center);
    await tester.pump();
    expect(interaction.last['hovered'], isTrue);
    final eventCount = interaction.length;
    await mouse.moveTo(center + const Offset(2, 0));
    await tester.pump();
    expect(interaction.length,
        eventCount); // Native AppKit tracks pointer movement.
    await mouse.down(center);
    await tester.pump();
    expect(interaction.last['pressed'], isTrue);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(interaction.last['pressed'], isFalse);
    expect(activated, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(interaction.last['pressed'], isTrue);
    expect(interaction.last['focused'], isTrue);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(activated,
        2); // Holding the activation key must not activate repeatedly.
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(interaction.last['pressed'], isFalse);
    await mouse.down(center);
    await tester.pump();
    expect(interaction.last['pressed'], isTrue);
    await mouse.cancel();
    await tester.pumpAndSettle();
    expect(interaction.last['pressed'], isFalse);
    expect(activated, 2);
    await mouse.moveTo(const Offset(400, 400));
    await tester.pump();
    expect(interaction.last['hovered'], isFalse);
    // Switching apps during a press must not leave a lit/pressed button behind.
    await mouse.moveTo(center);
    await mouse.down(center);
    await tester.pump();
    expect(interaction.last['pressed'], isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(interaction.last,
        {'hovered': false, 'pressed': false, 'focused': false});
    await mouse.cancel();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await mouse.moveTo(center + const Offset(2, 0));
    await tester.pump();
    expect(interaction.last['hovered'], isTrue);
    expect(interaction.last['pressed'], isFalse);
    expect(activated, 2);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Tab visits each macOS control once rather than focusing its visual view',
      (tester) async {
    final channels = <MethodChannel>[];
    final focused = <int, bool>{};
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final id = (call.arguments as Map)['id'] as int;
        final channel = MethodChannel('nipaplay/native_media_control_$id');
        channels.add(channel);
        focused[id] = false;
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'setInteraction') {
            focused[id] = (call.arguments as Map)['focused'] as bool;
          }
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Row(children: [
      SizedBox(
          width: 100,
          child: AppleNativeMediaControl(
              label: '评论', symbol: 'bubble.right', onPressed: () {})),
      SizedBox(
          width: 100,
          child: AppleNativeMediaControl(
              label: '更多', symbol: 'ellipsis', onPressed: () {})),
    ]))));
    await tester.pumpAndSettle();
    final ids = focused.keys.toList();
    expect(ids.length, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused[ids.first], isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(focused[ids.first], isFalse);
    expect(focused[ids.last], isTrue);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

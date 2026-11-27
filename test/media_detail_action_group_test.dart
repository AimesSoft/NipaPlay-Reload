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

  tearDown(() async {
    messenger.setMockMethodCallHandler(capabilities, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    await AppleNativeMediaControl.initialize();
    native.PlatformInfo.clearPlatformOverride();
  });

  Widget group(List<VoidCallback?> callbacks) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: AdaptiveMediaDetailActionGroup(
              nativeActions: [
                for (final (index, symbol) in [
                  'heart',
                  'bubble.left.and.bubble.right',
                  'square.and.pencil',
                  'ellipsis'
                ].indexed)
                  AppleNativeMediaAction(
                    label: ['收藏', '评论', '编辑 Bangumi 评分', '更多'][index],
                    symbol: symbol,
                    onPressed: callbacks[index],
                  ),
              ],
              children: [
                for (final (index, label)
                    in ['收藏', '评论', '编辑 Bangumi 评分', '更多'].indexed)
                  AdaptiveMediaDetailActionButton(
                    icon: Icons.favorite_outline,
                    label: label,
                    iconOnly: true,
                    grouped: true,
                    onPressed: callbacks[index],
                  ),
              ],
            ),
          ),
        ),
      );

  testWidgets(
      'capsule fits a phone and actions stay independent and accessible',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    final calls = <int>[];
    await tester.pumpWidget(group([
      () => calls.add(0),
      () => calls.add(1),
      null,
      () => calls.add(3),
    ]));
    expect(tester.getSize(find.byType(AdaptiveMediaDetailActionGroup)),
        const Size(184, 44));
    for (final label in ['收藏', '评论', '编辑 Bangumi 评分', '更多']) {
      await tester.tap(find.bySemanticsLabel(label));
    }
    expect(calls, [0, 1, 3]);
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Apple capsule uses one platform view with native symbols and disabled state',
      (tester) async {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.ios,
        iosVersion: 26);
    messenger.setMockMethodCallHandler(capabilities, (_) async => true);
    final creations = <Map>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') creations.add(call.arguments as Map);
      return null;
    });
    await AppleNativeMediaControl.initialize();
    await tester.pumpWidget(group([() {}, () {}, null, () {}]));
    await tester.pumpAndSettle();
    expect(creations, hasLength(1));
    final params = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(creations.single['params'] as Uint8List));
    final actions = (params as Map)['actions'] as List;
    expect(actions.map((action) => action['symbol']), [
      'heart',
      'bubble.left.and.bubble.right',
      'square.and.pencil',
      'ellipsis'
    ]);
    expect(actions[2]['enabled'], isFalse);
    expect(find.byType(AppleNativeMediaControl), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'macOS routes input through Flutter and reconnects native callbacks after returning',
      (tester) async {
    native.PlatformInfo.setPlatformOverride(native.PlatformOverride.macos);
    messenger.setMockMethodCallHandler(capabilities, (_) async => true);
    await AppleNativeMediaControl.initialize();
    final creations = <Map>[];
    final channels = <MethodChannel>[];
    final callbacks = <int>[];
    final activateCalls = <int>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform_views,
        (call) async {
      if (call.method == 'create') {
        final args = call.arguments as Map;
        creations.add(args);
        final channel =
            MethodChannel('nipaplay/native_media_control_${args['id']}');
        channels.add(channel);
        messenger.setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'activate') {
            final index = (call.arguments as Map)['index'] as int;
            activateCalls.add(index);
            // Simulate the native view firing its pressed callback for that
            // action so the round-trip Flutter tap -> channel -> callback works.
            await messenger.handlePlatformMessage(
                channel.name,
                const StandardMethodCodec()
                    .encodeMethodCall(MethodCall('pressed', {'index': index})),
                (_) {});
          }
          return null;
        });
      }
      return null;
    });
    addTearDown(() {
      for (final channel in channels) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    });
    Future<void> nativePress(MethodChannel channel, int index) async {
      await messenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec()
              .encodeMethodCall(MethodCall('pressed', {'index': index})),
          (_) {});
    }

    await tester.pumpWidget(group([
      () => callbacks.add(0),
      () => callbacks.add(1),
      null,
      () => callbacks.add(3),
    ]));
    await tester.pumpAndSettle();
    expect(creations, hasLength(1));
    expect(find.byType(AppleNativeMediaControl), findsNothing);
    final platformView = find.byType(AppKitView);
    expect(platformView, findsOneWidget);
    // Flutter owns input on macOS: the AppKitView must be wrapped in an active
    // IgnorePointer so the native view never receives duplicate events.
    expect(
        tester
            .widgetList<IgnorePointer>(find.ancestor(
                of: platformView, matching: find.byType(IgnorePointer)))
            .any((widget) => widget.ignoring),
        isTrue);
    // Tapping the capsule at each action's slot sends `activate` with the
    // matching index and fires the action callback. Slot 2 is disabled.
    final groupBox = tester.getRect(find.byType(AppleNativeMediaActionGroup));
    for (final xOffset in [4 + 22, 4 + 44 + 22, 4 + 88 + 22, 4 + 132 + 22]) {
      await tester.tapAt(groupBox.topLeft + Offset(xOffset.toDouble(), 22));
      await tester.pumpAndSettle();
    }
    expect(activateCalls, [0, 1, 3]); // index 2 is disabled, no activate sent.
    expect(callbacks, [0, 1, 3]); // index 2 is disabled, no callback.
    // Native-initiated callbacks still reach Flutter independently.
    callbacks.clear();
    await nativePress(channels.single, 1);
    await nativePress(channels.single, 2);
    await nativePress(channels.single, 99);
    expect(callbacks, [1]);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('另一页'))));
    await tester.pumpAndSettle();
    expect(find.byType(AppKitView), findsNothing);
    navigator.pop();
    await tester.pumpAndSettle();
    expect(creations, hasLength(2));
    await nativePress(channels.first, 0);
    expect(callbacks, [1]);
    await nativePress(channels.last, 0);
    expect(callbacks, [1, 0]);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

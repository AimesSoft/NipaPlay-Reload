import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/desktop_startup_window_placement.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final primary = {
    'id': 'primary',
    'size': {'width': 1920.0, 'height': 1080.0},
    'visiblePosition': {'dx': 0.0, 'dy': 24.0},
    'visibleSize': {'width': 1920.0, 'height': 1032.0},
  };
  final secondary = {
    'id': 'secondary',
    'size': {'width': 1600.0, 'height': 900.0},
    'visiblePosition': {'dx': -1600.0, 'dy': 24.0},
    'visibleSize': {'width': 1600.0, 'height': 852.0},
  };
  var cursor = const Offset(-800, 400);
  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.arguments, {'devicePixelRatio': 2.0});
      return switch (call.method) {
        'getPrimaryDisplay' => primary,
        'getAllDisplays' => {
            'displays': [primary, secondary]
          },
        'getCursorScreenPoint' => {'dx': cursor.dx, 'dy': cursor.dy},
        _ => throw StateError(call.method),
      };
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('windowed startup preserves cursor monitor and all five placements',
      () async {
    for (final entry in {
      Alignment.topLeft: const Offset(-1600, 24),
      Alignment.topRight: const Offset(-1280, 24),
      Alignment.center: const Offset(-1440, 90),
      Alignment.bottomLeft: const Offset(-1600, 156),
      Alignment.bottomRight: const Offset(-1280, 156),
    }.entries) {
      expect(
          await desktopStartupWindowPosition(
            const Size(1280, 720),
            entry.key,
            devicePixelRatio: 2,
          ),
          entry.value);
    }
  });

  test('cursor outside displays preserves primary display fallback', () async {
    cursor = const Offset(9000, 9000);
    expect(
        await desktopStartupWindowPosition(
          const Size(1280, 720),
          Alignment.center,
          devicePixelRatio: 2,
        ),
        const Offset(320, 180));
  });
}

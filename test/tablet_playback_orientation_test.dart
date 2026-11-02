import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/utils/screen_orientation_manager.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late List<List<String>> orientations;
  const landscape = [
    'DeviceOrientation.landscapeLeft',
    'DeviceOrientation.landscapeRight',
  ];
  const portrait = ['DeviceOrientation.portraitUp'];

  setUp(() {
    orientations = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'SystemChrome.setPreferredOrientations') {
          orientations.add(List<String>.from(call.arguments as List));
        }
        return null;
      },
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('portrait-locked tablet stays landscape after exit and next play',
      (tester) async {
    tester.view.physicalSize = const Size(1084, 2412);
    addTearDown(tester.view.resetPhysicalSize);
    final manager = ScreenOrientationManager.forTesting(
      isHarmonyOS: true,
      isMobilePlatform: true,
      isTablet: true,
    );
    await tester.runAsync(() async {
      expect(manager.isLandscape, isFalse);
      await manager.setInitialOrientation();
      expect(orientations.last, landscape);
      orientations.clear();
      await manager.resetOrientation();
      await manager.setVideoPlayingOrientation();
      await manager.setVideoStoppedOrientation();
      await manager.setVideoPlayingOrientation();
      expect(orientations, [landscape, landscape, landscape, landscape]);
    });
  });

  testWidgets('tablet play repairs an orientation changed outside playback',
      (tester) async {
    final manager = ScreenOrientationManager.forTesting(
      isHarmonyOS: true,
      isMobilePlatform: true,
      isTablet: true,
    );
    await tester.runAsync(() async {
      await manager.setInitialOrientation();
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      orientations.clear();
      await manager.setVideoPlayingOrientation();
      expect(orientations, [landscape]);
    });
  });

  testWidgets('phone still returns to portrait and reopens in landscape',
      (tester) async {
    final manager = ScreenOrientationManager.forTesting(
      isHarmonyOS: true,
      isMobilePlatform: true,
      isTablet: false,
    );
    await tester.runAsync(() async {
      await manager.setInitialOrientation();
      expect(orientations.last, portrait);
      await manager.setVideoPlayingOrientation();
      expect(orientations.last, landscape);
      await manager.resetOrientation();
      expect(orientations.last, portrait);
      await manager.setVideoPlayingOrientation();
      expect(orientations.last, landscape);
    });
  });

  testWidgets('desktop does not request mobile orientation changes',
      (tester) async {
    final manager = ScreenOrientationManager.forTesting(
      isHarmonyOS: false,
      isMobilePlatform: false,
      isTablet: false,
    );
    await manager.setInitialOrientation();
    await manager.resetOrientation();
    await manager.setVideoPlayingOrientation();
    expect(orientations, isEmpty);
  });
}

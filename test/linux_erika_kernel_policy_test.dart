import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Run once normally and once with --dart-define=NIPAPLAY_LINUX_ERIKA=true.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const enabled = bool.fromEnvironment('NIPAPLAY_LINUX_ERIKA');

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'fresh Linux install only defaults to Erika when its plugin is bundled',
    () async {
      await PlayerFactory.initialize();
      expect(PlayerFactory.isErikaKernelSupported, enabled);
      expect(
        PlayerFactory.getKernelType(),
        enabled ? PlayerKernelType.erika : PlayerKernelType.mdk,
      );
    },
  );

  test('Linux source build preserves a saved alternative kernel', () async {
    SharedPreferences.setMockInitialValues({
      'player_kernel_type': PlayerKernelType.mediaKit.index,
    });
    await PlayerFactory.initialize();
    expect(PlayerFactory.getKernelType(), PlayerKernelType.mediaKit);
  });

  test('saved Erika setting requires a bundled Linux plugin', () async {
    SharedPreferences.setMockInitialValues({
      'player_kernel_type': PlayerKernelType.erika.index,
    });
    await PlayerFactory.initialize();
    expect(
      PlayerFactory.getKernelType(),
      enabled ? PlayerKernelType.erika : PlayerKernelType.mdk,
    );
  });

  test('Linux build flag does not change the Windows default', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await PlayerFactory.initialize();
    expect(PlayerFactory.getKernelType(), PlayerKernelType.mdk);
  });
}

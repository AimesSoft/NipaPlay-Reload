import 'dart:async';
import 'dart:io';
import '../test/support/native_audio_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';

/// Native adapter smoke test. Run on the target device to cover its audio and
/// rendering backends; unit tests alone do not validate GPU/decoder handoff.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'alternating kernel create/teardown does not hang (6 rounds)',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp('kernel_swap_');
      final media = await writeNativeAudioFixture(directory);
      addTearDown(() => directory.delete(recursive: true));
      const rounds = 6;

      // 看门狗：整个序列必须在 90s 内完成（旧实现会在此永久挂起/冻结）。
      final watchdog = Timer(const Duration(seconds: 90), () {
        fail('watchdog: hot swap sequence exceeded 90s — native hang');
      });

      addTearDown(watchdog.cancel);

      for (var round = 1; round <= rounds; round++) {
        // 1) mdk 内核：创建 → 加载真实媒体
        //    → teardown（检查挂起、资源释放与重复调用）
        final sw = Stopwatch()..start();
        final mdkPlayer = MdkPlayerAdapter();
        mdkPlayer.setMedia(media.path, PlayerMediaType.video);
        await mdkPlayer.prepare();
        mdkPlayer.state = PlayerPlaybackState.playing;
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await mdkPlayer.disposeAsync();
        final mdkElapsed = sw.elapsed;
        PlayerKernelManager.traceHotSwapStage(
            'itest round=$round mdk teardown ${mdkElapsed.inMilliseconds}ms');
        expect(mdkElapsed.inSeconds, lessThan(10),
            reason: 'round $round: mdk teardown took $mdkElapsed');

        // 2) 并发 double disposeAsync 必须合并为同一次 teardown 并立即返回
        final doubleSw = Stopwatch()..start();
        await Future.wait([
          mdkPlayer.disposeAsync(),
          mdkPlayer.disposeAsync(),
        ]);
        expect(doubleSw.elapsed, lessThan(const Duration(seconds: 2)),
            reason: 'round $round: disposeAsync memoization broken '
                '(${doubleSw.elapsed})');

        // 3) media_kit(libmpv) 内核：同样场景，模拟 libmpv ↔ mdk 交替
        final swMk = Stopwatch()..start();
        final mediaKitPlayer = MediaKitPlayerAdapter();
        mediaKitPlayer.setMedia(media.path, PlayerMediaType.video);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await mediaKitPlayer.disposeAsync();
        final mkElapsed = swMk.elapsed;
        PlayerKernelManager.traceHotSwapStage(
            'itest round=$round media_kit teardown ${mkElapsed.inMilliseconds}ms');
        expect(mkElapsed.inSeconds, lessThan(12),
            reason: 'round $round: media_kit teardown took $mkElapsed');

        final mkDoubleSw = Stopwatch()..start();
        await Future.wait([
          mediaKitPlayer.disposeAsync(),
          mediaKitPlayer.disposeAsync(),
        ]);
        expect(mkDoubleSw.elapsed, lessThan(const Duration(seconds: 2)),
            reason: 'round $round: media_kit disposeAsync memoization broken '
                '(${mkDoubleSw.elapsed})');

        await tester.pump(const Duration(milliseconds: 50));
      }

      watchdog.cancel();
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}

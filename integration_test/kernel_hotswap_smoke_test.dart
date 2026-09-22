import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/player_abstraction/player_enums.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';

/// 内核热切换死锁冒烟测试（真原生实例，桌面端可跑，iOS 真机亦可跑）。
///
/// 复现的根因链：fvp 的 Player.dispose() 是 `async void`——内部
/// `await updateTexture(width:-1)`（releaseTexture 平台通道 + 等待
/// videoSize Completer）之后才执行 mdkPlayerAPI_delete，调用方等不到；
/// 旧实现调用后立即返回，旧 mdk 原生实例与新内核并存/并发 double delete，
/// 多轮交替切换在平台线程交叠 → 死锁卡死（用户 iPadOS 实测：空闲切换
/// 永不卡，播放中切换卡死；频繁切换第 4 次冻结）。
///
/// 媒体路径不存在时，fvp dispose 内部的 videoSize Completer 恰好永不
/// 完成——这是最恶劣的挂起分支，修复后 disposeAsync 必须在限期内完成。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets(
    'alternating kernel create/teardown does not hang (6 rounds)',
    (tester) async {
      const fakeMedia = 'NIPAPLAY_ITEST_NONEXISTENT_MEDIA.mp4';
      const rounds = 6;

      // 看门狗：整个序列必须在 90s 内完成（旧实现会在此永久挂起/冻结）。
      final watchdog = Timer(const Duration(seconds: 90), () {
        fail('watchdog: hot swap sequence exceeded 90s — native hang');
      });

      for (var round = 1; round <= rounds; round++) {
        // 1) mdk 内核：创建 → 设未加载媒体（videoSize 永不完成的最恶劣分支）
        //    → teardown（旧实现在这里挂起/泄漏/double delete）
        final sw = Stopwatch()..start();
        final mdkPlayer = MdkPlayerAdapter();
        mdkPlayer.setMedia(fakeMedia, PlayerMediaType.video);
        mdkPlayer.state = PlayerPlaybackState.playing;
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
        mediaKitPlayer.setMedia(fakeMedia, PlayerMediaType.video);
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

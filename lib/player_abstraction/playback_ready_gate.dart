import 'dart:async';

import 'player_abstraction.dart';

/// 非 MediaKit 内核（MDK）的媒体就绪门。
///
/// MDK prepare 的契约是：成功解码首帧后进入 paused，打开失败则停在 stopped。
/// duration>0 只说明读到了容器元数据，不等于可以渲染；若在 state 仍为
/// stopped 时放行，首帧永远不来的媒体会让 updateTexture 等 videoSize 直到
/// 超时，随后错误恢复级联会静默退出播放页（切集闪退回首页且无错误提示，
/// 见 issue #1010）。因此这里只在 paused/playing 放行；超时抛
/// [TimeoutException]，由调用方走统一的「打开媒体失败」错误路径。
///
/// [cancelled] 为真时静默返回且不区分“已就绪”，调用方须在返回后自行
/// 复查取消条件并中止后续初始化。
Future<void> waitForPlaybackReady(
  Player player, {
  required bool Function() cancelled,
  int maxPolls = 100,
  Duration pollInterval = const Duration(milliseconds: 100),
}) async {
  for (var poll = 0; poll < maxPolls; poll++) {
    await Future<void>.delayed(pollInterval);
    if (cancelled()) {
      return;
    }
    final state = player.state;
    if (state == PlaybackState.playing || state == PlaybackState.paused) {
      return;
    }
  }
  throw TimeoutException(
    '播放器未能开始解码媒体（state=${player.state.name}，'
    '内核=${player.getPlayerKernelName()}）',
  );
}

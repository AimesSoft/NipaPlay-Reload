part of video_player_state;

extension VideoPlayerStateLifecycle on VideoPlayerState {
  /// 处理应用生命周期变化，在移动端根据设置自动暂停。
  void handleAppLifecycleState(AppLifecycleState state) {
    if (!globals.isMobilePlatform) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 记录真实播放意图：进后台时是否处于播放状态。手动暂停后切后台
      // （status==paused）置 false，回前台不再被强制续播；播放中切后台
      // 置 true，回前台自动恢复（iOS 系统/内核可能已暂停内核）。
      _wasPlayingBeforeBackground = _status == PlayerStatus.playing;
      if (!_pauseOnBackground) return;
      if (_wasPlayingBeforeBackground) {
        debugPrint('[VideoPlayerState] 应用进入后台，自动暂停播放');
        pause();
      }
    } else if (state == AppLifecycleState.resumed) {
      // 回前台复位字幕编辑态：长按出框/拖动中切后台再回来，框与
      // dragActive 残留会拦截播放器长按倍速（video_player_ui 653 行）。
      setSubtitleEditBoxVisible(false);
      setSubtitleDragActive(false);
      // 后台因本功能自动暂停过 -> 回前台自动续播（erika/任何内核统一恢复）
      // iOS 退后台系统/内核可能暂停播放（无论是否开启自动暂停）：
      // 仅在进后台前确实在播时恢复；用户主动暂停的意图不被覆盖。
      if (hasVideo && _wasPlayingBeforeBackground) {
        _wasPlayingBeforeBackground = false;
        debugPrint('[VideoPlayerState] 回前台恢复播放');
        logPlayerEvent(
          'Player',
          '回前台恢复播放（内核 ${player.getPlayerKernelName()}）',
        );
        play();
      }
      // 回前台强制刷新一帧：iOS 切后台后渲染可能没跟上（画面灰/缺失），
      // 无论当前播放/暂停都同位置 seek 触发渲染（暂停时保持暂停态不变）。
      // 仅 iOS：Android libmpv 上这组 seek(-90ms)+seek(回) 会打乱外挂字幕
      // 轨道时间轴（字幕整体偏移，只能重开视频）。
      if (Platform.isIOS && hasVideo && _position.inMilliseconds > 0) {
        Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!hasVideo) return;
          final pos = _position.inMilliseconds;
          debugPrint('[VideoPlayerState] 回前台强制刷新画面帧 pos=$pos');
          // 同位置 seek 会被解码器优化掉（日志刷新但画面不重绘）：
          // 先退 90ms 强制解码新帧，再回到原位置，暂停态保持不变。
          final back = pos > 200 ? pos - 90 : 0;
          player.seek(position: back);
          Future<void>.delayed(const Duration(milliseconds: 160), () {
            if (hasVideo) {
              player.seek(position: pos);
            }
          });
        });
      }
    }
  }
}

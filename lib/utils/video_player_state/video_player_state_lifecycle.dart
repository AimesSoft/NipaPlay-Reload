part of video_player_state;

extension VideoPlayerStateLifecycle on VideoPlayerState {
  /// 处理应用生命周期变化，在移动端根据设置自动暂停。
  void handleAppLifecycleState(AppLifecycleState state) {
    if (!globals.isPhone) return;
    if (!_pauseOnBackground) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      if (_status == PlayerStatus.playing) {
        debugPrint('[VideoPlayerState] 应用进入后台，自动暂停播放');
        pause();
      }
    }
  }
}

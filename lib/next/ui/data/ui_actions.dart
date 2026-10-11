import '../../ui_data/ui_data.dart';

/// What the interface asks NipaPlay to do. Kept apart from [NextUiData],
/// which only reads.
abstract interface class NextUiActions {
  /// Plays [episode], or the work's next episode.
  Future<void> play(UiWork work, {UiEpisode? episode});
  Future<void> pauseTask(String taskId);
  Future<void> resumeTask(String taskId);
  Future<void> cancelTask(String taskId);

  /// Marks [episodes] watched or not, through `history.mark_watched_batch`
  /// like the agent. False when NipaPlay could not (no watch record yet).
  Future<bool> markWatched(List<UiEpisode> episodes, {required bool watched});

  /// Opens NipaPlay's own login window for [provider] (`accounts.login`).
  Future<void> login(String provider);
}

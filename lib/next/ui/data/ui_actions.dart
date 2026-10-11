import '../../ui_data/ui_data.dart';

/// What the interface asks NipaPlay to do. Kept apart from [NextUiData],
/// which only reads.
abstract interface class NextUiActions {
  /// Plays [episode], or the work's next episode.
  Future<void> play(UiWork work, {UiEpisode? episode});
  Future<void> pauseTask(String taskId);
  Future<void> resumeTask(String taskId);
  Future<void> cancelTask(String taskId);
}

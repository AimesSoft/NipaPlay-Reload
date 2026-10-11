/// What Next's own interface reads from the body.
///
/// The backend implements this on top of NextCore; the interface codes against
/// it and never parses Action envelopes. Every string here is shown to viewers
/// as is: natural, short, no IDs or process details.
library;

abstract interface class NextUiData {
  Future<UiHome> home();
  Future<UiWork?> work(String workId);
  Future<List<UiEpisode>> episodes(String workId, {int? season});

  /// Cards the agent presented in a chat turn, with live state resolved.
  Future<List<UiCard>> cards({required String threadId, String? turnId});

  /// Background tasks, emitted again whenever one changes.
  Stream<List<UiTask>> tasks();

  /// Fires when anything above may have changed; the interface re-reads.
  Stream<void> get changes;
}

/// Local file paths, ready for Image.file. [tint] is an ARGB colour taken
/// from the backdrop, for gradients while images load.
final class UiArtwork {
  const UiArtwork({this.backdrop, this.poster, this.logo, this.tint});
  final String? backdrop;
  final String? poster;
  final String? logo;
  final int? tint;
}

final class UiRating {
  const UiRating(this.source, this.value);

  /// Display name such as 'TMDB', '豆瓣', 'Bangumi'.
  final String source;
  final double value;
}

final class UiWork {
  const UiWork({
    required this.workId,
    required this.title,
    this.originalTitle,
    this.year,
    this.genres = const [],
    this.episodeCount,
    this.studio,
    this.overview,
    this.ratings = const [],
    this.artwork = const UiArtwork(),
    this.next,
  });
  final String workId;
  final String title;
  final String? originalTitle;
  final int? year;
  final List<String> genres;
  final int? episodeCount;
  final String? studio;
  final String? overview;
  final List<UiRating> ratings;
  final UiArtwork artwork;

  /// The episode a play button should start: next unwatched or in progress.
  final UiEpisode? next;
}

final class UiEpisode {
  const UiEpisode({
    required this.episodeId,
    required this.workId,
    required this.number,
    this.season,
    this.title,
    this.runtime,
    this.still,
    this.progress,
    this.heat,
    this.playable = false,
  });
  final String episodeId;
  final String workId;
  final int number;
  final int? season;
  final String? title;
  final Duration? runtime;

  /// Local file path of the episode still.
  final String? still;

  /// 0..1 when started, 1 when watched, null when never played.
  final double? progress;

  /// Danmaku density over the episode, normalised to 0..1, or null when
  /// there are no comments yet.
  final List<double>? heat;
  final bool playable;
}

final class UiHome {
  const UiHome({this.hero, this.shelves = const []});
  final UiHero? hero;
  final List<UiShelf> shelves;
}

final class UiHero {
  const UiHero(this.work, {this.note});
  final UiWork work;

  /// Nipa's one sentence about it, e.g. “准备好了，第一集随时可以看。”
  final String? note;
}

enum UiShelfKind { continueWatching, agent, recent }

final class UiShelf {
  const UiShelf({
    required this.id,
    required this.title,
    required this.kind,
    this.items = const [],
  });
  final String id;
  final String title;
  final UiShelfKind kind;
  final List<UiShelfItem> items;
}

final class UiShelfItem {
  const UiShelfItem(this.work, {this.episode, this.caption, this.badge});
  final UiWork work;
  final UiEpisode? episode;

  /// e.g. “第 31 集 · 剩 9 分钟”.
  final String? caption;

  /// A short corner label such as “新”.
  final String? badge;
}

enum UiTaskState { queued, running, paused, finished, failed }

final class UiTask {
  const UiTask({
    required this.taskId,
    required this.title,
    required this.state,
    this.artwork,
    this.progress,
    this.remaining,
  });
  final String taskId;
  final String title;
  final UiTaskState state;
  final UiArtwork? artwork;
  final double? progress;
  final Duration? remaining;
}

enum UiStepState { done, running, waiting, failed }

final class UiStep {
  const UiStep(this.label, this.state, {this.detail, this.progress});
  final String label;
  final UiStepState state;

  /// e.g. “简中内嵌 · 1080p”, “还要 3 分钟”.
  final String? detail;
  final double? progress;
}

final class UiCandidate {
  const UiCandidate(this.work, {this.reason});
  final UiWork work;
  final String? reason;
}

sealed class UiCard {
  const UiCard();
}

final class UiWorkCard extends UiCard {
  const UiWorkCard(this.work);
  final UiWork work;
}

final class UiEpisodeCard extends UiCard {
  const UiEpisodeCard(this.work, this.episode);
  final UiWork work;
  final UiEpisode episode;
}

final class UiCandidatesCard extends UiCard {
  const UiCandidatesCard(this.items);
  final List<UiCandidate> items;
}

final class UiPreparationCard extends UiCard {
  const UiPreparationCard(this.title, this.steps, {this.work});
  final String title;
  final List<UiStep> steps;
  final UiWork? work;
}

final class UiTaskCard extends UiCard {
  const UiTaskCard(this.task);
  final UiTask task;
}

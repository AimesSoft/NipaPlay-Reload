/// What Next's own interface reads from the body.
///
/// The backend implements this on top of NextCore; the interface codes against
/// it and never parses Action envelopes. Every string here is shown to viewers
/// as is: natural, short, no IDs or process details.
library;

/// What a playing file is in the library: the work and the episode.
abstract interface class NextNowPlaying {
  Future<UiNowPlaying?> nowPlaying(String path);
}

/// A playing file as the library knows it.
final class UiNowPlaying {
  const UiNowPlaying({
    required this.workId,
    required this.work,
    this.episodeId,
    this.episode,
  });

  /// The work, as [NextUiData.work] and [NextUiData.episodes] take it.
  final String workId;

  /// The work's name.
  final String work;

  /// The episode playing, as [NextUiData.episodes] lists it.
  final String? episodeId;

  /// The episode's name: “第 5 集 死者的幻影”.
  final String? episode;
}

abstract interface class NextUiData {
  Future<UiHome> home();
  Future<UiWork?> work(String workId);
  Future<List<UiEpisode>> episodes(String workId, {int? season});

  /// Every work the user has, on this device and the others in the mesh, one
  /// entry per real work; most recently added first.
  Future<List<UiWork>> library();

  /// Cards the agent presented in a chat turn, with live state resolved.
  /// A card's work may be one outside the library (`Found.isFound`), known
  /// from its provider; its page offers to prepare it.
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
    this.film = false,
    this.runtime,
    this.studio,
    this.overview,
    this.ratings = const [],
    this.artwork = const UiArtwork(),
    this.next,
    this.danmaku = const [],
    this.devices = const [],
  });
  final String workId;
  final String title;
  final String? originalTitle;
  final int? year;
  final List<String> genres;
  final int? episodeCount;

  /// Known to be a film: an identity NipaPlay holds says so (a TMDB movie,
  /// a server's Movie item). False for a series and when nobody knows.
  final bool film;

  /// How long it runs, when known: a film's length.
  final Duration? runtime;
  final String? studio;
  final String? overview;
  final List<UiRating> ratings;
  final UiArtwork artwork;

  /// The episode a play button should start: next unwatched or in progress.
  final UiEpisode? next;

  /// A few short comments viewers left on this work, for drifting over the
  /// hero. Empty when there are none.
  final List<String> danmaku;

  /// Other devices holding some of its episodes. Empty when everything is
  /// on this device.
  final List<UiDevice> devices;
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
    this.device,
  });
  final String episodeId;
  final String workId;

  /// Its stored number; null when it has none.
  final int? number;
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

  /// Whether it can be played right now, from here or from [device].
  final bool playable;

  /// The device it plays from; null when the file is on this device.
  final UiDevice? device;
}

/// Sorts [episodes] by season (none counts as [seasonless]), then by
/// number. In a season the ones without a number follow the numbered;
/// episodes left even keep the order they came in.
void sortEpisodes(List<UiEpisode> episodes, {int seasonless = 0}) {
  final order = {for (final (i, e) in episodes.indexed) e: i};
  episodes.sort((a, b) {
    final season =
        (a.season ?? seasonless).compareTo(b.season ?? seasonless);
    if (season != 0) return season;
    final number = switch ((a.number, b.number)) {
      (final x?, final y?) => x.compareTo(y),
      (null, _?) => 1,
      (_?, null) => -1,
      _ => 0,
    };
    return number != 0 ? number : order[a]!.compareTo(order[b]!);
  });
}

/// Another device in the user's mesh, as viewers know it.
final class UiDevice {
  const UiDevice({required this.name, this.online = true});

  /// The name its host gave it, e.g. “工作站”.
  final String name;

  /// False when it cannot be reached now; its works show from the last look.
  final bool online;
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

enum UiShelfKind {
  continueWatching,

  /// Works the user follows that have a new episode out today.
  airing,
  agent,
  recent,
}

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

enum UiTaskKind { background, helper }

final class UiTask {
  const UiTask({
    required this.taskId,
    required this.title,
    required this.state,
    this.artwork,
    this.progress,
    this.remaining,
    this.kind = UiTaskKind.background,
    this.startedAt,
    this.currentActivity,
    this.summary,
    this.threadId,
    this.parentThreadId,
    this.cancelled = false,
    this.source,
    this.type,
    this.workTitle,
    this.action,
  });
  final String taskId;
  final String title;

  /// The work it is for, when known: “迷宫饭”.
  final String? workTitle;

  /// What it does, in a word: “下载”.
  final String? action;
  final UiTaskState state;
  final UiArtwork? artwork;
  final double? progress;
  final Duration? remaining;
  final UiTaskKind kind;
  final DateTime? startedAt;
  final String? currentActivity;
  final String? summary;
  final String? threadId;
  final String? parentThreadId;
  final bool cancelled;
  final String? source;

  /// TaskEngine executor type, e.g. download or media.scan_classic.
  final String? type;
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

/// A question with a few answers to pick; picking one says it in the
/// conversation, as if the viewer had typed the label.
final class UiChoicesCard extends UiCard {
  const UiChoicesCard(this.options, {this.question});
  final String? question;
  final List<UiChoice> options;
}

final class UiChoice {
  const UiChoice(this.label, {this.detail, this.recommended = false});
  final String label;

  /// One short line on what sets it apart.
  final String? detail;

  /// The one Nipa would pick.
  final bool recommended;
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

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';

import '../capabilities/media_models.dart' show PlaybackSnapshot;
import '../capabilities/playback_capability.dart' show PlayerPort;
import '../capabilities/playback_controls_capability.dart'
    show PlaybackControlsPort;
import '../capabilities/playback_inspection.dart' show PlaybackInspectionPort;
import '../danmaku/service.dart'
    show DanmakuPlayerPort, DanmakuTrackRegistry, DanmakuTrackUpdater;
import '../settings/registry.dart' show SettingsRegistry;
import 'choices.dart';
import 'kernel/driver.dart' show VideoSurface;

export 'kernel/driver.dart' show VideoSurface, TextureSurface;
export 'package:nipaplay/services/intro_skip/skip_segment.dart'
    show SkipSegmentKind;
export 'package:nipaplay/utils/video_aspect_geometry.dart' show VideoAspectMode;
export 'choices.dart';

/// Where a playback is: what the session's phases will be (P1), read from
/// whatever plays now.
enum PlaybackPhase { idle, opening, ready, playing, paused, failed, closed }

/// What plays: the media, the open that asked for it and the kernel
/// instance under it. Changes when another media opens, the same one
/// reopens, its length becomes known or the kernel is replaced; never with
/// the position.
@immutable
final class PlaybackMedia {
  const PlaybackMedia({
    required this.path,
    required this.generation,
    required this.requestGeneration,
    required this.request,
    required this.durationKnown,
    required this.kernel,
  });

  static const none = PlaybackMedia(
      path: null,
      generation: 0,
      requestGeneration: 0,
      request: null,
      durationKnown: false,
      kernel: null);

  final String? path;

  /// Another media, or the same one again: each open has its own.
  final int generation;
  final int requestGeneration;

  /// The open that asked for what plays (compared by identity).
  final Object? request;
  final bool durationKnown;

  /// The kernel instance (compared by identity).
  final Object? kernel;

  @override
  bool operator ==(Object other) =>
      other is PlaybackMedia &&
      other.path == path &&
      other.generation == generation &&
      other.requestGeneration == requestGeneration &&
      identical(other.request, request) &&
      other.durationKnown == durationKnown &&
      identical(other.kernel, kernel);

  @override
  int get hashCode => Object.hash(path, generation, requestGeneration,
      identityHashCode(request), durationKnown, identityHashCode(kernel));
}

/// Whether it plays, as the player reports it ([status] is its own word,
/// as hooks and facts carry it). Never changes with the position.
@immutable
final class PlaybackTransport {
  const PlaybackTransport({
    required this.status,
    required this.phase,
    required this.hasVideo,
    required this.systemDrawn,
  });

  static const idle = PlaybackTransport(
      status: 'idle',
      phase: PlaybackPhase.idle,
      hasVideo: false,
      systemDrawn: false);

  final String status;
  final PlaybackPhase phase;
  final bool hasVideo;

  /// The system draws the video under the window (Erika, Media Kit's native
  /// video on macOS), not Flutter in a texture.
  final bool systemDrawn;

  bool get opening => phase == PlaybackPhase.opening;
  bool get playing => phase == PlaybackPhase.playing;

  /// Opening, or a video is up.
  bool get active => const {
        PlaybackPhase.opening,
        PlaybackPhase.ready,
        PlaybackPhase.playing,
        PlaybackPhase.paused,
      }.contains(phase);

  @override
  bool operator ==(Object other) =>
      other is PlaybackTransport &&
      other.status == status &&
      other.phase == phase &&
      other.hasVideo == hasVideo &&
      other.systemDrawn == systemDrawn;

  @override
  int get hashCode => Object.hash(status, phase, hasVideo, systemDrawn);
}

/// The danmaku tracks of what plays, for Next's danmaku service.
abstract interface class PlaybackDanmakuPort
    implements DanmakuPlayerPort, DanmakuTrackRegistry, DanmakuTrackUpdater {}

/// The subtitles of what plays, for Next's subtitle library and Mesh.
abstract interface class SubtitleTarget {
  /// The media the subtitles are for.
  String? get path;

  /// Offers a subtitle file without putting it on.
  Future<void> offer(String playbackPath, String title);

  /// One subtitle on screen: this embedded track, the files off.
  Future<void> applyEmbedded(int index);

  /// One subtitle on screen: this file, the embedded track off when the
  /// file is drawn over the video.
  Future<void> applyExternal(String playbackPath, String title);

  /// No subtitle at all.
  Future<void> clear();

  /// What is known of the subtitles of the file [fileId] changed: what was
  /// offered for it goes, its [tracks] (files) are offered and [selected]
  /// is put on (none when null), without telling it back as the person's
  /// choice.
  Future<void> reapply(String fileId, List<JsonMap> tracks, JsonMap? selected);

  /// Asked when a media opens: true when the subtitles were taken care of.
  set loader(Future<bool> Function(String path)? loader);

  /// Told when the person chooses a subtitle in the player.
  set selection(
      Future<void> Function(String path, int? index, String? external)?
          selection);
}

/// The kernel under what plays, for kernel reads and per-playback kernel
/// changes ([KernelControl]). [player] is the kernel itself while Classic's
/// player plays for Next; the session's driver takes its place (P4).
abstract interface class KernelHost {
  Player get player;
  PlayableItem? get request;
  String? get path;
  ValueListenable<PlaybackMedia> get media;
  ValueListenable<PlaybackTransport> get transport;
  bool get hasVideo;
  bool get paused;
  Duration get position;
  double get rate;
  List<String> get externalSubtitles;
  void selectEmbeddedAudio(int index);
  void subtitleTracksChanged();
  Future<void> addSubtitle(String path, String title);
  PlaybackSnapshot snapshot();

  /// The player's error for [sessionId], as playback.state reports it.
  JsonMap? error(String sessionId);

  /// Replaces the kernel and reopens [request] on [kernel] (null is the
  /// kernel setting).
  Future<void> reopen(PlayerKernelType? kernel, PlayableItem? request);
}

/// The picture of Next's own playback layer and what comes to it: the
/// stage under the controls draws [surface] (never the kernel, I3) and
/// sends the pointer and the keys here.
abstract interface class VideoStageHost {
  ValueListenable<VideoSurface?> get surface;
  void togglePlay();
  Future<void> toggleFullscreen();

  /// The pointer moved over the picture: the controls come up a while.
  void pointerMoved();

  /// A key while the picture is up; true when the player took it.
  bool key(KeyEvent event);
}

/// Next's playback: everything in Next that is not the player itself reads
/// and drives what plays through this. From P1 Next's own layer plays
/// ([SessionPlayback] over [NextPlayerHost]); [ClassicBackedPlayback], P0's
/// seam over Classic's player, stays only until P6 removes it.
///
/// What changes rarely is pushed ([media], [transport], [danmakuVersion]);
/// nothing in Next listens to the player at the rate its time moves except
/// the controls drawn over the video ([frame]).
abstract interface class NextPlayback {
  // ---- pushed, low frequency ----
  ValueListenable<PlaybackMedia> get media;
  ValueListenable<PlaybackTransport> get transport;

  /// Changes when the danmaku drawn over the video change (tracks loaded,
  /// removed, switched, moved).
  ValueListenable<int> get danmakuVersion;

  /// Notifies as the controls over the video need redrawing: over Next's
  /// own layer when what they show changes, and while they show, as the
  /// clock jumps and once a second as it runs.
  Listenable get frame;

  // ---- what the controls show ----
  bool get hasVideo;
  bool get showControls;
  String? get path;
  String? get workTitle;
  String? get episodeTitle;
  Duration get position;
  Duration get duration;
  Duration get buffered;
  bool get danmakuVisible;
  bool get fullscreen;

  /// Play was asked last (the play button), before the kernel confirms.
  bool get playIntent;

  /// What this playback offers besides play, pause, seeking, volume, speed
  /// and full screen.
  bool get offersDanmaku;
  bool get offersSubtitles;
  bool get offersScreenshot;
  double get volume;
  bool get canPlayNext;

  // ---- for capabilities and the rest of Next ----
  PlayerPort get port;
  PlaybackControlsPort get controls;
  PlaybackInspectionPort get inspection;
  KernelHost get kernelHost;
  SubtitleTarget get subtitleTarget;
  PlaybackDanmakuPort danmakuPort(
      {Future<void> Function(String bindingId, String operation, Object? value)?
          requestChange});

  /// Asked when a media opens, for danmaku files beside it.
  set localDanmakuLoader(Future<bool> Function(String path)? loader);

  /// Window, levels, danmaku sending and external players.
  Capability localOperations(
      SettingsRegistry settings, BuildContext Function() context);
  PlaybackSnapshot snapshot();
  Future<JsonMap> diagnostics();

  /// What plays, for an uncaught error's context.
  JsonMap errorContext();

  /// The player's failure now, for [PlaybackFailures.record].
  JsonMap captureFailure();
  Future<void> spoilerKeyChanged(String key);

  /// Lab-only VM service handles over the playback.
  void installDebug();

  /// Closes what plays, its progress and watch record saved, as leaving it
  /// does; nothing reopens it.
  Future<void> close({required String reason});

  // ---- the player's own controls, as the controls over the video ask ----
  static const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  /// How much of the screen danmaku may take: one line, then fractions.
  static const danmakuAreas = [0.0, 0.125, 0.25, 0.33, 0.67, 1.0];

  void togglePlay();
  void seek(Duration position);
  void toggleDanmaku();
  Future<void> toggleFullscreen();
  Future<void> nextEpisode();
  Future<void> setVolume(double value);
  void hover(bool over);
  SkipSegmentKind? get skippable;
  Future<void> skip();
  Future<void> leave();
  void holdHotkeys();
  void releaseHotkeys();
  List<double>? heat();
  Future<List<SubtitleChoice>> subtitles();
  Future<void> choose(SubtitleChoice choice);
  Future<bool> addSubtitleFile();
  Future<List<EpisodeChoice>> episodes();
  Future<void> play(EpisodeChoice episode);
  double get rate;
  Future<void> setRate(double rate);
  List<AudioChoice> audio();
  Future<void> chooseAudio(AudioChoice choice);
  bool get canFit;
  VideoAspectMode get fit;
  Future<void> setFit(VideoAspectMode mode);
  Future<String?> screenshot();
  Future<void> open(String path);
  bool get canPictureInPicture;
  Future<void> pictureInPicture(BuildContext context);
  PlayerDial get danmakuOpacity;
  Future<void> setDanmakuOpacity(double value);
  PlayerDial get danmakuSize;
  Future<void> setDanmakuSize(double value, {bool done = false});
  double get danmakuArea;
  Future<void> setDanmakuArea(double area);
  bool blocked(DanmakuLane lane);
  Future<void> block(DanmakuLane lane, bool on);
  PlayerDial get danmakuOffset;
  void setDanmakuOffset(double seconds);
  String? drawnOver(SubtitleChoice? on);
  PlayerDial subtitleDelay(SubtitleChoice? on);
  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds);
  bool canScaleSubtitles(SubtitleChoice? on);
  PlayerDial subtitleScale(SubtitleChoice? on);
  Future<void> setSubtitleScale(SubtitleChoice? on, double scale);
}

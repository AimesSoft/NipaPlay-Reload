import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/services/danmaku_density_analyzer.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../capabilities/media_models.dart';
import '../../capabilities/player_facts.dart';
import '../../harness_redaction.dart';
import '../../settings/registry.dart';
import '../core/arbiter.dart';
import '../next_playback.dart';
import '../perf/budget.dart';
import 'apply_selection.dart';
import 'classic_facts.dart';
import 'classic_playback_controls.dart';
import 'danmaku_port.dart';
import 'debug_local_operations.dart';
import 'local_playback_operations.dart';
import 'video_player_state_port.dart';

/// Next's playback while Classic's player plays behind it: the one place in
/// Next that reads [VideoPlayerState]. Until Next's own session layer plays
/// (P1), each part of [NextPlayback] is Classic's own path: leaving as its
/// back button does, subtitles as its track menu and Next's track
/// capability do, the next episode as its playlist does; the speed, the
/// picture, danmaku and subtitle looks as Classic's player menu sets them,
/// into the same settings.
///
/// Classic notifies its listeners every 120 ms while a video plays. One
/// listener here, there only while something listens to [media],
/// [transport] or [danmakuVersion], reads what changes rarely and pushes it
/// on when it did; nothing else in Next listens to Classic.
class ClassicBackedPlayback implements NextPlayback {
  /// Over Classic's player state in [context].
  factory ClassicBackedPlayback.of(BuildContext context) =>
      ClassicBackedPlayback(context.read<VideoPlayerState>());

  ClassicBackedPlayback(this.state) {
    _media = _Topic(PlaybackMedia.none, this);
    _transport = _Topic(PlaybackTransport.idle, this);
    _danmaku = _Topic(0, this);
  }

  final VideoPlayerState state;
  late final _Topic<PlaybackMedia> _media;
  late final _Topic<PlaybackTransport> _transport;
  late final _Topic<int> _danmaku;
  bool _listening = false;

  @override
  ValueListenable<PlaybackMedia> get media => _media;
  @override
  ValueListenable<PlaybackTransport> get transport => _transport;
  @override
  ValueListenable<int> get danmakuVersion => _danmaku;
  @override
  Listenable get frame => state;

  void _topicsChanged() {
    final wanted =
        _media.listened || _transport.listened || _danmaku.listened;
    if (wanted == _listening) return;
    _listening = wanted;
    wanted ? state.addListener(_changed) : state.removeListener(_changed);
  }

  void _changed() => PlayerPerf.span('classic.sync', _sync);

  static PlaybackPhase _phase(PlayerStatus status) => switch (status) {
        PlayerStatus.idle => PlaybackPhase.idle,
        PlayerStatus.loading || PlayerStatus.recognizing =>
          PlaybackPhase.opening,
        PlayerStatus.ready => PlaybackPhase.ready,
        PlayerStatus.playing => PlaybackPhase.playing,
        PlayerStatus.paused => PlaybackPhase.paused,
        PlayerStatus.error => PlaybackPhase.failed,
        PlayerStatus.disposed => PlaybackPhase.closed,
      };

  void _sync() {
    final s = state;
    _media.publish(PlaybackMedia(
      path: s.currentVideoPath,
      generation: s.playbackGeneration,
      requestGeneration: s.playbackRequestGeneration,
      request: s.lastPlaybackRequest,
      durationKnown: s.duration > Duration.zero,
      kernel: s.player,
    ));
    _transport.publish(PlaybackTransport(
      status: s.status.name,
      phase: _phase(s.status),
      hasVideo: s.hasVideo,
      systemDrawn: s.player.prefersPlatformVideoSurface,
    ));
    _danmaku.publish(s.danmakuListVersion);
  }

  // ---- what the controls show ----

  @override
  bool get hasVideo => state.hasVideo;
  @override
  bool get showControls => state.showControls;
  @override
  String? get path => state.currentVideoPath;
  @override
  String? get workTitle => state.animeTitle;
  @override
  String? get episodeTitle => state.episodeTitle;
  @override
  Duration get position => state.position;
  @override
  Duration get duration => state.duration;
  @override
  Duration get buffered => Duration(milliseconds: state.bufferedPosition);
  @override
  bool get danmakuVisible => state.danmakuVisible;
  @override
  bool get fullscreen => state.isFullscreen;
  @override
  double get volume => state.currentSystemVolume;
  @override
  bool get canPlayNext => state.canPlayNextEpisode;

  // ---- for capabilities and the rest of Next ----

  @override
  late final VideoPlayerStatePort port = VideoPlayerStatePort(state);
  late final ClassicPlaybackControls _classicControls =
      ClassicPlaybackControls(state);
  @override
  ClassicPlaybackControls get controls => _classicControls;
  @override
  ClassicPlaybackControls get inspection => _classicControls;
  @override
  late final KernelHost kernelHost = _ClassicKernelHost(this);
  @override
  late final SubtitleTarget subtitleTarget = _ClassicSubtitles(state);

  @override
  PlaybackDanmakuPort danmakuPort(
          {Future<void> Function(
                  String bindingId, String operation, Object? value)?
              requestChange}) =>
      VideoDanmakuPort(state, requestChange: requestChange);

  @override
  set localDanmakuLoader(Future<bool> Function(String path)? loader) =>
      state.nextLocalDanmakuLoader = loader;

  @override
  Capability localOperations(
          SettingsRegistry settings, BuildContext Function() context) =>
      LocalPlaybackOperations(state, settings, context);

  @override
  PlaybackSnapshot snapshot() =>
      PlayerPerf.span('classic.snapshot', port.snapshot);

  @override
  Future<JsonMap> diagnostics() async {
    final player = state.player;
    final info = player.mediaInfo;
    final media = await readPlayerMediaFacts(player);
    return {
      'available': true,
      'kernel': player.getPlayerKernelName(),
      'status': state.status.name,
      'hasVideo': state.hasVideo,
      'buffering': state.isBuffering,
      'bufferedPositionMs': state.bufferedPosition,
      'positionMs': state.position.inMilliseconds,
      'durationMs': state.duration.inMilliseconds,
      'video': [
        for (final video in info.video ?? const [])
          {
            'codec': video.codecName,
            'width': video.codec.width,
            'height': video.codec.height
          }
      ],
      'audio': [
        for (final audio in info.audio ?? const [])
          {
            'codec': audio.codec.name,
            'sampleRate': audio.codec.sampleRate,
            'channels': audio.codec.channels
          }
      ],
      'details': diagnosticsPlayerDetails(media, buffering: state.isBuffering),
      'perf': PlayerPerf.read(),
      'lease': KernelArbiter.instance.facts(),
    };
  }

  @override
  JsonMap errorContext() {
    final path = state.currentVideoPath;
    return {
      'status': state.status.name,
      'path': path == null ? null : redactHarnessText(path),
      'kernel': playerKernelId(state.player.getPlayerKernelName()),
      'positionMs': state.position.inMilliseconds,
    };
  }

  @override
  JsonMap captureFailure() =>
      captureClassicFailure(state, port.snapshot().sessionId!);

  @override
  Future<void> spoilerKeyChanged(String key) =>
      state.updateSpoilerAiSettings(apiKey: key);

  @override
  void installDebug() => installDebugLocalOperations(state);

  @override
  Future<void> close({required String reason}) async {
    if (!state.hasVideo &&
        !const {PlayerStatus.loading, PlayerStatus.recognizing}
            .contains(state.status)) {
      return;
    }
    debugPrint('[NextPlayback] close ($reason)');
    AutoNextEpisodeService.instance.cancelAutoNext();
    if (state.isFullscreen) await state.toggleFullscreen();
    final path = state.currentVideoPath;
    if (path != null && state.hasVideo) {
      await state.persistCurrentPositionForHotSwap(
          path: path, positionMs: state.position.inMilliseconds);
    }
    // Classic's own way out: the exit frame for the watch record, then the
    // watch record and progress saved as the player resets.
    if (state.hasVideo) await state.handleBackButton();
    await state.resetPlayer();
  }

  // ---- the player's own controls, as the controls over the video ask ----

  // The player's own controls, as Classic's bar calls them. (Most are
  // extension members of VideoPlayerState: the layer reaches them here.)
  @override
  void togglePlay() => state.togglePlayPause();
  @override
  void seek(Duration position) => state.seekTo(position);
  @override
  void toggleDanmaku() => state.toggleDanmakuVisible();
  @override
  Future<void> toggleFullscreen() => state.toggleFullscreen();
  @override
  Future<void> nextEpisode() => state.playNextEpisode();
  @override
  Future<void> setVolume(double value) =>
      state.setPlaybackVolume(value.clamp(0.0, 1.0));

  /// The pointer is on Next's controls: Classic keeps them up meanwhile.
  @override
  void hover(bool over) => state.setControlsHovered(over);

  /// The opening or ending the video is in, if it can be skipped.
  @override
  SkipSegmentKind? get skippable =>
      state.hasActiveSkipSegment ? state.activeSkipSegment?.kind : null;

  @override
  Future<void> skip() {
    state.resetHideControlsTimer();
    return state.skipCurrentSegment();
  }

  /// Back to the page the video was opened from: out of full screen and
  /// out of the video, the watch position and its frame kept.
  @override
  Future<void> leave() async {
    AutoNextEpisodeService.instance.cancelAutoNext();
    if (state.isFullscreen) {
      await state.toggleFullscreen();
      if (state.isFullscreen) return;
    }
    if (await state.handleBackButton()) await state.resetPlayer();
  }

  /// Classic's hotkeys (space, arrows, Esc…) rest, and its controls stay
  /// up, while something of Next is open over the video: the lock Classic's
  /// own player menus take.
  @override
  void holdHotkeys() => state.setControlsVisibilityLocked(true);
  @override
  void releaseHotkeys() => state.setControlsVisibilityLocked(false);

  int? _heatVersion;
  int? _heatSeconds;
  List<double>? _heat;

  /// Where the danmaku gather over the video, 0..1; null without any.
  @override
  List<double>? heat() {
    final seconds = state.duration.inSeconds;
    final version = state.danmakuListVersion;
    if (version == _heatVersion && seconds == _heatSeconds) return _heat;
    _heatVersion = version;
    _heatSeconds = seconds;
    final list = state.danmakuList;
    if (list.isEmpty || seconds <= 0) return _heat = null;
    final points = DanmakuDensityAnalyzer.analyzeDensity(
      danmakuList: list,
      videoDurationSeconds: seconds,
      segmentCount: 120,
    );
    var peak = 0;
    for (final point in points) {
      if (point.count > peak) peak = point.count;
    }
    if (peak == 0) return _heat = null;
    return _heat = [for (final point in points) point.count / peak];
  }

  @override
  Future<List<SubtitleChoice>> subtitles() async {
    final tracks = state.player.mediaInfo.subtitle ?? const [];
    final active = state.player.activeSubtitleTracks;
    final mounted = state.activeExternalSubtitlePaths;
    final files = <String>[...mounted];
    final path = state.currentVideoPath;
    if (path != null) {
      try {
        for (final saved in await SubtitleService().loadExternalSubtitles(path)) {
          final file = saved['path'];
          if (file is String && file.isNotEmpty && !files.contains(file)) {
            files.add(file);
          }
        }
      } catch (e) {
        debugPrint('[NextPlayer] saved subtitles: $e');
      }
    }
    final anyOn = active.isNotEmpty || mounted.isNotEmpty;
    return [
      SubtitleChoice.off(selected: !anyOn),
      for (final (i, track) in tracks.indexed)
        SubtitleChoice.embedded(
            _trackLabel(track.title, track.language, i), i,
            selected: active.contains(i)),
      for (final file in files)
        SubtitleChoice.file(_fileLabel(file), file,
            selected: mounted.contains(file)),
    ];
  }

  String _fileLabel(String path) {
    try {
      final name = state.externalSubtitleDisplayName(path).trim();
      if (name.isNotEmpty) return p.basenameWithoutExtension(name);
    } catch (_) {}
    return p.basenameWithoutExtension(path);
  }

  static const _languages = {
    'chi': '中文', 'zho': '中文', 'zh': '中文', 'chs': '简体中文',
    'cht': '繁体中文', 'jpn': '日语', 'ja': '日语', 'eng': '英语',
    'en': '英语', 'kor': '韩语', 'ko': '韩语',
  };

  static String _trackLabel(String? title, String? language, int index,
      {String fallback = '字幕'}) {
    final t = title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final l = language?.trim().toLowerCase() ?? '';
    if (l.isNotEmpty) return _languages[l] ?? language!.trim();
    return '$fallback ${index + 1}';
  }

  /// One subtitle at a time, as the menu shows them: the others go.
  @override
  Future<void> choose(SubtitleChoice choice) async {
    final mounted = [...state.activeExternalSubtitlePaths];
    if (choice.path case final file?) {
      if (!mounted.contains(file)) {
        await state.addExternalSubtitleToStack(file);
        await state.preloadSubtitleFile(file);
      }
      if (state.player.activeSubtitleTracks.isNotEmpty) {
        await _classicControls.selectTrack(
            {'kind': 'subtitle', 'origin': 'embedded', 'index': -1});
      }
      for (final other in mounted) {
        if (other != file) await state.removeExternalSubtitle(other);
      }
      return;
    }
    for (final file in mounted) {
      await state.removeExternalSubtitle(file);
    }
    await _classicControls.selectTrack(
        {'kind': 'subtitle', 'origin': 'embedded', 'index': choice.index});
  }

  /// A subtitle file the viewer picks; false when none was or it could not
  /// be used.
  @override
  Future<bool> addSubtitleFile() async {
    final file = await FilePickerService().pickSubtitleFile();
    if (file == null) return false;
    try {
      final loaded = await _classicControls.loadSubtitle({'path': file});
      await choose(SubtitleChoice.file('', loaded['path'] as String));
      return true;
    } catch (e) {
      debugPrint('[NextPlayer] subtitle file: $e');
      return false;
    }
  }

  @override
  Future<List<EpisodeChoice>> episodes() async {
    final items = await state.readPlaybackPlaylist();
    final path = state.currentVideoPath;
    final current = path == null ? null : MediaIdentityResolver.forPath(path);
    return [
      for (final e in items)
        EpisodeChoice(
          title: e.title,
          work: e.subtitle,
          progress: e.progress ?? e.historyItem?.watchProgress,
          current: current != null &&
              MediaIdentityResolver.forPath(e.videoPath) == current,
          still: e.historyItem?.thumbnailPath,
          source: e,
        ),
    ];
  }

  /// Classic's playlist plays the episode as it plays the next one.
  @override
  Future<void> play(EpisodeChoice episode) async {
    if (episode.current || episode.source == null) return;
    await state.playNextEpisode(verifiedPlaylistEpisode: episode.source);
  }

  // The speed, as Classic's 倍速 menu sets it.

  @override
  double get rate => state.playbackRate;
  @override
  Future<void> setRate(double rate) => state.setPlaybackRate(rate);

  // The audio tracks, as Classic's 音频轨道 menu lists them: the server's
  // own while it transcodes a Jellyfin or Emby stream, the file's otherwise.

  @override
  List<AudioChoice> audio() {
    if (_serverAudio() case final server?) return server;
    final tracks = state.player.mediaInfo.audio ?? const [];
    final active = state.player.activeAudioTracks;
    final labels = [
      for (final (i, t) in tracks.indexed)
        _trackLabel(t.title ?? t.metadata['title'], t.language, i,
            fallback: '音轨')
    ];
    return [
      for (final (i, t) in tracks.indexed)
        AudioChoice(
            _distinct(labels, i, t.codec.name), i,
            selected: active.contains(i)),
    ];
  }

  /// Two tracks called the same are told apart by their codec, or number.
  static String _distinct(List<String> labels, int i, String? codec) {
    final label = labels[i];
    if (labels.where((l) => l == label).length < 2) return label;
    final c = codec?.trim() ?? '';
    return c.isNotEmpty && !c.startsWith('Unknown')
        ? '$label · ${c.toUpperCase()}'
        : '$label ${i + 1}';
  }

  List<AudioChoice>? _serverAudio() {
    final path = state.currentVideoPath ?? '';
    final jellyfin = path.startsWith('jellyfin://');
    final emby = path.startsWith('emby://');
    final session = state.currentPlaybackSession;
    if (!(jellyfin && JellyfinService.instance.isTranscodeEnabled) &&
        !(emby && session?.isTranscoding == true)) {
      return null;
    }
    final source = session?.selectedSource ??
        (session?.mediaSources.isNotEmpty == true
            ? session!.mediaSources.first
            : null);
    final streams = [
      for (final s in source?.mediaStreams ?? const <Map<String, dynamic>>[])
        if (s['Type']?.toString() == 'Audio' &&
            int.tryParse('${s['Index']}') != null)
          s
    ];
    if (streams.isEmpty) return null;
    final itemId = path.substring(path.indexOf('://') + 3).split('/').last;
    int index(Map<String, dynamic> s) => int.parse('${s['Index']}');
    final selected = (jellyfin
            ? state.getJellyfinServerAudioSelection(itemId)
            : state.getEmbyServerAudioSelection(itemId)) ??
        index(streams.firstWhere((s) => s['IsDefault'] == true,
            orElse: () => streams.first));
    final labels = [
      for (final (i, s) in streams.indexed)
        _trackLabel(s['Title']?.toString(), s['Language']?.toString(), i,
            fallback: '音轨')
    ];
    return [
      for (final (i, s) in streams.indexed)
        AudioChoice(_distinct(labels, i, s['Codec']?.toString()), index(s),
            selected: index(s) == selected, server: true),
    ];
  }

  @override
  Future<void> chooseAudio(AudioChoice choice) async {
    if (choice.selected) return;
    await _classicControls.selectTrack({
      'kind': 'audio',
      'origin': choice.server ? 'server' : 'embedded',
      'index': choice.index,
    });
  }

  // The picture, as Classic's 画面比例 menu fits it (not where the video is
  // composited outside Flutter, as Classic's own bar hides it there).

  @override
  bool get canFit => state.supportsVideoAspectModes;
  @override
  VideoAspectMode get fit => state.videoAspectMode;
  @override
  Future<void> setFit(VideoAspectMode mode) => state.setVideoAspectMode(mode);

  // A still of what plays, where Classic's screenshot settings put it.

  @override
  Future<String?> screenshot() => state.captureScreenshot();
  @override
  Future<void> open(String path) =>
      launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);

  /// Picture in picture: Classic's own window, out of this one.
  @override
  bool get canPictureInPicture => DesktopPlayerWindowService.isFeatureEnabled;
  @override
  Future<void> pictureInPicture(BuildContext context) => DesktopPlayerWindowService
      .instance
      .detachAndEnterPictureInPicture(context, state);

  // Danmaku, as Classic's 弹幕设置 sets them; Titan's own while it draws
  // them (its opacity and size are its own settings in Classic too).

  bool get _titan {
    final renderer = DanmakuKernelFactory.activePluginRenderer;
    if (renderer == null || !renderer.usesTitanSettings) return false;
    // Erika draws its own danmaku whatever renderer is chosen.
    return state.player.getPlayerKernelName() != 'Erika';
  }

  @override
  PlayerDial get danmakuOpacity => _titan
      ? PlayerDial(state.titanDanmakuSettings.opacity, 0.2, 1, 0.05,
          DialUnit.percent)
      : PlayerDial(state.danmakuOpacity, 0, 1, 0.01, DialUnit.percent);

  @override
  Future<void> setDanmakuOpacity(double value) async {
    if (_titan) {
      state.setTitanDanmakuSettings(
          state.titanDanmakuSettings.copyWith(opacity: value));
    } else {
      await state.setDanmakuOpacity(value);
    }
  }

  @override
  PlayerDial get danmakuSize => _titan
      ? PlayerDial(
          state.titanDanmakuSettings.fontSize, 0.5, 2, 0.05, DialUnit.times)
      : PlayerDial(
          state.danmakuFontSize <= 0
              ? state.actualDanmakuFontSize
              : state.danmakuFontSize,
          12,
          60,
          1,
          DialUnit.points);

  /// While dragged the size shows at once; [done] keeps it.
  @override
  Future<void> setDanmakuSize(double value, {bool done = false}) async {
    if (!_titan) return state.setDanmakuFontSize(value, commit: done);
    final titan = state.titanDanmakuSettings.copyWith(fontSize: value);
    if (done) return state.commitTitanDanmakuSettings(titan);
    state.setTitanDanmakuSettings(titan);
  }

  @override
  double get danmakuArea {
    final area = state.danmakuDisplayArea;
    return NextPlayback.danmakuAreas.reduce(
        (a, b) => (area - a).abs() <= (area - b).abs() ? a : b);
  }

  @override
  Future<void> setDanmakuArea(double area) => state.setDanmakuDisplayArea(area);

  @override
  bool blocked(DanmakuLane lane) => switch (lane) {
        DanmakuLane.top => state.blockTopDanmaku,
        DanmakuLane.bottom => state.blockBottomDanmaku,
        DanmakuLane.scroll => state.blockScrollDanmaku,
      };

  @override
  Future<void> block(DanmakuLane lane, bool on) => switch (lane) {
        DanmakuLane.top => state.setBlockTopDanmaku(on),
        DanmakuLane.bottom => state.setBlockBottomDanmaku(on),
        DanmakuLane.scroll => state.setBlockScrollDanmaku(on),
      };

  /// Seconds the danmaku come later (earlier when negative).
  @override
  PlayerDial get danmakuOffset =>
      PlayerDial(state.manualDanmakuOffset, -600, 600, 0.5, DialUnit.seconds);
  @override
  void setDanmakuOffset(double seconds) =>
      state.setManualDanmakuOffset(seconds);

  // The subtitle on: its timing and size. A file NipaPlay draws over the
  // video keeps its own (as Classic's long press on it sets them); the
  // player's tracks share Classic's 字幕设置.

  /// The file of [on] when NipaPlay draws it over the video, not the player.
  @override
  String? drawnOver(SubtitleChoice? on) {
    final path = on?.path;
    if (path == null) return null;
    return state.externalSubtitleRenderedInApp(path) ? path : null;
  }

  /// Seconds the subtitle comes later (earlier when negative).
  @override
  PlayerDial subtitleDelay(SubtitleChoice? on) {
    final limit = state.subtitleDelayCustomLimitSeconds;
    final overlay = drawnOver(on);
    return PlayerDial(
        overlay != null
            ? state.pathSubtitleDelaySeconds(overlay)
            : state.subtitleDelaySeconds,
        -limit,
        limit,
        VideoPlayerState.subtitleDelayStep,
        DialUnit.seconds);
  }

  @override
  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds) async {
    if (drawnOver(on) case final overlay?) {
      state.setPathSubtitleDelaySeconds(overlay, seconds);
    } else {
      await state.setSubtitleDelaySeconds(seconds);
    }
  }

  /// The player scales its own subtitles in Media Kit and Erika only, as in
  /// Classic's menu.
  @override
  bool canScaleSubtitles(SubtitleChoice? on) =>
      drawnOver(on) != null ||
      const {'Media Kit', 'Erika'}.contains(state.player.getPlayerKernelName());

  @override
  PlayerDial subtitleScale(SubtitleChoice? on) => PlayerDial(
      drawnOver(on) != null ? state.srtSubtitleScale : state.subtitleScale,
      VideoPlayerState.minSubtitleScale,
      VideoPlayerState.maxSubtitleScale,
      0.05,
      DialUnit.percent);

  @override
  Future<void> setSubtitleScale(SubtitleChoice? on, double scale) =>
      drawnOver(on) != null
          ? state.setSrtSubtitleScale(scale)
          : state.setSubtitleScale(scale);
}

/// A pushed value that starts and stops the one listener on Classic as it
/// gains its first listener and loses its last; read while nothing listens,
/// it is read from Classic then and there.
final class _Topic<T> extends ValueNotifier<T> {
  _Topic(super.value, this._owner);
  final ClassicBackedPlayback _owner;

  bool get listened => hasListeners;

  @override
  T get value {
    if (!_owner._listening) _owner._sync();
    return super.value;
  }

  void publish(T next) => super.value = next;

  @override
  void addListener(VoidCallback listener) {
    // Fresh before anyone listens, so nothing is told of it meanwhile.
    if (!_owner._listening) _owner._sync();
    super.addListener(listener);
    _owner._topicsChanged();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _owner._topicsChanged();
  }
}

final class _ClassicKernelHost implements KernelHost {
  _ClassicKernelHost(this._playback);
  final ClassicBackedPlayback _playback;
  VideoPlayerState get _state => _playback.state;

  @override
  Player get player => _state.player;
  @override
  PlayableItem? get request => _state.lastPlaybackRequest;
  @override
  String? get path => _state.currentVideoPath;
  @override
  ValueListenable<PlaybackMedia> get media => _playback.media;
  @override
  ValueListenable<PlaybackTransport> get transport => _playback.transport;
  @override
  bool get hasVideo => _state.hasVideo;
  @override
  bool get paused => _state.isPaused;
  @override
  Duration get position => _state.position;
  @override
  double get rate => _state.playbackRate;
  @override
  List<String> get externalSubtitles => _state.activeExternalSubtitlePaths;
  @override
  void selectEmbeddedAudio(int index) => _state.selectEmbeddedAudioTrack(index);
  @override
  void subtitleTracksChanged() => _state.onSubtitleTrackChanged();
  @override
  Future<void> addSubtitle(String path, String title) =>
      _state.addNextSubtitle(path, title);
  @override
  PlaybackSnapshot snapshot() => _playback.snapshot();
  @override
  JsonMap? error(String sessionId) => playbackErrorFacts(_state, sessionId);

  /// Classic's own kernel hot swap, serialized with Classic's.
  @override
  Future<void> reopen(PlayerKernelType? kernel, PlayableItem? request) =>
      PlayerKernelManager.performPlayerKernelHotSwap(_state,
          kernelType: kernel, request: request);
}

final class _ClassicSubtitles implements SubtitleTarget {
  _ClassicSubtitles(this._state);
  final VideoPlayerState _state;

  @override
  String? get path => _state.currentVideoPath;
  @override
  Future<void> offer(String playbackPath, String title) =>
      _state.registerNextSubtitleCandidate(playbackPath, title);
  @override
  Future<void> applyEmbedded(int index) =>
      _state.applyNextEmbeddedSubtitle(index);
  @override
  Future<void> applyExternal(String playbackPath, String title) =>
      _state.applyNextExternalSubtitle(playbackPath, title);
  @override
  Future<void> clear() async => _state.player.activeSubtitleTracks = [];

  @override
  Future<void> reapply(
      String fileId, List<JsonMap> tracks, JsonMap? selected) async {
    final player = _state;
    final selectionCallback = player.nextSubtitleSelection;
    player.nextSubtitleSelection = null;
    try {
      player.subtitleTrackInfo.removeWhere(
          (key, value) => key.startsWith('next:') && value['fileId'] == fileId);
      for (final path in player.activeExternalSubtitlePaths.toList()) {
        await player.removeExternalSubtitle(path);
      }
      for (final track in tracks) {
        if (track['origin'] != 'embedded' && track['available'] == true) {
          await player.registerNextSubtitleCandidate(
              track['playbackPath'] as String? ?? track['path'] as String,
              track['title'] as String);
          player.subtitleManager.updateSubtitleTrackInfo('next:${track['id']}', {
            ...track,
            'fileId': fileId,
            'trackId': track['id'],
            'isActive': false,
            'path': track['playbackPath'] ?? track['path'],
          });
        }
      }
      if (selected == null) {
        player.player.activeSubtitleTracks = [];
      } else if (selected['origin'] == 'embedded') {
        await player.applyNextEmbeddedSubtitle(selected['index'] as int);
      } else {
        await player.applyNextExternalSubtitle(
            selected['playbackPath'] as String? ?? selected['path'] as String,
            selected['title'] as String);
      }
    } finally {
      player.nextSubtitleSelection = selectionCallback;
    }
  }
  @override
  set loader(Future<bool> Function(String path)? loader) =>
      _state.nextSubtitleLoader = loader;
  @override
  set selection(
          Future<void> Function(String path, int? index, String? external)?
              selection) =>
      _state.nextSubtitleSelection = selection;
}

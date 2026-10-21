import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/services/danmaku_density_analyzer.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../capabilities/classic_playback_controls.dart';

/// One subtitle the viewer can choose; [off] turns them all off.
@immutable
final class SubtitleChoice {
  const SubtitleChoice.off({this.selected = false})
      : label = '关闭',
        index = -1,
        path = null;
  const SubtitleChoice.embedded(this.label, this.index, {this.selected = false})
      : path = null;
  const SubtitleChoice.file(this.label, String this.path,
      {this.selected = false})
      : index = -1;

  final String label;
  final bool selected;

  /// The embedded track; -1 for a file or off.
  final int index;

  /// The subtitle file; null for an embedded track or off.
  final String? path;

  bool get off => index < 0 && path == null;
}

/// One episode of what plays, in the order the player goes through them.
@immutable
final class EpisodeChoice {
  const EpisodeChoice({
    required this.title,
    this.work,
    this.progress,
    this.current = false,
    this.still,
    this.source,
  });

  final String title;

  /// The work's name, when the episode names it apart from [title].
  final String? work;

  /// 0..1 watched; null when never played.
  final double? progress;
  final bool current;

  /// A frame from where it was last watched (a local path), if any.
  final String? still;

  /// Classic's own entry, which plays it.
  final PlaybackDetailEpisode? source;
}

/// One audio track the viewer can choose.
@immutable
final class AudioChoice {
  const AudioChoice(this.label, this.index,
      {this.selected = false, this.server = false});
  final String label;
  final int index;
  final bool selected;

  /// A track of the stream a Jellyfin or Emby server transcodes, not of the
  /// file the player decodes.
  final bool server;
}

/// A setting turned on a scale: where it is and how far it goes.
@immutable
final class PlayerDial {
  const PlayerDial(this.value, this.min, this.max, this.step, this.unit);
  final double value;
  final double min;
  final double max;
  final double step;
  final DialUnit unit;

  double clamp(double v) {
    final snapped = min + ((v - min) / step).round() * step;
    return double.parse(snapped.clamp(min, max).toStringAsFixed(3));
  }

  @override
  bool operator ==(Object other) =>
      other is PlayerDial &&
      other.value == value &&
      other.min == min &&
      other.max == max &&
      other.step == step &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(value, min, max, step, unit);
}

enum DialUnit { percent, points, times, seconds }

/// Where on the screen danmaku of a kind run.
enum DanmakuLane { top, bottom, scroll }

/// What the player layer asks of the player beyond what [VideoPlayerState]
/// shows directly. Each goes through Classic's own path: leaving as its
/// back button does, subtitles as its track menu and Next's track
/// capability do, the next episode as its playlist does; the speed, the
/// picture, danmaku and subtitle looks as Classic's player menu sets them,
/// into the same settings.
class NextPlayback {
  NextPlayback(this.state);
  final VideoPlayerState state;

  ClassicPlaybackControls get _controls => ClassicPlaybackControls(state);

  // The player's own controls, as Classic's bar calls them. (Most are
  // extension members of VideoPlayerState: the layer reaches them here.)
  void togglePlay() => state.togglePlayPause();
  void seek(Duration position) => state.seekTo(position);
  void toggleDanmaku() => state.toggleDanmakuVisible();
  Future<void> toggleFullscreen() => state.toggleFullscreen();
  Future<void> nextEpisode() => state.playNextEpisode();
  Future<void> setVolume(double value) =>
      state.setPlaybackVolume(value.clamp(0.0, 1.0));

  /// The pointer is on Next's controls: Classic keeps them up meanwhile.
  void hover(bool over) => state.setControlsHovered(over);

  /// The opening or ending the video is in, if it can be skipped.
  SkipSegmentKind? get skippable =>
      state.hasActiveSkipSegment ? state.activeSkipSegment?.kind : null;

  Future<void> skip() {
    state.resetHideControlsTimer();
    return state.skipCurrentSegment();
  }

  /// Back to the page the video was opened from: out of full screen and
  /// out of the video, the watch position and its frame kept.
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
  void holdHotkeys() => state.setControlsVisibilityLocked(true);
  void releaseHotkeys() => state.setControlsVisibilityLocked(false);

  int? _heatVersion;
  int? _heatSeconds;
  List<double>? _heat;

  /// Where the danmaku gather over the video, 0..1; null without any.
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
  Future<void> choose(SubtitleChoice choice) async {
    final mounted = [...state.activeExternalSubtitlePaths];
    if (choice.path case final file?) {
      if (!mounted.contains(file)) {
        await state.addExternalSubtitleToStack(file);
        await state.preloadSubtitleFile(file);
      }
      if (state.player.activeSubtitleTracks.isNotEmpty) {
        await _controls.selectTrack(
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
    await _controls.selectTrack(
        {'kind': 'subtitle', 'origin': 'embedded', 'index': choice.index});
  }

  /// A subtitle file the viewer picks; false when none was or it could not
  /// be used.
  Future<bool> addSubtitleFile() async {
    final file = await FilePickerService().pickSubtitleFile();
    if (file == null) return false;
    try {
      final loaded = await _controls.loadSubtitle({'path': file});
      await choose(SubtitleChoice.file('', loaded['path'] as String));
      return true;
    } catch (e) {
      debugPrint('[NextPlayer] subtitle file: $e');
      return false;
    }
  }

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
  Future<void> play(EpisodeChoice episode) async {
    if (episode.current || episode.source == null) return;
    await state.playNextEpisode(verifiedPlaylistEpisode: episode.source);
  }

  // The speed, as Classic's 倍速 menu sets it.

  static const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  double get rate => state.playbackRate;
  Future<void> setRate(double rate) => state.setPlaybackRate(rate);

  // The audio tracks, as Classic's 音频轨道 menu lists them: the server's
  // own while it transcodes a Jellyfin or Emby stream, the file's otherwise.

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

  Future<void> chooseAudio(AudioChoice choice) async {
    if (choice.selected) return;
    await _controls.selectTrack({
      'kind': 'audio',
      'origin': choice.server ? 'server' : 'embedded',
      'index': choice.index,
    });
  }

  // The picture, as Classic's 画面比例 menu fits it (not where the video is
  // composited outside Flutter, as Classic's own bar hides it there).

  bool get canFit => state.supportsVideoAspectModes;
  VideoAspectMode get fit => state.videoAspectMode;
  Future<void> setFit(VideoAspectMode mode) => state.setVideoAspectMode(mode);

  // A still of what plays, where Classic's screenshot settings put it.

  Future<String?> screenshot() => state.captureScreenshot();
  Future<void> open(String path) =>
      launchUrl(Uri.file(path), mode: LaunchMode.externalApplication);

  /// Picture in picture: Classic's own window, out of this one.
  bool get canPictureInPicture => DesktopPlayerWindowService.isFeatureEnabled;
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

  PlayerDial get danmakuOpacity => _titan
      ? PlayerDial(state.titanDanmakuSettings.opacity, 0.2, 1, 0.05,
          DialUnit.percent)
      : PlayerDial(state.danmakuOpacity, 0, 1, 0.01, DialUnit.percent);

  Future<void> setDanmakuOpacity(double value) async {
    if (_titan) {
      state.setTitanDanmakuSettings(
          state.titanDanmakuSettings.copyWith(opacity: value));
    } else {
      await state.setDanmakuOpacity(value);
    }
  }

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
  Future<void> setDanmakuSize(double value, {bool done = false}) async {
    if (!_titan) return state.setDanmakuFontSize(value, commit: done);
    final titan = state.titanDanmakuSettings.copyWith(fontSize: value);
    if (done) return state.commitTitanDanmakuSettings(titan);
    state.setTitanDanmakuSettings(titan);
  }

  /// How much of the screen danmaku may take: one line, then fractions.
  static const danmakuAreas = [0.0, 0.125, 0.25, 0.33, 0.67, 1.0];

  double get danmakuArea {
    final area = state.danmakuDisplayArea;
    return danmakuAreas.reduce(
        (a, b) => (area - a).abs() <= (area - b).abs() ? a : b);
  }

  Future<void> setDanmakuArea(double area) => state.setDanmakuDisplayArea(area);

  bool blocked(DanmakuLane lane) => switch (lane) {
        DanmakuLane.top => state.blockTopDanmaku,
        DanmakuLane.bottom => state.blockBottomDanmaku,
        DanmakuLane.scroll => state.blockScrollDanmaku,
      };

  Future<void> block(DanmakuLane lane, bool on) => switch (lane) {
        DanmakuLane.top => state.setBlockTopDanmaku(on),
        DanmakuLane.bottom => state.setBlockBottomDanmaku(on),
        DanmakuLane.scroll => state.setBlockScrollDanmaku(on),
      };

  /// Seconds the danmaku come later (earlier when negative).
  PlayerDial get danmakuOffset =>
      PlayerDial(state.manualDanmakuOffset, -600, 600, 0.5, DialUnit.seconds);
  void setDanmakuOffset(double seconds) =>
      state.setManualDanmakuOffset(seconds);

  // The subtitle on: its timing and size. A file NipaPlay draws over the
  // video keeps its own (as Classic's long press on it sets them); the
  // player's tracks share Classic's 字幕设置.

  /// The file of [on] when NipaPlay draws it over the video, not the player.
  @protected
  String? drawnOver(SubtitleChoice? on) {
    final path = on?.path;
    if (path == null) return null;
    return state.externalSubtitleRenderedInApp(path) ? path : null;
  }

  /// Seconds the subtitle comes later (earlier when negative).
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

  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds) async {
    if (drawnOver(on) case final overlay?) {
      state.setPathSubtitleDelaySeconds(overlay, seconds);
    } else {
      await state.setSubtitleDelaySeconds(seconds);
    }
  }

  /// The player scales its own subtitles in Media Kit and Erika only, as in
  /// Classic's menu.
  bool canScaleSubtitles(SubtitleChoice? on) =>
      drawnOver(on) != null ||
      const {'Media Kit', 'Erika'}.contains(state.player.getPlayerKernelName());

  PlayerDial subtitleScale(SubtitleChoice? on) => PlayerDial(
      drawnOver(on) != null ? state.srtSubtitleScale : state.subtitleScale,
      VideoPlayerState.minSubtitleScale,
      VideoPlayerState.maxSubtitleScale,
      0.05,
      DialUnit.percent);

  Future<void> setSubtitleScale(SubtitleChoice? on, double scale) =>
      drawnOver(on) != null
          ? state.setSrtSubtitleScale(scale)
          : state.setSubtitleScale(scale);
}

/// Tests and the fake world: the playback the layer below talks to.
class NextPlaybackScope extends InheritedWidget {
  const NextPlaybackScope(
      {super.key, required this.playback, required super.child});
  final NextPlayback playback;

  static NextPlayback? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NextPlaybackScope>()
      ?.playback;

  @override
  bool updateShouldNotify(NextPlaybackScope old) => old.playback != playback;
}

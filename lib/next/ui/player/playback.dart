import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/services/danmaku_density_analyzer.dart';
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;

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

/// What the player layer asks of the player beyond what [VideoPlayerState]
/// shows directly. Each goes through Classic's own path: leaving as its
/// back button does, subtitles as its track menu and Next's track
/// capability do, the next episode as its playlist does.
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

  static String _trackLabel(String? title, String? language, int index) {
    final t = title?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final l = language?.trim().toLowerCase() ?? '';
    if (l.isNotEmpty) return _languages[l] ?? language!.trim();
    return '字幕 ${index + 1}';
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

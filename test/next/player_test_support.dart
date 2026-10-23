import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/player/classic/classic_backed_playback.dart';
import 'package:nipaplay/next/ui/player/playback.dart';
import 'package:nipaplay/next/ui/shell/next_ui_gate.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The whole window, for pictures of it.
final playerShotKey = GlobalKey(debugLabel: 'player shot');

/// The gate with Next on (or off) over Classic's player in [status]; the
/// shell's services are NextShell.debugServices, the layer's playback a
/// recording one.
Future<PlayerRig> pumpPlayer(
  WidgetTester tester, {
  bool next = true,
  PlayerStatus status = PlayerStatus.idle,
  Widget classic = const Text('classic'),
  Size size = const Size(1440, 900),
  double pixelRatio = 1,
  FakePlayerState? state,
  FakePlayback Function(FakePlayerState state)? playback,
}) async {
  state ??= FakePlayerState();
  state.status = status;
  final rig = (playback ?? FakePlayback.new)(state);
  await _pumpGate(tester,
      next: next,
      state: state,
      playback: rig,
      classic: classic,
      size: size,
      pixelRatio: pixelRatio);
  return PlayerRig(state, rig);
}

/// The gate with Next on over Classic's own [VideoPlayerState] (its
/// settings, its setters, a player kernel that records what it is told):
/// what Next's controls set is what Classic keeps.
Future<ClassicRig> pumpClassicPlayer(
  WidgetTester tester, {
  ClassicPlayerState? state,
  Widget classic = const Text('classic'),
  Size size = const Size(1440, 900),
  double pixelRatio = 1,
  ClassicPlayback Function(ClassicPlayerState state)? playback,
}) async {
  state ??= ClassicPlayerState();
  final rig = (playback ?? ClassicPlayback.new)(state);
  await _pumpGate(tester,
      next: true,
      state: state,
      playback: rig,
      classic: classic,
      size: size,
      pixelRatio: pixelRatio);
  return ClassicRig(state, rig);
}

Future<void> _pumpGate(
  WidgetTester tester, {
  required bool next,
  required VideoPlayerState state,
  required NextPlayback playback,
  required Widget classic,
  required Size size,
  required double pixelRatio,
}) async {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({
    SettingsKeys.labsEnableAgentEndpoint: next,
    NextUiPreference.key: next,
  });
  final labs = LabsSettingsProvider(sandboxStatus: () async => false);
  final preference = NextUiPreference();
  await tester.runAsync(() async {
    await labs.ready;
    await preference.ready;
  });
  final rig = playback;
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: labs),
      ChangeNotifierProvider.value(value: preference),
      ChangeNotifierProvider<VideoPlayerState>.value(value: state),
    ],
    child: NextPlaybackScope(
      playback: rig,
      child: RepaintBoundary(
        key: playerShotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: NextUiGate(classic: classic),
        ),
      ),
    ),
  ));
  await tester.pump();
}

/// What a test drives: Classic's state and the layer's playback.
final class PlayerRig {
  PlayerRig(this.state, this.playback);
  final FakePlayerState state;
  final FakePlayback playback;
}

/// Classic's own state, and Next's playback over it.
final class ClassicRig {
  ClassicRig(this.state, this.playback);
  final ClassicPlayerState state;
  final ClassicPlayback playback;
}

/// The player kernel under Classic's state: the tracks of a file, and what
/// it is told (properties, the speed, the tracks on).
class ClassicKernel extends Fake implements MediaKitPlayerAdapter {
  final properties = <String, String>{};
  @override
  final buffering = ValueNotifier<bool>(false);
  @override
  final textureId = ValueNotifier<int?>(null);
  @override
  double volume = 1;
  @override
  double playbackRate = 1;
  @override
  PlayerPlaybackState state = PlayerPlaybackState.playing;
  @override
  PlayerMediaInfo mediaInfo = PlayerMediaInfo(
    duration: 24 * 60 * 1000,
    audio: [
      PlayerAudioStreamInfo(
          codec: PlayerAudioCodecParams(name: 'flac'),
          language: 'jpn',
          rawRepresentation: 'audio 0'),
      PlayerAudioStreamInfo(
          codec: PlayerAudioCodecParams(name: 'aac'),
          title: '评论音轨',
          language: 'jpn',
          rawRepresentation: 'audio 1'),
    ],
    subtitle: [
      PlayerSubtitleStreamInfo(
          title: '简体中文', language: 'chs', rawRepresentation: 'subtitle 0'),
    ],
  );
  @override
  List<int> activeAudioTracks = [0];
  @override
  List<int> activeSubtitleTracks = [0];
  @override
  int get position => 0;
  @override
  int get bufferedPosition => 0;
  @override
  String? getProperty(String key) => properties[key];
  @override
  void setProperty(String key, String value) => properties[key] = value;
  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  @override
  List<String> getDecoders(PlayerMediaType type) => ['FFmpeg'];
  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {}
  @override
  void setPlaybackRate(double rate) => playbackRate = rate;
  @override
  void dispose() {}
  @override
  Future<void> disposeAsync() async {}
}

/// Classic's [VideoPlayerState] itself, as it is with a video open: only
/// what the loading would have set (the status, the times, the names, the
/// danmaku) is given.
class ClassicPlayerState extends VideoPlayerState {
  ClassicPlayerState([ClassicKernel? kernel])
      : this._(kernel ?? ClassicKernel());
  ClassicPlayerState._(this.kernel)
      : super.forSettings(Player.withDelegate(kernel));
  final ClassicKernel kernel;

  PlayerStatus playing = PlayerStatus.playing;
  Duration at = const Duration(minutes: 14, seconds: 32);
  List<Map<String, dynamic>> comments = const [];

  @override
  PlayerStatus get status => playing;
  @override
  bool get hasVideo => const {
        PlayerStatus.ready,
        PlayerStatus.playing,
        PlayerStatus.paused
      }.contains(playing);
  @override
  bool get showControls => true;
  @override
  Duration get duration => const Duration(minutes: 24);
  @override
  Duration get position => at;
  @override
  String? get animeTitle => '葬送的芙莉莲';
  @override
  String? get episodeTitle => '第5话 死者的幻影';
  @override
  List<Map<String, dynamic>> get danmakuList => comments;
}

/// Next's own playback over Classic's state. Only what would leave the
/// test (the hotkeys' timers, the window, the disk, the system) is
/// recorded instead.
class ClassicPlayback extends ClassicBackedPlayback {
  ClassicPlayback(ClassicPlayerState super.state);
  int holds = 0, screenshots = 0, pictureInPictures = 0;
  final opened = <String>[];

  /// What a screenshot gives: its file, or null when it could not be taken.
  String? still = '/tmp/nipa-next/player-more-still.png';

  @override
  void holdHotkeys() => holds++;
  @override
  void releaseHotkeys() => holds--;
  @override
  void hover(bool over) {}
  @override
  Future<String?> screenshot() async {
    screenshots++;
    return still;
  }

  @override
  Future<void> open(String path) async => opened.add(path);
  @override
  bool get canPictureInPicture => true;
  @override
  Future<void> pictureInPicture(BuildContext context) async =>
      pictureInPictures++;
}

/// Classic's player state, as much of it as the layer reads.
class FakePlayerState extends ChangeNotifier implements VideoPlayerState {
  @override
  PlayerStatus status = PlayerStatus.idle;
  @override
  bool showControls = true;
  @override
  bool isFullscreen = false;
  @override
  bool danmakuVisible = true;
  @override
  double currentSystemVolume = 0.8;
  @override
  double playbackRate = 1;
  @override
  double subtitleDelaySeconds = 0;
  @override
  double subtitleScale = 1;
  @override
  double get subtitleDelayCustomLimitSeconds => 30;
  @override
  final Player player = Player.withDelegate(ClassicKernel());
  @override
  Duration position = const Duration(minutes: 1, seconds: 5);
  @override
  Duration duration = const Duration(minutes: 24);
  @override
  String? currentVideoPath;
  @override
  final String animeTitle = '葬送的芙莉莲';
  @override
  final String episodeTitle = '第5话 死者的幻影';
  @override
  List<Map<String, dynamic>> danmakuList = [
    for (var i = 0; i < 400; i++) {'time': (i * 7 % 1440).toDouble()},
    for (var i = 0; i < 300; i++) {'time': 600.0 + i % 30},
  ];

  int toggles = 0, fullscreenToggles = 0, nextEpisodes = 0;
  bool hovered = false;
  final seeks = <Duration>[];

  void notify() => notifyListeners();

  void play() {
    status = PlayerStatus.playing;
    notifyListeners();
  }

  @override
  bool get hasVideo => const {
        PlayerStatus.ready,
        PlayerStatus.playing,
        PlayerStatus.paused
      }.contains(status);
  @override
  int get danmakuListVersion => 1;
  @override
  int get playbackGeneration => 1;
  @override
  int get playbackRequestGeneration => 1;
  @override
  PlayableItem? get lastPlaybackRequest => null;
  @override
  int get bufferedPosition => 4 * 60 * 1000;
  /// Classic offers a next episode (as it does for any Jellyfin or Emby
  /// stream, films too).
  @override
  bool canPlayNextEpisode = true;
  @override
  bool get instantHidePlayerUiEnabled => false;

  @override
  Future<void> setPlaybackVolume(double value) async {
    currentSystemVolume = value;
    notifyListeners();
  }

  /// What Classic does when the pointer rests or moves.
  void showControlsNow(bool value) {
    showControls = value;
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The layer's asks of the player, recorded.
class FakePlayback extends ClassicBackedPlayback {
  FakePlayback(FakePlayerState super.state);
  int left = 0, holds = 0;
  final chosen = <SubtitleChoice>[];
  final played = <EpisodeChoice>[];

  @override
  Future<void> leave() async {
    left++;
    final s = state as FakePlayerState;
    s.status = PlayerStatus.idle;
    s.notify();
  }

  @override
  void holdHotkeys() => holds++;
  @override
  void releaseHotkeys() => holds--;

  @override
  Future<List<SubtitleChoice>> subtitles() async => const [
        SubtitleChoice.off(),
        SubtitleChoice.embedded('简体中文', 0, selected: true),
        SubtitleChoice.file('日语', '/subs/ep5.ja.ass'),
      ];

  @override
  Future<void> choose(SubtitleChoice choice) async => chosen.add(choice);

  /// No file is drawn over this video: Classic's own look applies.
  @override
  String? drawnOver(SubtitleChoice? on) => null;

  @override
  Future<void> setSubtitleDelay(SubtitleChoice? on, double seconds) async {
    _s.subtitleDelaySeconds = seconds;
    _s.notify();
  }

  @override
  Future<void> setSubtitleScale(SubtitleChoice? on, double scale) async {
    _s.subtitleScale = scale;
    _s.notify();
  }

  @override
  Future<List<EpisodeChoice>> episodes() async => [
        for (final (i, t) in const [
          '冒险的结束',
          '也不一定要是魔法…',
          '杀人魔法',
          '灵魂安眠之地',
          '死者的幻影',
          '村子的英雄',
        ].indexed)
          EpisodeChoice(
              title: '第${i + 1}话 $t',
              current: i == 4,
              progress: i < 4 ? 1 : null),
      ];

  @override
  Future<void> play(EpisodeChoice episode) async => played.add(episode);

  FakePlayerState get _s => state as FakePlayerState;

  @override
  void togglePlay() {
    _s.toggles++;
    _s.status = _s.status == PlayerStatus.playing
        ? PlayerStatus.paused
        : PlayerStatus.playing;
    _s.notify();
  }

  @override
  void toggleDanmaku() {
    _s.danmakuVisible = !_s.danmakuVisible;
    _s.notify();
  }

  @override
  Future<void> toggleFullscreen() async {
    _s.fullscreenToggles++;
    _s.isFullscreen = !_s.isFullscreen;
    _s.notify();
  }

  @override
  Future<void> nextEpisode() async => _s.nextEpisodes++;

  @override
  void seek(Duration position) => _s.seeks.add(position);

  @override
  void hover(bool over) => _s.hovered = over;

  SkipSegmentKind? segment;
  int skips = 0;

  @override
  SkipSegmentKind? get skippable => segment;

  @override
  Future<void> skip() async => skips++;
}

/// The services the player's tests run on; [chat] instead of a host that
/// is never there.
NextUiServices playerTestServices({ChatPort? chat}) {
  final unused = _Unused();
  return NextUiServices(
    data: _Data(),
    actions: _Actions(),
    chat: chat ?? _Port(),
    discover: unused,
    library: unused,
    libraryActions: unused,
    search: _Search(),
    settings: FakeSettings(),
  );
}

/// What the library knows of a playing file, by path.
final playerTestLibrary = <String, UiNowPlaying>{};

/// The library's works and their episodes, by work.
final playerTestWorks = <String, (UiWork, List<UiEpisode>)>{};

/// What the shell was asked to play, in order.
final playerTestPlays = <(UiWork, UiEpisode?)>[];

/// The library knows the file at [path] as [playing] of [work], whose
/// episodes are [episodes].
void putInPlayerTestLibrary(
    String path, UiWork work, List<UiEpisode> episodes, String playing) {
  playerTestWorks[work.workId] = (work, episodes);
  final e = episodes.firstWhere((e) => e.episodeId == playing);
  playerTestLibrary[path] = UiNowPlaying(
      workId: work.workId,
      work: work.title,
      episodeId: playing,
      episode: '第 ${e.number} 集 ${e.title ?? ''}'.trim());
}

/// Clears what a test put in the library, and what it played.
void resetPlayerTestLibrary() {
  playerTestLibrary.clear();
  playerTestWorks.clear();
  playerTestPlays.clear();
}

final class _Data implements NextUiData, NextNowPlaying {
  @override
  Future<UiNowPlaying?> nowPlaying(String path) async =>
      playerTestLibrary[path];

  @override
  Future<UiWork?> work(String workId) async => playerTestWorks[workId]?.$1;

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async => [
        for (final e in playerTestWorks[workId]?.$2 ?? const <UiEpisode>[])
          if (season == null || e.season == season) e
      ];

  @override
  Future<UiHome> home() async => const UiHome();
  @override
  Future<List<UiCard>> cards(
          {required String threadId, String? turnId}) async =>
      const [];
  @override
  Stream<List<UiTask>> tasks() => Stream.value(const []);
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Port implements ChatPort {
  @override
  bool get available => false;
  @override
  bool get busy => false;
  @override
  bool busyOn(String threadId) => false;
  @override
  Stream<ChatEvent> get display => const Stream.empty();
  @override
  Stream<ChatEvent> get questions => const Stream.empty();
  @override
  void dispose() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Actions implements NextUiActions {
  @override
  Future<void> play(UiWork work, {UiEpisode? episode}) async =>
      playerTestPlays.add((work, episode));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Unused
    implements
        NextUiActions,
        NextDiscoverData,
        NextLibraryData,
        NextLibraryActions {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Search implements NextSearchData {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

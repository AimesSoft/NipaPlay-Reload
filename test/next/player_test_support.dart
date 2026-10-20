import 'dart:async';

import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/next/ui/conversation/chat_port.dart';
import 'package:nipaplay/next/ui/data/discover.dart';
import 'package:nipaplay/next/ui/data/search.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/data/ui_actions.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/player/playback.dart';
import 'package:nipaplay/next/ui/shell/next_ui_gate.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/next/ui_data/library.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
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
  state ??= FakePlayerState();
  state.status = status;
  final rig = (playback ?? FakePlayback.new)(state);
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
  return PlayerRig(state, rig);
}

/// What a test drives: Classic's state and the layer's playback.
final class PlayerRig {
  PlayerRig(this.state, this.playback);
  final FakePlayerState state;
  final FakePlayback playback;
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
  int get bufferedPosition => 4 * 60 * 1000;
  @override
  bool get canPlayNextEpisode => true;
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
class FakePlayback extends NextPlayback {
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

NextUiServices playerTestServices() {
  final unused = _Unused();
  return NextUiServices(
    data: _Data(),
    actions: _Actions(),
    chat: _Port(),
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

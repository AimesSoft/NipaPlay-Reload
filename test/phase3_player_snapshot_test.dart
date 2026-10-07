import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/playback/player_ui_snapshot.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class _Player extends Fake implements Player {
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 10000);
  @override
  bool get prefersPlatformVideoSurface => false;
  @override
  bool get handlesVideoAspectFit => false;
}

class _State extends ChangeNotifier implements VideoPlayerState {
  @override
  final Player player = _Player();
  @override
  PlayerStatus status = PlayerStatus.playing;
  @override
  int playerSurfaceGeneration = 0;
  @override
  bool showControls = false;
  @override
  final List<String> statusMessages = [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    return switch (invocation.memberName) {
      #hasVideo || #supportsVideoAspectModes || #danmakuVisible => true,
      #isDfmStartupGatePending ||
      #isFullscreen ||
      #desktopHoverSettingsMenuEnabled ||
      #isInFinalLoadingPhase ||
      #shouldHideDanmakuForScreenshot ||
      #isNativeDanmakuActive =>
        false,
      #videoAspectMode => VideoAspectMode.contain,
      #aspectRatio => 16 / 9,
      #actualDanmakuFontSize => 25.0,
      #mappedDanmakuOpacity => 1.0,
      #videoDuration => const Duration(seconds: 10),
      #danmakuOverlayKey => 1,
      #error ||
      #currentVideoPath ||
      #animeTitle ||
      #episodeTitle ||
      #animeId ||
      #loadingCoverImageUrl =>
        null,
      _ => super.noSuchMethod(invocation),
    };
  }

  void tick() => notifyListeners();
}

void main() {
  testWidgets(
      'clock notifications do not rebuild layout; controls, messages and kernel changes do',
      (tester) async {
    final state = _State();
    var builds = 0;
    await tester.pumpWidget(ChangeNotifierProvider<VideoPlayerState>.value(
        value: state,
        child: Selector<VideoPlayerState, List<Object?>>(
          selector: (_, value) => playerUiSnapshot(value),
          builder: (_, snapshot, __) {
            builds++;
            return const SizedBox();
          },
        )));
    for (var i = 0; i < 100; i++) {
      state.tick();
      await tester.pump();
    }
    expect(builds, 1);
    state.showControls = true;
    state.tick();
    await tester.pump();
    expect(builds, 2);
    state.statusMessages.add('loading');
    state.tick();
    await tester.pump();
    expect(builds, 3);
    state.playerSurfaceGeneration++;
    state.tick();
    await tester.pump();
    expect(builds, 4);
    state.status = PlayerStatus.paused;
    state.tick();
    await tester.pump();
    expect(builds, 5);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}

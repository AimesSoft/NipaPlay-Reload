import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/widgets/external_subtitle_overlay.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stacked-subtitle auto placement tests:
/// when an app-rendered external subtitle is activated while an embedded
/// track is displayed (mixed stacking), it is automatically placed
/// centered in the bottom letterbox bar (below the video rect) so the user
/// does not have to long-press-drag it there on every episode. Manual
/// drags / global sliders take over and clear the auto placement, and the
/// placement never touches the subtitle edit box (no danmaku flicker
/// source at playback start).
class _FakeMediaKitDelegate extends Fake implements MediaKitPlayerAdapter {
  _FakeMediaKitDelegate({this.embeddedTracks = const [0]});

  final List<int> embeddedTracks;
  final Map<String, String> writtenProperties = {};

  @override
  void setProperty(String key, String value) {
    writtenProperties[key] = value;
  }

  @override
  int get position => 0;

  @override
  List<int> get activeSubtitleTracks => embeddedTracks;

  @override
  bool get supportsExternalSubtitles => true;

  @override
  void setMedia(String path, PlayerMediaType type) {}

  @override
  ValueListenable<bool> get buffering => ValueNotifier<bool>(false);
}

Future<VideoPlayerState> _buildVideoPlayerState(
    AbstractPlayer delegate,
    {Map<String, Object>? carriedPrefs}) async {
  // setMockInitialValues replaces the whole backing store: when a test
  // builds a second state it must carry the previous store over, or saved
  // per-path display states are lost.
  SharedPreferences.setMockInitialValues(carriedPrefs ?? <String, Object>{});
  final videoState = VideoPlayerState();
  final player = Player.withDelegate(delegate);
  videoState.player = player;
  // Production syncs managers via player_kernel_manager; tests must do it
  // manually so SubtitleManager observes the fake kernel (Media Kit).
  videoState.subtitleManager.updatePlayer(player);
  return videoState;
}

Future<String> _writeTempSrt([String marker = '外挂字幕行']) async {
  final dir = await Directory.systemTemp.createTemp('auto_place_test');
  final file = File('${dir.path}/sample.chs.srt');
  await file.writeAsString('1\n00:00:00,000 -- 01:00:00,000\n'.replaceAll(
      ' -- ', ' --> ') +
      '$marker\n');
  return file.path;
}

void main() {
  testWidgets('auto-places a stacked external into the bottom letterbox bar',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    // The auto placement is an async state write; settle the microtasks.
    await tester.pump();
    await tester.pump();

    expect(videoState.pathSubtitleBelowVideo(path), isTrue,
        reason: 'Mixed stacking (embedded displayed) must auto-place the '
            'external subtitle below the video rect');
    // The placement is a pure state write: no edit box at playback start.
    expect(videoState.subtitleEditBoxVisible, isFalse);
  });

  testWidgets('manual position drag takes over and clears the auto placement',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pump();
    await tester.pump();
    expect(videoState.pathSubtitleBelowVideo(path), isTrue);

    videoState.setPathSubtitlePosition(path, 50);
    expect(videoState.pathSubtitleBelowVideo(path), isFalse,
        reason: 'An explicit drag/slider position is user intent and must '
            'override the auto placement');
  });

  testWidgets('a previously adjusted subtitle keeps its saved placement',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pump();
    await tester.pump();
    videoState.setPathSubtitlePosition(path, 42);

    // A fresh state (new episode session) restores the saved placement and
    // must not re-auto-place over it. Seed the store with the same saved
    // display-state JSON the first state wrote (same key rule as
    // SubtitleManager: subtitle_display_<sha1(path)>).
    final savedJson = json.encode(<String, double>{
      'delay': 0.0,
      'position': 42.0,
      'marginX': 0.0,
    });
    final displayStateKey =
        'subtitle_display_${sha1.convert(utf8.encode(path))}';
    final secondState = await _buildVideoPlayerState(delegate, carriedPrefs: {
      displayStateKey: savedJson,
    });
    secondState.setExternalSubtitle(path);
    await tester.pump();
    await tester.pump();
    expect(secondState.pathSubtitleBelowVideo(path), isFalse);
    expect(secondState.pathSubtitlePosition(path), 42);
  });

  testWidgets('no auto placement without a displayed embedded track',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(embeddedTracks: const []);
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pump();
    await tester.pump();
    expect(videoState.pathSubtitleBelowVideo(path), isFalse,
        reason: 'Solo external subtitles keep the regular default position');
  });

  testWidgets('renders centered in the bottom bar, computed from live rect',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pumpWidget(_wrapStage(videoState, path));
    // Wait for the subtitle parse to fill the text cache.
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (videoState.pathSubtitleTextAt(path, 1000).isNotEmpty) return;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pump();
    expect(videoState.pathSubtitleTextAt(path, 1000), isNotEmpty);
    // In the real player the overlay rebuilds every frame via the playback
    // position ValueListenableBuilder; the bare test harness must re-pump
    // to pick up the state that changed during runAsync (SubtitleManager
    // notifications do not reach VideoPlayerState listeners).
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.pump();

    // Stage 800x600, default 16:9 video: rect bottom at 525/600, bar center
    // at 562.5 → Align y = ((562.5-16)/568)*2-1 ≈ 0.9243.
    final align = tester.widget<Align>(
      find.ancestor(
        of: find.text('外挂字幕行'),
        matching: find.byType(Align),
      ).first,
    );
    expect((align.alignment as Alignment).y, closeTo(0.9243, 0.001));

    // Regular placement (auto cleared) renders at the position value
    // (default 90 → y = 0.8).
    videoState.setPathSubtitlePosition(path, 90);
    await tester.pump();
    final alignRegular = tester.widget<Align>(
      find.ancestor(
        of: find.text('外挂字幕行'),
        matching: find.byType(Align),
      ).first,
    );
    expect((alignRegular.alignment as Alignment).y, 0.8);
  });

  testWidgets('edit box collapses on outside tap', (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (videoState.pathSubtitleTextAt(path, 1000).isNotEmpty) return;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.pump();

    // 长按出框
    await tester.longPress(find.text('外挂字幕行').first);
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isTrue);

    // 点击框外任意区域（舞台级命中层）→ 收框，点击恢复透传
    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isFalse);
  });

  testWidgets('idle-gap placeholder is dismissible by outside tap',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (videoState.pathSubtitleTextAt(path, 1000).isNotEmpty) return;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.pump();
    await tester.longPress(find.text('外挂字幕行').first);
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isTrue);

    // 播放推进到无字幕的空隙：占位小框出现（边界可辨识）
    await tester.pumpWidget(_wrapStage(videoState, path, positionMs: 3700000));
    await tester.pump();
    expect(videoState.pathSubtitleTextAt(path, 3700000), isEmpty);

    // 占位小框期间点框外 → 收框（修复：以前空隙期孤框无法消）
    await tester.tapAt(const Offset(30, 30));
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isFalse);
    expect(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).border != null),
      findsNothing,
    );
  });

  testWidgets('closing the settings panel collapses the edit box',
      (tester) async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    late final String path;
    await tester.runAsync(() async {
      path = await _writeTempSrt();
    });

    videoState.setExternalSubtitle(path);
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.runAsync(() async {
      for (var i = 0; i < 40; i++) {
        if (videoState.pathSubtitleTextAt(path, 1000).isNotEmpty) return;
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpWidget(_wrapStage(videoState, path));
    await tester.pump();
    await tester.longPress(find.text('外挂字幕行').first);
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isTrue);

    // 打开设置面板（框上 tune 按钮），点面板外（barrier）关闭 → 收框
    await tester.tap(find.byIcon(Icons.tune));
    await tester.pump();
    await tester.pump();
    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pump();
    expect(videoState.subtitleEditBoxVisible, isFalse,
        reason: '设置面板关闭（确认/取消）后编辑框必须一并收起');
  });
}

Widget _wrapStage(VideoPlayerState videoState, String path,
    {double positionMs = 1000}) {
  return ChangeNotifierProvider<VideoPlayerState>.value(
    value: videoState,
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: Stack(
            children: [
              Positioned.fill(
                child: const ExternalSubtitleOverlay(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

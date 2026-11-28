import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:nipaplay/player_abstraction/media_kit_player_adapter.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_subtitle_tracks_pane.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/player_remote_control_bridge.dart';
import 'package:nipaplay/themes/nipaplay/widgets/base_settings_menu.dart';
import 'package:nipaplay/themes/nipaplay/widgets/subtitle_tracks_menu.dart';
import 'package:nipaplay/widgets/embedded_subtitle_overlay.dart';
import 'package:nipaplay/widgets/external_subtitle_overlay.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whole-block embedded subtitle mode tests:
/// 1. Kernel contract — enabling the mode writes sub-visibility=no and the
///    app polls sub-text; disabling restores kernel rendering and clears
///    the residue text.
/// 2. External ASS gate — while a kernel-rendered external ASS/SSA is
///    active, the mode steps aside: sub-visibility stays on, the plain-text
///    block stays hidden, polling clears residue; clearing the external
///    resumes the mode.
/// 3. Rendering — the bilingual block renders both lines at slider 0 and
///    100 (line gap can never collapse), with kana-based line-order
///    auto-correction.
class _FakeMediaKitDelegate extends Fake implements MediaKitPlayerAdapter {
  _FakeMediaKitDelegate({this.liveProperties = const {}});

  Map<String, String> liveProperties;
  final Map<String, String> writtenProperties = {};
  @override
  final ChangeNotifier subtitleTrackChanges = ChangeNotifier();
  final List<List<int>> subtitleSelections = [];
  List<int> selectedSubtitleTracks = [];
  Future<String?> Function(String)? readLiveProperty;

  @override
  void setProperty(String key, String value) {
    writtenProperties[key] = value;
  }

  @override
  Future<String?> getLiveProperty(String name) async {
    if (readLiveProperty != null) return readLiveProperty!(name);
    return liveProperties[name];
  }

  // The external subtitle selection/clear paths touch these members
  // (guards evaluate before short-circuiting); leaving them unimplemented
  // would abort setExternalSubtitle and keep stale state.
  @override
  bool get supportsExternalSubtitles => true;

  @override
  List<int> get activeSubtitleTracks => selectedSubtitleTracks;

  // Loading an external ASS into the kernel also sets tracks and reads
  // mediaInfo; the menu-path test below goes through that load.
  @override
  set activeSubtitleTracks(List<int> value) {
    selectedSubtitleTracks = List.of(value);
    subtitleSelections.add(List.of(value));
  }

  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 10000);

  @override
  int get position => 500;

  @override
  void setMedia(String path, PlayerMediaType type) {}

  // The player= setter probes buffering state through the facade.
  @override
  ValueListenable<bool> get buffering => ValueNotifier<bool>(false);
}

// Keep the real Media Kit adapter and deliver mpv's confirmation separately
// from its selection request, including events that originate in mpv.
class _SubtitlePlatform extends mk.PlatformPlayer {
  _SubtitlePlatform() : super(configuration: const mk.PlayerConfiguration());
  final properties = <String, String>{};
  mk.SubtitleTrack? requested;

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setSubtitleTrack(mk.SubtitleTrack track) async {
    requested = track;
  }

  Future<void> setProperty(String name, String value) async {
    properties[name] = value;
  }

  void reportTracks(mk.Tracks tracks) {
    state = state.copyWith(tracks: tracks);
    tracksController.add(tracks);
  }

  Future<void> confirm(mk.SubtitleTrack track) async {
    state = state.copyWith(track: mk.Track(subtitle: track));
    trackController.add(state.track);
    await Future<void>.delayed(Duration.zero);
  }
}

class _MenuVideoState extends VideoPlayerState {
  _MenuVideoState(this.currentVideoPath);
  @override
  final String currentVideoPath;
}

Future<VideoPlayerState> _buildVideoPlayerState(AbstractPlayer delegate,
    {String? videoPath}) async {
  // Construct the state against the inert video_player kernel (no native
  // library loads in the test env); the Media Kit fake delegate is swapped
  // in right after, which is what the assertions below observe.
  SharedPreferences.setMockInitialValues(<String, Object>{
    'player_kernel_type': PlayerKernelType.videoPlayer.index,
  });
  await PlayerFactory.initialize();
  final videoState =
      videoPath == null ? VideoPlayerState() : _MenuVideoState(videoPath);
  final player = Player.withDelegate(delegate);
  videoState.player = player;
  // In production player_kernel_manager syncs the managers with the player
  // facade on kernel swaps; tests must do it manually, otherwise
  // SubtitleManager still holds the un-materialized lazy delegate (kernel
  // name "未知") and the external-ASS gate never engages.
  videoState.subtitleManager.updatePlayer(player);
  return videoState;
}

Widget _wrap(Widget child, VideoPlayerState videoState) {
  return ChangeNotifierProvider<VideoPlayerState>.value(
    value: videoState,
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _prepareSubtitleFixture(
  VideoPlayerState videoState,
  String path,
  String content,
) async {
  await File(path).writeAsString(content);
  // These tests observe rendering/track ownership, not parser scheduling.
  // Complete parsing before activation starts its fire-and-forget preloads,
  // so those calls use the cache and cannot hold a fixture open at teardown.
  await videoState.preloadSubtitleFile(path);
  expect(videoState.getCachedSubtitle(path), isNotEmpty);
}

void main() {
  testWidgets('whole-block mode writes sub-visibility and polls sub-text',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);

    await videoState.setEmbeddedSubtitleOverlayMode(true);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'no',
      reason: 'Enabling whole-block mode must hide kernel rendering',
    );
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayText, '中文翻译行\n日本語原文行');

    await videoState.setEmbeddedSubtitleOverlayMode(false);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'yes',
      reason: 'Disabling whole-block mode must restore kernel rendering',
    );
    expect(videoState.embeddedSubtitleOverlayText, isEmpty);
  });

  testWidgets('whole-block mode steps aside for kernel-rendered external ASS',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);

    // Inject an active kernel-track external ASS without touching the
    // filesystem or the kernel.
    const assPath = 'Z:/sample.chs.ass';
    videoState.setCurrentExternalSubtitlePath(assPath);
    videoState.updateDanmakuTrackInfo('external_subtitle', <String, dynamic>{
      'path': assPath,
      'title': '外挂ASS',
      'isActive': true,
      'isManualSet': true,
    });
    expect(videoState.isKernelRenderedExternalAssActive, isTrue);

    await videoState.setEmbeddedSubtitleOverlayMode(true);
    expect(
      delegate.writtenProperties['sub-visibility'],
      isNot('no'),
      reason: 'External ASS must keep libass script rendering; '
          'sub-visibility must not be turned off',
    );

    // The plain-text block must step back entirely, otherwise \pos
    // positioning and colored annotations get flattened into white
    // centered text drawn on top of the libass render.
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行');
    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: 800,
        height: 600,
        child: EmbeddedSubtitleOverlay(),
      ),
      videoState,
    ));
    await tester.pump();
    expect(find.textContaining('中文翻译行'), findsNothing);

    // Polling must not refill the block while the external ASS is active,
    // and must drop any residue collected before the switch.
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayText, isEmpty);

    // Clearing the external subtitle hands control back to the mode:
    // sub-visibility=no again and the plain-text block renders.
    videoState.setExternalSubtitle('');
    expect(
      delegate.writtenProperties['sub-visibility'],
      'no',
      reason: 'Whole-block mode must resume after the external is cleared',
    );
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行');
    await tester.pump();
    expect(find.textContaining('中文翻译行'), findsNWidgets(2)); // stroke + fill
  });

  // A plain test: the stack entry points await real file IO, which the
  // fake-async zone of testWidgets would never let complete.
  test(
      'attaching and removing a kernel ASS from the menu re-syncs sub-visibility',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    expect(delegate.writtenProperties['sub-visibility'], 'no');

    final dir = await Directory.systemTemp.createTemp('whole_block_ass');
    addTearDown(() => dir.delete(recursive: true));
    final assPath = '${dir.path}/sample.chs.ass';
    await _prepareSubtitleFixture(
      videoState,
      assPath,
      '[Script Info]\nScriptType: v4.00+\n\n[Events]\n'
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
      'Dialogue: 0,0:00:01.00,0:00:02.00,Default,,0,0,0,,外挂\n',
    );
    // The subtitle menu goes through the stack entry points, which only
    // reach SubtitleManager.
    await videoState.addExternalSubtitleToStack(assPath);
    expect(videoState.isKernelRenderedExternalAssActive, isTrue);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'yes',
      reason: 'libass must render the attached external ASS',
    );

    await videoState
        .removeExternalSubtitle(videoState.activeExternalSubtitlePaths.single);
    expect(videoState.isKernelRenderedExternalAssActive, isFalse);
    expect(
      delegate.writtenProperties['sub-visibility'],
      'no',
      reason: 'Whole-block mode must take over again after the ASS is removed',
    );
  });

  testWidgets(
      'an external SRT renders once and coexists with the embedded text block',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': 'External cue',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.debugSetEmbeddedSubtitleOverlayText('External cue');
    final dir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('external_srt_overlay_'));
    addTearDown(() => dir!.delete(recursive: true));
    final path = '${dir!.path}/movie.srt';
    await tester.runAsync(() async {
      await _prepareSubtitleFixture(
          videoState, path, '1\n00:00:00,000 --> 00:00:01,000\nExternal cue\n');
      await videoState.addExternalSubtitleToStack(path);
    });
    (videoState.playbackTimeMs as ValueNotifier<double>).value = 500;

    // Even if a native sidecar appears late, its renderer stays hidden and
    // sub-text must not create another app overlay for the same SRT.
    delegate.selectedSubtitleTracks = [0];
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    videoState.debugSetEmbeddedSubtitleOverlayText('External cue');
    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: 800,
        height: 600,
        child: Stack(children: [
          EmbeddedSubtitleOverlay(),
          ExternalSubtitleOverlay(),
        ]),
      ),
      videoState,
    ));
    await tester.pump();
    expect(find.text('External cue'), findsNWidgets(2)); // stroke + fill

    // The same mounted overlay follows selection changes through listeners.
    // 多选共存：选内嵌轨不再摘外挂，外挂 SRT 两份 stroke/fill 保持显示；
    // 内嵌轨改由内核渲染，whole-block 文本块退位（'Embedded cue' 卸载）。
    videoState.selectEmbeddedSubtitleTrack(0);
    videoState.debugSetEmbeddedSubtitleOverlayText('Embedded cue');
    await tester.pump();
    expect(find.text('External cue'), findsNWidgets(2));
    expect(find.text('Embedded cue'), findsNothing);
  });

  test('an app-only external stack hides native sidecars until it is removed',
      () async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    final dir = await Directory.systemTemp.createTemp('srt_native_visibility_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/movie.srt';
    await _prepareSubtitleFixture(
        videoState, path, '1\n00:00:00,000 --> 00:00:01,000\nCue\n');
    var notifications = 0;
    videoState.addListener(() => notifications++);

    // The adapter's cached active list is empty even if mpv selected a
    // sidecar before publishing its track event. 多选共存：挂载外挂不再清
    // 内嵌轨，因此不会向适配器写入空的 selection。
    expect(delegate.activeSubtitleTracks, isEmpty);
    await videoState.addExternalSubtitleToStack(path);
    expect(delegate.subtitleSelections, isEmpty);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    expect(notifications, greaterThan(0));

    await videoState.setEmbeddedSubtitleOverlayMode(true);
    await videoState.setEmbeddedSubtitleOverlayMode(false);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    expect(videoState.shouldRenderEmbeddedSubtitleOverlay, isFalse);

    videoState.selectEmbeddedSubtitleTrack(0);
    // 多选共存：选内嵌轨不再摘外挂。
    expect(videoState.activeExternalSubtitlePaths, [path]);
    expect(delegate.activeSubtitleTracks, [0]);
    expect(delegate.writtenProperties['sub-visibility'], 'yes');

    await videoState.addExternalSubtitleToStack(path);
    final beforeRemoval = notifications;
    await videoState.removeExternalSubtitle(path);
    expect(notifications, greaterThan(beforeRemoval));
    expect(delegate.writtenProperties['sub-visibility'], 'yes');

    // Episode reset suppresses manager notifications; the normal open hook
    // must nevertheless recompute visibility for the new media.
    videoState.setExternalSubtitle(path);
    videoState.subtitleManager.clearExternalSubtitle(notifyListenersToo: false);
    videoState.subtitleManager.setCurrentVideoPath('${dir.path}/next.mkv');
    // 换视频后内核轨道列表重置（新媒体的 track 事件回写空）——真实内核
    // 行为，测试替身需显式模拟，否则上一条视频选中的轨道残留会误判
    // “内嵌轨选中”。
    delegate.activeSubtitleTracks = [];
    videoState.applyEmbeddedSubtitleOverlayKernelState();
    expect(delegate.writtenProperties['sub-visibility'], 'yes');
    expect(videoState.activeExternalSubtitlePaths, isEmpty);
    videoState.setExternalSubtitle(path);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    videoState.selectEmbeddedSubtitleTrack(-1);
    // 多选共存：关闭字幕(<0)只清内嵌侧，外挂仍由 Flutter 叠层渲染，
    // whole-block 模式继续接管（sub-visibility 保持 no）。
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    expect(delegate.activeSubtitleTracks, isEmpty);
    expect(videoState.activeExternalSubtitlePaths, [path]);
  });

  test('whole-block mode remains active for a confirmed embedded-only track',
      () async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.selectEmbeddedSubtitleTrack(0);
    expect(videoState.shouldRenderEmbeddedSubtitleOverlay, isTrue);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
  });

  test('Media Kit reconciles a delayed embedded selection with an SRT overlay',
      () async {
    final platform = _SubtitlePlatform();
    final adapter =
        MediaKitPlayerAdapter.withPlayer(mk.Player(platformPlayer: platform));
    addTearDown(adapter.disposeAsync);
    final videoState = await _buildVideoPlayerState(adapter);
    const embedded = mk.SubtitleTrack('1', 'English', 'eng');
    const sidecar = mk.SubtitleTrack('2', 'Sidecar', null, isExternal: true);
    const tracks = mk.Tracks(subtitle: [embedded, sidecar]);
    platform.reportTracks(tracks);
    await Future<void>.delayed(Duration.zero);
    expect(adapter.mediaInfo.subtitle, hasLength(1));
    final dir = await Directory.systemTemp.createTemp('delayed_track_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/sample.srt';
    await _prepareSubtitleFixture(
        videoState, path, '1\n00:00:00,000 --> 00:00:01,000\nExternal cue\n');
    await videoState.addExternalSubtitleToStack(path);
    await platform.confirm(sidecar);
    expect(adapter.activeSubtitleTracks, isEmpty);
    expect(platform.properties['sub-visibility'], 'no');

    videoState.selectEmbeddedSubtitleTrack(0);
    expect(platform.requested, embedded);
    expect(adapter.activeSubtitleTracks, isEmpty);
    expect(platform.properties['sub-visibility'], 'no');
    await platform.confirm(embedded);
    expect(adapter.activeSubtitleTracks, [0]);
    expect(platform.properties['sub-visibility'], 'yes');
    expect(videoState.activeExternalSubtitlePaths, [path]);

    videoState.selectEmbeddedSubtitleTrack(-1);
    expect(platform.requested, mk.SubtitleTrack.no());
    await platform.confirm(mk.SubtitleTrack.no());
    expect(platform.properties['sub-visibility'], 'no');
    expect(videoState.activeExternalSubtitlePaths, [path]);
  });

  testWidgets(
      'Cupertino subtitle menu retains the SRT and shows the confirmed embedded selection',
      (tester) async {
    final platform = _SubtitlePlatform();
    final adapter =
        MediaKitPlayerAdapter.withPlayer(mk.Player(platformPlayer: platform));
    addTearDown(adapter.disposeAsync);
    const embedded = mk.SubtitleTrack('1', 'English', 'eng');
    const tracks = mk.Tracks(subtitle: [embedded]);
    platform.reportTracks(tracks);
    await tester.pump();
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('cupertino_subtitles_')))!;
    addTearDown(() => dir.delete(recursive: true));
    final videoPath = '${dir.path}/movie.mkv';
    final srt = '${dir.path}/overlay.srt';
    final videoState =
        await _buildVideoPlayerState(adapter, videoPath: videoPath);
    await tester.runAsync(() async {
      await _prepareSubtitleFixture(
          videoState, srt, '1\n00:00:00,000 --> 00:00:01,000\nOverlay\n');
      await videoState.addExternalSubtitleToStack(srt);
      await SubtitleService().addExternalSubtitle(videoPath, {
        'path': srt,
        'name': 'overlay.srt',
        'type': 'srt',
        'isActive': true,
      });
      await SubtitleService().setExternalSubtitleActive(videoPath, 0, true);
    });
    await tester.pumpWidget(
        _wrap(CupertinoSubtitleTracksPane(videoState: videoState), videoState));
    await tester.pumpAndSettle();
    final row = find.widgetWithText(AdaptivePlayerMenuTile, 'English');
    expect(row, findsOneWidget);
    await tester.ensureVisible(row);
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(platform.requested, embedded);
    final persisted = await SubtitleService().loadExternalSubtitles(videoPath);
    expect(persisted.single['isActive'], true);
    await tester.runAsync(() => platform.confirm(embedded));
    await tester.pump();
    expect(
        find.descendant(
            of: row,
            matching: find.byIcon(CupertinoIcons.check_mark_circled_solid)),
        findsOneWidget);
    await tester.ensureVisible(find.text('关闭字幕'));
    await tester.tap(find.text('关闭字幕'));
    await tester.pumpAndSettle();
    expect(videoState.activeExternalSubtitlePaths, isEmpty);
    expect(platform.requested, mk.SubtitleTrack.no());
  });

  testWidgets('NipaPlay embedded row turns off just that track',
      (tester) async {
    final platform = _SubtitlePlatform();
    final adapter =
        MediaKitPlayerAdapter.withPlayer(mk.Player(platformPlayer: platform));
    addTearDown(adapter.disposeAsync);
    const embedded = mk.SubtitleTrack('1', 'English', 'eng');
    const tracks = mk.Tracks(subtitle: [embedded]);
    platform.reportTracks(tracks);
    await tester.pump();
    final dir = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('nipaplay_subtitles_')))!;
    addTearDown(() => dir.delete(recursive: true));
    final videoPath = '${dir.path}/movie.mkv';
    final srt = '${dir.path}/overlay.srt';
    final videoState =
        await _buildVideoPlayerState(adapter, videoPath: videoPath);
    await tester.runAsync(() async {
      await _prepareSubtitleFixture(
          videoState, srt, '1\n00:00:00,000 --> 00:00:01,000\nOverlay\n');
      await videoState.addExternalSubtitleToStack(srt);
      await platform.confirm(embedded);
    });
    await tester.pumpWidget(_wrap(
        ChangeNotifierProvider(
            create: (_) => AppearanceSettingsProvider(),
            child: SettingsMenuScope(
                standaloneWindow: true,
                child: SubtitleTracksMenu(onClose: () {}))),
        videoState));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('English'));
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(platform.requested, mk.SubtitleTrack.no());
    expect(videoState.activeExternalSubtitlePaths, [srt]);
    expect(find.text('已关闭内嵌字幕'), findsOneWidget);
    await tester.runAsync(() => platform.confirm(mk.SubtitleTrack.no()));
    await tester.pump();
    await tester.ensureVisible(find.text('关闭所有字幕'));
    await tester.tap(find.text('关闭所有字幕'));
    await tester.pump();
    expect(videoState.activeExternalSubtitlePaths, isEmpty);
    expect(find.text('关闭所有字幕'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  test('remote close subtitles turns off embedded and external subtitles',
      () async {
    final platform = _SubtitlePlatform();
    final adapter =
        MediaKitPlayerAdapter.withPlayer(mk.Player(platformPlayer: platform));
    addTearDown(adapter.disposeAsync);
    final dir = await Directory.systemTemp.createTemp('remote_subtitles_');
    addTearDown(() => dir.delete(recursive: true));
    final videoPath = '${dir.path}/movie.mkv';
    final srt = '${dir.path}/overlay.srt';
    final videoState =
        await _buildVideoPlayerState(adapter, videoPath: videoPath);
    videoState.subtitleManager.setCurrentVideoPath(videoPath);
    const embedded = mk.SubtitleTrack('1', 'English', 'eng');
    const tracks = mk.Tracks(subtitle: [embedded]);
    platform.reportTracks(tracks);
    await platform.confirm(embedded);
    await _prepareSubtitleFixture(
        videoState, srt, '1\n00:00:00,000 --> 00:00:01,000\nOverlay\n');
    await videoState.addExternalSubtitleToStack(srt);
    expect(videoState.player.activeSubtitleTracks, [0]);
    expect(
        (await SubtitleService().loadExternalSubtitles(videoPath))
            .single['isActive'],
        isTrue);
    final bridge = PlayerRemoteControlBridge.instance;
    bridge.attach(videoState);
    addTearDown(() => bridge.detach(videoState));
    final response = await bridge.executeCommand(
        'set_parameter', {'key': 'subtitle.activeTrackIndex', 'value': -1});
    expect(response['success'], isTrue);
    expect(platform.requested, mk.SubtitleTrack.no());
    expect(videoState.activeExternalSubtitlePaths, isEmpty);
    final persisted =
        (await SubtitleService().loadExternalSubtitles(videoPath)).single;
    expect(persisted['isActive'], isFalse);
    expect(
        await SubtitleService().getLastActiveSubtitleIndex(videoPath), isNull);
  });

  test('an ASS and SRT stack retains libass until the native ASS is removed',
      () async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    final dir =
        await Directory.systemTemp.createTemp('mixed_ass_srt_visibility_');
    addTearDown(() => dir.delete(recursive: true));
    final assPath = '${dir.path}/movie.ass';
    final srtPath = '${dir.path}/movie.srt';
    await _prepareSubtitleFixture(
      videoState,
      assPath,
      '[Script Info]\nScriptType: v4.00+\n\n[Events]\n'
      'Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n'
      'Dialogue: 0,0:00:00.00,0:00:01.00,Default,,0,0,0,,ASS cue\n',
    );
    await _prepareSubtitleFixture(
        videoState, srtPath, '1\n00:00:00,000 --> 00:00:01,000\nSRT cue\n');

    await videoState.addExternalSubtitleToStack(srtPath);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    await videoState.addExternalSubtitleToStack(assPath);
    expect(delegate.writtenProperties['sub-visibility'], 'yes');
    expect(videoState.isKernelRenderedExternalAssActive, isTrue);
    expect(videoState.shouldRenderEmbeddedSubtitleOverlay, isFalse);

    // Reloading the SRT makes it the primary path, without removing the ASS.
    videoState.subtitleManager
        .setExternalSubtitle(srtPath, preserveStack: true);
    expect(videoState.getActiveExternalSubtitlePath(), srtPath);
    expect(videoState.isKernelRenderedExternalAssActive, isTrue);
    expect(delegate.writtenProperties['sub-visibility'], 'yes');

    await videoState.removeExternalSubtitle(assPath);
    expect(videoState.activeExternalSubtitlePaths, [srtPath]);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
    await videoState.removeExternalSubtitle(srtPath);
    expect(videoState.shouldRenderEmbeddedSubtitleOverlay, isTrue);
    expect(delegate.writtenProperties['sub-visibility'], 'no');
  });

  test('a pending native text read cannot refill the block after SRT selection',
      () async {
    final delegate = _FakeMediaKitDelegate();
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    final response = Completer<String?>();
    delegate.readLiveProperty = (_) => response.future;
    videoState.pollEmbeddedSubtitleOverlayText();
    final dir = await Directory.systemTemp.createTemp('pending_sub_text_');
    addTearDown(() => dir.delete(recursive: true));
    final path = '${dir.path}/movie.srt';
    await _prepareSubtitleFixture(
        videoState, path, '1\n00:00:00,000 --> 00:00:01,000\nCue\n');
    await videoState.addExternalSubtitleToStack(path);
    response.complete('stale native SRT text');
    await Future<void>.delayed(Duration.zero);
    expect(videoState.embeddedSubtitleOverlayText, isEmpty);
  });

  testWidgets(
      'bilingual line order auto-corrects: translation above, original below',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      // Kernel event order can put the Japanese line first.
      'sub-text': '日本語原文行テスト\n中文翻译行',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();

    // Kana lines are the original (bottom), pure-Han lines the translation
    // (top) — no manual switch needed.
    expect(videoState.embeddedSubtitleOverlayDisplayText, '中文翻译行\n日本語原文行テスト');
    await tester.pumpWidget(_wrap(
      const SizedBox(
        width: 800,
        height: 600,
        child: EmbeddedSubtitleOverlay(),
      ),
      videoState,
    ));
    await tester.pump();
    expect(find.text('中文翻译行\n日本語原文行テスト'), findsNWidgets(2));

    // Already-correct kernel order stays untouched. (Polling throttles on
    // the real clock; tests inject via the debug entry point.)
    videoState.debugSetEmbeddedSubtitleOverlayText('中文翻译行\n日本語原文行テスト');
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayDisplayText, '中文翻译行\n日本語原文行テスト');

    // All-kana (pure Japanese) block: no evidence to reorder, keep as-is.
    videoState.debugSetEmbeddedSubtitleOverlayText('日本語一行目\n日本語二行目');
    await tester.pump();
    expect(videoState.embeddedSubtitleOverlayDisplayText, '日本語一行目\n日本語二行目');
  });

  testWidgets('bilingual block renders both lines at slider 0 and 100',
      (tester) async {
    final delegate = _FakeMediaKitDelegate(liveProperties: {
      'sub-text': '中文翻译行\n日本語原文行',
    });
    final videoState = await _buildVideoPlayerState(delegate);
    await videoState.setEmbeddedSubtitleOverlayMode(true);
    videoState.pollEmbeddedSubtitleOverlayText();
    await tester.pump();
    await tester.pump();

    Future<void> pumpAtPosition(double position) async {
      await videoState.setSubtitlePosition(position);
      await tester.pumpWidget(_wrap(
        const SizedBox(
          width: 800,
          height: 600,
          child: EmbeddedSubtitleOverlay(),
        ),
        videoState,
      ));
      await tester.pump();
    }

    // Position 0 (top): both lines must render in full — the whole-block
    // mode can never collapse the authored line gap.
    await pumpAtPosition(0);
    expect(find.textContaining('中文翻译行'), findsNWidgets(2)); // stroke + fill
    expect(find.textContaining('日本語原文行'), findsNWidgets(2));
    final alignAtTop = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('中文翻译行'),
            matching: find.byType(Align),
          )
          .first,
    );
    expect((alignAtTop.alignment as Alignment).y, -1);

    // Position 100 (bottom): the same block moved as a whole, both lines
    // still complete.
    await pumpAtPosition(100);
    expect(find.textContaining('中文翻译行'), findsNWidgets(2));
    expect(find.textContaining('日本語原文行'), findsNWidgets(2));
    final alignAtBottom = tester.widget<Align>(
      find
          .ancestor(
            of: find.textContaining('中文翻译行'),
            matching: find.byType(Align),
          )
          .first,
    );
    expect((alignAtBottom.alignment as Alignment).y, 1);
  });
}

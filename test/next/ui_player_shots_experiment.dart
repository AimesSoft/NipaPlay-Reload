// Run explicitly: pictures of Next's player layer, for looking at, not a
// regression suite. The video is a still from the TMDB sample directory
// (lib/next/ui/dev/dev_services.dart); the shell runs on its fake world.
//
//   flutter test --no-pub test/next/ui_player_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/player-shots.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/dev/fake_world.dart';
import 'package:nipaplay/next/ui/player/playback.dart';
import 'package:nipaplay/next/ui/player/timeline.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/shell/shell_controller.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/utils/video_player_state.dart';

import 'player_test_support.dart';

const _samples = '/tmp/nipa-next/visual/tmdb';
const _out = '/tmp/nipa-next/player-shots';
const _still = '$_samples/frieren-ep5.jpg';

const _fontFiles = {
  'PingFang SC': [
    '/System/Library/AssetsV2/com_apple_MobileAsset_Font8/86ba2c91f017a3749571a82f2c6d890ac7ffb2fb.asset/AssetData/PingFang.ttc',
    '/System/Library/Fonts/Hiragino Sans GB.ttc',
  ],
  'CupertinoSystemText': ['/System/Library/Fonts/SFNS.ttf'],
  'CupertinoSystemDisplay': ['/System/Library/Fonts/SFNS.ttf'],
  'Songti SC': ['/System/Library/Fonts/Supplemental/Songti.ttc'],
  'Menlo': ['/System/Library/Fonts/Menlo.ttc'],
};

Future<void> _loadFonts() async {
  for (final MapEntry(key: family, value: files) in _fontFiles.entries) {
    final file = files.map(File.new).where((f) => f.existsSync()).firstOrNull;
    if (file == null) continue;
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    await loader.load();
  }
}

/// Comments over a 24 minute episode: a steady murmur, a crowd at the
/// opening and around a few scenes.
List<Map<String, dynamic>> _danmaku() {
  final random = math.Random(5);
  double around(double at, double spread) =>
      at + (random.nextDouble() + random.nextDouble() - 1) * spread;
  return [
    for (var i = 0; i < 1500; i++) {'time': random.nextDouble() * 1440},
    for (var i = 0; i < 700; i++) {'time': around(60, 50)},
    for (var i = 0; i < 500; i++) {'time': around(540, 70)},
    for (var i = 0; i < 900; i++) {'time': around(905, 60)},
    for (var i = 0; i < 400; i++) {'time': around(1260, 80)},
    for (var i = 0; i < 300; i++) {'time': around(1390, 30)},
  ];
}

/// The fake world, knowing a playing file as Frieren's fifth episode.
final class _Knows implements NextUiData, NextNowPlaying {
  _Knows(this.world);
  final FakeWorld world;

  @override
  Future<UiNowPlaying?> nowPlaying(String path) async {
    final fifth = (await world.episodes('frieren'))
        .where((e) => e.number == 5)
        .firstOrNull;
    return UiNowPlaying(
        workId: 'frieren',
        work: '葬送的芙莉莲',
        episodeId: fifth?.episodeId,
        episode: '第 5 集 ${fifth?.title ?? ''}'.trim());
  }

  @override
  Future<UiHome> home() => world.home();
  @override
  Future<UiWork?> work(String workId) => world.work(workId);
  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) =>
      world.episodes(workId, season: season);
  @override
  Future<List<UiWork>> library() => world.library();
  @override
  Future<List<UiCard>> cards({required String threadId, String? turnId}) =>
      world.cards(threadId: threadId, turnId: turnId);
  @override
  Stream<List<UiTask>> tasks() => world.tasks();
  @override
  Stream<void> get changes => world.changes;
}

NextUiServices _world() {
  final world = FakeWorld.load(_samples, tasks: false)!;
  return NextUiServices(
    data: _Knows(world),
    actions: world,
    chat: FakeChatPort(world),
    discover: world,
    library: world.catalog,
    libraryActions: world.catalog,
    search: world.search,
    settings: FakeSettings(),
    onDispose: world.dispose,
  );
}

/// Episodes as the sample work has them.
class _Rig extends FakePlayback {
  _Rig(super.state);

  @override
  Future<List<EpisodeChoice>> episodes() async => [
        for (final (i, t) in const [
          '冒险的结束',
          '也不一定要是魔法…',
          '杀人魔法',
          '灵魂安眠之地',
          '死者的幻影',
          '村子的英雄',
          '就像是在讲童话故事',
          '葬送的芙莉莲',
          '断头台阿乌拉',
          '强大的魔法使',
        ].indexed)
          EpisodeChoice(
              title: '第${i + 1}话 $t',
              current: i == 4,
              progress: i < 4 ? 1 : (i == 5 ? 0.3 : null)),
      ];

  @override
  Future<List<SubtitleChoice>> subtitles() async => const [
        SubtitleChoice.off(),
        SubtitleChoice.embedded('简体中文', 0, selected: true),
        SubtitleChoice.embedded('繁体中文', 1),
        SubtitleChoice.file('葬送的芙莉莲 05.ja', '/subs/05.ja.ass'),
      ];
}

void main() {
  final shoot = File(_still).existsSync();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
    NextShell.debugServices = (_) => _world();
  });
  tearDown(() => NextShell.debugServices = null);

  Finder button(String label) => find.byWidgetPredicate(
      (w) => w is Pressable && w.semanticLabel == label);

  Future<PlayerRig> open(WidgetTester tester,
      {PlayerStatus status = PlayerStatus.playing}) async {
    // Decoded outside the test's fake clock, so the picture is there at once.
    final still = await tester.runAsync(() async {
      await _loadFonts();
      // Nipa's face, into the image cache before anything asks for it.
      final face = Completer<void>();
      const NipaFaceImage().resolve(ImageConfiguration.empty).addListener(
          ImageStreamListener((_, __) => face.complete(),
              onError: (_, __) => face.complete()));
      await face.future;
      final codec =
          await ui.instantiateImageCodec(File(_still).readAsBytesSync());
      return (await codec.getNextFrame()).image;
    });
    final rig = await pumpPlayer(
      tester,
      status: status,
      pixelRatio: 2,
      classic: RawImage(image: still, fit: BoxFit.cover),
      state: FakePlayerState()
        ..position = const Duration(minutes: 14, seconds: 32)
        ..danmakuList = _danmaku(),
      playback: _Rig.new,
    );
    await tester.pump(const Duration(milliseconds: 900));
    return rig;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    // A frame for what changed, then the time its animations take.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(() async {
      final boundary = playerShotKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('playing, the pointer on the timeline', (tester) async {
    final rig = await open(tester);
    rig.playback.segment = SkipSegmentKind.opening;
    rig.state.notify();
    final line = tester.getRect(find.byType(PlayerTimeline));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(720, 400));
    await mouse.moveTo(Offset(line.left + line.width * 0.62, line.bottom - 12));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('跳过片头'), findsOneWidget);
    await shot(tester, '1-playing');
    await mouse.removePointer();
    await close(tester);
  }, skip: !shoot);

  testWidgets('subtitles', (tester) async {
    await open(tester);
    await tester.tap(button('字幕'));
    await shot(tester, '2-subtitles');
    await close(tester);
  }, skip: !shoot);

  testWidgets('episodes', (tester) async {
    await open(tester);
    await tester.tap(button('剧集'));
    await shot(tester, '3-episodes');
    await close(tester);
  }, skip: !shoot);

  testWidgets('episodes of a work the library knows', (tester) async {
    final rig = await open(tester);
    rig.state.currentVideoPath = '/v/Frieren - 05.mkv';
    rig.state.notify();
    await tester.pump();
    // The stills, read and decoded for real, at the size the menu decodes
    // them (112 wide at 2x, rounded up to 128 pixels).
    final context = tester.element(find.byType(PlayerTimeline));
    await tester.runAsync(() async {
      for (var n = 1; n <= 12; n++) {
        final file = File('$_samples/frieren-ep$n.jpg');
        if (!file.existsSync()) continue;
        await precacheImage(
            ResizeImage(FileImage(file), width: 256), context);
      }
    });
    await tester.tap(button('剧集'));
    await tester.pump();
    await shot(tester, '3b-episodes-library');
    await close(tester);
  }, skip: !shoot);

  testWidgets('梨花 over the video', (tester) async {
    await open(tester);
    final shell = NextShellScope.of(tester.element(find.byType(PlayerTimeline)));
    shell.openChat();
    await tester.pump(const Duration(seconds: 1));
    await shot(tester, '4-nipa');
    await close(tester);
  }, skip: !shoot);

  testWidgets('opening', (tester) async {
    await open(tester, status: PlayerStatus.loading);
    await shot(tester, '5-loading');
    await close(tester);
  }, skip: !shoot);

  testWidgets('the pointer rests', (tester) async {
    final rig = await open(tester);
    rig.state.showControlsNow(false);
    await shot(tester, '6-resting');
    await close(tester);
  }, skip: !shoot);
}

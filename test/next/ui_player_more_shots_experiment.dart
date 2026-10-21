// Run explicitly: pictures of ⋯ and the subtitle menu's look in Next's
// player, for looking at, not a regression suite. The video is a still from
// the TMDB sample directory; the menus run over Classic's own state.
//
//   flutter test --no-pub test/next/ui_player_more_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/player-more-shots.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/ui/data/services.dart';
import 'package:nipaplay/next/ui/dev/fake_settings.dart';
import 'package:nipaplay/next/ui/dev/fake_world.dart';
import 'package:nipaplay/next/ui/player/playback.dart';
import 'package:nipaplay/next/ui/shell/next_shell.dart';
import 'package:nipaplay/next/ui/widgets/buttons.dart';
import 'package:nipaplay/next/ui/widgets/nipa_avatar.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';

const _samples = '/tmp/nipa-next/visual/tmdb';
const _out = '/tmp/nipa-next/player-more-shots';
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

/// Comments over a 24 minute episode, for the timeline's heat.
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
  ];
}

NextUiServices _world() {
  final world = FakeWorld.load(_samples, tasks: false)!;
  return NextUiServices(
    data: world,
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

void main() {
  final shoot = File(_still).existsSync();

  setUp(() {
    // Classic's state reads its settings as it is made.
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('nipaplay/next_chrome'),
            (call) async => {'leading': 78.0, 'fullScreen': false});
    NextShell.debugServices = (_) => _world();
  });
  tearDown(() => NextShell.debugServices = null);

  Finder button(String label) =>
      find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

  Future<ClassicRig> open(WidgetTester tester) async {
    final still = await tester.runAsync(() async {
      await _loadFonts();
      final face = Completer<void>();
      const NipaFaceImage().resolve(ImageConfiguration.empty).addListener(
          ImageStreamListener((_, __) => face.complete(),
              onError: (_, __) => face.complete()));
      await face.future;
      final codec =
          await ui.instantiateImageCodec(File(_still).readAsBytesSync());
      return (await codec.getNextFrame()).image;
    });
    final state = ClassicPlayerState()..comments = _danmaku();
    final rig = await pumpClassicPlayer(
      tester,
      state: state,
      pixelRatio: 2,
      classic: RawImage(image: still, fit: BoxFit.cover),
      playback: (s) => ClassicPlayback(s)..still = _still,
    );
    await tester.pump(const Duration(milliseconds: 900));
    return rig;
  }

  Future<void> shot(WidgetTester tester, String name) async {
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
    await tester.pump(const Duration(seconds: 5));
  }

  /// Frames as a screen draws them, so a page's size settles as it would.
  Future<void> frames(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> more(WidgetTester tester, [String? page]) async {
    await tester.tap(button('更多'));
    await frames(tester);
    if (page != null) {
      await tester.tap(button(page));
      await frames(tester);
    }
  }

  testWidgets('⋯', (tester) async {
    await open(tester);
    await more(tester);
    await shot(tester, '1-more');
    await close(tester);
  }, skip: !shoot);

  testWidgets('the speed', (tester) async {
    final rig = await open(tester);
    await rig.state.setPlaybackRate(1.25);
    await more(tester, '倍速');
    await shot(tester, '2-rate');
    await close(tester);
  }, skip: !shoot);

  testWidgets('the audio track', (tester) async {
    await open(tester);
    await more(tester, '音轨');
    await shot(tester, '3-audio');
    await close(tester);
  }, skip: !shoot);

  testWidgets('the picture', (tester) async {
    await open(tester);
    await more(tester, '画面');
    await shot(tester, '4-fit');
    await close(tester);
  }, skip: !shoot);

  testWidgets('danmaku', (tester) async {
    final rig = await open(tester);
    await rig.state.setDanmakuOpacity(0.8);
    await rig.state.setDanmakuDisplayArea(0.33);
    await rig.state.setBlockTopDanmaku(true);
    rig.state.setManualDanmakuOffset(1.5);
    await more(tester, '弹幕');
    await shot(tester, '5-danmaku');
    await close(tester);
  }, skip: !shoot);

  testWidgets('the subtitle on', (tester) async {
    final rig = await open(tester);
    await rig.state.setSubtitleDelaySeconds(0.5);
    await tester.tap(button('字幕'));
    await tester.pump(const Duration(milliseconds: 400));
    await shot(tester, '6-subtitles');
    await close(tester);
  }, skip: !shoot);

  testWidgets('a still, and the speed beside the time', (tester) async {
    final rig = await open(tester);
    await rig.state.setPlaybackRate(1.5);
    // The thumbnail decoded as the corner decodes it (192 wide at 2x).
    final context = tester.element(find.byType(NextPlaybackScope));
    await tester.runAsync(() => precacheImage(
        ResizeImage(FileImage(File(_still)), width: 384), context));
    await more(tester);
    await tester.tap(button('截图'));
    await tester.pump(const Duration(milliseconds: 60));
    await shot(tester, '7-still');
    await close(tester);
  }, skip: !shoot);
}

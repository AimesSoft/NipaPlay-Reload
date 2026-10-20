// Run explicitly: pictures of NipaPlay's own windows (asking before
// deleting, logging in) in Next's look, for looking at, not a regression
// suite. The page under them is a backdrop from the TMDB sample directory.
//
//   flutter test --no-pub test/next/ui_dialog_shots_experiment.dart
//
// Writes PNGs to /tmp/nipa-next/dialog-shots.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/accounts/login_dialog.dart';
import 'package:nipaplay/next/media_sources/login_dialog.dart';
import 'package:nipaplay/next/tasks/user_consent.dart';
import 'package:nipaplay/next/ui/theme/tokens.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

const _samples = '/tmp/nipa-next/visual/tmdb';
const _out = '/tmp/nipa-next/dialog-shots';
const _backdrop = '$_samples/frieren-backdrop.jpg';

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

final _shotKey = GlobalKey(debugLabel: 'dialog shot');

void main() {
  final shoot = File(_backdrop).existsSync();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'),
            (call) async => call.method == 'isMinimized' ? false : null);
  });
  tearDown(() => globals.nextShellHostsPlayer = false);

  /// A detail page's worth of backdrop under the window.
  Future<void> page(WidgetTester tester, {bool next = true}) async {
    tester.view.physicalSize = const Size(1440, 900) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final image = await tester.runAsync(() async {
      await _loadFonts();
      final codec =
          await ui.instantiateImageCodec(File(_backdrop).readAsBytesSync());
      return (await codec.getNextFrame()).image;
    });
    globals.nextShellHostsPlayer = next;
    await tester.pumpWidget(RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        navigatorKey: globals.navigatorKey,
        home: Stack(fit: StackFit.expand, children: [
          RawImage(image: image, fit: BoxFit.cover),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xF008080B), Color(0x4008080B)],
                stops: [0.1, 0.8],
              ),
            ),
          ),
          Positioned(
            left: 96,
            bottom: 220,
            child: Text('葬送的芙莉莲', style: NextText.serif(64)),
          ),
        ]),
      ),
    ));
    await tester.pump();
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      final boundary =
          _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(_out).create(recursive: true);
      await File('$_out/$name.png').writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
    });
  }

  final preview = {
    'downloads': [
      {
        'files': [
          {
            'path':
                '/dl/[Sakurato] Sousou no Frieren [05][AVC-8bit 1080p AAC][CHS].mkv',
            'expectedSize': 1 << 30
          },
          {
            'path':
                '/dl/[Sakurato] Sousou no Frieren [06][AVC-8bit 1080p AAC][CHS].mkv',
            'expectedSize': 1 << 30
          },
          {
            'path':
                '/dl/[Sakurato] Sousou no Frieren [07][AVC-8bit 1080p AAC][CHS].mkv',
            'expectedSize': 1 << 30
          },
          for (var i = 8; i <= 12; i++)
            {'path': '/dl/Frieren $i.mkv', 'expectedSize': 1 << 30},
        ]
      }
    ]
  };

  testWidgets('deleting', (tester) async {
    await page(tester);
    unawaited(showUserConsent('删除文件', downloadDeletionWords(preview), '删除',
        destructive: true));
    await shot(tester, '1-delete');
  }, skip: !shoot);

  testWidgets('弹弹play', (tester) async {
    await page(tester);
    unawaited(showAccountLogin({'provider': 'dandanplay', 'username': 'sakiko'},
        Completer<void>().future));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'secret');
    await shot(tester, '2-dandanplay');
  }, skip: !shoot);

  testWidgets('a media source', (tester) async {
    await page(tester);
    unawaited(showMediaSourceLogin({
      'name': '家里的 Jellyfin',
      'type': 'jellyfin',
      'url': 'http://192.168.1.20:8096',
      'username': 'sakiko'
    }, Completer<void>().future));
    await shot(tester, '3-source');
  }, skip: !shoot);

  testWidgets('Bangumi', (tester) async {
    await page(tester);
    unawaited(
        showAccountLogin({'provider': 'bangumi'}, Completer<void>().future));
    await shot(tester, '4-bangumi');
  }, skip: !shoot);

  testWidgets('a question that is not a deletion', (tester) async {
    await page(tester);
    unawaited(showUserConsent('快捷键冲突', '这个快捷键已被其他操作使用，要替换吗？', '替换'));
    await shot(tester, '5-replace');
  }, skip: !shoot);

  testWidgets('Next off: Classic', (tester) async {
    await page(tester, next: false);
    unawaited(showUserConsent('删除文件', downloadDeletionWords(preview), '删除',
        destructive: true));
    await shot(tester, '0-classic-delete');
  }, skip: !shoot);
}

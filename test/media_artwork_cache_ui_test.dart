import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/immersive_anime_detail_scaffold.dart';
import 'package:nipaplay/utils/image_cache_manager.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/widgets/image_cache_memory_pressure_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<List<int>> png({bool logo = false}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (logo) {
    final text = TextPainter(
        textDirection: TextDirection.ltr,
        text: const TextSpan(
            text: '作品标志',
            style: TextStyle(
                color: Colors.white,
                fontSize: 64,
                fontFamily: 'subfont',
                fontWeight: FontWeight.w900)))
      ..layout();
    text.paint(canvas, const Offset(8, 15));
    text.dispose();
  } else {
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = Colors.pink);
  }
  final picture = recorder.endRecording();
  final image = await picture.toImage(logo ? 500 : 16, logo ? 120 : 16);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return bytes!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('subfont')
          ..addFont(rootBundle.load('assets/subfont.ttf')))
        .load();
    await (FontLoader('packages/kmbal_ionicons/Ionicons')
          ..addFont(rootBundle
              .load('packages/kmbal_ionicons/assets/fonts/Ionicons.ttf')))
        .load();
  });
  late Directory directory;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('artwork-cache-ui-');
    StorageService.debugAppStorageDirectoryOverride = directory;
  });
  tearDown(() async {
    ImageCacheManager.instance.clear();
    StorageService.debugAppStorageDirectoryOverride = null;
    // The singleton uses the first directory throughout this test process.
    if (directory != firstDirectory && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  Future<void> seed(String url,
      {bool logo = false, int? width, int? height}) async {
    // ImageCacheManager retains its initial storage root; discover that same
    // root through StorageService before the first access in this test file.
    final root = firstDirectory ??= directory;
    final cache = Directory('${root.path}/compressed_images');
    await cache.create(recursive: true);
    final hash = sha256.convert(utf8.encode(url));
    await File('${cache.path}/$hash.jpg').writeAsBytes(await png(logo: logo));
    await ImageCacheManager.instance
        .loadImage(url, targetWidth: width, targetHeight: height);
  }

  testWidgets(
      'memory hit stays opaque on remount and low resolution does not force a refresh',
      (tester) async {
    const url = 'https://artwork.test/small-poster.png';
    await tester.runAsync(() => seed(url, width: 16, height: 16));
    final cached = ImageCacheManager.instance
        .getCachedImage(url, targetWidth: 16, targetHeight: 16);
    Widget image() => const MaterialApp(
        home: CachedNetworkImageWidget(
            imageUrl: url,
            width: 200,
            height: 300,
            memCacheWidth: 16,
            memCacheHeight: 16,
            blurIfLowRes: true));
    for (var mount = 0; mount < 2; mount++) {
      await tester.pumpWidget(image());
      await tester.pump();
      await tester.pump();
      for (final opacity
          in tester.widgetList<AnimatedOpacity>(find.byType(AnimatedOpacity))) {
        expect(opacity.opacity, 1,
            reason: 'cached frame must not disappear during future completion');
      }
      expect(
          ImageCacheManager.instance
              .getCachedImage(url, targetWidth: 16, targetHeight: 16),
          same(cached));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets(
      'resuming without a background release does not reload every image',
      (tester) async {
    await tester
        .pumpWidget(const ImageCacheMemoryPressureHandler(child: SizedBox()));
    final generation = ImageCacheManager.instance.lifecycleGeneration.value;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(ImageCacheManager.instance.lifecycleGeneration.value, generation);
    await tester.pumpWidget(const SizedBox());
  });

  for (final size in [
    const Size(1194, 834),
    const Size(1366, 1024),
    const Size(390, 844)
  ]) {
    testWidgets('logo replaces hero text and top title truncates at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const logo = 'https://artwork.test/title-logo.png';
      await tester.runAsync(() => seed(logo, logo: true, width: 1000));
      final repaint = GlobalKey();
      const title = '很长的中文标题用于验证返回按钮右侧的单行省略展示很长的中文标题用于验证返回按钮右侧的单行省略展示';
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(brightness: Brightness.dark, fontFamily: 'subfont'),
          home: Material(
              child: AppDisplaySurfaceScope(
            surface: size.width < 600
                ? AppDisplaySurface.phone
                : AppDisplaySurface.desktopTablet,
            child: RepaintBoundary(
                key: repaint,
                child: ImmersiveAnimeDetailScaffold(
                  title: title,
                  logoUrl: logo,
                  onBack: () {},
                  metadata: const ['TV动画', '2024', '共12集'],
                  description: '这是用于验证媒体信息页布局的简介。',
                  actions:
                      const Text('观看', style: TextStyle(color: Colors.white)),
                  episodeRail: const Center(
                      child: Text('剧集', style: TextStyle(color: Colors.white))),
                )),
          ))));
      await tester.pumpAndSettle();
      final top = tester
          .widget<Text>(find.byKey(const ValueKey('immersive-top-title')));
      expect(top.maxLines, 1);
      expect(top.overflow, TextOverflow.ellipsis);
      expect(top.style?.fontWeight, FontWeight.w700);
      expect(
          find.byKey(const ValueKey('immersive-title-logo')), findsOneWidget);
      expect(find.byKey(const ValueKey('immersive-hero-title')), findsNothing,
          reason: 'loaded logo replaces the text hero title');
      expect(tester.takeException(), isNull);
      final boundary =
          repaint.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final capture = await boundary.toImage(pixelRatio: 1);
        final bytes = await capture.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/nipaplay-tmdb-layout-${size.width.toInt()}.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        capture.dispose();
      });
      await tester.pumpWidget(const SizedBox());
    });
  }
  tearDownAll(() async {
    final root = firstDirectory;
    if (root != null && await root.exists()) await root.delete(recursive: true);
  });
}

Directory? firstDirectory;

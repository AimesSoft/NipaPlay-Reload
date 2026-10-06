import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/providers/bottom_bar_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_capture_dialog.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPlayer implements Player {
  final requests = <GifExportRequest>[];
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 30000);

  @override
  String getPlayerKernelName() => 'MediaKit';

  @override
  bool get supportsGifExport => true;

  @override
  Future<GifExportResult> exportGif(GifExportRequest request) async {
    requests.add(request);
    return GifExportResult(
      outputPath: request.outputPath,
      width: request.outputWidth,
      height: request.outputHeight,
      frameCount: 1,
      fileSize: 3,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestVideoState extends ChangeNotifier implements VideoPlayerState {
  @override
  final _TestPlayer player = _TestPlayer();

  @override
  Duration get duration => const Duration(seconds: 30);

  @override
  Duration get position => const Duration(seconds: 2);

  @override
  double get aspectRatio => 16 / 9;

  @override
  bool get screenshotCaptureIncludesDanmaku => false;

  @override
  bool get screenshotCaptureIncludesSubtitles => false;

  @override
  bool get danmakuVisible => false;

  @override
  bool get screenshotCropLetterbox => false;

  @override
  bool get hasVideo => false;

  @override
  String? get currentResolvedMediaSource => '/tmp/example.mp4';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('GIF numeric editing only updates range labels', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final videoState = _TestVideoState();
    try {
      await tester.pumpWidget(AppDisplaySurfaceScope(
        surface: AppDisplaySurface.phone,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MediaCaptureDialogContent(
                videoState: videoState,
                onCaptureImage: (_,
                    {required includeDanmaku,
                    required includeSubtitles}) async {},
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('GIF 截取'));
      await tester.pumpAndSettle();
      final endField = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '结束时间');
      await tester.showKeyboard(endField);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(endField);
      final preview = tester.widget(find.byKey(const ValueKey('gif-preview')));
      final slider = tester.widget(find.byType(Slider));
      const value = TextEditingValue(
        text: '00:09.5',
        selection: TextSelection.collapsed(offset: 7),
        composing: TextRange(start: 6, end: 7),
      );
      tester.testTextInput.updateEditingValue(value);
      await tester.pump();
      expect(field.controller!.value, value);
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.text('共 7.5 秒'), findsOneWidget);
      expect(find.text('00:02.0 – 00:09.5'), findsOneWidget);
      expect(tester.widget(endField), same(field));
      expect(tester.widget(find.byKey(const ValueKey('gif-preview'))),
          same(preview));
      expect(tester.widget(find.byType(Slider)), same(slider));
      tester.testTextInput.updateEditingValue(value.copyWith(
        selection: const TextSelection.collapsed(offset: 2),
        composing: TextRange.empty,
      ));
      await tester.pump();
      expect(field.controller!.selection.baseOffset, 2);
      expect(tester.widget(find.byType(Slider)), same(slider));
      await tester.enterText(endField, '00:');
      await tester.pump();
      expect(field.controller!.text, '00:');
      expect(field.focusNode!.hasFocus, isTrue);
      expect(videoState.player.requests, isEmpty);
      await tester.enterText(endField, '00:01.0');
      await tester.pump();
      expect(find.text('时间范围无效'), findsOneWidget);
      await tester.tap(find.text('填入当前时间'));
      await tester.pump();
      expect(find.text('共 0.5 秒'), findsOneWidget);
      expect(field.controller!.text, '00:02.5');
      expect(tester.widget(find.byType(Slider)), same(slider));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      videoState.dispose();
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GIF slider updates stay local and preserve active input',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final videoState = _TestVideoState();
    try {
      await tester.pumpWidget(AppDisplaySurfaceScope(
        surface: AppDisplaySurface.phone,
        child: MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
          child: MediaCaptureDialogContent(
            videoState: videoState,
            onCaptureImage: (_,
                {required includeDanmaku, required includeSubtitles}) async {},
          ),
        ))),
      ));
      await tester.tap(find.text('GIF 截取'));
      await tester.pumpAndSettle();
      final fieldFinder = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '结束时间');
      await tester.showKeyboard(fieldFinder);
      const editing = TextEditingValue(
          text: '00:09.5',
          selection: TextSelection.collapsed(offset: 7),
          composing: TextRange(start: 6, end: 7));
      tester.testTextInput.updateEditingValue(editing);
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(fieldFinder);
      final preview = tester.widget(find.byKey(const ValueKey('gif-preview')));
      final quality =
          tester.widget(find.byType(SegmentedButton<GifExportQuality>));
      for (final fps in [16.0, 20.0, 25.0, 30.0, 5.0]) {
        tester.widget<Slider>(find.byType(Slider)).onChanged!(fps);
        await tester.pump();
        expect(find.text('${fps.round()} fps'), findsOneWidget);
        expect(tester.widget(fieldFinder), same(field));
        expect(tester.widget(find.byKey(const ValueKey('gif-preview'))),
            same(preview));
        expect(tester.widget(find.byType(SegmentedButton<GifExportQuality>)),
            same(quality));
        expect(field.controller!.value, editing);
        expect(field.focusNode!.hasFocus, isTrue);
      }
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChanged!(5.2);
      await tester.pump();
      expect(tester.widget(find.byType(Slider)), same(slider));
      expect(videoState.player.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      videoState.dispose();
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('GIF phone sheet preserves form during Android IME inset frames',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    final videoState = _TestVideoState();
    try {
      await tester.pumpWidget(ChangeNotifierProvider(
        create: (_) => BottomBarProvider(),
        child: MaterialApp(
            home: AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showMediaCaptureDialog(
                            context: context,
                            videoState: videoState,
                            onCaptureImage: (_,
                                {required includeDanmaku,
                                required includeSubtitles}) async {},
                          ),
                      child: const Text('Open capture')))),
        )),
      ));
      await tester.tap(find.text('Open capture'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('GIF 截取'));
      await tester.pumpAndSettle();
      final fieldFinder = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '宽度');
      await tester.ensureVisible(fieldFinder);
      await tester.tap(fieldFinder);
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      final field = tester.widget<TextField>(fieldFinder);
      final preview = tester.widget(find.byKey(const ValueKey('gif-preview')));
      final slider = tester.widget(find.byType(Slider));
      for (final bottom in [
        60.0,
        120.0,
        200.0,
        300.0,
        200.0,
        120.0,
        60.0,
        0.0
      ]) {
        tester.view.viewInsets = FakeViewPadding(bottom: bottom);
        await tester.pump(const Duration(milliseconds: 16));
        expect(tester.widget(fieldFinder), same(field));
        expect(tester.widget(find.byKey(const ValueKey('gif-preview'))),
            same(preview));
        expect(tester.widget(find.byType(Slider)), same(slider));
        expect(field.focusNode!.hasFocus, isTrue);
        if (bottom == 300) {
          await tester.pumpAndSettle();
          expect(tester.getRect(fieldFinder).bottom, lessThanOrEqualTo(544));
        }
      }
      await tester.pumpAndSettle();
      expect(videoState.player.requests, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      tester.view.resetViewInsets();
      videoState.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform GIF menu hides unsupported clipboard action',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(const Size(390, 844));
      final videoState = _TestVideoState();
      try {
        await tester.pumpWidget(AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(size: Size(390, 844)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MediaCaptureDialogContent(
                    videoState: videoState,
                    onCaptureImage: (_,
                        {required includeDanmaku,
                        required includeSubtitles}) async {},
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.tap(find.text('GIF 截取'));
        await tester.pumpAndSettle();

        expect(find.text('复制到剪贴板'), findsNothing);
        expect(find.text('导出动图文件'), findsOneWidget);
        final scrollable = tester.state<ScrollableState>(
          find.byWidgetPredicate((widget) =>
              widget is Scrollable &&
              widget.axisDirection == AxisDirection.down),
        );
        expect(scrollable.position.maxScrollExtent, greaterThan(0));
        await tester.drag(find.text('GIF 导出设置'), const Offset(0, -400));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(tester.takeException(), isNull);

        await tester.ensureVisible(find.text('图片截取'));
        await tester.tap(find.text('图片截取'));
        await tester.pumpAndSettle();
        expect(find.text('图片截取设置'), findsOneWidget);
        await tester.drag(find.text('图片截取设置'), const Offset(0, -300));
        await tester.pumpAndSettle();
        expect(scrollable.position.pixels, greaterThan(0));
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      } finally {
        videoState.dispose();
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  for (final size in [const Size(844, 390), const Size(667, 375)]) {
    testWidgets('landscape phone $size keeps actions reachable',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.binding.setSurfaceSize(size);
      final videoState = _TestVideoState();
      try {
        await tester.pumpWidget(AppDisplaySurfaceScope(
          surface: AppDisplaySurface.phone,
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: MediaCaptureDialogContent(
                    videoState: videoState,
                    onCaptureImage: (_,
                        {required includeDanmaku,
                        required includeSubtitles}) async {},
                  ),
                ),
              ),
            ),
          ),
        ));
        expect(
            tester.getTopLeft(find.text('图片截取设置')).dx,
            greaterThan(
                tester.getTopLeft(find.byIcon(Icons.image_outlined)).dx));
        expect(
            tester.getBottomLeft(find.text('立即截取')).dy, lessThan(size.height));

        await tester.tap(find.text('GIF 截取'));
        await tester.pumpAndSettle();
        expect(
            tester.getTopLeft(find.text('GIF 导出设置')).dx,
            greaterThan(
                tester.getTopLeft(find.byIcon(Icons.gif_box_outlined)).dx));
        expect(tester.getBottomLeft(find.text('导出动图文件')).dy,
            lessThan(size.height));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 3));
      } finally {
        videoState.dispose();
        await tester.binding.setSurfaceSize(null);
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  testWidgets('GIF time and size fields request the mobile keyboard',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final videoState = _TestVideoState();
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCaptureDialogContent(
            videoState: videoState,
            onCaptureImage: (_,
                {required includeDanmaku, required includeSubtitles}) async {},
          ),
        ),
      ));
      await tester.tap(find.text('GIF 截取'));
      await tester.pumpAndSettle();

      for (final label in ['开始时间', '结束时间', '宽度', '高度']) {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        );
        expect(field, findsOneWidget);
        await tester.ensureVisible(field);
        await tester.tap(field);
        await tester.pump();
        expect(tester.testTextInput.isVisible, isTrue, reason: label);
        expect(tester.widget<TextField>(field).focusNode?.hasFocus, isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      videoState.dispose();
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android screenshot keeps one immediate gallery action',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final videoState = _TestVideoState();
    ScreenshotSaveTarget? selectedTarget;
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCaptureDialogContent(
            videoState: videoState,
            onCaptureImage: (target,
                {required includeDanmaku, required includeSubtitles}) async {
              selectedTarget = target;
            },
          ),
        ),
      ));
      expect(find.text('立即截取'), findsOneWidget);
      expect(find.text('保存到文件'), findsNothing);
      await tester.tap(find.text('立即截取'));
      await tester.pump();
      expect(selectedTarget, ScreenshotSaveTarget.photos);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 3));
    } finally {
      videoState.dispose();
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Android GIF export saves directly to the gallery',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.binding.setSurfaceSize(const Size(1100, 900));
    final videoState = _TestVideoState();
    final directory =
        Directory.systemTemp.createTempSync('nipaplay-gif-ui-test-');
    final previousPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TestPathProvider(directory.path);
    const channel = MethodChannel('nipaplay/photo_library');
    MethodCall? captured;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        captured = call;
        return null;
      },
    );
    try {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MediaCaptureDialogContent(
            videoState: videoState,
            onCaptureImage: (_,
                {required includeDanmaku, required includeSubtitles}) async {},
          ),
        ),
      ));
      await tester.tap(find.text('GIF 截取'));
      await tester.pumpAndSettle();
      for (final entry in {
        '开始时间': '00:03.2',
        '结束时间': '00:08.5',
        '宽度': '320',
        '高度': '180',
      }.entries) {
        final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == entry.key);
        await tester.ensureVisible(field);
        await tester.enterText(field, entry.value);
      }
      await tester.pumpAndSettle();
      tester.widget<Slider>(find.byType(Slider)).onChanged!(25);
      tester
          .widget<SegmentedButton<GifExportQuality>>(
              find.byType(SegmentedButton<GifExportQuality>))
          .onSelectionChanged!({GifExportQuality.high});
      await tester.pump();
      final exportButton = find.text('导出动图文件');
      await tester.ensureVisible(exportButton);
      await tester.pumpAndSettle();
      await tester.tap(exportButton);
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(
        captured?.method,
        'saveFile',
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .whereType<String>()
            .join(' | '),
      );
      expect((captured?.arguments as Map)['mimeType'], 'image/gif');
      final request = videoState.player.requests.single;
      expect(request.start, const Duration(milliseconds: 3200));
      expect(request.end, const Duration(milliseconds: 8500));
      expect(request.outputWidth, 320);
      expect(request.outputHeight, 180);
      expect(request.framesPerSecond, 25);
      expect(request.quality, GifExportQuality.high);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      );
      PathProviderPlatform.instance = previousPathProvider;
      directory.deleteSync(recursive: true);
      videoState.dispose();
      await tester.binding.setSurfaceSize(null);
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _TestPathProvider extends PathProviderPlatform {
  _TestPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

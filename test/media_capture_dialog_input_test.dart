import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_capture_dialog.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _TestPlayer implements Player {
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 30000);

  @override
  String getPlayerKernelName() => 'MediaKit';

  @override
  bool get supportsGifExport => true;

  @override
  Future<GifExportResult> exportGif(GifExportRequest request) async {
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
  Player get player => _TestPlayer();

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
    final directory = Directory.systemTemp.createTempSync('nipaplay-gif-ui-test-');
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
      final exportButton = find.text('导出动图文件');
      await tester.ensureVisible(exportButton);
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

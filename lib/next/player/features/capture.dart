import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/player_abstraction/erika_gif_export.dart';
import 'package:nipaplay/utils/video_aspect_geometry.dart';

import '../../capabilities/media_frames_erika.dart';
import '../core/session.dart';
import '../kernel/driver.dart';
import 'kernel_features.dart';

/// The scene being displayed, without controls. Subtitle and danmaku layers
/// can read [options] while a capture is in progress. Capturing never changes
/// native track selection (in particular during MDK teardown).
final class PlaybackCapture {
  final sceneKey = GlobalKey(debugLabel: 'next.capture.scene');
  final overlayKey = GlobalKey(debugLabel: 'next.capture.overlays');
  final options = ValueNotifier(const CaptureOptions());
  bool _busy = false;

  Future<JsonMap> capture(PlaybackSession session, JsonMap input,
      {VideoAspectMode aspectMode = VideoAspectMode.contain}) async {
    if (!session.phase.value.open) {
      throw const Failure(FailureCode.unavailable, 'No open video session.');
    }
    if (_busy) {
      throw const Failure(
          FailureCode.conflict, 'A capture is already running.');
    }
    _busy = true;
    try {
      if (input['kind'] == 'gif') return await _gif(session, input);
      final prefs = await SharedPreferences.getInstance();
      final danmaku = input['includeDanmaku'] as bool? ??
          prefs.getBool('screenshot_include_danmaku') ??
          true;
      final subtitles = input['includeSubtitles'] as bool? ??
          prefs.getBool('screenshot_include_subtitles') ??
          true;
      final output = input['outputPath'] as String?;
      final extension = output == null
          ? (prefs.getString('screenshot_format') == 'jpeg' ? '.jpg' : '.png')
          : p.extension(output).toLowerCase();
      if (!{'.png', '.jpg', '.jpeg'}.contains(extension)) {
        throw const Failure(
            FailureCode.invalidInput, 'Screenshot output must be PNG or JPEG.');
      }
      final savedDirectory = prefs.getString('screenshot_save_directory');
      final path = output ??
          p.join(
              savedDirectory == null || savedDirectory.isEmpty
                  ? (await getApplicationDocumentsDirectory()).path
                  : savedDirectory,
              'NipaPlay_${DateTime.now().microsecondsSinceEpoch}$extension');
      await validateOutput(path);
      options.value = CaptureOptions(danmaku: danmaku, subtitles: subtitles);
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
      _live(session);
      final boundary = sceneKey.currentContext?.findRenderObject();
      final mounted =
          boundary is RenderRepaintBoundary && !boundary.size.isEmpty;
      final ratio = mounted
          ? View.of(sceneKey.currentContext!).devicePixelRatio.clamp(1.0, 2.0)
          : 1.0;
      final viewport = mounted
          ? boundary.size
          : Size(session.media.value!.width.toDouble(),
              session.media.value!.height.toDouble());
      final size = Size((viewport.width * ratio).roundToDouble(),
          (viewport.height * ratio).roundToDouble());
      final media = session.media.value!;
      final at = session.position;
      KernelPicture picture;
      KernelPicture? overlay;
      var source = 'displayed_scene';
      final replaceVideo = !subtitles && media.activeSubtitles.isNotEmpty;
      if (mounted && !replaceVideo && session.surface.value is TextureSurface) {
        picture = await _readBoundary(boundary, ratio);
      } else if (replaceVideo) {
        final decoder = await const ErikaFrameEngine().open(session.source.uri,
            width: media.width, timeout: const Duration(seconds: 10));
        try {
          final frame = await decoder.frameAt(at.inMilliseconds);
          picture = KernelPicture(frame.width, frame.height, frame.rgba);
        } finally {
          await decoder.close();
        }
        source = 'independent_decoder_with_displayed_overlays';
      } else if (session.driver case final KernelFrameFeatures frames) {
        picture = await frames.snapshotPicture();
        source = 'kernel_snapshot_with_displayed_overlays';
      } else {
        throw const Failure(
            FailureCode.unavailable, 'The video scene is not mounted.');
      }
      final replaceScene = source != 'displayed_scene';
      if (overlayKey.currentContext?.findRenderObject()
          case final RenderRepaintBoundary overlays when replaceScene) {
        overlay = await _readBoundary(overlays, ratio);
      }
      _live(session);
      final quality = switch (prefs.getString('screenshot_quality')) {
        'low' => 60,
        'high' => 95,
        _ => 85,
      };
      final natural = Size(media.width.toDouble(), media.height.toDouble());
      final videoRect = VideoAspectGeometry.displayRect(
          mode: aspectMode,
          viewport: size,
          sourceAspect: media.aspect,
          naturalSize: natural);
      final crop = (prefs.getBool('screenshot_crop_letterbox') ?? true)
          ? VideoAspectGeometry.visibleVideoRect(
              mode: aspectMode,
              viewport: size,
              sourceAspect: media.aspect,
              naturalSize: natural)
          : Offset.zero & size;
      final encoded = await _encodeScene(picture,
          overlay: overlay,
          sceneSize: size,
          videoRect: videoRect,
          crop: crop,
          replaceScene: replaceScene,
          jpeg: extension != '.png',
          quality: quality);
      final bytes = encoded.$1;
      await File(path).writeAsBytes(bytes, flush: true);
      return {
        'path': path,
        'kind': 'screenshot',
        'bytes': bytes.length,
        'width': encoded.$2,
        'height': encoded.$3,
        'sessionId': session.id,
        'positionMs': at.inMilliseconds,
        'danmakuRequested': danmaku,
        'danmakuIncluded': danmaku,
        'subtitlesRequested': subtitles,
        'subtitlesIncluded': subtitles,
        'source': source
      };
    } finally {
      options.value = const CaptureOptions();
      _busy = false;
    }
  }

  static Future<KernelPicture> _readBoundary(
      RenderRepaintBoundary boundary, double ratio) async {
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bytes == null) throw StateError('The scene returned no pixels.');
      return KernelPicture(image.width, image.height,
          bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    } finally {
      image.dispose();
    }
  }

  static Future<(Uint8List, int, int)> _encodeScene(KernelPicture picture,
          {KernelPicture? overlay,
          required Size sceneSize,
          required Rect videoRect,
          required Rect crop,
          required bool replaceScene,
          required bool jpeg,
          required int quality}) =>
      Isolate.run(() {
        img.Image decode(KernelPicture p) => img.Image.fromBytes(
            width: p.width,
            height: p.height,
            bytes: p.rgba.buffer,
            bytesOffset: p.rgba.offsetInBytes,
            numChannels: 4);
        var image = decode(picture);
        if (replaceScene) {
          final scene = img.Image(
              width: sceneSize.width.round(),
              height: sceneSize.height.round(),
              numChannels: 4);
          img.fill(scene, color: img.ColorRgba8(0, 0, 0, 255));
          image = img.copyResize(image,
              width: videoRect.width.round().clamp(1, 16384),
              height: videoRect.height.round().clamp(1, 16384));
          img.compositeImage(scene, image,
              dstX: videoRect.left.round(), dstY: videoRect.top.round());
          if (overlay != null) img.compositeImage(scene, decode(overlay));
          image = scene;
        }
        final x = crop.left.round().clamp(0, image.width - 1);
        final y = crop.top.round().clamp(0, image.height - 1);
        image = img.copyCrop(image,
            x: x,
            y: y,
            width: crop.width.round().clamp(1, image.width - x),
            height: crop.height.round().clamp(1, image.height - y));
        return (
          jpeg ? img.encodeJpg(image, quality: quality) : img.encodePng(image),
          image.width,
          image.height
        );
      });

  Future<JsonMap> _gif(PlaybackSession s, JsonMap input) async {
    final output = input['outputPath'] as String?;
    final start = (input['startMs'] as num?)?.toInt();
    final end = (input['endMs'] as num?)?.toInt();
    if (output == null ||
        p.extension(output).toLowerCase() != '.gif' ||
        start == null ||
        end == null ||
        start < 0 ||
        end <= start ||
        end - start > 30000 ||
        end > s.duration.inMilliseconds) {
      throw const Failure(FailureCode.invalidInput,
          'GIF requires a .gif outputPath and an interval within the video, at most 30 seconds.');
    }
    await validateOutput(output);
    // Independent Erika decoder, regardless of the playback kernel. The
    // exporter performs decoding, scaling and encoding on a worker isolate.
    final result = await exportGifWithErika({
      'inputUri': s.source.uri,
      'outputPath': output,
      'startMillis': start,
      'endMillis': end,
      'framesPerSecond': (input['fps'] as num?)?.toInt() ?? 12,
      'outputWidth': (input['width'] as num?)?.toInt() ?? 480,
      'outputHeight': (input['height'] as num?)?.toInt() ?? 270,
      'quality': input['quality'] == 'high' ? 1 : 0,
    });
    return {
      'path': result['outputPath'],
      'kind': 'gif',
      'bytes': result['fileSize'],
      'width': result['width'],
      'height': result['height'],
      'frames': result['frameCount'],
      'source': 'erika_independent_decoder',
      'danmakuIncluded': false,
      'subtitlesIncluded': false
    };
  }

  static void _live(PlaybackSession s) {
    if (s.phase.value.done) throw const KernelFenced();
  }

  static Future<void> validateOutput(String path) async {
    if (!p.isAbsolute(path)) {
      throw const Failure(
          FailureCode.invalidInput, 'outputPath must be absolute.');
    }
    if (await FileSystemEntity.type(path) != FileSystemEntityType.notFound) {
      throw const Failure(
          FailureCode.conflict, 'The output file already exists.');
    }
    await Directory(p.dirname(path)).create(recursive: true);
  }

  static Future<Uint8List> encodePicture(KernelPicture picture,
          {bool jpeg = false, int quality = 85}) =>
      Isolate.run(() {
        final decoded = img.Image.fromBytes(
            width: picture.width,
            height: picture.height,
            bytes: picture.rgba.buffer,
            bytesOffset: picture.rgba.offsetInBytes,
            numChannels: 4);
        return jpeg
            ? img.encodeJpg(decoded, quality: quality)
            : img.encodePng(decoded);
      });
}

@immutable
final class CaptureOptions {
  const CaptureOptions({this.danmaku = true, this.subtitles = true});
  final bool danmaku;
  final bool subtitles;
}

/// One displayed composition, with a separate transparent overlay read-back
/// for native video surfaces. Tracks need only supply their widgets here.
class PlaybackCaptureScene extends StatelessWidget {
  const PlaybackCaptureScene(
      {super.key,
      required this.capture,
      required this.video,
      this.overlays = const []});
  final PlaybackCapture capture;
  final Widget video;
  final List<Widget> overlays;
  @override
  Widget build(BuildContext context) => RepaintBoundary(
      key: capture.sceneKey,
      child: Stack(fit: StackFit.expand, children: [
        video,
        IgnorePointer(
            child: RepaintBoundary(
                key: capture.overlayKey,
                child: Stack(fit: StackFit.expand, children: overlays))),
      ]));
}

/// Used by subtitle/danmaku scene widgets: exclusion is applied only to this
/// capture frame, without changing the selected native tracks or user prefs.
class PlaybackCaptureLayer extends StatelessWidget {
  const PlaybackCaptureLayer(
      {super.key,
      required this.capture,
      required this.danmaku,
      required this.child});
  final PlaybackCapture capture;
  final bool danmaku;
  final Widget child;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<CaptureOptions>(
      valueListenable: capture.options,
      child: child,
      builder: (_, options, child) =>
          (danmaku ? options.danmaku : options.subtitles)
              ? child!
              : const SizedBox.shrink());
}

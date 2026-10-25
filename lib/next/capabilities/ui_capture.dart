import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import '../instance_facts.dart';
import '../player/features/kernel_features.dart' show KernelPicture;

/// The video as the player exported it, in logical pixels of the Flutter view.
final class UiVideoLayer {
  const UiVideoLayer({
    required this.picture,
    required this.rect,
    required this.positionMs,
    required this.kernel,
  });
  final KernelPicture picture;
  final ui.Rect rect;
  final int positionMs;
  final String kernel;
}

/// What a player offers `ui.capture` when the system draws its video: the
/// exported picture, or the reason it could not.
final class UiVideoCapture {
  const UiVideoCapture(UiVideoLayer this.layer)
      : failure = null,
        inScene = null;
  const UiVideoCapture.failure(String this.failure)
      : layer = null,
        inScene = null;

  /// The Flutter scene holds the picture itself ([how]: what draws it).
  const UiVideoCapture.inScene(String this.inScene)
      : layer = null,
        failure = null;
  final UiVideoLayer? layer;
  final String? failure;
  final String? inScene;
}

final class ClassicUiCapture {
  const ClassicUiCapture(this.facts, {this.videoLayer});
  final InstanceFacts facts;

  /// Asked on hosts that cannot take the window as composed on screen.
  final Future<UiVideoCapture?> Function()? videoLayer;

  static const _window = MethodChannel('nipaplay/window_shot');

  Future<JsonMap> capture({bool originalSize = false}) async {
    final instance = await facts.read();
    final viewId = instance['viewId'] ??
        (globals.navigatorKey.currentContext == null
            ? null
            : View.of(globals.navigatorKey.currentContext!).viewId);
    final views = RendererBinding.instance.renderViews
        .where((view) => view.flutterView.viewId == viewId);
    if (views.isEmpty) {
      throw const Failure(FailureCode.unavailable,
          'The connected NipaPlay main window has no attached Flutter view.');
    }
    final view = views.single;
    // The root transform layer preserves the window's actual physical pixel scale.
    // ignore: invalid_use_of_protected_member
    final layer = view.layer;
    if (view.size.isEmpty || layer == null) {
      throw const Failure(FailureCode.unavailable,
          'The connected NipaPlay main window has not rendered.');
    }
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    final directory =
        await Directory('${(await getTemporaryDirectory()).path}/ui-captures')
            .create(recursive: true);
    final physical = view.flutterView.physicalSize;
    // macOS: the window as the window server composes it, so the native
    // video layer (Erika, native Media Kit) is in the picture. Anywhere else,
    // or where that fails, the Flutter content alone, and the result says so.
    String? nativeFailure;
    if (!kIsWeb && Platform.isMacOS) {
      try {
        final path =
            '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.png';
        final shot = Map<String, Object?>.from(await _window.invokeMethod<Map>(
                'shot', {
              'path': path,
              'maxLongEdge': originalSize ? 0 : 1280,
            }) ??
            const {});
        if (shot['path'] == path) {
          return {
            'path': path,
            'bytes': await File(path).length(),
            'mimeType': 'image/png',
            'width': shot['width'],
            'height': shot['height'],
            'originalWidth': shot['originalWidth'],
            'originalHeight': shot['originalHeight'],
            'capturedAt': DateTime.now().toUtc().toIso8601String(),
            'instance': instance,
            'surface': 'main_window_composited',
            'method': 'window_composite',
            'includesNativeVideo': true,
            'includesVideo': true,
            'limitations': const [
              'Only this application\'s main window, as composed on screen; the OS window frame, other windows and external players are not included.',
            ],
          };
        }
        nativeFailure = 'The window capture returned no file.';
      } on PlatformException catch (error) {
        nativeFailure = '${error.code}: ${error.message}';
      } on MissingPluginException {
        nativeFailure = 'This build has no window capture.';
      }
    }
    final scale = originalSize
        ? 1.0
        : math.min(1.0, 1280 / math.max(physical.width, physical.height));
    final sceneImage = await (layer as OffsetLayer)
        .toImage(ui.Offset.zero & physical, pixelRatio: scale);
    // The video the system draws under the view is not in the scene (a hole):
    // the player's own picture goes under the scene, as the screen layers it.
    UiVideoCapture? video;
    if (!kIsWeb && !Platform.isMacOS && videoLayer != null) {
      video = await videoLayer!();
    }
    var image = sceneImage;
    final videoPicture = video?.layer;
    if (videoPicture != null) {
      try {
        image = await _underlay(sceneImage, videoPicture,
            logicalToImage: view.flutterView.devicePixelRatio * scale);
      } finally {
        sceneImage.dispose();
      }
    }
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final file = File(
          '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          flush: true);
      return {
        'path': file.path,
        'bytes': await file.length(),
        'mimeType': 'image/png',
        'width': image.width,
        'height': image.height,
        'originalWidth': physical.width.round(),
        'originalHeight': physical.height.round(),
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'instance': instance,
        'surface': videoPicture == null
            ? 'main_window_flutter_content'
            : 'main_window_flutter_content_over_player_frame',
        'method': videoPicture == null
            ? 'flutter_scene'
            : 'flutter_scene_over_player_frame',
        'includesNativeVideo': videoPicture != null,
        'includesVideo': videoPicture != null || video?.inScene != null,
        if (video?.inScene != null)
          'video': {'source': 'flutter_scene', 'drawnBy': video!.inScene},
        if (videoPicture != null)
          'video': {
            'source': 'kernel_snapshot',
            'kernel': videoPicture.kernel,
            'positionMs': videoPicture.positionMs,
            'width': videoPicture.picture.width,
            'height': videoPicture.picture.height,
          },
        if (video?.failure != null) 'videoFailure': video!.failure,
        if (nativeFailure != null) 'windowCaptureFailure': nativeFailure,
        'limitations': [
          'Erika native danmaku is not included, as with playback.capture.',
          if (videoPicture != null)
            'The video is the player\'s own exported picture at positionMs, drawn under the interface layer; the screen\'s scaling, colour handling and any native overlay can differ from it.'
          else if (video?.inScene != null)
            'The video is a Flutter texture inside the scene, as the kernel renders it; platform views outside the scene are not included.'
          else
            'Native video overlays and platform views outside the Flutter scene are not included: where a native layer draws the picture, it is missing here.',
          if (videoPicture != null && !videoPicture.picture.subtitlesDrawn)
            'The exported picture has no subtitles: the kernel draws them in its own window, which is not in this capture, so the selected subtitle track does not show here.',
          'The OS window frame, other windows and external players are not included.',
        ],
      };
    } finally {
      image.dispose();
    }
  }
}

/// [scene] over the player's picture on black: the layers as the screen
/// stacks them, the video under the interface.
Future<ui.Image> _underlay(ui.Image scene, UiVideoLayer video,
    {required double logicalToImage}) async {
  final pixels = await ui.ImmutableBuffer.fromUint8List(video.picture.rgba);
  final descriptor = ui.ImageDescriptor.raw(pixels,
      width: video.picture.width,
      height: video.picture.height,
      pixelFormat: ui.PixelFormat.rgba8888);
  final codec = await descriptor.instantiateCodec();
  final frame = (await codec.getNextFrame()).image;
  try {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    final size = ui.Size(scene.width.toDouble(), scene.height.toDouble());
    canvas.drawRect(ui.Offset.zero & size,
        ui.Paint()..color = const ui.Color(0xFF000000));
    final target = ui.Rect.fromLTWH(
        video.rect.left * logicalToImage,
        video.rect.top * logicalToImage,
        video.rect.width * logicalToImage,
        video.rect.height * logicalToImage);
    canvas.drawImageRect(
        frame,
        ui.Offset.zero &
            ui.Size(video.picture.width.toDouble(),
                video.picture.height.toDouble()),
        target,
        ui.Paint()..filterQuality = ui.FilterQuality.medium);
    canvas.drawImage(scene, ui.Offset.zero, ui.Paint());
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(scene.width, scene.height);
    } finally {
      picture.dispose();
    }
  } finally {
    frame.dispose();
    codec.dispose();
    descriptor.dispose();
    pixels.dispose();
  }
}

final class UiCaptureCapability implements Capability {
  UiCaptureCapability(Future<JsonMap> Function({bool originalSize}) capture)
      : actions = [UiCaptureAction(capture)];
  @override
  final List<Action> actions;
}

final class UiCaptureAction extends Action<InstanceValue, InstanceValue> {
  const UiCaptureAction(this.capture);
  final Future<JsonMap> Function({bool originalSize}) capture;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'ui.capture',
        title: 'Capture this NipaPlay main interface',
        description:
            'Capture the connected NipaPlay main window, including pages, controls and dialogs, into a local PNG file readable by the Agent. '
            'On macOS the window is captured as the window server composes it, so the native video layer (Erika, native Media Kit) and native danmaku are in the picture (method window_composite, includesNativeVideo true); only this application\'s own window, no screen-recording permission. '
            'Elsewhere, or when that fails, it is the Flutter content (method flutter_scene, includesNativeVideo false: a picture drawn by a native layer is missing) and the result says why. '
            'Where the system draws the video under the view (iOS) and the player can export its picture, that picture is put under the Flutter content, as the screen layers them (method flutter_scene_over_player_frame, includesNativeVideo true; video says the kernel and position, the frame is the player\'s own export, not a screen read), otherwise videoFailure says why the video is left out. includesVideo says whether any video is in the picture, however it got there (a Flutter texture is in the scene itself). '
            'Default PNG long edge is at most 1280 physical pixels, with aspect ratio preserved and no upscaling; originalSize=true requests full resolution. '
            'No application-name lookup or screen-recording permission is used. '
            'The OS window frame, other windows and external players are never included; '
            'the result always states what is left out. The file is temporary and on the host device.',
        effect: Effect.read,
        input: ObjectSchema({'originalSize': BooleanSchema()}),
        output: ObjectSchema({
          'path': StringSchema(),
          'bytes': IntegerSchema(),
          'mimeType': StringSchema(),
          'width': IntegerSchema(),
          'height': IntegerSchema(),
          'originalWidth': IntegerSchema(),
          'originalHeight': IntegerSchema(),
          'capturedAt': StringSchema(),
          'instance': instanceFactsSchema,
          'surface': StringSchema(),
          'method': StringSchema(),
          'includesNativeVideo': BooleanSchema(),
          'includesVideo': BooleanSchema(),
          'windowCaptureFailure': StringSchema(),
          'video': ObjectSchema({}, additionalProperties: true),
          'videoFailure': StringSchema(),
          'limitations': ArraySchema(StringSchema()),
        }, required: [
          'path',
          'bytes',
          'mimeType',
          'width',
          'height',
          'capturedAt',
          'instance',
          'surface',
          'method',
          'includesNativeVideo',
          'limitations'
        ]),
      );
  @override
  InstanceValue decodeInput(JsonMap input) => InstanceValue(input);
  @override
  Future<Outcome<InstanceValue>> run(
          InstanceValue input, Invocation invocation) async =>
      Completed(InstanceValue(await capture(
          originalSize: input.value['originalSize'] as bool? ?? false)));
}

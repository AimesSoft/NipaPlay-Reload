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

final class ClassicUiCapture {
  const ClassicUiCapture(this.facts);
  final InstanceFacts facts;

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
    final image = await (layer as OffsetLayer)
        .toImage(ui.Offset.zero & physical, pixelRatio: scale);
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
        'surface': 'main_window_flutter_content',
        'method': 'flutter_scene',
        'includesNativeVideo': false,
        if (nativeFailure != null) 'windowCaptureFailure': nativeFailure,
        'limitations': const [
          'Erika native danmaku is not included, as with playback.capture.',
          'Native video overlays and platform views outside the Flutter scene are not included: where a native layer draws the picture, it is missing here.',
          'The OS window frame, other windows and external players are not included.',
        ],
      };
    } finally {
      image.dispose();
    }
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
            'Elsewhere, or when that fails, it is the Flutter content alone (method flutter_scene, includesNativeVideo false: a picture drawn by a native layer is missing) and the result says why. '
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
          'windowCaptureFailure': StringSchema(),
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

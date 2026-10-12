import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' hide Action;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import '../instance_facts.dart';

final class ClassicUiCapture {
  const ClassicUiCapture(this.facts);
  final InstanceFacts facts;

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
    final physical = view.flutterView.physicalSize;
    final scale = originalSize
        ? 1.0
        : math.min(1.0, 1280 / math.max(physical.width, physical.height));
    final image = await (layer as OffsetLayer)
        .toImage(ui.Offset.zero & physical, pixelRatio: scale);
    try {
      final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final directory =
          await Directory('${(await getTemporaryDirectory()).path}/ui-captures')
              .create(recursive: true);
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
        'limitations': const [
          'Erika native danmaku is not included, as with playback.capture.',
          'Native video overlays and platform views outside the Flutter scene are not included.',
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
            'Capture the entire Flutter content of the connected NipaPlay main window, '
            'including pages, controls and dialogs, into a local PNG file readable by the Agent. '
            'Default PNG long edge is at most 1280 physical pixels, with aspect ratio preserved and no upscaling; originalSize=true requests full resolution. '
            'No application-name lookup or screen-recording permission is used. '
            'Erika native danmaku, native video overlays/platform views outside the Flutter scene, '
            'the OS window frame, other windows and external players are omitted; '
            'the result always states these limitations. The file is temporary and on the host device.',
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

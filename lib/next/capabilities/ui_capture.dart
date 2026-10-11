import 'dart:io';
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

  Future<JsonMap> capture() async {
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
    final image = await (layer as OffsetLayer)
        .toImage(ui.Offset.zero & view.flutterView.physicalSize);
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
  UiCaptureCapability(Future<JsonMap> Function() capture)
      : actions = [UiCaptureAction(capture)];
  @override
  final List<Action> actions;
}

final class UiCaptureAction extends Action<InstanceValue, InstanceValue> {
  const UiCaptureAction(this.capture);
  final Future<JsonMap> Function() capture;
  @override
  ActionSpec get spec => const ActionSpec(
        id: 'ui.capture',
        title: 'Capture this NipaPlay main interface',
        description:
            'Capture the entire Flutter content of the connected NipaPlay main window, '
            'including pages, controls and dialogs, into a local PNG file readable by the Agent. '
            'No application-name lookup or screen-recording permission is used. '
            'Erika native danmaku, native video overlays/platform views outside the Flutter scene, '
            'the OS window frame, other windows and external players are omitted; '
            'the result always states these limitations. The file is temporary and on the host device.',
        effect: Effect.read,
        input: ObjectSchema({}),
        output: ObjectSchema({
          'path': StringSchema(),
          'bytes': IntegerSchema(),
          'mimeType': StringSchema(),
          'width': IntegerSchema(),
          'height': IntegerSchema(),
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
      Completed(InstanceValue(await capture()));
}

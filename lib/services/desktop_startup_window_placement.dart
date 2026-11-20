import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// The screen plugin's Dart wrapper assumes a single FlutterView. Startup
/// already has multiple views on macOS, so supply the window's scale explicitly.
Future<Offset> desktopStartupWindowPosition(
  Size windowSize,
  Alignment alignment, {
  required double devicePixelRatio,
}) async {
  const channel = MethodChannel('dev.leanflutter.plugins/screen_retriever');
  final arguments = {'devicePixelRatio': devicePixelRatio};
  final primary = Display.fromJson(Map<String, dynamic>.from(
      (await channel.invokeMapMethod('getPrimaryDisplay', arguments))!));
  final result = (await channel.invokeMapMethod('getAllDisplays', arguments))!;
  final displays = (result['displays'] as List)
      .map((value) => Display.fromJson(Map<String, dynamic>.from(value)));
  final point =
      (await channel.invokeMapMethod('getCursorScreenPoint', arguments))!;
  final cursor =
      Offset((point['dx'] as num).toDouble(), (point['dy'] as num).toDouble());
  final display = displays.firstWhere(
    (display) => Rect.fromLTWH(
      display.visiblePosition!.dx,
      display.visiblePosition!.dy,
      display.size.width,
      display.size.height,
    ).contains(cursor),
    orElse: () => primary,
  );
  final origin = display.visiblePosition ?? Offset.zero;
  final size = display.visibleSize ?? display.size;
  return origin +
      Offset(
        (size.width - windowSize.width) * (alignment.x + 1) / 2,
        (size.height - windowSize.height) * (alignment.y + 1) / 2,
      );
}

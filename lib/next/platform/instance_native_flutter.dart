import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

Future<Map<String, Object?>> readNativeInstanceFacts() async {
  return Platform.isMacOS
      ? (await const MethodChannel('nipaplay/instance')
          .invokeMapMethod<String, Object?>('facts'))!
      : <String, Object?>{
          'executablePath': Platform.resolvedExecutable,
          'appBundlePath': null,
          'windowTitle': Platform.isWindows || Platform.isLinux
              ? await windowManager.getTitle()
              : null,
          'windowId': null,
          'viewId': null,
        };
}

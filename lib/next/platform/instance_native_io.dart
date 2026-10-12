import 'dart:io';

Future<Map<String, Object?>> readNativeInstanceFacts() async => {
      'executablePath': Platform.resolvedExecutable,
      'appBundlePath': null,
      'windowTitle': null,
      'windowId': null,
      'viewId': null,
    };

import 'dart:io';

import 'package:flutter_js/flutter_js.dart';
import 'package:nipaplay/plugins/js_runtime_ohos.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';

class FlutterJsRuntimeAdapter implements PluginJsRuntime {
  FlutterJsRuntimeAdapter()
      : _delegate = Platform.operatingSystem == 'ohos'
            ? HarmonyQuickJsRuntimeAdapter()
            : _FlutterJsDelegate();

  final PluginJsRuntime _delegate;

  @override
  String evaluate(String code) => _delegate.evaluate(code);

  @override
  void dispose() => _delegate.dispose();

  @override
  void setupBridge(String channelName, dynamic Function(dynamic args) fn) =>
      _delegate.setupBridge(channelName, fn);
}

class _FlutterJsDelegate implements PluginJsRuntime {
  _FlutterJsDelegate() : _runtime = getJavascriptRuntime(xhr: false);

  final JavascriptRuntime _runtime;

  @override
  String evaluate(String code) {
    final result = _runtime.evaluate(code);
    if (result.isError) {
      throw StateError(result.stringResult);
    }
    return result.stringResult;
  }

  @override
  void dispose() => _runtime.dispose();

  @override
  void setupBridge(String channelName, dynamic Function(dynamic args) fn) {
    _runtime.setupBridge(channelName, fn);
    // JSC (iOS/macOS) uses a single static native callback pointer that always
    // dispatches to the last runtime. Register under every runtime id so older
    // plugin runtimes continue to receive bridge calls.
    final allMaps = JavascriptRuntime.channelFunctionsRegistered;
    for (final id in allMaps.keys) {
      allMaps[id]![channelName] = fn;
    }
  }
}

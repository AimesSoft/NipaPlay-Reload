import 'package:flutter_js/flutter_js.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';

class FlutterJsRuntimeAdapter implements PluginJsRuntime {
  FlutterJsRuntimeAdapter() : _runtime = getJavascriptRuntime(xhr: false);

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
  void dispose() {
    _runtime.dispose();
  }

  @override
  void setupBridge(String channelName, dynamic Function(dynamic args) fn) {
    _runtime.setupBridge(channelName, fn);
    // JSC (iOS/macOS) uses a single static native callback pointer
    // (_sendMessageDartFunc) that always dispatches to the *last* created
    // runtime's channel map. When multiple plugin runtimes coexist, bridge
    // calls from earlier runtimes are routed to the last runtime's map and
    // silently fail (return null). Work around this by registering the bridge
    // function under every known runtime instance id, so the lookup succeeds
    // regardless of which runtime the static pointer points to.
    final allMaps = JavascriptRuntime.channelFunctionsRegistered;
    for (final id in allMaps.keys) {
      allMaps[id]![channelName] = fn;
    }
  }
}

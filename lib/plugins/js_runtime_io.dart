import 'package:flutter_js/flutter_js.dart';
import 'package:nipaplay/plugins/js_runtime_types.dart';

class FlutterJsRuntimeAdapter implements PluginJsRuntime {
  FlutterJsRuntimeAdapter() : _runtime = getJavascriptRuntime();

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
}

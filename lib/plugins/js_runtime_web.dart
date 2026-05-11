import 'package:nipaplay/plugins/js_runtime_types.dart';

class FlutterJsRuntimeAdapter implements PluginJsRuntime {
  @override
  String evaluate(String code) {
    throw UnsupportedError('JS runtime is not supported on web yet.');
  }

  @override
  void dispose() {}

  @override
  void setupBridge(String channelName, dynamic Function(dynamic args) fn) {
    throw UnsupportedError('JS runtime is not supported on web yet.');
  }
}

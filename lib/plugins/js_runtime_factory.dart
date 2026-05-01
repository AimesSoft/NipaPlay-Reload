import 'package:nipaplay/plugins/js_runtime_types.dart';
import 'package:nipaplay/plugins/js_runtime_web.dart'
    if (dart.library.io) 'package:nipaplay/plugins/js_runtime_io.dart';

PluginJsRuntime createPluginRuntime() => FlutterJsRuntimeAdapter();

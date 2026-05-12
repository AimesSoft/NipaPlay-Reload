abstract class PluginJsRuntime {
  String evaluate(String code);
  void dispose();
  void setupBridge(String channelName, dynamic Function(dynamic args) fn);
}

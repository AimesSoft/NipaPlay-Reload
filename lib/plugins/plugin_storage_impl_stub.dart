import 'package:nipaplay/plugins/plugin_storage.dart';

class _StubPluginStorage implements PluginStorage {
  @override
  Future<String?> getPluginDirectoryPath() async => null;

  @override
  Future<List<PluginStorageScript>> listScripts() async =>
      const <PluginStorageScript>[];

  @override
  Future<String> readTextFile(String filePath) async {
    throw UnsupportedError('External JS plugins are not supported on web.');
  }

  @override
  Future<String> saveScript(String fileName, String content) async {
    throw UnsupportedError('External JS plugins are not supported on web.');
  }
}

PluginStorage createPluginStorage() => _StubPluginStorage();

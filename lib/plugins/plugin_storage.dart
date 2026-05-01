import 'package:nipaplay/plugins/plugin_storage_impl_stub.dart'
    if (dart.library.io) 'package:nipaplay/plugins/plugin_storage_impl_io.dart'
    as impl;

class PluginStorageScript {
  const PluginStorageScript({
    required this.path,
    required this.content,
  });

  final String path;
  final String content;
}

abstract class PluginStorage {
  Future<List<PluginStorageScript>> listScripts();
  Future<String> readTextFile(String filePath);
  Future<String> saveScript(String fileName, String content);
  Future<String?> getPluginDirectoryPath();
}

PluginStorage createPluginStorage() => impl.createPluginStorage();

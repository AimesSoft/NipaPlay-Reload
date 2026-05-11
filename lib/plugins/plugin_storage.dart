import 'dart:convert';
import 'package:nipaplay/plugins/plugin_storage_impl_stub.dart'
    if (dart.library.io) 'package:nipaplay/plugins/plugin_storage_impl_io.dart'
    as impl;
import 'package:nipaplay/plugins/models/plugin_index_entry.dart';

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
  Future<void> deleteScript(String filePath);
  Future<String?> getPluginDirectoryPath();
  Future<Map<String, PluginIndexEntry>> loadPluginIndex();
  Future<void> savePluginIndex(Map<String, PluginIndexEntry> index);
}

PluginStorage createPluginStorage() => impl.createPluginStorage();

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:nipaplay/plugins/plugin_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:nipaplay/plugins/models/plugin_index_entry.dart';

class _IoPluginStorage implements PluginStorage {
  static const String _pluginsDirName = 'plugins';
  static const String _indexFileName = 'plugins_index.json';

  Future<Directory> _ensurePluginDirectory() async {
    final appDir = await StorageService.getAppStorageDirectory();
    final pluginDir = Directory(
      path.join(
        appDir.path,
        _pluginsDirName,
      ),
    );
    if (!await pluginDir.exists()) {
      await pluginDir.create(recursive: true);
    }
    return pluginDir;
  }

  @override
  Future<String?> getPluginDirectoryPath() async {
    final dir = await _ensurePluginDirectory();
    return dir.path;
  }

  @override
  Future<List<PluginStorageScript>> listScripts() async {
    final dir = await _ensurePluginDirectory();
    final entities = await dir.list().toList();
    final scripts = <PluginStorageScript>[];
    for (final entity in entities) {
      if (entity is! File) continue;
      if (!entity.path.toLowerCase().endsWith('.js')) continue;
      final content = await entity.readAsString();
      scripts.add(
        PluginStorageScript(
          path: entity.path,
          content: content,
        ),
      );
    }
    scripts.sort((a, b) => a.path.compareTo(b.path));
    return scripts;
  }

  @override
  Future<String> readTextFile(String filePath) async {
    return File(filePath).readAsString();
  }

  @override
  Future<String> saveScript(String fileName, String content) async {
    final dir = await _ensurePluginDirectory();
    final safeName = _sanitizeFileName(fileName);
    final targetPath = path.join(dir.path, safeName);
    final file = File(targetPath);
    await file.writeAsString(content);
    return file.path;
  }

  @override
  Future<void> deleteScript(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _sanitizeFileName(String input) {
    var name = input.trim();
    if (name.isEmpty) {
      name = 'plugin_${DateTime.now().millisecondsSinceEpoch}.js';
    }
    name = path.basename(name);
    name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    if (!name.toLowerCase().endsWith('.js')) {
      name = '$name.js';
    }
    return name;
  }

  @override
  Future<Map<String, PluginIndexEntry>> loadPluginIndex() async {
    try {
      final dir = await _ensurePluginDirectory();
      final indexFile = File(path.join(dir.path, _indexFileName));
      if (!await indexFile.exists()) {
        return {};
      }
      final jsonString = await indexFile.readAsString();
      final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;
      return jsonMap.map((key, value) {
        return MapEntry(
          key,
          PluginIndexEntry.fromJson(value as Map<String, dynamic>),
        );
      });
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> savePluginIndex(Map<String, PluginIndexEntry> index) async {
    try {
      final dir = await _ensurePluginDirectory();
      final indexFile = File(path.join(dir.path, _indexFileName));
      final jsonMap = index.map((key, value) {
        return MapEntry(key, value.toJson());
      });
      final jsonString = jsonEncode(jsonMap);
      await indexFile.writeAsString(jsonString);
    } catch (_) {
      // 忽略保存错误，不影响主要功能
    }
  }
}

PluginStorage createPluginStorage() => _IoPluginStorage();

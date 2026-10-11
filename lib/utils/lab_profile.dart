import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
// Use the installed plugin interfaces; lab profiles add no dependencies.
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/types.dart';

/// A debug process profile. Never reads or migrates the normal instance's state.
abstract final class LabProfile {
  static final String? name = parseName(
      kIsWeb || !kDebugMode ? null : Platform.environment['NIPAPLAY_PROFILE']);
  static String? _root;
  static bool get active => name != null;
  static String get root => _root!;
  static String location(String child) => p.join(root, child);
  static String title(String title) => active ? '$title · LAB [$name]' : title;

  static String? parseName(String? value) {
    if (value == null) return null;
    if (!RegExp(r'^[a-z0-9][a-z0-9_-]{0,63}$').hasMatch(value)) {
      throw ArgumentError(
          'NIPAPLAY_PROFILE must be 1–64 lowercase ASCII letters, digits, _ or -, starting with a letter or digit.');
    }
    return value;
  }

  static Future<void> initialize() async {
    if (!active) return;
    if (!Platform.isMacOS) {
      throw UnsupportedError('Lab profiles require the macOS write sandbox.');
    }
    final info = await const MethodChannel('security_bookmark')
        .invokeMapMethod<String, Object?>('labProfileInfo');
    if (info?['name'] != name || info?['writeSandbox'] != true) {
      throw StateError('Native lab profile isolation was not installed.');
    }
    _root = info!['root'] as String;
    await File(location('lab-profile.json')).writeAsString(
        jsonEncode({
          'profile': name,
          'endpointFile': location('endpoint.json'),
        }),
        flush: true);
    PathProviderPlatform.instance = LabPaths(root);
    SharedPreferencesStorePlatform.instance =
        LabPreferences(File(location('preferences.json')));
    debugPrint('LAB [$name] root=$root; external files are read-only');
  }
}

final class LabPaths extends PathProviderPlatform {
  LabPaths(this.root);
  final String root;
  Future<String> _directory(String child) async =>
      (await Directory(p.join(root, child)).create(recursive: true)).path;
  @override
  Future<String?> getTemporaryPath() => _directory('temp');
  @override
  Future<String?> getApplicationSupportPath() => _directory('support');
  @override
  Future<String?> getLibraryPath() => _directory('library');
  @override
  Future<String?> getApplicationDocumentsPath() => _directory('documents');
  @override
  Future<String?> getApplicationCachePath() => _directory('cache');
  @override
  Future<String?> getDownloadsPath() => _directory('data/downloads');
}

/// Serial writes preserve simultaneous Classic and Next preference updates.
final class LabPreferences extends SharedPreferencesStorePlatform {
  LabPreferences(this.file);
  final File file;
  Future<void> _pending = Future.value();

  Map<String, Object> _read() => file.existsSync()
      ? Map<String, Object>.from(jsonDecode(file.readAsStringSync()) as Map)
      : {};

  Future<bool> _update(void Function(Map<String, Object>) operation) {
    final result = _pending.then((_) async {
      final values = _read();
      operation(values);
      final staging = File('${file.path}.pending');
      await staging.writeAsString(jsonEncode(values), flush: true);
      await staging.rename(file.path);
      return true;
    });
    _pending = result.then<void>((_) {});
    return result;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _update((values) => values[key] = value);
  @override
  Future<bool> remove(String key) => _update((values) => values.remove(key));
  @override
  Future<bool> clear() => clearWithParameters(
      ClearParameters(filter: PreferencesFilter(prefix: 'flutter.')));
  @override
  Future<bool> clearWithParameters(ClearParameters parameters) =>
      _update((values) => values.removeWhere((key, _) =>
          key.startsWith(parameters.filter.prefix) &&
          (parameters.filter.allowList == null ||
              parameters.filter.allowList!.contains(key))));
  @override
  Future<Map<String, Object>> getAll() => getAllWithParameters(
      GetAllParameters(filter: PreferencesFilter(prefix: 'flutter.')));
  @override
  Future<Map<String, Object>> getAllWithParameters(
      GetAllParameters parameters) async {
    await _pending;
    return _read()
      ..removeWhere((key, _) =>
          !key.startsWith(parameters.filter.prefix) ||
          (parameters.filter.allowList != null &&
              !parameters.filter.allowList!.contains(key)));
  }
}

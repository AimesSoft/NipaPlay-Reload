import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/services/full_backup_service.dart';

/// Persisted configuration for the incremental multi-device sync repository.
///
/// The legacy local-folder keys are intentionally retained so an existing
/// installation can still be disabled or inspected without losing settings.
class AutoSyncSettings {
  static const String _enabledKey = 'auto_sync_enabled';
  static const String _legacyPathKey = 'auto_sync_path';
  static const String _serverUrlKey = 'incremental_sync_webdav_url';
  static const String _usernameKey = 'incremental_sync_webdav_username';
  static const String _passwordKey = 'incremental_sync_webdav_password';
  static const String _remotePathKey = 'incremental_sync_remote_path';
  static const String _intervalMinutesKey = 'incremental_sync_interval_minutes';
  static const String _categoriesKey = 'incremental_sync_categories';
  static const String _deviceIdKey = 'incremental_sync_device_id';
  static const String _lastSyncAtKey = 'incremental_sync_last_sync_at';
  static const String _lastSyncErrorKey = 'incremental_sync_last_error';

  static const int defaultIntervalMinutes = 30;
  static const String defaultRemotePath = '/NipaPlay/sync';

  static SharedPreferences? _prefs;

  static Future<void> _ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static Future<bool> isEnabled() async {
    await _ensureInitialized();
    return _prefs!.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool enabled) async {
    await _ensureInitialized();
    await _prefs!.setBool(_enabledKey, enabled);
    debugPrint('增量同步已${enabled ? "启用" : "禁用"}');
  }

  /// Legacy local-folder setting. Kept for migration/UI compatibility only.
  static Future<String?> getSyncPath() async {
    await _ensureInitialized();
    return _prefs!.getString(_legacyPathKey);
  }

  static Future<void> setSyncPath(String? path) async {
    await _ensureInitialized();
    if (path == null || path.trim().isEmpty) {
      await _prefs!.remove(_legacyPathKey);
    } else {
      await _prefs!.setString(_legacyPathKey, path.trim());
    }
  }

  static Future<String?> getSyncFilePath() async {
    final syncPath = await getSyncPath();
    return syncPath == null ? null : '$syncPath/nipaplay_auto_sync.nph';
  }

  static Future<String> getServerUrl() async {
    await _ensureInitialized();
    return _prefs!.getString(_serverUrlKey) ?? '';
  }

  static Future<String> getUsername() async {
    await _ensureInitialized();
    return _prefs!.getString(_usernameKey) ?? '';
  }

  static Future<String> getPassword() async {
    await _ensureInitialized();
    return _prefs!.getString(_passwordKey) ?? '';
  }

  static Future<String> getRemotePath() async {
    await _ensureInitialized();
    return _normalizeRemotePath(
      _prefs!.getString(_remotePathKey) ?? defaultRemotePath,
    );
  }

  static Future<int> getIntervalMinutes() async {
    await _ensureInitialized();
    final value = _prefs!.getInt(_intervalMinutesKey) ?? defaultIntervalMinutes;
    return value < 5 ? defaultIntervalMinutes : value;
  }

  static Future<Set<BackupCategory>> getCategories() async {
    await _ensureInitialized();
    final raw = _prefs!.getString(_categoriesKey);
    if (raw == null || raw.isEmpty) return BackupCategory.values.toSet();
    try {
      final names = (jsonDecode(raw) as List<dynamic>).cast<String>().toSet();
      final result = BackupCategory.values
          .where((category) => names.contains(category.name))
          .toSet();
      return result.isEmpty ? BackupCategory.values.toSet() : result;
    } catch (_) {
      return BackupCategory.values.toSet();
    }
  }

  static Future<void> saveWebDavConfiguration({
    required String serverUrl,
    required String username,
    required String password,
    required String remotePath,
    required int intervalMinutes,
    required Set<BackupCategory> categories,
  }) async {
    await _ensureInitialized();
    await Future.wait([
      _prefs!.setString(_serverUrlKey, serverUrl.trim()),
      _prefs!.setString(_usernameKey, username.trim()),
      _prefs!.setString(_passwordKey, password),
      _prefs!.setString(_remotePathKey, _normalizeRemotePath(remotePath)),
      _prefs!.setInt(
        _intervalMinutesKey,
        intervalMinutes < 5 ? defaultIntervalMinutes : intervalMinutes,
      ),
      _prefs!.setString(
        _categoriesKey,
        jsonEncode(categories.map((category) => category.name).toList()),
      ),
    ]);
  }

  static Future<bool> hasWebDavConfiguration() async {
    return (await getServerUrl()).trim().isNotEmpty;
  }

  static Future<String> getOrCreateDeviceId() async {
    await _ensureInitialized();
    final existing = _prefs!.getString(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final salt = Object().hashCode.abs().toRadixString(36);
    final created = '$now-$salt';
    await _prefs!.setString(_deviceIdKey, created);
    return created;
  }

  static Future<DateTime?> getLastSyncAt() async {
    await _ensureInitialized();
    return DateTime.tryParse(_prefs!.getString(_lastSyncAtKey) ?? '');
  }

  static Future<String?> getLastSyncError() async {
    await _ensureInitialized();
    return _prefs!.getString(_lastSyncErrorKey);
  }

  static Future<void> recordSyncSuccess(DateTime at) async {
    await _ensureInitialized();
    await Future.wait([
      _prefs!.setString(_lastSyncAtKey, at.toIso8601String()),
      _prefs!.remove(_lastSyncErrorKey),
    ]);
  }

  static Future<void> recordSyncError(Object error) async {
    await _ensureInitialized();
    await _prefs!.setString(_lastSyncErrorKey, error.toString());
  }

  static String _normalizeRemotePath(String value) {
    var normalized = value.trim().replaceAll('\\', '/');
    if (normalized.isEmpty) normalized = defaultRemotePath;
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
}

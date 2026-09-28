import 'dart:io';

import 'package:flutter/services.dart';

class HarmonyMediaImportResult {
  const HarmonyMediaImportResult({
    required this.directory,
    required this.importedCount,
    required this.failedCount,
  });

  final String directory;
  final int importedCount;
  final int failedCount;
}

/// Companion operations implemented by the bundled file_selector_ohos plugin.
class HarmonyLocalMediaService {
  static Future<Object?> _call(String method,
      [List<Object?> args = const []]) async {
    final channel = BasicMessageChannel<Object?>(
      'dev.flutter.pigeon.FileSelectorApi.$method',
      const StandardMessageCodec(),
    );
    final response = await channel.send(args) as List<Object?>?;
    if (response == null || response.isEmpty) {
      throw PlatformException(code: 'channel-error', message: '鸿蒙媒体导入服务未连接。');
    }
    if (response.length > 1) {
      throw PlatformException(
        code: response[0]! as String,
        message: response[1] as String?,
        details: response[2],
      );
    }
    return response.single;
  }

  static bool canOfferImport(PlatformException error) => const {
        'directory-selection-unsupported',
        'directory-permission-unavailable',
        'directory-access-denied',
      }.contains(error.code);

  /// Called before the media library and playback services start accessing files.
  /// Returns revoked/unavailable grants without discarding the saved records.
  static Future<List<String>> restoreDirectoryPermissions() async {
    final result = await _call('restoreDirectoryPermissions') as List<Object?>;
    return result.cast<String>();
  }

  static Future<void> ensureDirectoryAccess(String path) async {
    await _call('ensureDirectoryAccess', [path]);
  }

  /// Media sources need only read permission; download/storage pickers retain
  /// the normal file_selector path with a read/write grant.
  static Future<String?> pickMediaDirectory() async {
    return await _call('pickMediaDirectory') as String?;
  }

  static Future<HarmonyMediaImportResult?> importMediaFiles() async {
    final value = await _call('importMediaFiles');
    if (value == null) return null;
    final result = value as Map<Object?, Object?>;
    return HarmonyMediaImportResult(
      directory: result['directory']! as String,
      importedCount: result['importedCount']! as int,
      failedCount: result['failedCount']! as int,
    );
  }

  /// A media source needs read access, not the write access of an app data folder.
  /// This also rejects a raw Picker URI before it can reach Dart/Rust file I/O.
  static Future<bool> canReadDirectory(String path) async {
    if (!path.startsWith('/')) return false;
    try {
      await Directory(path).list(followLinks: false).take(1).drain<void>();
      return true;
    } on FileSystemException {
      return false;
    }
  }
}

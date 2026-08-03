import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';

const String nipaPlayFullBackupUti = 'com.nipaplay.backup.npb';
const String nipaPlayHistoryBackupUti = 'com.nipaplay.backup.nph';

/// Builds a backup type group that is valid on every file_selector backend.
/// iOS ignores extension-only groups and requires at least one UTI.
XTypeGroup buildBackupFileTypeGroup({
  required String label,
  required String extension,
  TargetPlatform? platform,
}) {
  final normalizedExtension = extension.replaceFirst(RegExp(r'^\.'), '');
  final targetPlatform = platform ?? defaultTargetPlatform;
  final String? iosUti = switch (normalizedExtension.toLowerCase()) {
    'npb' => nipaPlayFullBackupUti,
    'nph' => nipaPlayHistoryBackupUti,
    _ => null,
  };

  return XTypeGroup(
    label: label,
    extensions: [normalizedExtension],
    uniformTypeIdentifiers:
        targetPlatform == TargetPlatform.iOS && iosUti != null
            ? [iosUti]
            : null,
  );
}

bool hasBackupFileExtension(String path, String expectedExtension) {
  final normalizedExtension =
      expectedExtension.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
  return path.toLowerCase().endsWith('.$normalizedExtension');
}

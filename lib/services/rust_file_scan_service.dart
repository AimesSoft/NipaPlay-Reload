import 'package:flutter/foundation.dart';
import 'package:nipaplay/src/rust/api/file_scan.dart' as rust;
import 'package:nipaplay/src/rust/rust_init.dart';

class RustFileScanResult {
  const RustFileScanResult({
    required this.currentCount,
    required this.cachedCount,
    required this.currentFiles,
    required this.newFiles,
    required this.modifiedFiles,
    required this.deletedFiles,
    required this.folderHash,
    required this.currentHashes,
  });

  final int currentCount;
  final int cachedCount;
  final List<String> currentFiles;
  final List<String> newFiles;
  final List<String> modifiedFiles;
  final List<String> deletedFiles;
  final String folderHash;
  final Map<String, String> currentHashes;
}

class RustFileScanService {
  const RustFileScanService._();

  static Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      await ensureRustInitialized();
      return rust.isRustFileScanAvailable();
    } catch (error) {
      debugPrint('RustFileScanService: Rust scan unavailable: $error');
      return false;
    }
  }

  static Future<RustFileScanResult> calculateDiff({
    required String folderPath,
    required Map<String, String> cachedHashes,
  }) async {
    await ensureRustInitialized();
    final diff = await rust.diffVideoFiles(
      folderPath: folderPath,
      cachedHashes: cachedHashes.entries
          .map(
            (entry) => rust.RustFileHashEntry(
              relativePath: entry.key,
              hash: entry.value,
            ),
          )
          .toList(growable: false),
    );

    return RustFileScanResult(
      currentCount: diff.currentCount,
      cachedCount: diff.cachedCount,
      currentFiles: List<String>.from(diff.currentFiles),
      newFiles: List<String>.from(diff.newFiles),
      modifiedFiles: List<String>.from(diff.modifiedFiles),
      deletedFiles: List<String>.from(diff.deletedFiles),
      folderHash: diff.folderHash,
      currentHashes: {
        for (final entry in diff.currentHashes) entry.relativePath: entry.hash,
      },
    );
  }
}

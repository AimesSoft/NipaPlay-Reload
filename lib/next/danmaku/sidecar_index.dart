import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/utils/local_danmaku_match.dart';

import 'sidecar.dart';
import 'store.dart';

/// Reconciles the sidecar pointers for the complete local catalogue. This runs
/// in the library worker: directory walks, candidate ranking, sidecar parsing
/// and comparisons never execute in the UI isolate.
Future<JsonMap> reconcileSidecarIndex({
  required DanmakuStore store,
  required Database db,
  required List<JsonMap> locations,
}) async {
  var changed = 0, failed = 0;
  String? lastRun, lastError;
  for (final row in locations) {
    try {
      final id = row['file_id'] as String;
      final path = row['locator'] as String;
      if (await _inspect(store, id, path)) changed++;
      lastRun = store.now;
      lastError = null;
    } catch (error) {
      failed++;
      lastError = error.runtimeType.toString();
    }
  }
  return {
    'scanned': locations.length,
    'changed': changed,
    'failed': failed,
    'lastRun': lastRun,
    'error': lastError,
  };
}

Future<bool> _inspect(DanmakuStore store, String id, String path) async {
  final bindings = await store.bindings(id);
  final previous = bindings.where((b) => b['local_file'] != null).firstOrNull;
  final old = previous?['local_file'] as JsonMap?;
  final candidates = await localDanmakuCandidates(path);
  final revision = (await store.identities.entity(id))['revision'];
  for (final candidate in candidates) {
    if (bindings.any((b) =>
        b['status'] == 'accepted' &&
        b['entity_revision'] == revision &&
        b['local_file'] == null &&
        b['cache_key'] != null &&
        (b['provenance'] as JsonMap?)?['filePath'] == candidate)) {
      return false;
    }
    final stat = await File(candidate).stat();
    if (old?['path'] == candidate &&
        old?['available'] == true &&
        old?['size'] == stat.size &&
        old?['modifiedAt'] == stat.modified.toUtc().toIso8601String() &&
        previous?['entity_revision'] == revision) {
      return false;
    }
    try {
      final facts = await readSidecarFactsHere(candidate);
      await store.recordSidecar(id, facts);
      return true;
    } on FormatException catch (error) {
      if (old?['path'] == candidate) {
        await store.recordSidecar(id, {
          ...old!,
          'available': false,
          'checkedAt': store.now,
          'error': error.message.toString()
        });
        return true;
      }
    } on FileSystemException catch (error) {
      if (old?['path'] == candidate) {
        await store.recordSidecar(id, {
          ...old!,
          'available': false,
          'checkedAt': store.now,
          'error': error.message
        });
        return true;
      }
    }
  }
  if (old != null && old['available'] == true) {
    await store.recordSidecar(id, {
      ...old,
      'available': false,
      'checkedAt': store.now,
      'error': 'No readable matching file'
    });
    return true;
  }
  return false;
}

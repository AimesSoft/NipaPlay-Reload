import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:nipaplay/services/intro_skip/skip_segment.dart';

import '../../media/file_identity_merge.dart';
import '../../media/identity_store.dart';

/// Nipa's skip segments, remembered per file so that the same episode opened
/// again has them. Reads and writes are small and run off the UI isolate (the
/// database's own).
final class SkipSegmentStore {
  SkipSegmentStore(this._identities);
  final IdentityStore Function() _identities;

  Future<String> _fileId(String path) async {
    final identities = _identities();
    final id = await identities.ensureFile(path);
    return canonicalFileId(identities.database, id);
  }

  /// What was set for the file opened from [path], as segments of the `agent`
  /// source.
  Future<List<SkipSegment>> read(String path) async {
    final id = await _fileId(path);
    return _segments(await _identities().database
        .query('file_skip_segments', where: 'file_id = ?', whereArgs: [id]));
  }

  /// Sets or, with [range] null, clears the [kind] of the file; returns every
  /// segment the file has afterwards.
  Future<List<SkipSegment>> write(String path, SkipSegmentKind kind,
      {({int startMs, int endMs})? range, String? invocationId}) async {
    final identities = _identities();
    final id = await _fileId(path);
    final db = identities.database;
    if (range == null) {
      await db.delete('file_skip_segments',
          where: 'file_id = ? AND kind = ?', whereArgs: [id, kind.name]);
    } else {
      await db.insert(
          'file_skip_segments',
          {
            'file_id': id,
            'kind': kind.name,
            'start_ms': range.startMs,
            'end_ms': range.endMs,
            'set_at': DateTime.now().toUtc().toIso8601String(),
            'invocation_id': invocationId,
          },
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    return _segments(await db
        .query('file_skip_segments', where: 'file_id = ?', whereArgs: [id]));
  }

  static List<SkipSegment> _segments(List<Map<String, Object?>> rows) => [
        for (final row in rows)
          SkipSegment(
              kind: SkipSegmentKind.values.byName(row['kind'] as String),
              source: SkipSegmentSource.agent,
              startSeconds: (row['start_ms'] as int) / 1000,
              endSeconds: (row['end_ms'] as int) / 1000)
      ];
}

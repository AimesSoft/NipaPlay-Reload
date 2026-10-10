import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> migrateMediaPrimitives(DatabaseExecutor db) async {
  // Binding evidence is independent of the retired workflow tables.
  await db.execute('DROP TABLE media_candidates');
  await db.execute('DROP TABLE media_identifications');
  await db.execute(
      'ALTER TABLE media_scan_items DROP COLUMN identification_job_id');
  await db.execute('CREATE TABLE media_binding_operations ('
      'id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL, result TEXT NOT NULL)');
  final rows = await db.query('jobs',
      where: 'type IN (?,?)',
      whereArgs: ['media.identify', 'media.apply_release']);
  for (final row in rows) {
    final old = Job.fromJson(Map<String, Object?>.from(
        jsonDecode(row['snapshot'] as String) as Map));
    if (old.state.isTerminal) continue;
    final now = DateTime.now().toUtc();
    final next = Job.fromJson({
      ...old.toStorageJson(),
      'state': 'failed',
      'phase': 'retired',
      'revision': old.revision + 1,
      'updatedAt': now.toIso8601String(),
      'decision': null,
      'retryAt': null,
      'receipt': JobReceipt(
          verification: VerificationLevel.acknowledged,
          details: {
            'reason': 'workflow_retired',
            'bindingsPreserved': true
          }).toJson(),
      'error': const Failure(FailureCode.unavailable,
              'Identification workflow retired; explicit media primitives are available. Existing bindings are preserved.')
          .toJson()
    });
    await db.update(
        'jobs',
        {
          'state': next.state.wireName,
          'revision': next.revision,
          'snapshot': jsonEncode(next.toStorageJson())
        },
        where: 'job_id=?',
        whereArgs: [old.jobId]);
    await db.insert('job_events', {
      'job_id': next.jobId,
      'revision': next.revision,
      'kind': 'workflow_retired',
      'at': now.toIso8601String(),
      'snapshot': jsonEncode(next.toJson())
    });
  }
}

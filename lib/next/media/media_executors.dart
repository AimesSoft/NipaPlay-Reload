import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_service.dart';
import 'metadata_provider.dart';

List<JobExecutor> mediaExecutors(MediaService service) => [
      _ScanExecutor(service),
      _RefreshExecutor(service),
      _ProjectionExecutor(service)
    ];

const _videoExtensions = {
  '.mkv',
  '.mp4',
  '.avi',
  '.mov',
  '.m4v',
  '.ts',
  '.webm',
  '.wmv',
  '.flv'
};

final class _ProjectionExecutor implements JobExecutor {
  const _ProjectionExecutor(this.service);
  final MediaService service;
  @override
  String get type => 'media.project';
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);
  Future<void> _run(JobContext context) async {
    final control = _Control(context);
    final fileId = context.job.input['fileId'] as String;
    if (await control.stop({'fileId': fileId, 'projectionVerified': false})) {
      return;
    }
    await context.running(phase: 'project');
    await service.mutate(() => service.projection.drain(fileId: fileId));
    if (await control.stop({'fileId': fileId, 'projectionVerified': false})) {
      return;
    }
    await context.markSideEffectCommitted();
    await context.report(phase: 'verify');
    if ((await service.store.pendingProjections(fileId: fileId)).isNotEmpty) {
      throw const Failure(
          FailureCode.unavailable, 'Projection remains pending.');
    }
    await context.succeed(JobReceipt(
        verification: VerificationLevel.verified,
        details: {'fileId': fileId, 'projectionVerified': true}));
  }
}

final class _Control {
  _Control(this.context) {
    stopped = context.job.cancelRequestedAt != null;
    context.stopRequested.then((_) => stopped = true);
  }
  final JobContext context;
  bool stopped = false;
  Future<bool> stop(JsonMap details) async {
    if (!stopped) return false;
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      await context.cancelled(JobReceipt(
          verification: VerificationLevel.acknowledged, details: details));
    }
    return true;
  }
}

final class _ScanExecutor implements JobExecutor {
  const _ScanExecutor(this.service);
  final MediaService service;
  @override
  String get type => 'media.scan';
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);
  Future<void> _run(JobContext context) async {
    final control = _Control(context);
    if (await control.stop({'reason': 'scan_stopped'})) return;
    await context.running(phase: 'enumerate');
    final root = await service
        .authorizedPath(context.job.input['root'] as String, directory: true);
    final db = service.store.database;
    var discovered = (await db.query('media_scan_items',
        where: 'job_id = ?', whereArgs: [context.job.jobId])).length;
    if (context.job.checkpoint['enumerated'] != true) {
      await for (final entry
          in Directory(root).list(recursive: true, followLinks: false)) {
        if (await control
            .stop({'discovered': discovered, 'indexed': discovered})) {
          return;
        }
        if (!await FileSystemEntity.isFile(entry.path) ||
            !_videoExtensions.contains(p.extension(entry.path).toLowerCase())) {
          continue;
        }
        final recorded = await db.rawQuery('''SELECT 1 FROM media_scan_items i
          JOIN media_locations l ON l.file_id=i.file_id
          WHERE i.job_id=? AND l.locator=? LIMIT 1''', [context.job.jobId, entry.path]);
        if (recorded.isNotEmpty) continue;
        final fileId = await service.index(entry.path);
        if (await control
            .stop({'discovered': discovered, 'indexed': discovered})) {
          return;
        }
        final file = await service.store.entity(fileId);
        await db.insert(
            'media_scan_items',
            {
              'job_id': context.job.jobId,
              'file_id': fileId,
              'file_revision': file['revision']
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
        discovered++;
        await context.markSideEffectCommitted();
        await context.report(
            progress: JobProgress(completed: discovered, unit: 'files'));
      }
      await context.report(checkpoint: {'enumerated': true});
    }
    final items = await db.query('media_scan_items',
        where: 'job_id = ?', whereArgs: [context.job.jobId]);
    await context
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'indexed': items.length,
      'fileIds': [for (final row in items) row['file_id']]
    }));
  }
}

final class _RefreshExecutor implements JobExecutor {
  const _RefreshExecutor(this.service);
  final MediaService service;
  @override
  String get type => 'media.metadata.refresh';
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);
  Future<void> _run(JobContext context) async {
    final control = _Control(context);
    if (await control.stop({'refreshed': false})) return;
    await context.running(phase: 'fetch');
    final ref = ExternalRef.fromJson(
        Map<String, Object?>.from(context.job.input['ref'] as Map));
    final String id;
    if (context.job.checkpoint['snapshotId'] != null) {
      id = context.job.checkpoint['snapshotId'] as String;
    } else {
      final MetadataRecord record;
      try {
        record = await service
            .provider(ref.provider)
            .get(ref, language: context.job.input['language'] as String);
      } on ProviderRetry catch (error) {
        if (await control.stop({'refreshed': false})) return;
        final retries = (context.job.checkpoint['retries'] as int?) ?? 0;
        if (retries >= 3) {
          throw Failure(FailureCode.unavailable,
              '${error.provider} retry budget exhausted: ${error.reason}');
        }
        await context.retryAt(
            error.at,
            Failure(
                FailureCode.unavailable, '${error.provider}: ${error.reason}',
                retryable: true),
            checkpoint: {'retries': retries + 1});
        return;
      }
      if (await control.stop({'refreshed': false})) return;
      id = await service.store.saveSnapshot(record);
      await context.markSideEffectCommitted(checkpoint: {'snapshotId': id});
    }
    await context.report(phase: 'verify');
    final rows = await service.store.database
        .query('media_snapshots', where: 'id = ?', whereArgs: [id]);
    if (rows.length != 1) {
      throw const Failure(
          FailureCode.conflict, 'Metadata snapshot readback failed.');
    }
    await context
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'snapshotId': id,
      'refreshed': true,
      'identityChanged': false,
      'userOverridesPreserved': true
    }));
  }
}

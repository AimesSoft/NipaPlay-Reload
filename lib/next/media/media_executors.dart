import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_service.dart';
import 'identity_store.dart' show decodeMediaJson, stableMediaId;
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
            where: 'job_id = ?', whereArgs: [context.job.jobId]))
        .length;
    // A directory that cannot be listed (on Windows one deeper than 259
    // characters, without the system's long path setting) is left out and
    // reported; the rest of the folder is still scanned.
    final unreadable = <String>[];
    var unreadableCount = 0;
    String? unreadableReason;
    if (context.job.checkpoint['enumerated'] != true) {
      await for (final entry in Directory(root)
          .list(recursive: true, followLinks: false)
          .handleError((Object error) {
        error as FileSystemException;
        unreadableCount++;
        if (unreadable.length < 5 && error.path != null) {
          unreadable.add(error.path!);
        }
        unreadableReason ??=
            'os error ${error.osError?.errorCode}: ${error.osError?.message ?? error.message}';
      }, test: (error) => error is FileSystemException)) {
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
          WHERE i.job_id=? AND l.locator=? LIMIT 1''',
            [context.job.jobId, entry.path]);
        if (recorded.isNotEmpty) continue;
        await context
            .report(phase: 'probe', details: {'currentPath': entry.path});
        // Race only read-only work. A cancelled/timed-out probe must never
        // resume later and write an index behind the task engine's back.
        final info = await Future.any<JsonMap?>([
          service.probe(entry.path, stopRequested: context.stopRequested),
          context.stopRequested.then((_) => null),
        ]).timeout(const Duration(seconds: 30), onTimeout: () {
          throw Failure(FailureCode.unavailable,
              'File probe timed out after 30 seconds: ${entry.path}',
              details: {'stage': 'probe', 'path': entry.path});
        });
        if (await control
            .stop({'discovered': discovered, 'indexed': discovered})) {
          return;
        }
        if (info == null) return;
        final path = await service.authorizedPath(entry.path);
        await context.report(phase: 'index');
        final fileId = await service.mutate(() async {
          // Cancellation can also arrive while waiting for the mutation queue.
          if (control.stopped) return null;
          final id =
              await service.store.registerFile(path, info, via: 'local_scan');
          await service.projection.drain(fileId: id);
          return id;
        });
        if (await control
            .stop({'discovered': discovered, 'indexed': discovered})) {
          return;
        }
        if (fileId == null) return;
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
      'fileIds': [for (final row in items) row['file_id']],
      if (unreadableCount > 0)
        'unreadableDirectories': {
          'count': unreadableCount,
          'examples': unreadable,
          'reason': unreadableReason,
        },
    }));
  }
}

final class _RefreshExecutor implements JobExecutor, JobReconciler {
  const _RefreshExecutor(this.service);
  final MediaService service;
  @override
  String get type => 'media.metadata.refresh';
  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) async {
    JobReceipt? receipt;
    try {
      receipt = await _storedResult(context.job);
    } on Failure catch (error) {
      if (error.code != FailureCode.conflict) rethrow;
    }
    if (receipt == null) return _run(context);
    await context.markSideEffectCommitted(
        checkpoint: {'snapshotId': receipt.details['snapshotId']});
    if (context.job.cancelRequestedAt != null) {
      await context.cancelled(receipt);
    } else {
      await context.succeed(receipt);
    }
  }

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
        final fetched = await Future.any<MetadataRecord?>([
          service
              .provider(ref.provider)
              .get(ref, language: context.job.input['language'] as String),
          context.stopRequested.then((_) => null),
        ]).timeout(const Duration(seconds: 60), onTimeout: () {
          throw const Failure(FailureCode.unavailable,
              'Metadata fetch timed out before persistence.');
        });
        if (await control.stop({'refreshed': false})) return;
        if (fetched == null) return;
        record = fetched;
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
      await context.report(phase: 'persist');
      id = await service.store.saveSnapshot(record,
          onCommitted: (snapshotId) async {
        await context
            .markSideEffectCommitted(checkpoint: {'snapshotId': snapshotId});
        await context.report(phase: 'notify');
      }, onNotificationError: (error) async {
        await context.report(details: {
          ...context.job.details,
          'notificationStatus': 'unconfirmed',
          'notificationError': error is TimeoutException
              ? 'notification_timeout'
              : 'notification_failed',
          'metadataCommitted': true,
        });
      });
    }
    await context.report(phase: 'verify');
    await context.succeed(await _verify(context.job, id));
  }

  @override
  Future<JobReceipt> reconcile(Job job) async {
    if (service.engine.isActive(job.jobId) &&
        !{'notify', 'verify'}.contains(job.phase)) {
      throw const Failure(FailureCode.conflict,
          'Executor may still fetch or persist data; it cannot be detached safely.');
    }
    return _storedResult(job);
  }

  Future<JobReceipt> _storedResult(Job job) async {
    final known = job.checkpoint['snapshotId'] as String?;
    if (known != null) return _verify(job, known, reconciled: true);
    // Older jobs did not checkpoint until notification delivery returned.
    // Verify the requested result (ref, language, time, detail acquisition),
    // without claiming which invocation produced a matching snapshot.
    final rows = await service.store.database.query('media_snapshots',
        columns: ['id'],
        where: 'object_id=? AND language=? AND fetched_at>=? '
            r"AND json_extract(fields, '$.acquisition.kind')='detail'",
        whereArgs: [
          stableMediaId('object', job.input['ref'] as Map),
          job.input['language'],
          job.createdAt.toUtc().toIso8601String()
        ],
        orderBy: 'fetched_at DESC',
        limit: 1);
    if (rows.isEmpty) {
      throw const Failure(FailureCode.conflict,
          'No persisted detail snapshot satisfies this refresh; task left unchanged.');
    }
    return _verify(job, rows.single['id'] as String, reconciled: true);
  }

  Future<JobReceipt> _verify(Job job, String id,
      {bool reconciled = false}) async {
    final rows = await service.store.database
        .query('media_snapshots', where: 'id = ?', whereArgs: [id]);
    if (rows.length != 1) {
      throw const Failure(
          FailureCode.conflict, 'Metadata snapshot readback failed.');
    }
    final row = rows.single;
    final fields = decodeMediaJson(row['fields']);
    final fetchedAt = DateTime.tryParse(row['fetched_at'] as String);
    if (stableMediaId('object', fields['ref'] as Map) !=
            stableMediaId('object', job.input['ref'] as Map) ||
        row['language'] != job.input['language'] ||
        fetchedAt == null ||
        fetchedAt.isBefore(job.createdAt)) {
      throw const Failure(
          FailureCode.conflict, 'Snapshot does not satisfy this refresh.');
    }
    return JobReceipt(verification: VerificationLevel.verified, details: {
      'snapshotId': id,
      'refreshed': true,
      'ref': job.input['ref'],
      'acquisition': fields['acquisition'],
      'childrenRefreshed': false,
      'identityChanged': false,
      'userOverridesPreserved': true,
      if (job.details['notificationStatus'] != null)
        'notificationStatus': job.details['notificationStatus'],
      if (reconciled) ...{
        'reconciledFromStoredSnapshot': true,
        'originalExecutionCompletionProven': false,
        'notificationStatus': 'unconfirmed',
        'operationReexecuted': false,
      },
    });
  }
}

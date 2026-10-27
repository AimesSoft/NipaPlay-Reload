import 'dart:async';
import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'source.dart';
import 'service.dart';
import 'alignment.dart';
import '../media/identity_store.dart';

List<JobExecutor> danmakuExecutors(DanmakuService service) =>
    [_Fetch(service), _Align(service)];

final class _Control {
  _Control(this.context) {
    if (context.job.cancelRequestedAt != null) cancellation.cancel();
    context.stopRequested.then((_) => cancellation.cancel());
  }
  final JobContext context;
  final cancellation = DanmakuCancellation();
  Future<void> Function()? verifyCommitted;
  Future<bool> stop(JsonMap details) async {
    if (!cancellation.cancelled) return false;
    final current = await context.snapshot();
    if (current.cancelRequestedAt != null) {
      if (current.sideEffectCommitted) {
        await verifyCommitted!();
        await context.fail(
            const Failure(FailureCode.unavailable,
                'Stopped after committed effects; partial result verified.'),
            JobReceipt(
                verification: VerificationLevel.verified,
                details: {...details, 'stopped': true, 'partial': true}));
      } else {
        await context.cancelled(JobReceipt(
            verification: VerificationLevel.acknowledged, details: details));
      }
    }
    return true;
  }
}

final class _Fetch implements JobExecutor {
  _Fetch(this.service);
  final DanmakuService service;
  final Map<String, Future<void>> _tails = {};
  @override
  String get type => 'danmaku.fetch';
  @override
  Future<void> execute(JobContext c) => run(c);
  @override
  Future<void> recover(JobContext c) => run(c);
  Future<void> run(JobContext c) async {
    final control = _Control(c);
    final video = DanmakuVideo.fromJson(
        Map<String, Object?>.from(c.job.input['video'] as Map));
    final source = service.source(video.sourceId);
    final plan = source.planFetch(
        video, c.job.input['startMs'] as int, c.job.input['endMs'] as int);
    final cacheKey = service.store.cacheKey(video, source,
        refreshJobId: c.job.input['refresh'] == true ? c.job.jobId : null);
    final completed = <int>{};
    final localDuration = c.job.input['localDurationMs'] as int?;
    final requiredPlan = localDuration == null
        ? plan
        : plan.where((chunk) => chunk.startMs < localDuration).toList();
    if (c.job.cancelRequestedAt != null) {
      for (final chunk in plan) {
        if (await service.store.chunk(cacheKey, chunk, fresh: false) != null) {
          completed.add(chunk.index);
        }
      }
    }
    control.verifyCommitted = () async {
      for (final index in completed) {
        if (await service.store.chunk(
                cacheKey, plan.singleWhere((chunk) => chunk.index == index),
                fresh: false) ==
            null) {
          throw const Failure(FailureCode.conflict,
              'Committed cache disappeared before cancellation verification.');
        }
      }
    };
    final missing = <JsonMap>[];
    JsonMap details({String status = 'partial', bool loaded = false}) => {
          'sourceId': video.sourceId,
          'videoId': video.videoId,
          'cacheKey': cacheKey,
          'status': status,
          'complete': source.validate(plan, completed),
          'localRangeComplete': source.validate(requiredPlan,
              completed.intersection(requiredPlan.map((c) => c.index).toSet())),
          'localDurationMs': localDuration,
          'outOfRangeFailures': [
            for (final failure in missing)
              if (failure['outsideLocalRange'] == true) failure
          ],
          'loaded': loaded,
          'requestedRange': {
            'startMs': c.job.input['startMs'],
            'endMs': c.job.input['endMs']
          },
          'coverageMeaning':
              source.describe.aggregation ? 'relatedPool' : 'currentPool',
          'historyComplete': false,
          'completedChunks': completed.toList()..sort(),
          'missingChunks': [
            for (final chunk in plan)
              if (!completed.contains(chunk.index)) chunk.toJson()
          ],
          'failures': missing,
          'alignmentVerified': false,
          'verificationMeaning':
              'Response structure, requested pool coverage and cache readback; platform completeness and semantic matching remain unverified.'
        };
    final previous = _tails[video.sourceId] ?? Future<void>.value();
    final done = Completer<void>();
    _tails[video.sourceId] = previous.then((_) => done.future);
    await Future.any([previous, control.cancellation.stopped]);
    try {
      if (await control.stop(details())) return;
      await c.running(phase: 'fetch');
      final bindingId = c.job.input['bindingId'] as String?;
      final binding = bindingId == null ? null : await service.store.binding(bindingId);
      final expectedEntityId = c.job.input['bindingEntityId'] as String? ?? binding?['entity_id'] as String?;
      final expectedEntityRevision = c.job.input['bindingEntityRevision'] as int? ?? binding?['entity_revision'] as int?;
      if (binding != null && (binding['entity_id'] != expectedEntityId || binding['entity_revision'] != expectedEntityRevision)) {
        throw const Failure(FailureCode.conflict, 'Danmaku target changed after this acquisition was requested.');
      }
      final cacheRevision = bindingId == null
          ? null
          : binding!['cache_revision'] as int;
      var acquiredCount = 0;
      for (final chunk in plan) {
        if (await control.stop(details())) return;
        var result =
            c.job.input['refresh'] == true && !completed.contains(chunk.index)
                ? null
                : await service.store.chunk(cacheKey, chunk);
        if (result == null) {
          try {
            result =
                await source.fetchChunk(video, chunk, control.cancellation);
          } on SourceFailure catch (error) {
            if (localDuration == null ||
                chunk.startMs < localDuration ||
                error.status == SourceStatus.cancelled) {
              rethrow;
            }
            missing.add({
              ...chunk.toJson(),
              'status': error.status.name,
              if (error.diagnostics != null) 'diagnostics': error.diagnostics,
              'outsideLocalRange': true
            });
            continue;
          }
          if (acquiredCount + result.entries.length > 100000) {
            throw const SourceFailure(SourceStatus.schemaChanged);
          }
          if (await control.stop(details())) return;
          await service.store.saveChunk(cacheKey, chunk, result);
          completed.add(chunk.index);
          await c.markSideEffectCommitted(checkpoint: {
            'cacheKey': cacheKey,
            'completedChunks': completed.toList()
          });
        } else {
          completed.add(chunk.index);
        }
        acquiredCount += result.entries.length;
        if (acquiredCount > 100000) {
          throw const SourceFailure(SourceStatus.schemaChanged);
        }
        await c.report(
            progress: JobProgress(
                completed: completed.length,
                total: plan.length,
                unit: 'chunks'),
            checkpoint: {
              'cacheKey': cacheKey,
              'completedChunks': completed.toList()
            });
      }
      if (await control.stop(details())) return;
      await c.report(phase: 'verify');
      var rawCount = 0;
      for (final chunk
          in plan.where((chunk) => completed.contains(chunk.index))) {
        final cached = await service.store.chunk(cacheKey, chunk, fresh: false);
        if (cached == null) {
          throw const Failure(
              FailureCode.conflict, 'Requested cache coverage disappeared.');
        }
        rawCount += cached.entries.length;
      }
      if (!source.validate(requiredPlan,
          completed.intersection(requiredPlan.map((c) => c.index).toSet()))) {
        throw const Failure(FailureCode.conflict, 'Incomplete chunk plan.');
      }
      var loaded = false;
      if (bindingId != null) {
        if (await control.stop(details())) return;
        await service.store.assignCache(bindingId, cacheKey, c.job.jobId,
            expectedCacheRevision: cacheRevision,
            expectedEntityId: expectedEntityId,
            expectedEntityRevision: expectedEntityRevision);
        await c.markSideEffectCommitted();
        await service.refreshCurrent(
            replaceBindingId:
                c.job.input['refresh'] == true ? bindingId : null);
        loaded = service.player.loaded(bindingId)?['cacheKey'] == cacheKey;
      }
      final count = (await service.store.entries(cacheKey)).length;
      await c.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
        ...details(
            status: missing.isNotEmpty
                ? 'localRangeComplete'
                : rawCount == 0
                    ? 'validEmpty'
                    : 'complete',
            loaded: loaded),
        'partial': missing.isNotEmpty,
        'rawCount': rawCount,
        'cachedUniqueCount': count,
        'bindingId': bindingId
      }));
    } on SourceFailure catch (error) {
      if (await control.stop(details())) return;
      for (final chunk in plan) {
        if (await service.store.chunk(cacheKey, chunk, fresh: false) != null) {
          completed.add(chunk.index);
        }
      }
      missing.add({
        'status': error.status.name,
        if (error.diagnostics != null) 'diagnostics': error.diagnostics
      });
      final retries = c.job.checkpoint['retries'] as int? ?? 0;
      if ((error.status == SourceStatus.rateLimited ||
              error.status == SourceStatus.transportFailed) &&
          retries < 3) {
        await c.retryAt(
            error.retryAt ??
                DateTime.now().toUtc().add(Duration(seconds: 2 << retries)),
            Failure(
                FailureCode.unavailable, '${video.sourceId}: ${error.message}',
                retryable: true),
            checkpoint: {
              'retries': retries + 1,
              'cacheKey': cacheKey,
              'completedChunks': completed.toList()
            });
      } else {
        final available = await service.availability(
            video, cacheKey, c.job.input['bindingId'] as String?);
        await c.fail(
            Failure(
                FailureCode.unavailable, '${video.sourceId}: ${error.message}'),
            JobReceipt(verification: VerificationLevel.acknowledged, details: {
              ...details(
                  status: error.status.name,
                  loaded: (available['player'] as JsonMap)['loaded'] == true),
              'bindingId': c.job.input['bindingId'],
              'acquisitionSucceeded': false,
              'available': available
            }));
      }
    } on Failure catch (error) {
      if (await control.stop(details())) return;
      final available = await service.availability(
          video, cacheKey, c.job.input['bindingId'] as String?);
      await c.fail(
          error,
          JobReceipt(verification: VerificationLevel.acknowledged, details: {
            ...details(
                loaded: (available['player'] as JsonMap)['loaded'] == true),
            'bindingId': c.job.input['bindingId'],
            'acquisitionSucceeded': false,
            'available': available
          }));
    } finally {
      done.complete();
    }
  }
}

final class _Align implements JobExecutor {
  const _Align(this.service);
  final DanmakuService service;
  @override
  String get type => 'danmaku.align';
  @override
  Future<void> execute(JobContext c) => run(c);
  @override
  Future<void> recover(JobContext c) => run(c);
  Future<void> run(JobContext c) async {
    final control = _Control(c), id = c.job.input['bindingId'] as String;
    control.verifyCommitted = () async {
      final saved = await service.store.db.query('danmaku_alignment_candidates',
          where: 'job_id = ?', whereArgs: [c.job.jobId]);
      if (saved.length != 1) {
        throw const Failure(
            FailureCode.conflict, 'Committed alignment candidate disappeared.');
      }
    };
    if (await control.stop({'bindingId': id, 'applied': false})) return;
    await c.running(phase: 'estimate');
    final db = service.store.db;
    final rows = await db.query('danmaku_alignment_candidates',
        where: 'job_id = ?', whereArgs: [c.job.jobId]);
    final choice = c.job.checkpoint['choice'];
    if (choice != null) {
      final row = rows.single;
      if (row['state'] == 'proposed') {
        if (choice == 'apply') {
          final proposal = decodeMediaJson(row['payload']);
          await db.transaction((tx) async {
            final b = await service.store.binding(id, tx: tx);
            if (b['revision'] != row['binding_revision']) {
              throw const Failure(FailureCode.conflict,
                  'Binding changed during alignment decision.');
            }
            final revision = (b['revision'] as int) + 1;
            await tx.update(
                'danmaku_bindings',
                {
                  'offset_ms': proposal['offsetMs'],
                  'revision': revision,
                  'alignment': jsonEncode({
                    ...proposal,
                    'confirmed': true,
                    'confirmedBy': c.job.checkpoint['boundBy']
                  }),
                  'invocation_id': c.job.checkpoint['invocationId']
                },
                where: 'id = ?',
                whereArgs: [id]);
            await tx.insert('danmaku_binding_events', {
              'id': stableMediaId('danmaku-event', [id, revision]),
              'binding_id': id,
              'revision': revision,
              'invocation_id': c.job.checkpoint['invocationId'],
              'payload':
                  jsonEncode({'alignment': proposal, 'jobId': c.job.jobId}),
              'created_at': service.store.now
            });
            await tx.update(
                'danmaku_alignment_candidates', {'state': 'applied'},
                where: 'job_id = ?', whereArgs: [c.job.jobId]);
          });
        } else {
          await db.update('danmaku_alignment_candidates', {'state': 'kept'},
              where: 'job_id = ?', whereArgs: [c.job.jobId]);
        }
        await c.markSideEffectCommitted();
      }
      if (choice == 'apply') await service.refreshCurrent();
      final readback = (await db.query('danmaku_alignment_candidates',
              where: 'job_id = ?', whereArgs: [c.job.jobId]))
          .single;
      await c.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
        'bindingId': id,
        'applied': readback['state'] == 'applied',
        'proposal': decodeMediaJson(readback['payload']),
        'verificationMeaning':
            'Recorded anchor estimate and explicit choice read back; no automatic semantic validation.'
      }));
      return;
    }
    final b = await service.store.binding(id);
    if (b['revision'] != c.job.input['bindingRevision']) {
      throw const Failure(
          FailureCode.conflict, 'Binding changed before alignment.');
    }
    if (rows.isEmpty) {
      final anchors = [
        for (final a in c.job.input['anchors'] as List)
          Map<String, Object?>.from(a as Map)
      ];
      final analysis = analyzeDanmakuAnchors(anchors);
      final proposal = {
        'method': 'manualAnchors',
        'offsetMs': analysis['estimateOffsetMs'],
        'anchors': anchors,
        'maxResidualMs': analysis['maxResidualMs'],
        'confidence': analysis['confidence'],
        'confirmed': false,
        'applicableRange': 'requested media version',
        'autoApply': false
      };
      if (await control.stop({'bindingId': id, 'applied': false})) return;
      await db.insert(
          'danmaku_alignment_candidates',
          {
            'job_id': c.job.jobId,
            'binding_id': id,
            'binding_revision': b['revision'],
            'payload': jsonEncode(proposal),
            'state': 'proposed'
          },
          conflictAlgorithm: ConflictAlgorithm.ignore);
      await c.markSideEffectCommitted();
    }
    final proposal = decodeMediaJson((await db.query(
            'danmaku_alignment_candidates',
            where: 'job_id = ?',
            whereArgs: [c.job.jobId]))
        .single['payload']);
    if (await control.stop({'bindingId': id, 'applied': false})) return;
    await c
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'bindingId': id,
      'observedRevision': b['revision'],
      'applied': false,
      'proposal': proposal,
      'analysis': analyzeDanmakuAnchors([
        for (final a in proposal['anchors'] as List)
          Map<String, Object?>.from(a as Map)
      ]),
      'migration': 'danmaku.analyze_alignment + danmaku.update',
      'verificationMeaning':
          'Stored anchor estimate read back; binding unchanged. Set any explicit offsetMs with danmaku.update and expectedRevision.'
    }));
  }
}

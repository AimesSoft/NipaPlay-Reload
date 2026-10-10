import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'identity_store.dart';
import 'media_service.dart';
import 'metadata_provider.dart';

List<JobExecutor> mediaExecutors(MediaService service) => [
      _ScanExecutor(service),
      _IdentificationExecutor(service),
      _RefreshExecutor(service),
      _ProjectionExecutor(service)
    ];

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
  Future<bool> retired() async =>
      stopped && (await context.snapshot()).cancelRequestedAt == null;
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
    var discovered = 0;
    if (context.job.checkpoint['enumerated'] != true) {
      await for (final entry
          in Directory(root).list(recursive: true, followLinks: false)) {
        if (await control.stop({
          'discovered': discovered,
          'identification': 'separate_child_jobs'
        })) {
          return;
        }
        if (entry is! File ||
            !{
              '.mkv',
              '.mp4',
              '.avi',
              '.mov',
              '.m4v',
              '.ts',
              '.webm',
              '.wmv',
              '.flv'
            }.contains(p.extension(entry.path).toLowerCase())) {
          continue;
        }
        final fileId = await service.index(entry.path);
        if (await control.stop({
          'discovered': discovered,
          'identification': 'separate_child_jobs'
        })) {
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
    await context.report(phase: 'schedule');
    final items = await db.query('media_scan_items',
        where: 'job_id = ?', whereArgs: [context.job.jobId]);
    final jobs = <String>[];
    for (final item in items) {
      if (await control
          .stop({'discovered': items.length, 'scheduled': jobs.length})) {
        return;
      }
      final existing = item['identification_job_id'] as String?;
      final id = existing ??
          (await service.identify(item['file_id'] as String,
                  sources:
                      (context.job.input['sources'] as List?)?.cast<String>(),
                  expectedRevision: item['file_revision'] as int))
              .jobId;
      await db.update('media_scan_items', {'identification_job_id': id},
          where: 'job_id = ? AND file_id = ?',
          whereArgs: [context.job.jobId, item['file_id']]);
      jobs.add(id);
    }
    await context.report(
        phase: 'verify',
        progress: JobProgress(
            completed: items.length, total: items.length, unit: 'files'));
    final readback = await db.query('media_scan_items',
        where: 'job_id = ?', whereArgs: [context.job.jobId]);
    if (readback.length != items.length ||
        readback.any((row) => row['identification_job_id'] == null)) {
      throw const Failure(
          FailureCode.conflict, 'Scan scheduling readback failed.');
    }
    for (final id in jobs) {
      await service.engine.get(id);
    }
    await context
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'discovered': items.length,
      'scheduled': jobs.length,
      'identificationJobIds': jobs,
      'enumerationVerified': true,
      'identificationComplete': false
    }));
  }
}

final class _IdentificationExecutor implements JobExecutor {
  _IdentificationExecutor(this.service);
  final MediaService service;
  final _slots = _IdentificationSlots(4);
  @override
  String get type => 'media.identify';
  @override
  Future<void> execute(JobContext context) => _limited(context);
  @override
  Future<void> recover(JobContext context) => _limited(context);
  Future<void> _limited(JobContext context) async {
    final control = _Control(context);
    final saved = await service.store.database.query('media_identifications',
        columns: ['state'],
        where: 'job_id = ?',
        whereArgs: [context.job.jobId]);
    if (context.job.checkpoint['choice'] == 'bind' &&
        saved.isNotEmpty &&
        saved.single['state'] == 'accepted') {
      await _run(context);
      return;
    }
    final entered = await _slots.enter(context.stopRequested);
    if (!entered) {
      await control
          .stop({'fileId': context.job.input['fileId'], 'identified': false});
      return;
    }
    try {
      if (await control
          .stop({'fileId': context.job.input['fileId'], 'identified': false})) {
        return;
      }
      await _run(context);
    } finally {
      _slots.leave();
    }
  }

  Future<void> _run(JobContext context) async {
    final control = _Control(context);
    final jobId = context.job.jobId;
    final fileId = context.job.input['fileId'] as String;
    final choice = context.job.checkpoint['choice'] as String?;
    final saved = await service.store.database.query('media_identifications',
        where: 'job_id = ?', whereArgs: [jobId]);
    final committedChoice = choice == 'bind' &&
        saved.isNotEmpty &&
        saved.single['state'] == 'accepted';
    if (!committedChoice &&
        await control.stop({'fileId': fileId, 'identified': false})) {
      return;
    }
    if (context.job.state == JobState.cancelling) {
      await context.report(phase: 'verify');
    } else {
      await context.running(phase: 'probe');
    }
    if (choice == 'skip' || choice == 'defer') {
      await service.store.checkContext(jobId);
      await service.store.setIdentificationState(
          jobId, choice == 'skip' ? 'skipped' : 'deferred');
      await context.markSideEffectCommitted();
      await context.succeed(
          JobReceipt(verification: VerificationLevel.verified, details: {
        'fileId': fileId,
        'identified': false,
        'disposition': choice,
        'readBack': (await service.store.identification(jobId))['state']
      }));
      return;
    }
    if (choice == 'bind') {
      final actor = context.job.checkpoint['boundBy'] as String;
      await service.accept(
          jobId,
          context.job.checkpoint['candidateId'] as String,
          actor,
          Invocation(
              origin: actor == 'user'
                  ? 'gui'
                  : actor == 'automatic'
                      ? 'task_engine'
                      : 'mcp',
              id: context.job.checkpoint['invocationId'] as String),
          committed: () async {
        await context.markSideEffectCommitted();
      });
      if (await control.retired()) return;
      await _verify(context, fileId);
      return;
    }
    await service.validateFile(fileId);
    if (await control.stop({'fileId': fileId, 'identified': false})) return;
    final file = await service.store.entity(fileId);
    if (file['revision'] != context.job.input['fileRevision']) {
      throw const Failure(
          FailureCode.conflict, 'File revision changed before identification.');
    }
    final links = await service.store.database.query('media_file_episodes',
        where: 'file_id = ?', whereArgs: [fileId]);
    final location = (await service.store.locations(fileId))
        .firstWhere((row) => row['source'] == 'local');
    final signals = service.parser.parse(location['locator'] as String);
    await service.store.beginIdentification(jobId, fileId, {
      'signals': signals.toJson(),
      'probe': (file['attributes'] as JsonMap)['probe'],
      'attempts': <JsonMap>[]
    });
    await service.store.checkContext(jobId);
    if (links.isNotEmpty) {
      await service.mutate(() => service.projection.drain(fileId: fileId));
      await service.store.setIdentificationState(jobId, 'accepted');
      await service.store.updateIdentificationContext(jobId, {
        'signals': signals.toJson(),
        'probe': (file['attributes'] as JsonMap)['probe'],
        'attempts': [
          {
            'provider': 'local',
            'status': 'reused',
            'detail': 'Accepted identity for unchanged content read back.'
          }
        ]
      });
      if (await control.retired()) return;
      await _verify(context, fileId);
      return;
    }
    if (choice == 'reconsider') {
      await _decide(context);
      return;
    }
    final sources = (context.job.input['sources'] as List).cast<String>();
    var completed = (context.job.checkpoint['sourceIndex'] as int?) ?? 0;
    final attempts = List<JsonMap>.from(((await service.store
        .identification(jobId))['context'] as JsonMap)['attempts'] as List);
    final releaseId = context.job.input['releaseId'] as String?;
    if (releaseId != null) {
      try {
        final payload = await service.releaseCandidate(releaseId, signals);
        if (await control.stop({'fileId': fileId, 'identified': false})) return;
        final candidate = await service.store
            .addCandidate(jobId, payload, 'accepted_release');
        final release = payload['release'] as Map;
        final automatic = signals.number != null &&
            signals.endNumber == null &&
            signals.cour == null &&
            (signals.season == null || signals.season == release['season']);
        if (automatic) {
          await context.report(checkpoint: {
            'choice': 'bind',
            'candidateId': candidate,
            'boundBy': 'automatic',
            'invocationId': '$jobId:auto'
          });
          await service.accept(jobId, candidate, 'automatic',
              Invocation(origin: 'task_engine', id: '$jobId:auto'),
              committed: () async {
            await context.markSideEffectCommitted();
          });
          if (await control.retired()) return;
          await _verify(context, fileId);
          return;
        }
      } on Failure catch (error) {
        if (context.job.checkpoint['choice'] == 'bind') rethrow;
        if (error.code != FailureCode.notFound &&
            error.code != FailureCode.conflict) {
          rethrow;
        }
        attempts.add({
          'provider': 'local_release',
          'status': error.code.wireName,
          'detail': error.message
        });
      }
    }
    for (var i = completed; i < sources.length; i++) {
      final provider = service.provider(sources[i]);
      await context.report(phase: 'match:${provider.id}');
      try {
        if (provider is HashMetadataProvider) {
          final probe = (file['attributes'] as JsonMap)['probe'] as JsonMap;
          final matched = await provider.matchHash(
              signals.raw, probe['headMd5'] as String, probe['size'] as int);
          if (await control.stop({'fileId': fileId, 'identified': false})) {
            return;
          }
          final legacy = await service.store.database.rawQuery(
              'SELECT h.payload FROM media_legacy_history h JOIN media_locations l ON l.id=h.location_id WHERE l.file_id = ?',
              [fileId]);
          for (final work in matched) {
            if (work.episodes.length != 1) {
              throw const Failure(FailureCode.unavailable,
                  'Hash response must identify exactly one episode per match.');
            }
            final legacyConflict = legacy
                .map((row) => decodeMediaJson(row['payload']))
                .any((row) =>
                    row['animeId'] != null &&
                    row['episodeId'] != null &&
                    (row['animeName'] as String).isNotEmpty &&
                    (row['animeId'].toString() != work.ref.externalId ||
                        row['episodeId'].toString() !=
                            work.episodes.single.ref.externalId));
            final numberConflict = signals.number != null &&
                work.episodes.single.number != null &&
                double.tryParse(signals.number!) !=
                    double.tryParse(work.episodes.single.number!);
            final payload = {
              'work': work.toJson(),
              'release': work.toJson(),
              'episodes': [work.episodes.single.toJson()],
              'workId': null,
              'relation': 'exact',
              'scope': {
                'order': 'provider',
                'season': null,
                'cour': null,
                'numbers': [work.episodes.single.number],
                'startMs': null,
                'endMs': null
              },
              'evidence': {
                'reason': legacyConflict
                    ? 'hashOnly result conflicts with unconfirmed legacy matching fields.'
                    : numberConflict
                        ? 'hashOnly result conflicts with filename numbering.'
                        : 'hashOnly response for this content revision.',
                'url': null
              }
            };
            final candidate =
                await service.store.addCandidate(jobId, payload, 'hashOnly');
            if (matched.length != 1 ||
                signals.endNumber != null ||
                legacyConflict ||
                numberConflict) {
              continue;
            }
            // Durable automatic choice precedes its transaction and Classic delivery.
            await context.report(checkpoint: {
              'choice': 'bind',
              'candidateId': candidate,
              'boundBy': 'automatic',
              'invocationId': '$jobId:auto'
            });
            await service.accept(jobId, candidate, 'automatic',
                Invocation(origin: 'task_engine', id: '$jobId:auto'),
                committed: () async {
              await context.markSideEffectCommitted();
            });
            if (await control.retired()) return;
            await _verify(context, fileId);
            return;
          }
        }
        final results =
            await provider.search(signals.title, year: signals.year);
        if (provider.id == 'tmdb' && signals.number == null) {
          results.addAll(await provider.search(signals.title,
              kind: 'movie', year: signals.year));
        }
        for (final result in results) {
          if (await control.stop({'fileId': fileId, 'identified': false})) {
            return;
          }
          try {
            final payload = await service.candidate(result, signals);
            if (await control.stop({'fileId': fileId, 'identified': false})) {
              return;
            }
            await service.store.addCandidate(jobId, payload, 'filename');
          } on Failure catch (error) {
            if (error.code != FailureCode.notFound &&
                error.code != FailureCode.conflict) {
              rethrow;
            }
            attempts.add({
              'provider': provider.id,
              'status': error.code.wireName,
              'detail': error.message
            });
          }
        }
        attempts.add({
          'provider': provider.id,
          'status': 'searched',
          'detail':
              '${results.length} work candidates; filename results require confirmation.'
        });
      } on ProviderRetry catch (error) {
        if (await control.stop({'fileId': fileId, 'identified': false})) return;
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
            checkpoint: {'sourceIndex': i, 'retries': retries + 1});
        return;
      } on Failure catch (error) {
        if (context.job.checkpoint['choice'] == 'bind') rethrow;
        if (error.code != FailureCode.unavailable &&
            error.code != FailureCode.notFound) {
          rethrow;
        }
        attempts.add({
          'provider': provider.id,
          'status': error.code.wireName,
          'detail': error.message
        });
      }
      if (await control.stop({'fileId': fileId, 'identified': false})) return;
      completed = i + 1;
      await service.store.updateIdentificationContext(jobId, {
        'signals': signals.toJson(),
        'probe': (file['attributes'] as JsonMap)['probe'],
        'attempts': attempts
      });
      await context
          .report(checkpoint: {'sourceIndex': completed, 'retries': 0});
    }
    await _decide(context);
  }

  Future<void> _decide(JobContext context) async {
    final candidates = await service.store.candidates(context.job.jobId);
    final revision = context.job.revision + 1;
    JsonMap input({String? candidateId}) => {
          'jobId': context.job.jobId,
          'revision': revision,
          if (candidateId != null) 'candidateId': candidateId
        };
    await context.needsDecision(
        Decision(
            prompt: candidates.isEmpty
                ? 'No acceptable identity was found. Read the context and add verified catalogue evidence, defer, or skip.'
                : 'Filename candidates need confirmation of work, release and episode order. Read evidence before choosing.',
            options: [
              for (final candidate
                  in candidates.where((row) => row['state'] == 'proposed'))
                DecisionOption(
                    label:
                        '${((candidate['payload'] as JsonMap)['work'] as Map)['title']} · ${((candidate['payload'] as JsonMap)['release'] as Map)['title']}',
                    detail: ((candidate['payload'] as JsonMap)['evidence']
                        as Map)['reason'] as String,
                    call: ActionCall('media.identity.bind',
                        input(candidateId: candidate['id'] as String))),
              DecisionOption(
                  label: 'Reconsider added evidence',
                  call: ActionCall('media.identification.reconsider', input())),
              DecisionOption(
                  label: 'Skip this identification',
                  call: ActionCall('media.identification.skip', input())),
              DecisionOption(
                  label: 'Defer until more evidence is available',
                  call: ActionCall('media.identification.defer', input())),
            ]),
        checkpoint: {
          'sourceIndex': context.job.checkpoint['sourceIndex'] ?? 0
        });
  }

  Future<void> _verify(JobContext context, String fileId) async {
    await context.report(phase: 'verify');
    final file = await service.store.entity(fileId);
    if (file['revision'] != context.job.input['fileRevision']) {
      throw const Failure(
          FailureCode.conflict, 'File revision changed before verification.');
    }
    final links = await service.store.database.query('media_file_episodes',
        where: 'file_id = ?', whereArgs: [fileId]);
    final bindings = await service.store.database.query('media_bindings',
        where: 'entity_id = ? AND status = ?', whereArgs: [fileId, 'accepted']);
    final pending = await service.store.pendingProjections(fileId: fileId);
    if (links.isEmpty || bindings.isEmpty || pending.isNotEmpty) {
      throw const Failure(FailureCode.conflict,
          'Identity or Classic projection readback failed.');
    }
    await context
        .succeed(JobReceipt(verification: VerificationLevel.verified, details: {
      'fileId': fileId,
      'fileRevision': file['revision'],
      'bindingRevision': (file['attributes'] as JsonMap)['bindingRevision'],
      'identified': true,
      'episodeIds': [for (final link in links) link['episode_id']],
      'bindingIds': [for (final binding in bindings) binding['id']],
      'classicProjectionPending': 0,
      'verificationMeaning':
          'Persisted identity and required Classic projection read back; semantic correctness remains the recorded choice.'
    }));
  }
}

final class _IdentificationSlots {
  _IdentificationSlots(this._available);
  int _available;
  final _waiting = Queue<Completer<bool>>();
  Future<bool> enter(Future<void> stopped) async {
    if (_available > 0) {
      _available--;
      return true;
    }
    final ready = Completer<bool>();
    _waiting.add(ready);
    stopped.then((_) {
      if (_waiting.remove(ready)) ready.complete(false);
    });
    return ready.future;
  }

  void leave() {
    if (_waiting.isEmpty) {
      _available++;
    } else {
      _waiting.removeFirst().complete(true);
    }
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

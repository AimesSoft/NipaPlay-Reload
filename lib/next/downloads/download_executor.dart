import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

import 'download_backend.dart';
import 'download_paths.dart';
import 'file_bindings.dart';

final class DownloadExecutor implements JobExecutor {
  DownloadExecutor(
      {required this.backends,
      required this.library,
      required this.isEnabled,
      this.pollInterval = const Duration(seconds: 5),
      this.importRetryDelay = const Duration(minutes: 1),
      this.stallAfter = const Duration(minutes: 5)});
  final DownloadBackends backends;
  final DownloadLibrary library;
  final Future<bool> Function() isEnabled;
  final Duration pollInterval, importRetryDelay;

  /// How long a download goes without a new byte before that is a fact
  /// worth telling whoever started it.
  final Duration stallAfter;
  late TaskEngine engine;
  final Map<String, Completer<void>> _workers = {};
  @override
  String get type => 'download';

  Future<void> quiesce(String jobId) async {
    await _workers[jobId]?.future;
  }

  final Map<String, Future<void>> _locks = {};

  /// Runs [operation] alone among everything that rewrites this job's
  /// `completedFiles` rows: the worker's per-file stage and the declarations
  /// of `download.declare_files`. Each reads the rows when it gets the turn.
  Future<T> exclusive<T>(String jobId, Future<T> Function() operation) async {
    final previous = _locks[jobId] ?? Future<void>.value();
    final done = Completer<void>();
    final tail = _locks[jobId] = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
      if (identical(_locks[jobId], tail)) _locks.remove(jobId);
    }
  }

  @override
  Future<void> execute(JobContext context) => _run(context);
  @override
  Future<void> recover(JobContext context) => _run(context);

  Future<void> _run(JobContext context) async {
    final done = Completer<void>();
    _workers[context.job.jobId] = done;
    var stopped = false;
    unawaited(context.stopRequested.then((_) => stopped = true));
    DownloadSnapshot? task;
    final files = <JsonMap>[];
    try {
      final ref = DownloadBackendRef.fromJson(
          context.job.details['backend'] as JsonMap);
      if (!await isEnabled() && context.job.cancelRequestedAt == null) {
        await context.retryAt(
            DateTime.now().toUtc().add(pollInterval),
            const Failure(FailureCode.unavailable, 'Downloader is disabled.',
                retryable: true));
        return;
      }
      final backend = backends.resolve(ref);
      await backend.initialize();
      final request = DownloadRequest.fromJson(context.job.input);
      final matches = (await backend.list())
          .where((task) => task.infoHash == request.infoHash);
      if (matches.isNotEmpty) task = await backend.read(matches.single.handle);
      if (task == null) {
        if (context.job.cancelRequestedAt != null) {
          if (context.job.sideEffectCommitted) {
            await context.cancelled(
                JobReceipt(verification: VerificationLevel.verified, details: {
              'files': await _readRemovedFiles(backend, context.job),
              'reason': 'removed',
              'sessionPresent': false
            }));
          } else {
            await context.cancelled(JobReceipt(
                verification: VerificationLevel.unverified,
                details: {'files': [], 'reason': 'cancelled_before_add'}));
          }
          return;
        }
        if (context.job.sideEffectCommitted ||
            context.job.input['adopted'] == true) {
          await context.fail(
              const Failure(FailureCode.notFound,
                  'Download is absent from its backend session.'),
              JobReceipt(
                  verification: VerificationLevel.unverified,
                  details: {'files': [], 'reason': 'session_missing'}));
          return;
        }
        if (stopped) return;
        task = await backend.add(request, stopRequested: context.stopRequested);
      }
      // A crash between native add and this checkpoint is reconciled by hash.
      if (!stopped || context.job.cancelRequestedAt != null) {
        final snapshot = task;
        await exclusive(
            context.job.jobId,
            () => context.markSideEffectCommitted(checkpointPatch: {
                  'completedFiles': context.job.checkpoint['completedFiles'] ??
                      context.job.input['completedFiles'] ??
                      [],
                  'infoHash': snapshot.infoHash,
                  'handle': snapshot.handle,
                  'output': snapshot.output.path,
                  'files': [
                    for (final file in snapshot.files)
                      {
                        'path': file.location.path,
                        'expectedSize': file.expectedSize,
                        'local': file.location.isLocal,
                        'included': file.included,
                      }
                  ],
                }));
      }
      while (true) {
        if (stopped) {
          if (context.job.cancelRequestedAt == null) {
            // Pause retires this context. Native operations must also stop.
            if (context.job.state == JobState.paused) {
              await backend.pause(task!.handle);
            }
            return;
          }
          await _finishCancelled(context, backend, task!, files,
              reason: task.finished
                  ? 'cancelled_before_import'
                  : 'cancelled_incomplete');
          return;
        }
        task = await backend.read(task!.handle);
        if (task.error != null && task.error!.isNotEmpty) {
          if (context.job.state == JobState.interrupted) {
            await context.running();
          }
          await context.retryAt(DateTime.now().toUtc().add(importRetryDelay),
              Failure(FailureCode.unavailable, task.error!, retryable: true));
          return;
        }
        if (task.paused && !task.finished && !stopped) {
          await engine.pause(context.job.jobId);
          return;
        }
        if (context.job.state == JobState.interrupted) await context.running();
        await _completedFiles(context, backend, task);
        if (stopped) continue;
        if (task.finished) break;
        await _noteStall(context, task);
        await context.report(
            phase: 'downloading',
            progress: JobProgress(
                completed: task.completed,
                total: task.total > 0 ? task.total : null,
                unit: 'bytes'));
        await Future.any(
            [Future<void>.delayed(pollInterval), context.stopRequested]);
      }
      await context.report(
          phase: 'verifying',
          progress: JobProgress(
              completed: 0, total: task.files.length, unit: 'files'));
      final valid = await _verify(backend, task, files, requireComplete: true);
      if (stopped && context.job.cancelRequestedAt == null) return;
      if (context.job.cancelRequestedAt != null) {
        await _finishCancelled(context, backend, task, files,
            reason: 'cancelled_before_import');
        return;
      }
      await context.report(
          progress: JobProgress(
              completed: files.length, total: files.length, unit: 'files'));
      if (!valid) {
        const error = Failure(FailureCode.conflict,
            'Completed download files are missing or have incorrect sizes.',
            retryable: true);
        await context.retryAt(
            DateTime.now().toUtc().add(importRetryDelay), error,
            checkpointPatch: {'files': files});
        return;
      }
      final key = task.importKey;
      final autoImport = await library.enabled;
      final alreadyImported = await library.wasImported(key);
      final localVideos = task.files
          .where((f) => f.included && f.isVideo && f.location.isLocal)
          .toList();
      for (final file in files) {
        final match =
            task.files.singleWhere((f) => f.location.path == file['path']);
        final media = match.included && match.location.isLocal && match.isVideo
            ? await library.lookup(match.location.path)
            : null;
        file['imported'] = media != null;
        if (media != null) file['media'] = media;
        if (media == null) {
          file['reason'] = !match.included
              ? 'not_selected'
              : !match.isVideo
                  ? 'not_video'
                  : !match.location.isLocal
                      ? 'requires_transfer'
                      : alreadyImported
                          ? 'previous_import_record_missing'
                          : !autoImport
                              ? 'auto_import_disabled'
                              : 'not_identified';
        }
        if (media == null &&
            match.included &&
            match.isVideo &&
            match.location.isLocal) {
          file['identificationPending'] = true;
        } else if (media?['identificationPending'] == true) {
          file['identificationPending'] = true;
          file['reason'] = 'not_identified';
        }
      }
      if (stopped && context.job.cancelRequestedAt == null) return;
      if (autoImport && localVideos.isNotEmpty && !alreadyImported) {
        if (context.job.cancelRequestedAt != null) {
          await _finishCancelled(context, backend, task, files,
              reason: 'cancelled_before_import');
          return;
        }
        await context.report(
            phase: 'importing',
            progress: JobProgress(
                completed: 0, total: localVideos.length, unit: 'files'));
        final pending = <DownloadFile>[];
        for (final f in localVideos) {
          final index = task.files.indexOf(f);
          if (!await library.wasImported('${task.importKey}:file:$index') &&
              (files.singleWhere((row) => row['path'] == f.location.path)[
                          'imported'] !=
                      true ||
                  (files.singleWhere(
                              (row) => row['path'] == f.location.path)['media']
                          as Map?)?['classicScanPending'] ==
                      true)) {
            pending.add(f);
          }
        }
        if (pending.isNotEmpty) {
          if (context.job.cancelRequestedAt != null) {
            await _finishCancelled(context, backend, task, files,
                reason: 'cancelled_before_import');
            return;
          }
          if (library.isBusy) {
            await context.retryAt(
                DateTime.now().toUtc().add(pollInterval),
                const Failure(FailureCode.unavailable, 'Media scanner is busy.',
                    retryable: true));
            return;
          }
          await library.importFiles(
              pending.map((f) => f.location.path).toList(), task.output.path);
          for (final file in files) {
            if (localVideos
                .any((video) => video.location.path == file['path'])) {
              final media = await library.lookup(file['path'] as String);
              file['imported'] = media != null;
              if (media != null) {
                file['media'] = media;
                if (media['identificationPending'] == true) {
                  file['identificationPending'] = true;
                  file['reason'] = 'not_identified';
                } else {
                  file.remove('reason');
                  file.remove('identificationPending');
                }
              }
            }
          }
        }
        if (stopped && context.job.cancelRequestedAt == null) return;
        final imported = files.where((row) => row['imported'] == true).length;
        await context.report(
            progress: JobProgress(
                completed: imported, total: localVideos.length, unit: 'files'));
        if (context.job.cancelRequestedAt == null) {
          await library.markImported(key);
        }
      } else if (autoImport &&
          task.output.isLocal &&
          localVideos.isEmpty &&
          context.job.cancelRequestedAt == null) {
        await library.markImported(key);
      }
      if (stopped && context.job.cancelRequestedAt == null) return;
      if (context.job.cancelRequestedAt != null) {
        await _finishCancelled(context, backend, task, files);
        return;
      }
      await context.succeed(_receipt(task, files, unreached: _unreached(context, task)));
    } on FileSystemException catch (error) {
      if (stopped && context.job.cancelRequestedAt == null) return;
      final failure =
          Failure(FailureCode.unavailable, error.toString(), retryable: true);
      if (context.job.cancelRequestedAt != null) {
        await context.fail(
            failure,
            JobReceipt(
                verification: VerificationLevel.unverified,
                details: {'files': files, 'reason': error.toString()}));
      } else {
        await context.retryAt(
            DateTime.now().toUtc().add(importRetryDelay), failure,
            checkpointPatch: {'files': files});
      }
    } on DownloadAddStopped {
      if (context.job.cancelRequestedAt != null) {
        await context.cancelled(JobReceipt(
            verification: VerificationLevel.unverified,
            details: {'files': [], 'reason': 'cancelled_before_add'}));
      }
    } on Failure catch (failure) {
      if (stopped && context.job.cancelRequestedAt == null) return;
      if (failure.code == FailureCode.unavailable &&
          failure.retryable &&
          context.job.cancelRequestedAt == null) {
        await context.retryAt(
            DateTime.now().toUtc().add(importRetryDelay), failure);
      } else {
        await context.fail(
            failure,
            JobReceipt(
                verification: VerificationLevel.unverified,
                details: {'files': files, 'reason': failure.message}));
      }
    } finally {
      _workers.remove(context.job.jobId);
      done.complete();
    }
  }

  Future<void> _completedFiles(JobContext context, DownloadBackend backend,
          DownloadSnapshot task) =>
      exclusive(
          context.job.jobId, () => _completedFilesLocked(context, backend, task));

  Future<void> _completedFilesLocked(JobContext context,
      DownloadBackend backend, DownloadSnapshot task) async {
    final completed = [
      for (final row in context.job.checkpoint['completedFiles'] as List? ??
          [])
        Map<String, Object?>.from(row as Map)
    ];
    // A crash between registering a file and saving its binding leaves the
    // row pending; the stable requestId makes running it again safe.
    for (final row in completed) {
      if ((row['binding'] as Map?)?['status'] == 'pending') {
        await _bindCompleted(context, completed, row);
      }
    }
    for (var index = 0; index < task.files.length; index++) {
      final file = task.files[index];
      if (!file.included ||
          !file.complete ||
          completed.any((row) => row['index'] == index)) {
        continue;
      }
      if (file.location.isLocal) {
        await checkedDownloadPath(task.output.path, file.location.path);
      }
      final size = await backend.readSize(file);
      if (size != file.expectedSize) continue;
      final scanKey = '${task.importKey}:file:$index';
      if (file.isVideo &&
          file.location.isLocal &&
          await library.enabled &&
          !await library.wasImported(scanKey)) {
        if (library.isBusy) continue;
        await library.importFiles([file.location.path], task.output.path);
        await library.markImported(scanKey);
      }
      final media = file.isVideo && file.location.isLocal
          ? await library.lookup(file.location.path)
          : null;
      completed.add({
        'objectId': '${context.job.jobId}:$index',
        'jobId': context.job.jobId,
        'index': index,
        'path': file.location.path,
        if (file.location.isLocal)
          'canonicalPath':
              await File(file.location.path).resolveSymbolicLinks(),
        'expectedSize': file.expectedSize,
        'actualSize': size,
        'completedBytes': file.completedBytes,
        'complete': true,
        'verification': 'verified',
        'local': file.location.isLocal,
        'included': file.included,
        'isVideo': file.isVideo,
        'imported': media != null,
        if (media != null) 'media': media,
        if (file.isVideo &&
            (media == null || media['identificationPending'] == true))
          'identificationPending': true,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      // The declaration is read here, under the lock: one made by
      // download.declare_files before this point is honoured now, one made
      // later finds this row and binds it itself.
      final declared = fileBindingFor(context.job, index) != null &&
          file.isVideo &&
          file.location.isLocal;
      // Pending keeps the file event back until the binding outcome is on
      // the row; the media access check needs this row saved first.
      if (declared) completed.last['binding'] = {'status': 'pending'};
      // Persist before task observers publish the file event. Recovery reads this fact.
      await context.report(
          checkpointPatch: {'completedFiles': completed.toList()});
      if (declared) await _bindCompleted(context, completed, completed.last);
    }
  }

  /// Applies the file's declared episode identity and saves the outcome on
  /// its row. Whatever happens here, the download carries on: the outcome is
  /// a fact for whoever ordered it, and nothing retries it.
  Future<void> _bindCompleted(
      JobContext context, List<JsonMap> completed, JsonMap row) async {
    await bindRow(context.job, row);
    await context.report(
        checkpointPatch: {'completedFiles': completed.toList()});
  }

  /// Binds the file of one `completedFiles` [row] as [job] declares it and
  /// writes the outcome (and the re-read library entry) into [row]; the
  /// caller saves the row. [declaration] stands in for the stored one. Never
  /// throws: a failure is the outcome.
  Future<JsonMap> bindRow(Job job, JsonMap row, {JsonMap? declaration}) async {
    final index = row['index'] as int;
    declaration ??= fileBindingFor(job, index);
    JsonMap outcome;
    try {
      if (declaration == null) {
        outcome = {'status': 'not_applied', 'reason': 'no_declaration'};
      } else {
        final path = row['path'] as String;
        final requestId = fileBindingRequestId(job.jobId, index,
            declarationId: declaration['declarationId'] as String?);
        var media = await library.lookup(path);
        final fileId = media?['fileId'] as String?;
        final existing = [
          for (final e in media?['episodes'] as List? ?? [])
            (e as Map)['episodeId']
        ];
        final previous = row['binding'];
        if (fileId == null) {
          outcome = {'status': 'not_applied', 'reason': 'file_not_registered'};
        } else if (existing.isNotEmpty &&
            previous is Map &&
            previous['status'] == 'bound' &&
            row['bindingRequestId'] == requestId) {
          // This very declaration is what bound the file.
          outcome = Map<String, Object?>.from(previous);
        } else if (existing.isNotEmpty &&
            media?['classicMatchOnly'] != true) {
          // Another identification came first; the declaration does not
          // overwrite it. (A Classic match alone is not one: the declaration
          // takes its place.)
          outcome = {
            'status': 'already_identified',
            'existingEpisodeIds': existing
          };
        } else {
          final bound = await library.bindFile(
              fileId: fileId,
              declaration: declaration,
              requestId: requestId,
              origin: declaration['origin'] as String? ??
                  job.input['bindingOrigin'] as String? ??
                  'download');
          outcome = {
            'status': 'bound',
            'workId': bound['workId'],
            'releaseId': bound['releaseId'],
            'episodeIds': bound['episodeIds'],
            if (bound['supersededClassic'] != null)
              'supersededClassic': bound['supersededClassic'],
          };
          row['bindingRequestId'] = requestId;
          media = await library.lookup(path) ?? media;
        }
        if (media != null) {
          row['media'] = media;
          row['imported'] = true;
          if (media['identificationPending'] == true) {
            row['identificationPending'] = true;
          } else {
            row.remove('identificationPending');
          }
        }
      }
    } on Failure catch (failure) {
      outcome = {'status': 'failed', 'error': failure.toJson()};
    } catch (error) {
      outcome = {
        'status': 'failed',
        'error': Failure(FailureCode.internal, 'Binding failed: $error')
            .toJson()
      };
    }
    row['binding'] = outcome;
    return outcome;
  }

  /// Declared files that did not get a binding attempt, and why.
  List<JsonMap> _unreached(JobContext context, DownloadSnapshot task) {
    final done = {
      for (final row in context.job.checkpoint['completedFiles'] as List? ?? [])
        if ((row as Map)['binding'] != null) row['index']
    };
    return [
      for (final entry in effectiveFileBindings(context.job))
        if (!done.contains(entry['fileIndex']))
          {
            'fileIndex': entry['fileIndex'],
            'reason': (entry['fileIndex'] as int) >= task.files.length
                ? 'no_such_file'
                : !task.files[entry['fileIndex'] as int].included
                    ? 'not_selected'
                    : !task.files[entry['fileIndex'] as int].isVideo
                        ? 'not_video'
                        : 'not_completed'
          }
    ];
  }

  /// Each stretch without progress is recorded once, with what the engine
  /// saw; it closes when a byte is seen after it began. Time without
  /// progress restarts with the process, so only an observed byte closes it.
  Future<void> _noteStall(JobContext context, DownloadSnapshot task) async {
    final health = task.health;
    final seconds = health?['secondsWithoutProgress'];
    if (seconds is! int) return;
    final stalls = [
      for (final s in context.job.checkpoint['stalls'] as List? ?? [])
        Map<String, Object?>.from(s as Map)
    ];
    final open = stalls.lastOrNull?['resumedAt'] == null ? stalls.lastOrNull : null;
    final now = DateTime.now().toUtc();
    if (open != null) {
      final progressAt = health!['lastProgressAt'] as String?;
      if (progressAt == null ||
          !DateTime.parse(progressAt).isAfter(DateTime.parse(open['at'] as String))) {
        return;
      }
      open['resumedAt'] = progressAt;
    } else {
      if (seconds < stallAfter.inSeconds) return;
      stalls.add({
        'index': stalls.length,
        'at': now.toIso8601String(),
        'secondsWithoutProgress': seconds,
        'completedBytes': task.completed,
        'totalBytes': task.total > 0 ? task.total : null,
        'connectedPeers': health!['connectedPeers'],
        'seenPeers': health['seenPeers'],
        'deadPeers': health['deadPeers'],
      });
    }
    await context.report(checkpointPatch: {'stalls': stalls});
  }

  Future<void> _finishCancelled(JobContext context, DownloadBackend backend,
      DownloadSnapshot task, List<JsonMap> files,
      {String? reason}) async {
    if (!task.paused) await backend.pause(task.handle);
    task = await backend.read(task.handle);
    if (!task.paused) {
      throw const Failure(
          FailureCode.conflict, 'Download backend did not stop the torrent.');
    }
    await _verify(backend, task, files, requireComplete: false);
    // A file's size says nothing here: the engine allocates every file at
    // full size up front. Only files it verified are looked up, since a
    // lookup registers the path.
    final verified = {
      for (final f in context.job.checkpoint['completedFiles'] as List? ?? [])
        (f as Map)['path']
    };
    for (final row in files) {
      row['retained'] = row['actualSize'] != null;
      final file =
          task.files.singleWhere((f) => f.location.path == row['path']);
      final complete = task.finished || verified.contains(file.location.path);
      row['complete'] = complete;
      final media =
          complete && file.included && file.isVideo && file.location.isLocal
              ? await library.lookup(file.location.path)
              : null;
      row['imported'] = media != null;
      if (media != null) {
        row['media'] = media;
        if (media['identificationPending'] == true) {
          row['identificationPending'] = true;
          row['reason'] = 'not_identified';
        }
      } else if (!row.containsKey('reason')) {
        row['reason'] = !file.included
            ? 'not_selected'
            : !file.isVideo
                ? 'not_video'
                : !file.location.isLocal
                    ? 'requires_transfer'
                    : task.finished && reason == null
                        ? 'not_identified'
                        : reason ?? 'cancelled_before_import';
      }
      if (media == null &&
          file.included &&
          file.isVideo &&
          file.location.isLocal &&
          task.finished) {
        row['identificationPending'] = true;
      }
    }
    await context.cancelled(_receipt(task, files,
        reason: reason, unreached: _unreached(context, task)));
  }

  Future<bool> _verify(
      DownloadBackend backend, DownloadSnapshot task, List<JsonMap> rows,
      {required bool requireComplete}) async {
    rows.clear();
    var valid = task.files.isNotEmpty || task.total == 0;
    for (final file in task.files) {
      if (file.location.isLocal) {
        await checkedDownloadPath(task.output.path, file.location.path);
      }
      final size = await backend.readSize(file);
      final matches = size == file.expectedSize;
      valid = valid && (!file.included || matches);
      rows.add({
        'path': file.location.path,
        'expectedSize': file.expectedSize,
        'actualSize': size,
        if (size != null && file.location.isLocal)
          'canonicalPath':
              await File(file.location.path).resolveSymbolicLinks(),
        'local': file.location.isLocal,
        'included': file.included,
        'imported': false,
        if (!file.included)
          'reason': 'not_selected'
        else if (!matches)
          'reason': size == null ? 'missing' : 'size_mismatch'
      });
    }
    return !requireComplete || valid;
  }

  Future<List<JsonMap>> _readRemovedFiles(
      DownloadBackend backend, Job job) async {
    final files = <JsonMap>[];
    for (final row
        in (job.checkpoint['files'] as List? ?? []).cast<JsonMap>()) {
      final size = await backend.readSize(DownloadFile(
          location: DownloadLocation(
              path: row['path'] as String, isLocal: row['local'] as bool),
          expectedSize: row['expectedSize'] as int,
          isVideo: false));
      files.add({
        'path': row['path'],
        'expectedSize': row['expectedSize'],
        'actualSize': size,
        'retained': size != null,
        'imported': await library.lookup(row['path'] as String) != null,
      });
    }
    return files;
  }

  JobReceipt _receipt(DownloadSnapshot task, List<JsonMap> files,
          {String? reason, List<JsonMap> unreached = const []}) =>
      JobReceipt(verification: VerificationLevel.verified, details: {
        'infoHash': task.infoHash,
        'outputDirectory': task.output.path,
        'downloadComplete': task.finished,
        'paused': task.paused,
        'files': files,
        'fileIds': {
          for (final row in files)
            if ((row['media'] as Map?)?['fileId'] case final String id) id
        }.toList(),
        'workIds': {
          for (final row in files)
            ...?((row['media'] as Map?)?['workIds'] as List?)
        }.toList(),
        if (reason != null) 'reason': reason,
        if (unreached.isNotEmpty) 'unboundDeclarations': unreached
      });
}

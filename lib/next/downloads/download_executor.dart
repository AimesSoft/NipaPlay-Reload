import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';

import 'download_backend.dart';
import 'download_paths.dart';

final class DownloadExecutor implements JobExecutor {
  DownloadExecutor(
      {required this.backends,
      required this.library,
      required this.isEnabled,
      this.pollInterval = const Duration(seconds: 5),
      this.importRetryDelay = const Duration(minutes: 1)});
  final DownloadBackends backends;
  final DownloadLibrary library;
  final Future<bool> Function() isEnabled;
  final Duration pollInterval, importRetryDelay;
  late TaskEngine engine;
  final Map<String, Completer<void>> _workers = {};
  @override
  String get type => 'download';

  Future<void> quiesce(String jobId) async {
    await _workers[jobId]?.future;
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
        await context.markSideEffectCommitted(checkpoint: {
          'infoHash': task.infoHash,
          'handle': task.handle,
          'output': task.output.path,
          'files': [
            for (final file in task.files)
              {
                'path': file.location.path,
                'expectedSize': file.expectedSize,
                'local': file.location.isLocal,
                'included': file.included,
              }
          ],
        });
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
        if (task.finished) break;
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
            checkpoint: {...context.job.checkpoint, 'files': files});
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
        final pending = localVideos
            .where((f) =>
                files.singleWhere(
                    (row) => row['path'] == f.location.path)['imported'] !=
                true)
            .toList();
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
      await context.succeed(_receipt(task, files));
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
            checkpoint: {...context.job.checkpoint, 'files': files});
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
    for (final row in files) {
      row['retained'] = row['actualSize'] != null;
      final file =
          task.files.singleWhere((f) => f.location.path == row['path']);
      final media = file.included && file.isVideo && file.location.isLocal
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
    await context.cancelled(_receipt(task, files, reason: reason));
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
          {String? reason}) =>
      JobReceipt(verification: VerificationLevel.verified, details: {
        'infoHash': task.infoHash,
        'outputDirectory': task.output.path,
        'downloadComplete': task.finished,
        'paused': task.paused,
        'files': files,
        if (reason != null) 'reason': reason
      });
}

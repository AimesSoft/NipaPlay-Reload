import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';

import 'download_backend.dart';
import 'download_executor.dart';
import 'download_paths.dart';

/// Coordinates identity and controls for GUI and Actions. The backend remains
/// the source of live torrent/seeding state; the engine owns durable stages.
final class DownloadService {
  DownloadService(
      {required this.engine,
      required this.executor,
      required this.backends,
      required this.library});
  final TaskEngine engine;
  final DownloadExecutor executor;
  final DownloadBackends backends;
  final DownloadLibrary library;
  Future<JsonMap?> Function(Invocation)? returnTarget;
  Future<JsonMap> bandwidth(JsonMap input) => _serial(() async {
    for (final value in input.values.cast<int>()) {
      if (value != 0 && (value < 16384 || value > 4294967295)) {
        throw const Failure(FailureCode.invalidInput, 'Use 0 for unlimited, or 16384..4294967295 bytes/second.');
      }
    }
    final backend = backends.resolve(const DownloadBackendRef.builtin());
    final facts = backend is BandwidthDownloadBackend ? await (backend as BandwidthDownloadBackend).bandwidth(input)
      : <String, Object?>{'supported': false, 'applied': false, 'reason': 'backend_has_no_bandwidth_control'};
    return {...facts, 'scope': 'builtinSession', 'appliesTo': 'all builtin torrents',
      'lifetime': 'current native session; new sessions default to unlimited',
      'unit': 'bytes/second; 0 means unlimited', 'minimumPositive': 16384};
  });
  Future<void> _tail = Future.value();

  Future<T> _serial<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  DownloadBackendRef _ref(Job job) =>
      DownloadBackendRef.fromJson(job.details['backend'] as JsonMap);
  bool _matches(Job job, DownloadBackendRef ref, String infoHash) =>
      _ref(job).key == ref.key && job.input['infoHash'] == infoHash;

  Future<Job> add(DownloadRequest request,
          {DownloadBackendRef backend = const DownloadBackendRef.builtin(),
          Invocation? invocation}) =>
      _serial(() async {
        backends.resolve(backend);
        final jobs = await engine.list(type: 'download');
        final existing = jobs.where((job) =>
            _matches(job, backend, request.infoHash) && !job.state.isTerminal);
        if (existing.isNotEmpty) return existing.last;
        final previous =
            jobs.where((job) => _matches(job, backend, request.infoHash));
        if (previous.isNotEmpty &&
            (await backends.resolve(backend).list())
                .any((task) => task.infoHash == request.infoHash)) {
          return previous.last;
        }
        final target =
            invocation == null ? null : await returnTarget?.call(invocation);
        return engine.submit(
            type: 'download',
            title: request.title,
            input: {
              ...request.toJson(),
              if (target != null) 'returnTo': target
            },
            details: {'backend': backend.toJson()},
            phase: 'downloading');
      });

  Future<Job> adopt(DownloadBackend backend, DownloadSnapshot task) =>
      _serial(() async {
        final jobs = (await engine.list(type: 'download'))
            .where((job) => _matches(job, backend.reference, task.infoHash))
            .toList();
        if (jobs.isNotEmpty) {
          final latest = jobs.last;
          if (!latest.state.isTerminal) return latest;
          if (latest.state == JobState.cancelled && task.paused) return latest;
          // Turning automatic import back on must also process old completed data.
          if (latest.state == JobState.succeeded &&
              task.finished &&
              !(task.finished &&
                  task.output.isLocal &&
                  await library.enabled &&
                  !await library.wasImported(task.importKey))) {
            return latest;
          }
          if (latest.state == JobState.failed &&
              (task.paused ||
                  !const {'cancelled_incomplete', 'session_missing', 'removed'}
                      .contains(latest.receipt!.details['reason']))) {
            return latest;
          }
        }
        return engine.submit(
            type: 'download',
            title: task.title,
            input: {
              ...DownloadRequest(
                      source: '', infoHash: task.infoHash, title: task.title)
                  .toJson(),
              'adopted': true
            },
            details: {'backend': backend.reference.toJson()},
            phase: 'downloading');
      });

  Future<Job> jobFor(DownloadBackendRef ref, String infoHash) async {
    final jobs = (await engine.list(type: 'download'))
        .where((job) => _matches(job, ref, infoHash));
    if (jobs.isEmpty) {
      throw const Failure(
          FailureCode.notFound, 'Download has no persisted job.');
    }
    return jobs.last;
  }

  Future<DownloadSnapshot?> _task(DownloadBackend backend, Job job) async {
    final tasks = (await backend.list())
        .where((task) => task.infoHash == job.input['infoHash']);
    return tasks.isEmpty ? null : await backend.read(tasks.single.handle);
  }

  Future<Job> _downloadJob(String jobId) async {
    final job = await engine.get(jobId);
    if (job.type != 'download') {
      throw const Failure(FailureCode.invalidInput, 'Job is not a download.');
    }
    return job;
  }

  Future<Job> pause(String jobId) => _serial(() async {
        var job = await _downloadJob(jobId);
        final backend = backends.resolve(_ref(job));
        if (!job.state.isTerminal && job.state != JobState.paused) {
          job = await engine.pause(jobId);
          await executor.quiesce(jobId);
        }
        final task = await _task(backend, job);
        if (task != null && !task.paused) await backend.pause(task.handle);
        return engine.get(jobId);
      });

  Future<DownloadSnapshot?> snapshot(String jobId) async {
    final job = await _downloadJob(jobId);
    return _task(backends.resolve(_ref(job)), job);
  }

  Future<JsonMap> read(String jobId) async {
    final job = await _downloadJob(jobId);
    final backend = backends.resolve(_ref(job));
    final task = await _task(backend, job);
    final facts = task?.toJson();
    if (task != null) {
      // What the worker saved per completed file: its library entry.
      final completed = {
        for (final row in job.checkpoint['completedFiles'] as List? ?? [])
          (row as Map)['index']: row
      };
      for (final entry in task.files.indexed) {
        final row = (facts!['files'] as List)[entry.$1] as JsonMap;
        if (completed[entry.$1] case final Map saved) {
          for (final key in const [
            'imported',
            'identificationPending',
            'media'
          ]) {
            if (saved[key] != null) row[key] = saved[key];
          }
          // The entry saved at completion is a past fact; a registered file
          // is read again so its episode links are as they are now.
          if (saved['media'] != null) {
            try {
              final live = await library.lookup(saved['path'] as String);
              if (live != null) row['media'] = live;
            } catch (_) {}
          }
        }
      }
      for (final entry in task.files.indexed) {
        if (!entry.$2.included && entry.$2.location.isLocal) {
          // A file no longer selected may still hold data, or have had it deleted.
          final row = (facts!['files'] as List)[entry.$1] as JsonMap;
          row['actualSize'] = await backend.readSize(entry.$2);
          row['playable'] = false;
        } else if (entry.$2.complete && entry.$2.location.isLocal) {
          final row = (facts!['files'] as List)[entry.$1] as JsonMap;
          final size = await backend.readSize(entry.$2);
          row['actualSize'] = size;
          row['playable'] =
              row['playable'] == true && size == entry.$2.expectedSize;
          if (row['playable'] == true) {
            try {
              await checkedDownloadPath(
                  task.output.path, entry.$2.location.path);
            } on Failure catch (failure) {
              if (failure.code != FailureCode.invalidInput) rethrow;
              row['playable'] = false;
              row['playbackUnavailableReason'] = failure.message;
            }
          }
        }
      }
    }
    return {'job': job.toJson(), 'task': facts};
  }

  /// Returns the completed, imported, verified video files of [jobId] whose
  /// index is not in [known] as soon as there are any, when the download has
  /// ended, or after [waitSeconds]. It polls the saved checkpoint, which is
  /// cheap; the full [read] runs only for the answer.
  Future<JsonMap> waitFiles(String jobId, Set<int> known, int waitSeconds,
      {Duration interval = const Duration(seconds: 1)}) async {
    final clock = Stopwatch()..start();
    final limit = Duration(seconds: waitSeconds);
    while (true) {
      final job = await _downloadJob(jobId);
      final ready = {
        for (final row in job.checkpoint['completedFiles'] as List? ?? [])
          if ((row as Map)['isVideo'] == true &&
              row['imported'] == true &&
              row['verification'] == 'verified' &&
              !known.contains(row['index']))
            row['index'] as int
      };
      final ended = job.state.isTerminal;
      final timedOut = !ended && ready.isEmpty && clock.elapsed >= limit;
      if (ready.isNotEmpty || ended || timedOut) {
        final read = await this.read(jobId);
        final files = [
          for (final row in (read['task'] as Map?)?['files'] as List? ?? [])
            if (ready.contains((row as Map)['index']) &&
                row['isVideo'] == true &&
                row['imported'] == true)
              row
        ];
        return {
          'jobId': jobId,
          'state': (read['job'] as Map)['state'],
          'files': files,
          'ended': ended,
          'timedOut': timedOut,
        };
      }
      final remaining = limit - clock.elapsed;
      await Future<void>.delayed(remaining < interval ? remaining : interval);
    }
  }

  Future<JsonMap> selectFiles(String jobId, List<int> indices) =>
      _serial(() async {
        final job = await _downloadJob(jobId);
        if (job.state == JobState.cancelling ||
            job.state == JobState.cancelled) {
          throw const Failure(FailureCode.conflict, 'Download was cancelled.');
        }
        final backend = backends.resolve(_ref(job));
        if (backend is! SelectableDownloadBackend) {
          throw const Failure(FailureCode.unavailable,
              'Backend does not support file selection.');
        }
        final task = await _task(backend, job);
        if (task == null) {
          throw const Failure(
              FailureCode.notFound, 'Download session is missing.');
        }
        if (indices.toSet().length != indices.length ||
            indices.any((index) => index < 0 || index >= task.files.length)) {
          throw const Failure(FailureCode.invalidInput,
              'File indices must be unique manifest indices.');
        }
        final wasPaused = task.paused;
        if (!job.state.isTerminal && job.state != JobState.paused) {
          await engine.pause(jobId);
          await executor.quiesce(jobId);
        }
        final current = await backend.read(task.handle);
        if (!current.paused) await backend.pause(task.handle);
        try {
          await (backend as SelectableDownloadBackend)
              .selectFiles(task.handle, indices);
        } finally {
          if (!wasPaused) {
            await backend.resume(task.handle);
            if (!job.state.isTerminal) await engine.resume(jobId);
          }
        }
        final changed = await backend.read(task.handle);
        if (changed.files.indexed
            .any((entry) => entry.$2.included != indices.contains(entry.$1))) {
          throw const Failure(
              FailureCode.conflict, 'Backend selection readback differs.');
        }
        // Expanding a finished selection starts a new observation; the old receipt stays intact.
        if (job.state.isTerminal && !changed.finished) {
          final replacement = await engine.submit(
              type: 'download',
              title: changed.title,
              input: {
                ...job.input,
                'adopted': true,
                'completedFiles': job.checkpoint['completedFiles'] ?? []
              },
              details: job.details,
              phase: 'downloading');
          return {'job': replacement.toJson(), 'task': changed.toJson()};
        }
        return {
          'job': (await engine.get(jobId)).toJson(),
          'task': changed.toJson()
        };
      });

  Future<JsonMap> importCompleted(String jobId) => _serial(() async {
        final job = await _downloadJob(jobId);
        final backend = backends.resolve(_ref(job));
        final task = await _task(backend, job);
        if (task == null) {
          throw const Failure(FailureCode.notFound,
              'Download is absent from its backend session.');
        }
        if (!task.finished || !task.output.isLocal) {
          throw const Failure(FailureCode.conflict,
              'Import requires a completed local download.');
        }
        final videos = task.files
            .where((f) => f.included && f.isVideo && f.location.isLocal)
            .toList();
        for (final file in videos) {
          await checkedDownloadPath(task.output.path, file.location.path);
          if (await backend.readSize(file) != file.expectedSize) {
            throw const Failure(FailureCode.conflict,
                'Completed video is missing or has an incorrect size.');
          }
        }
        if (library.isBusy) {
          throw const Failure(FailureCode.unavailable, 'Media scanner is busy.',
              retryable: true);
        }
        await library.importFiles(
            videos.map((f) => f.location.path).toList(), task.output.path);
        await library.markImported(task.importKey);
        final result = task.toJson();
        for (final file in (result['files'] as List).cast<JsonMap>()) {
          final media = await library.lookup(file['path'] as String);
          file['imported'] = media != null;
          if (media != null) file['media'] = media;
          if (file['included'] == true &&
              file['isVideo'] == true &&
              media == null) {
            file['identificationPending'] = true;
          }
        }
        return {'job': (await engine.get(jobId)).toJson(), 'task': result};
      });
  Future<Job> resume(String jobId) => _serial(() async {
        final job = await _downloadJob(jobId);
        final backend = backends.resolve(_ref(job));
        final task = await _task(backend, job);
        if (task == null) {
          throw const Failure(
              FailureCode.notFound, 'Download is absent from its backend.');
        }
        if (job.state == JobState.cancelling ||
            job.cancelRequestedAt != null && !job.state.isTerminal) {
          throw const Failure(FailureCode.conflict,
              'Download cancellation is still in progress.');
        }
        if (task.paused || (task.error?.isNotEmpty ?? false)) {
          await backend.resume(task.handle);
        }
        if (job.state == JobState.paused) return engine.resume(jobId);
        return engine.get(jobId);
      });
  /// Deletes the data of some files of a download and stops selecting them;
  /// the session, the other files and their seeding or downloading go on.
  /// Only these files, only inside the output directory, never a directory.
  Future<JsonMap> deleteFiles(String jobId, List<int> indices) =>
      _serial(() async {
        final job = await _downloadJob(jobId);
        if (job.state == JobState.cancelling ||
            job.state == JobState.cancelled) {
          throw const Failure(FailureCode.conflict, 'Download was cancelled.');
        }
        final backend = backends.resolve(_ref(job));
        if (backend is! SelectableDownloadBackend ||
            backend is! FileDeletingDownloadBackend) {
          throw const Failure(FailureCode.unavailable,
              'Backend does not support deleting individual files.');
        }
        final task = await _task(backend, job);
        if (task == null) {
          throw const Failure(
              FailureCode.notFound, 'Download session is missing.');
        }
        if (indices.isEmpty ||
            indices.toSet().length != indices.length ||
            indices.any((index) => index < 0 || index >= task.files.length)) {
          throw const Failure(FailureCode.invalidInput,
              'File indices must be unique, non-empty manifest indices.');
        }
        for (final index in indices) {
          final file = task.files[index];
          if (!file.location.isLocal) {
            throw const Failure(
                FailureCode.invalidInput, 'Only local files can be deleted.');
          }
          await checkedDownloadPath(task.output.path, file.location.path);
        }
        final kept = [
          for (final entry in task.files.indexed)
            if (entry.$2.included && !indices.contains(entry.$1)) entry.$1
        ];
        final wasPaused = task.paused;
        if (!job.state.isTerminal && job.state != JobState.paused) {
          await engine.pause(jobId);
          await executor.quiesce(jobId);
        }
        final current = await backend.read(task.handle);
        if (!current.paused) await backend.pause(task.handle);
        try {
          // Unselect first so the engine stops reading these files, then
          // remove the data.
          await (backend as SelectableDownloadBackend)
              .selectFiles(task.handle, kept);
          await (backend as FileDeletingDownloadBackend)
              .deleteFiles(task.handle, indices);
        } finally {
          if (!wasPaused) {
            await backend.resume(task.handle);
            if (!job.state.isTerminal) await engine.resume(jobId);
          }
        }
        final changed = await backend.read(task.handle);
        for (final entry in changed.files.indexed) {
          if (entry.$2.included != kept.contains(entry.$1)) {
            throw const Failure(
                FailureCode.conflict, 'Backend selection readback differs.');
          }
        }
        for (final index in indices) {
          if (await backend.readSize(changed.files[index]) != null) {
            throw const Failure(FailureCode.unavailable,
                'A file was unselected but its data remains.');
          }
        }
        return {
          'job': (await engine.get(jobId)).toJson(),
          'task': changed.toJson(),
          'deletedFiles': [
            for (final index in indices)
              {'index': index, 'path': changed.files[index].location.path}
          ]
        };
      });

  Future<Job> remove(String jobId, {bool deleteData = false}) =>
      _serial(() async {
        final job = await _downloadJob(jobId);
        final backend = backends.resolve(_ref(job));
        var task = await _task(backend, job);
        if (deleteData && task != null) {
          for (final file in task.files) {
            if (file.location.isLocal) {
              await checkedDownloadPath(task.output.path, file.location.path);
            }
          }
        }
        if (!job.state.isTerminal) {
          var stopped = await engine.cancel(jobId);
          while (!stopped.state.isTerminal) {
            stopped = await engine.wait(jobId, afterRevision: stopped.revision);
          }
          await executor.quiesce(jobId);
          task = await _task(backend, job);
        }
        if (task != null) {
          if (deleteData) {
            for (final file in task.files) {
              if (file.location.isLocal) {
                await checkedDownloadPath(task.output.path, file.location.path);
              }
            }
            await backend.delete(task.handle);
            for (final file in task.files) {
              if (file.included && await backend.readSize(file) != null) {
                throw const Failure(FailureCode.unavailable,
                    'Download session was removed but a downloaded file remains.');
              }
            }
          } else {
            await backend.remove(task.handle);
          }
          // A job that had already ended keeps its old receipt otherwise;
          // an ended job removed while running was recorded by the executor.
          if (job.state.isTerminal) {
            await _amendRemoved(job, backend, deleteData);
          }
        }
        return engine.get(jobId);
      });

  Future<void> _amendRemoved(
      Job job, DownloadBackend backend, bool deleteData) async {
    final reread = {
      for (final row in await readRemovedFiles(backend, library, job))
        row['path']: row
    };
    final receipt = job.receipt;
    final old = receipt?.details ?? const <String, Object?>{};
    final oldFiles = (old['files'] as List? ?? []).cast<JsonMap>();
    final files = oldFiles.isEmpty
        ? reread.values.toList()
        : [
            for (final row in oldFiles)
              if (reread[row['path']] case final fresh?)
                {
                  for (final entry in row.entries)
                    if (fresh['retained'] == true ||
                        (entry.key != 'canonicalPath' &&
                            entry.key != 'media'))
                      entry.key: entry.value,
                  'actualSize': fresh['actualSize'],
                  'retained': fresh['retained'],
                  'imported': fresh['imported'],
                }
              else
                row
          ];
    await engine.amendReceipt(
        job.jobId,
        JobReceipt(
            verification: receipt?.verification ?? VerificationLevel.verified,
            details: {
              ...old,
              'files': files,
              'sessionPresent': false,
              'removedAt': DateTime.now().toUtc().toIso8601String(),
              'dataDeleted': deleteData
            }));
  }
}

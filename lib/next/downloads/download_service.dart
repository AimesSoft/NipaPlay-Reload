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
          {DownloadBackendRef backend = const DownloadBackendRef.builtin()}) =>
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
        return engine.submit(
            type: 'download',
            title: request.title,
            input: request.toJson(),
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
      for (final entry in task.files.indexed) {
        if (entry.$2.complete && entry.$2.location.isLocal) {
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
        }
        return engine.get(jobId);
      });
}

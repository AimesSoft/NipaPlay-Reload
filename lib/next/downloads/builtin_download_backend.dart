import 'dart:io';
import 'dart:convert';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/src/rust/api/torrent.dart' as native;
import 'package:path/path.dart' as p;

import 'download_backend.dart';
import 'download_paths.dart';
import 'bandwidth_native.dart';

final class BuiltinDownloadBackend
    implements
        DownloadBackend,
        SelectableDownloadBackend,
        FileDeletingDownloadBackend,
        BandwidthDownloadBackend {
  BuiltinDownloadBackend(this.service);
  final TorrentDownloadService service;
  @override
  Future<JsonMap> bandwidth(JsonMap input) async => NativeBandwidth.call(input);
  final _observations = <String,
      ({
    DateTime since,
    DateTime? lastProgress,
    int bytes,
    DateTime at,
    int previousBytes
  })>{};
  @override
  DownloadBackendRef get reference => const DownloadBackendRef.builtin();
  @override
  String? get credentialRef => null;
  @override
  Future<void> initialize() => _nativeCall(service.initialize);
  @override
  Future<List<DownloadSnapshot>> list() => _nativeCall(() async => [
        for (final task in await service.listTasks()) _snapshot(task),
      ]);
  @override
  Future<DownloadSnapshot> read(String handle) => _nativeCall(() async {
        final matches = (await service.listTasks())
            .where((task) => task.id.toString() == handle);
        if (matches.isEmpty) {
          throw const Failure(
              FailureCode.notFound, 'Torrent session handle is missing.');
        }
        final task = matches.single;
        final output = await service.resolveTaskOutputDirectory(task);
        final facts = jsonDecode(await native.torrentDownloadFacts(id: task.id))
            as JsonMap;
        final details = TorrentTask.fromMap(
            {...facts['details'] as JsonMap, 'stats': facts['stats']});
        final stats = facts['stats'] as JsonMap;
        final progress = (stats['file_progress'] as List).cast<int>();
        final now = DateTime.now().toUtc();
        final observationKey = '${task.infoHash}|$output';
        final previous = _observations[observationKey];
        final bytes = progress.fold<int>(0, (a, b) => a + b);
        final observation = (
          since: previous?.since ?? now,
          lastProgress: previous != null && bytes > previous.bytes
              ? now
              : previous?.lastProgress,
          bytes: bytes,
          at: now,
          previousBytes: previous?.bytes ?? bytes
        );
        _observations[observationKey] = observation;
        final peers = ((stats['live'] as Map?)?['snapshot']
            as Map?)?['peer_stats'] as Map?;
        return _snapshot(details,
            resolvedOutput: output,
            progress: progress,
            disk: facts['disk'] as JsonMap,
            health: {
              'observedAt': now.toIso8601String(),
              'observingSince': observation.since.toIso8601String(),
              'lastProgressAt': observation.lastProgress?.toIso8601String(),
              'secondsWithoutProgress': now
                  .difference(observation.lastProgress ?? observation.since)
                  .inSeconds,
              'sampleSeconds': previous == null
                  ? 0
                  : now.difference(previous.at).inMilliseconds / 1000,
              'checkedBytesChange': bytes - observation.previousBytes,
              'connectedPeers': peers?['live'],
              'seenPeers': peers?['seen'],
              'connectingPeers': peers?['connecting'],
              'queuedPeers': peers?['queued'],
              'deadPeers': peers?['dead'],
              'sources': facts['sources'],
              'seeders': null,
              'pieceAvailability': null,
              'availabilityReason':
                  'librqbit public API does not expose peer bitfields or tracker seed counts',
              'fileSelectionSupported': true,
              'filePrioritySupported': false,
            });
      });

  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested}) async {
    var stopped = false;
    stopRequested?.then((_) => stopped = true);
    try {
      final result = await _nativeCall(() async =>
          request.source.startsWith('magnet:')
              ? await service.addMagnetWithPreview(request.source,
                  onlyFiles: request.fileIndices,
                  stopRequested: stopRequested,
                  downloadDirectory: request.downloadDirectory,
                  createFolderForTask: request.createFolderForTask)
              : await service.addTorrentFile(request.source,
                  onlyFiles: request.fileIndices,
                  downloadDirectory: request.downloadDirectory,
                  createFolderForTask: request.createFolderForTask));
      return read(result.id.toString());
    } on StateError {
      if (stopped) throw const DownloadAddStopped();
      rethrow;
    }
  }

  @override
  Future<void> selectFiles(String handle, List<int> indices) =>
      _nativeCall(() => native.torrentSelectFiles(
          id: int.parse(handle), fileIndices: indices));

  @override
  Future<void> pause(String handle) =>
      _nativeCall(() => service.pause(int.parse(handle)));
  @override
  Future<void> resume(String handle) =>
      _nativeCall(() => service.resume(int.parse(handle)));
  @override
  Future<void> remove(String handle) =>
      _nativeCall(() => service.forget(int.parse(handle)));
  @override
  Future<void> delete(String handle) async {
    final task = await read(handle);
    for (final file in task.files) {
      await checkedDownloadPath(task.output.path, file.location.path);
    }
    await _nativeCall(() => service.delete(int.parse(handle)));
  }

  @override
  Future<void> deleteFiles(String handle, List<int> indices) async {
    final task = await read(handle);
    final targets = <File>[];
    for (final index in indices) {
      if (index < 0 || index >= task.files.length) {
        throw const Failure(FailureCode.invalidInput,
            'File indices must be manifest indices.');
      }
      final file = task.files[index];
      if (!file.location.isLocal) {
        throw const Failure(
            FailureCode.invalidInput, 'Only local files can be deleted.');
      }
      final path =
          await checkedDownloadPath(task.output.path, file.location.path);
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.directory) {
        throw const Failure(
            FailureCode.invalidInput, 'A directory is not a download file.');
      }
      targets.add(File(path));
    }
    for (final file in targets) {
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<int?> readSize(DownloadFile file) async {
    final local = File(file.location.path);
    return await local.exists() ? await local.length() : null;
  }

  DownloadSnapshot _snapshot(TorrentTask task,
          {String? resolvedOutput,
          List<int> progress = const [],
          JsonMap? health,
          JsonMap? disk}) =>
      DownloadSnapshot(
        handle: task.id.toString(),
        infoHash: task.infoHash.toLowerCase(),
        title: task.name,
        output: DownloadLocation(
            path: resolvedOutput ?? task.outputFolder, isLocal: true),
        libraryKey: task.autoScanKey,
        state: task.state,
        downloadSpeedBytesPerSecond: task.downloadSpeedBytesPerSecond,
        uploadSpeedBytesPerSecond: task.uploadSpeedBytesPerSecond,
        completed: task.progressBytes,
        total: task.totalBytes,
        finished: task.finished,
        paused: task.isPaused,
        health: health,
        disk: disk,
        error: task.hasError
            ? task.error ?? 'Torrent backend reported an error.'
            : null,
        files: [
          for (final file in task.files)
            DownloadFile(
              location: DownloadLocation(
                  path: p.normalize(p.join(
                      resolvedOutput ?? task.outputFolder, file.displayName)),
                  isLocal: true),
              expectedSize: file.length,
              completedBytes:
                  file.index < progress.length ? progress[file.index] : null,
              isVideo: file.isVideo,
              included: file.included,
            )
        ],
      );

  Future<T> _nativeCall<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AnyhowException catch (error) {
      throw Failure(FailureCode.unavailable, error.toString(), retryable: true);
    } on String catch (error) {
      throw Failure(FailureCode.unavailable, error, retryable: true);
    }
  }
}

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show AnyhowException;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:path/path.dart' as p;

import 'download_backend.dart';
import 'download_paths.dart';

final class BuiltinDownloadBackend implements DownloadBackend {
  BuiltinDownloadBackend(this.service);
  final TorrentDownloadService service;
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
        return _snapshot(await service.getTaskDetails(task),
            resolvedOutput: output);
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
                  stopRequested: stopRequested,
                  downloadDirectory: request.downloadDirectory,
                  createFolderForTask: request.createFolderForTask)
              : await service.addTorrentFile(request.source,
                  downloadDirectory: request.downloadDirectory,
                  createFolderForTask: request.createFolderForTask));
      return read(result.id.toString());
    } on StateError {
      if (stopped) throw const DownloadAddStopped();
      rethrow;
    }
  }

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
  Future<int?> readSize(DownloadFile file) async {
    final local = File(file.location.path);
    return await local.exists() ? await local.length() : null;
  }

  DownloadSnapshot _snapshot(TorrentTask task, {String? resolvedOutput}) =>
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

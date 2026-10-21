import 'dart:async';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/downloads/download_backend.dart';

const testHash = '0123456789abcdef0123456789abcdef01234567';
const testRequest = DownloadRequest(
    source: 'magnet:?xt=urn:btih:$testHash',
    infoHash: testHash,
    title: 'Episode');

final class FakeDownloadBackend
    implements
        DownloadBackend,
        SelectableDownloadBackend,
        FileDeletingDownloadBackend {
  FakeDownloadBackend(this.root,
      {this.reference = const DownloadBackendRef.builtin()});
  final Directory root;
  @override
  final DownloadBackendRef reference;
  @override
  String? get credentialRef => 'credential:test-reference';
  bool present = false,
      finished = false,
      paused = false,
      online = true,
      local = true;
  int additions = 0,
      pauses = 0,
      resumes = 0,
      removals = 0,
      deletions = 0,
      initializations = 0;
  int completed = 0, total = 4;
  String handle = '1';
  String? error;
  List<DownloadFile>? overrideFiles;
  JsonMap? health;
  final addEntered = Completer<void>();
  Future<void>? addGate;
  bool stopAddBeforeCommit = false;
  Future<void> Function(DownloadFile)? onReadSize;
  void _online() {
    if (!online) {
      throw const Failure(FailureCode.unavailable, 'offline', retryable: true);
    }
  }

  DownloadFile get video => DownloadFile(
      location:
          DownloadLocation(path: '${root.path}/episode.mkv', isLocal: local),
      expectedSize: total,
      isVideo: true);
  DownloadSnapshot get snapshot => DownloadSnapshot(
      handle: handle,
      infoHash: testHash,
      title: 'Episode',
      output: DownloadLocation(path: root.path, isLocal: local),
      completed: completed,
      total: total,
      finished: finished,
      paused: paused,
      error: error,
      health: health,
      files: overrideFiles ?? [video]);
  Future<void> finish({int size = 4}) async {
    await File(video.location.path).writeAsBytes(List.filled(size, 1));
    finished = true;
    completed = total;
  }

  @override
  Future<void> initialize() async {
    _online();
    initializations++;
  }

  @override
  Future<List<DownloadSnapshot>> list() async {
    _online();
    return present ? [snapshot] : [];
  }

  @override
  Future<DownloadSnapshot> read(String handle) async {
    _online();
    if (!present || this.handle != handle) {
      throw const Failure(FailureCode.notFound, 'missing handle');
    }
    return snapshot;
  }

  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
      {Future<void>? stopRequested}) async {
    _online();
    if (!addEntered.isCompleted) addEntered.complete();
    if (stopAddBeforeCommit) {
      await stopRequested;
      throw const DownloadAddStopped();
    }
    await addGate;
    additions++;
    present = true;
    return snapshot;
  }

  @override
  Future<void> selectFiles(String handle, List<int> indices) async {
    _online();
    overrideFiles = [
      for (final entry in snapshot.files.indexed)
        DownloadFile(
            location: entry.$2.location,
            expectedSize: entry.$2.expectedSize,
            isVideo: entry.$2.isVideo,
            completedBytes: entry.$2.completedBytes,
            included: indices.contains(entry.$1))
    ];
  }

  /// Index lists of every [deleteFiles] call, in order.
  final fileDeletions = <List<int>>[];
  @override
  Future<void> deleteFiles(String handle, List<int> indices) async {
    _online();
    fileDeletions.add(List.of(indices));
    for (final index in indices) {
      final localFile = File(snapshot.files[index].location.path);
      if (await localFile.exists()) await localFile.delete();
    }
  }

  @override
  Future<void> pause(String handle) async {
    _online();
    if (paused) throw 'already paused';
    pauses++;
    paused = true;
  }

  @override
  Future<void> resume(String handle) async {
    _online();
    if (!paused && error == null) throw 'already running';
    resumes++;
    paused = false;
    error = null;
  }

  @override
  Future<void> remove(String handle) async {
    _online();
    if (!present) throw 'missing session';
    removals++;
    present = false;
  }

  @override
  Future<void> delete(String handle) async {
    _online();
    if (!present) throw 'missing session';
    deletions++;
    present = false;
    for (final file in snapshot.files) {
      final localFile = File(file.location.path);
      if (await localFile.exists()) await localFile.delete();
    }
  }

  @override
  Future<int?> readSize(DownloadFile file) async {
    _online();
    await onReadSize?.call(file);
    final localFile = File(file.location.path);
    return await localFile.exists() ? await localFile.length() : null;
  }
}

final class FakeDownloadLibrary implements DownloadLibrary {
  bool autoImport = true,
      busy = false,
      identify = true,
      acknowledgeOnly = false;
  final media = <String, JsonMap>{};
  final importedKeys = <String>{};
  final scans = <List<String>>[];
  Future<void> Function(List<String>)? onImport;
  @override
  Future<bool> get enabled async => autoImport;
  @override
  bool get isBusy => busy;
  @override
  Future<bool> wasImported(String key) async => importedKeys.contains(key);
  final lookups = <String>[];
  @override
  Future<JsonMap?> lookup(String path) async {
    lookups.add(path);
    return media[path];
  }
  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    scans.add(List.of(paths));
    await onImport?.call(paths);
    if (identify && !acknowledgeOnly) {
      for (final path in paths) {
        media[path] = {'path': path, 'animeId': 1, 'episodeId': 2};
      }
    }
    return identify;
  }

  @override
  Future<void> markImported(String key) async {
    importedKeys.add(key);
  }
}

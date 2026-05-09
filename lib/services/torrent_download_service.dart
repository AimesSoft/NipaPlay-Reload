import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/src/rust/api/torrent.dart' as rust_torrent;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as p;

class TorrentDownloadService {
  TorrentDownloadService._();

  static final TorrentDownloadService instance = TorrentDownloadService._();

  bool _sessionInitialized = false;
  String _sessionDownloadDir = '';

  Future<String> getDownloadDirectory() async {
    final saved = await SettingsStorage.loadString(
      SettingsKeys.torrentDownloadDirectory,
    );
    if (saved.trim().isNotEmpty) {
      return _resolveDownloadDirectoryAccess(saved.trim());
    }
    final defaultDir = await StorageService.getDownloadsDirectory();
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      defaultDir.path,
    );
    return defaultDir.path;
  }

  Future<void> setDownloadDirectory(String directory) async {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) return;
    final resolved = await _resolveDownloadDirectoryAccess(trimmed);
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      resolved,
    );
    _sessionDownloadDir = resolved;
  }

  Future<void> initialize() async {
    await _initSession(await getDownloadDirectory());
  }

  Future<List<TorrentTask>> listTasks() async {
    final downloadDir = await getDownloadDirectory();
    await _initSession(downloadDir);
    final jsonText = await rust_torrent.torrentList(downloadDir: downloadDir);
    return TorrentTask.listFromJson(jsonText);
  }

  Future<TorrentTask> getTaskDetails(TorrentTask task) async {
    await ensureRustInitialized();
    final jsonText = await rust_torrent.torrentDetails(id: task.id);
    final details = TorrentTask.detailsFromJson(jsonText);
    if (details == null) return task;
    return task.copyWith(files: details.files);
  }

  Future<List<TorrentTaskFile>> listPlayableFiles(TorrentTask task) async {
    final details = task.files.isNotEmpty ? task : await getTaskDetails(task);
    return details.files
        .where((file) => file.included && file.isVideo)
        .toList(growable: false);
  }

  Future<String> getStreamUrl(TorrentTask task, TorrentTaskFile file) async {
    await ensureRustInitialized();
    return rust_torrent.torrentStreamUrl(
      id: task.id,
      fileId: file.index,
      filename: file.fileName,
    );
  }

  Future<TorrentPlaybackSource> getPlaybackSource(
    TorrentTask task,
    TorrentTaskFile file,
  ) async {
    if (task.finished) {
      final localPath = await _findCompletedFilePath(task, file);
      if (localPath == null) {
        throw Exception('找不到已完成的视频文件: ${file.displayName}');
      }
      final historyItem = await _resolveCompletedFileHistory(localPath);
      _log('play completed file from disk: "$localPath"');
      return TorrentPlaybackSource(
        videoPath: localPath,
        historyItem: historyItem,
      );
    }

    final streamUrl = await getStreamUrl(task, file);
    _log('play unfinished file from stream: "$streamUrl"');
    return TorrentPlaybackSource(
      videoPath: streamUrl,
      actualPlayUrl: streamUrl,
    );
  }

  Future<void> addMagnet(String magnetUri) async {
    final downloadDir = await getDownloadDirectory();
    final createFolder = await _createFolderForTask();
    _log(
      'addMagnet start: ${_summarizeMagnetForLog(magnetUri)}, '
      'downloadDir="$downloadDir", createFolderForTask=$createFolder',
    );
    try {
      await _initSession(downloadDir);
      await rust_torrent.torrentAddMagnet(
        magnetUri: magnetUri,
        downloadDir: downloadDir,
        createFolderForTask: createFolder,
      );
      _log('addMagnet success: ${_summarizeMagnetForLog(magnetUri)}');
    } catch (error, stackTrace) {
      _log('addMagnet failed: $error');
      _log('addMagnet stackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<void> addTorrentFile(String torrentFilePath) async {
    final downloadDir = await getDownloadDirectory();
    final createFolder = await _createFolderForTask();
    _log(
      'addTorrentFile start: path="$torrentFilePath", '
      'downloadDir="$downloadDir", createFolderForTask=$createFolder',
    );
    try {
      await _initSession(downloadDir);
      await rust_torrent.torrentAddFile(
        torrentFilePath: torrentFilePath,
        downloadDir: downloadDir,
        createFolderForTask: createFolder,
      );
      _log('addTorrentFile success: path="$torrentFilePath"');
    } catch (error, stackTrace) {
      _log('addTorrentFile failed: $error');
      _log('addTorrentFile stackTrace: $stackTrace');
      rethrow;
    }
  }

  Future<void> pause(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentPause(id: id);
  }

  Future<void> resume(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentResume(id: id);
  }

  Future<void> forget(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentForget(id: id);
  }

  Future<void> delete(int id) async {
    await ensureRustInitialized();
    await rust_torrent.torrentDelete(id: id);
  }

  Future<void> _initSession(String downloadDir) async {
    if (_sessionInitialized && _sessionDownloadDir == downloadDir) {
      _log('initSession skipped: already initialized for "$downloadDir"');
      return;
    }
    _log(
      'initSession start: downloadDir="$downloadDir", '
      'previousDir="$_sessionDownloadDir", initialized=$_sessionInitialized',
    );
    await ensureRustInitialized();
    await rust_torrent.torrentInitSession(downloadDir: downloadDir);
    _sessionInitialized = true;
    _sessionDownloadDir = downloadDir;
    _log('initSession success: downloadDir="$downloadDir"');
  }

  Future<bool> _createFolderForTask() {
    return SettingsStorage.loadBool(
      SettingsKeys.downloaderCreateFolderForTask,
      defaultValue: true,
    );
  }

  Future<String?> _findCompletedFilePath(
    TorrentTask task,
    TorrentTaskFile file,
  ) async {
    final outputFolder = task.outputFolder.trim();
    if (outputFolder.isEmpty) return null;

    final resolvedOutputFolder =
        await _resolveDownloadDirectoryAccess(outputFolder);
    final candidates = <String>{
      p.normalize(p.join(resolvedOutputFolder, file.displayName)),
      p.normalize(p.join(resolvedOutputFolder, file.fileName)),
      p.normalize(p.join(resolvedOutputFolder, task.name)),
    };

    for (final candidate in candidates) {
      if (await io.File(candidate).exists()) {
        return candidate;
      }
    }

    final found = await _findFileByNameAndSize(
      resolvedOutputFolder,
      file.fileName,
      file.length,
    );
    if (found != null) return found;

    _log(
      'completed file not found: task="${task.name}", file="${file.displayName}", '
      'outputFolder="$resolvedOutputFolder", candidates=$candidates',
    );
    return null;
  }

  Future<WatchHistoryItem> _resolveCompletedFileHistory(String filePath) async {
    final existing = await WatchHistoryManager.getHistoryItem(filePath);
    if (existing != null) {
      _log(
        'play completed file with existing history: '
        '"${existing.animeName}" / "${existing.episodeTitle ?? ''}"',
      );
      return existing;
    }

    final fallback = WatchHistoryItem(
      filePath: filePath,
      animeName: p.basenameWithoutExtension(filePath),
      episodeTitle: null,
      watchProgress: 0,
      lastPosition: 0,
      duration: 0,
      lastWatchTime: DateTime.now(),
      isFromScan: false,
    );
    await WatchHistoryManager.addOrUpdateHistory(fallback);
    _log(
      'created fallback history before scraping completed file: "$filePath"',
    );
    return fallback;
  }

  Future<String?> _findFileByNameAndSize(
    String folder,
    String fileName,
    int expectedLength,
  ) async {
    final directory = io.Directory(folder);
    if (!await directory.exists()) return null;

    await for (final entity in directory.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! io.File || p.basename(entity.path) != fileName) {
        continue;
      }
      if (expectedLength <= 0 || await entity.length() == expectedLength) {
        return entity.path;
      }
    }

    return null;
  }

  Future<String> _resolveDownloadDirectoryAccess(String directory) async {
    if (!io.Platform.isMacOS) return directory;

    try {
      final resolved = await SecurityBookmarkService.resolveBookmark(directory);
      if (resolved != null && resolved.trim().isNotEmpty) {
        if (resolved != directory) {
          _log(
            'download directory bookmark resolved: "$directory" -> "$resolved"',
          );
        } else {
          _log('download directory bookmark restored: "$directory"');
        }
        return resolved;
      }

      _log(
          'download directory has no bookmark, using path directly: "$directory"');
    } catch (error) {
      _log('download directory bookmark restore failed: "$directory", $error');
    }

    return directory;
  }

  Future<Set<String>> loadAutoScannedCompletedTaskKeys() async {
    final keys = await SettingsStorage.loadStringList(
      SettingsKeys.downloaderAutoScannedCompletedTaskKeys,
    );
    return keys.toSet();
  }

  Future<void> markAutoScannedCompletedTask(String key) async {
    final trimmed = key.trim();
    if (trimmed.isEmpty) return;
    final keys = await loadAutoScannedCompletedTaskKeys();
    keys.add(trimmed);
    await SettingsStorage.saveStringList(
      SettingsKeys.downloaderAutoScannedCompletedTaskKeys,
      keys.toList(growable: false),
    );
  }

  void _log(String message) {
    debugPrint('[TorrentDownloadService] $message');
  }

  String _summarizeMagnetForLog(String magnetUri) {
    final trimmed = magnetUri.trim();
    final hasOuterWhitespace = trimmed.length != magnetUri.length;
    final hasInnerWhitespace = trimmed.runes.any((rune) {
      return String.fromCharCode(rune).trim().isEmpty;
    });
    final buffer = StringBuffer()
      ..write('length=${trimmed.length}')
      ..write(', startsWithMagnet=${trimmed.startsWith('magnet:')}')
      ..write(
        ', startsWithMagnetCi=${trimmed.toLowerCase().startsWith('magnet:')}',
      )
      ..write(', hasOuterWhitespace=$hasOuterWhitespace')
      ..write(', hasInnerWhitespace=$hasInnerWhitespace');

    try {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) {
        buffer.write(', uriParse=null');
        return buffer.toString();
      }

      final xtValues = uri.queryParametersAll['xt'] ?? const <String>[];
      final dn = uri.queryParameters['dn'];
      final trackerCount = uri.queryParametersAll['tr']?.length ?? 0;
      buffer
        ..write(', scheme=${uri.scheme.isEmpty ? '<empty>' : uri.scheme}')
        ..write(', xt=${xtValues.map(_truncateForLog).join('|')}')
        ..write(', dn=${dn == null ? '<none>' : _truncateForLog(dn)}')
        ..write(', trackerCount=$trackerCount');
    } catch (error) {
      buffer.write(', uriParseError=$error');
    }

    return buffer.toString();
  }

  String _truncateForLog(String value, {int maxLength = 96}) {
    if (value.length <= maxLength) return value;
    return '${value.substring(0, maxLength)}...';
  }
}

class TorrentPlaybackSource {
  const TorrentPlaybackSource({
    required this.videoPath,
    this.actualPlayUrl,
    this.historyItem,
  });

  final String videoPath;
  final String? actualPlayUrl;
  final WatchHistoryItem? historyItem;
}

import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/torrent_magnet_preview.dart';
import 'package:nipaplay/models/torrent_task.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/src/rust/api/torrent.dart' as rust_torrent;
import 'package:nipaplay/src/rust/rust_init.dart';
import 'package:nipaplay/utils/settings_storage.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:path/path.dart' as p;

class TorrentDownloadService {
  TorrentDownloadService._({
    bool Function()? isIos,
    Future<io.Directory> Function()? getDownloadsDirectory,
    Future<bool> Function(String path)? directoryExists,
  })  : _isIos = isIos ?? (() => io.Platform.isIOS),
        _getDownloadsDirectory =
            getDownloadsDirectory ?? StorageService.getDownloadsDirectory,
        _directoryExists =
            directoryExists ?? ((path) => io.Directory(path).exists());

  static final TorrentDownloadService instance = TorrentDownloadService._();

  @visibleForTesting
  factory TorrentDownloadService.forTesting({
    required bool Function() isIos,
    required Future<io.Directory> Function() getDownloadsDirectory,
    required Future<bool> Function(String path) directoryExists,
  }) {
    return TorrentDownloadService._(
      isIos: isIos,
      getDownloadsDirectory: getDownloadsDirectory,
      directoryExists: directoryExists,
    );
  }

  static const int _maxRecentDownloadDirectories = 8;

  final bool Function() _isIos;
  final Future<io.Directory> Function() _getDownloadsDirectory;
  final Future<bool> Function(String path) _directoryExists;

  bool _sessionInitialized = false;
  String _sessionDownloadDir = '';

  Future<String> getDownloadDirectory() async {
    final saved = await SettingsStorage.loadString(
      SettingsKeys.torrentDownloadDirectory,
    );
    if (saved.trim().isNotEmpty) {
      final savedDirectory = saved.trim();
      final resolved = await _resolveDownloadDirectoryAccess(savedDirectory);
      if (!_isIos() || await _directoryExists(resolved)) {
        return resolved;
      }

      return _recoverInvalidIosDownloadDirectory(
        savedDirectory: savedDirectory,
        resolvedDirectory: resolved,
      );
    }
    final defaultDir = await _getDownloadsDirectory();
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      defaultDir.path,
    );
    return defaultDir.path;
  }

  Future<String> _recoverInvalidIosDownloadDirectory({
    required String savedDirectory,
    required String resolvedDirectory,
  }) async {
    final defaultDirectory = await _getDownloadsDirectory();
    final defaultPath = defaultDirectory.path;
    _log(
      'saved iOS download directory no longer exists; '
      'recovering from "$savedDirectory" to "$defaultPath"',
    );

    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      defaultPath,
    );

    final invalidDirectories = <String>{
      savedDirectory,
      resolvedDirectory,
    };
    final recentDirectories = await SettingsStorage.loadStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
    );
    final updatedRecentDirectories = <String>[
      defaultPath,
      ...recentDirectories.where(
        (directory) =>
            directory != defaultPath && !invalidDirectories.contains(directory),
      ),
    ].take(_maxRecentDownloadDirectories).toList(growable: false);
    await SettingsStorage.saveStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
      updatedRecentDirectories,
    );
    await SettingsStorage.saveBool(
      SettingsKeys.torrentRecentDownloadDirectoriesMigrated,
      true,
    );

    return defaultPath;
  }

  Future<void> setDownloadDirectory(String directory) async {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) return;
    final resolved = await _resolveDownloadDirectoryAccess(trimmed);
    await SettingsStorage.saveString(
      SettingsKeys.torrentDownloadDirectory,
      resolved,
    );
    await rememberRecentDownloadDirectory(resolved);
    _sessionDownloadDir = resolved;
  }

  Future<List<String>> loadRecentDownloadDirectories() async {
    await _migrateRecentDownloadDirectoriesIfNeeded();
    final saved = await SettingsStorage.loadStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
    );
    return _normalizeRecentDirectories(saved);
  }

  Future<void> rememberRecentDownloadDirectory(String directory) async {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) return;
    final existing = await loadRecentDownloadDirectories();
    final updated = <String>[
      trimmed,
      ...existing.where((value) => value != trimmed),
    ].take(_maxRecentDownloadDirectories).toList(growable: false);
    await SettingsStorage.saveStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
      updated,
    );
  }

  Future<void> removeRecentDownloadDirectory(String directory) async {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) return;
    final existing = await loadRecentDownloadDirectories();
    final updated = existing.where((value) => value != trimmed).toList();
    await SettingsStorage.saveStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
      updated,
    );
  }

  Future<void> _migrateRecentDownloadDirectoriesIfNeeded() async {
    final migrated = await SettingsStorage.loadBool(
      SettingsKeys.torrentRecentDownloadDirectoriesMigrated,
    );
    if (migrated) return;

    final saved = await SettingsStorage.loadString(
      SettingsKeys.torrentDownloadDirectory,
    );
    final initial = saved.trim().isEmpty ? <String>[] : <String>[saved.trim()];
    await SettingsStorage.saveStringList(
      SettingsKeys.torrentRecentDownloadDirectories,
      initial,
    );
    await SettingsStorage.saveBool(
      SettingsKeys.torrentRecentDownloadDirectoriesMigrated,
      true,
    );
  }

  List<String> _normalizeRecentDirectories(List<String> directories) {
    final normalized = <String>[];
    for (final directory in directories) {
      final trimmed = directory.trim();
      if (trimmed.isEmpty || normalized.contains(trimmed)) continue;
      normalized.add(trimmed);
      if (normalized.length >= _maxRecentDownloadDirectories) break;
    }
    return normalized;
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

  Future<List<WatchHistoryItem>> listCompletedFileScanHistoryItems(
    TorrentTask task,
  ) async {
    if (!task.finished) return const <WatchHistoryItem>[];

    final playableFiles = await listPlayableFiles(task);
    final historyItems = <WatchHistoryItem>[];
    for (final file in playableFiles) {
      final filePath = await _findCompletedFilePath(task, file);
      if (filePath == null) continue;

      final historyItem = await WatchHistoryManager.getHistoryItem(filePath);
      if (historyItem != null) {
        historyItems.add(historyItem);
      }
    }
    return historyItems;
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

  Future<TorrentMagnetPreview> previewMagnet(
    String magnetUri, {
    String? downloadDirectory,
  }) async {
    final downloadDir = await _resolveDownloadDirectoryForAction(
      downloadDirectory,
    );
    await _initSession(downloadDir);
    final jsonText = await rust_torrent.torrentPreviewMagnet(
      magnetUri: magnetUri,
      downloadDir: downloadDir,
    );
    return TorrentMagnetPreview.fromJson(jsonText);
  }

  Future<void> addMagnet(
    String magnetUri, {
    String? downloadDirectory,
    bool? createFolderForTask,
  }) async {
    final downloadDir = await _resolveDownloadDirectoryForAction(
      downloadDirectory,
    );
    final createFolder = createFolderForTask ?? await _createFolderForTask();
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

  Future<void> addTorrentFile(
    String torrentFilePath, {
    String? downloadDirectory,
    bool? createFolderForTask,
  }) async {
    final downloadDir = await _resolveDownloadDirectoryForAction(
      downloadDirectory,
    );
    final createFolder = createFolderForTask ?? await _createFolderForTask();
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
      return;
    }
    await ensureRustInitialized();
    await rust_torrent.torrentInitSession(downloadDir: downloadDir);
    _sessionInitialized = true;
    _sessionDownloadDir = downloadDir;
  }

  Future<String> _resolveDownloadDirectoryForAction(String? directory) async {
    final trimmed = directory?.trim() ?? '';
    if (trimmed.isEmpty) {
      return getDownloadDirectory();
    }
    return _resolveDownloadDirectoryAccess(trimmed);
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
        return resolved;
      }
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

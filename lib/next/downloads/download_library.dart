import 'dart:async';
import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/classic_mode_policy.dart';
import 'package:nipaplay/services/scan_service.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';

import 'download_backend.dart';
import 'indexed_download_library.dart';
import '../media/media_service.dart';

final class AppDownloadLibrary implements DownloadLibrary {
  AppDownloadLibrary(this.service,
      {MediaService Function()? media,
      ScanService? scanner,
      Future<WatchHistoryItem?> Function(String)? readClassic,
      Future<void> Function()? refreshClassic})
      : _media = media ?? (() => ServiceProvider.nextCore.media.service),
        _scanner = scanner ?? ServiceProvider.scanService,
        _readClassic = readClassic ?? WatchHistoryManager.getHistoryItem,
        _refreshClassic =
            refreshClassic ?? ServiceProvider.watchHistoryProvider.refresh;
  final TorrentDownloadService service;
  final MediaService Function() _media;
  final ScanService _scanner;
  final Future<WatchHistoryItem?> Function(String) _readClassic;
  final Future<void> Function() _refreshClassic;
  late final _indexed = IndexedDownloadLibrary.lazy(_media);
  Future<bool> _classicMode() => ClassicModePolicy.allowsImplicitWork();

  @override
  Future<bool> get enabled async =>
      !await _classicMode() ||
      await SettingsStorage.loadBool(
          SettingsKeys.downloaderAutoScanCompletedTasks,
          defaultValue: true);
  @override
  bool get isBusy => ClassicModePolicy.classicActive && _scanner.isScanning;
  @override
  Future<bool> wasImported(String key) async => await _classicMode()
      ? (await service.loadAutoScannedCompletedTaskKeys()).contains(key)
      : _indexed.wasImported(key);
  @override
  Future<JsonMap?> lookup(String path) async {
    if (!await _classicMode()) return _indexed.lookup(path);
    final media = _media();
    final fileId = await media
        .mutate(() => media.store.ensureFile(path, via: 'download_import'));
    return _entry(path, fileId);
  }

  @override
  Future<JsonMap?> registered(String path) async {
    if (!await _classicMode()) return _indexed.registered(path);
    final fileId = await _media().store.registeredFileId(path);
    return fileId == null ? null : _entry(path, fileId);
  }

  Future<JsonMap> _entry(String path, String fileId) async {
    final media = _media();
    final links = await media.store.database.rawQuery(
        'SELECT DISTINCT r.parent_id AS workId, e.id AS episodeId, '
        'e.attributes AS episodeFacts FROM media_file_episodes fe '
        'JOIN media_entities e ON e.id=fe.episode_id '
        'JOIN media_entities r ON r.id=e.parent_id WHERE fe.file_id=?',
        [fileId]);
    final sources = await media.store.linkSources(fileId);
    final item = await _readClassic(path);
    if (item == null || item.animeId == null || item.episodeId == null) {
      return {
        'path': path,
        'fileId': fileId,
        'workIds': {for (final row in links) row['workId']}.toList(),
        'episodes': [
          for (final row in links)
            {
              'episodeId': row['episodeId'],
              'workId': row['workId'],
              'facts': jsonDecode(row['episodeFacts'] as String),
              'identitySources': sources[row['episodeId']] ?? <JsonMap>[]
            }
        ],
        'identificationPending': links.isEmpty,
        'classicScanPending': item == null
      };
    }
    return {
      'path': item.filePath,
      'fileId': fileId,
      'workIds': {for (final row in links) row['workId']}.toList(),
      'episodes': [
        for (final row in links)
          {
            'episodeId': row['episodeId'],
            'workId': row['workId'],
            'facts': jsonDecode(row['episodeFacts'] as String),
            'identitySources': sources[row['episodeId']] ?? <JsonMap>[]
          }
      ],
      'identificationPending': links.isEmpty,
      'animeId': item.animeId,
      'episodeId': item.episodeId,
      'animeName': item.animeName,
      'episodeTitle': item.episodeTitle
    };
  }

  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    if (!await _classicMode()) {
      return _indexed.importFiles(paths, outputDirectory);
    }
    final success =
        await _scanner.scanCompletedFiles(paths, folderPath: outputDirectory);
    await _refreshClassic();
    return success;
  }

  Future<void> _registryUpdates = Future.value();
  @override
  Future<void> markImported(String key) async {
    if (!await _classicMode()) return _indexed.markImported(key);
    final previous = _registryUpdates;
    final done = Completer<void>();
    _registryUpdates = done.future;
    await previous;
    try {
      if (await _classicMode()) {
        await service.markAutoScannedCompletedTask(key);
      } else {
        await _indexed.markImported(key);
      }
    } finally {
      done.complete();
    }
  }
}

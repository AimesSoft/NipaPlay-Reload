import 'dart:async';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/torrent_download_service.dart';
import 'package:nipaplay/utils/settings_storage.dart';

import 'download_backend.dart';

final class AppDownloadLibrary implements DownloadLibrary {
  AppDownloadLibrary(this.service);
  final TorrentDownloadService service;
  @override
  Future<bool> get enabled =>
      SettingsStorage.loadBool(SettingsKeys.downloaderAutoScanCompletedTasks,
          defaultValue: true);
  @override
  bool get isBusy => ServiceProvider.scanService.isScanning;
  @override
  Future<bool> wasImported(String key) async =>
      (await service.loadAutoScannedCompletedTaskKeys()).contains(key);
  @override
  Future<JsonMap?> lookup(String path) async {
    final item = await WatchHistoryManager.getHistoryItem(path);
    if (item == null || item.animeId == null || item.episodeId == null) {
      return null;
    }
    return {
      'path': item.filePath,
      'animeId': item.animeId,
      'episodeId': item.episodeId,
      'animeName': item.animeName,
      'episodeTitle': item.episodeTitle
    };
  }

  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    final success = await ServiceProvider.scanService
        .scanCompletedFiles(paths, folderPath: outputDirectory);
    await ServiceProvider.watchHistoryProvider.refresh();
    return success;
  }

  Future<void> _registryUpdates = Future.value();
  @override
  Future<void> markImported(String key) async {
    final previous = _registryUpdates;
    final done = Completer<void>();
    _registryUpdates = done.future;
    await previous;
    try {
      await service.markAutoScannedCompletedTask(key);
    } finally {
      done.complete();
    }
  }
}

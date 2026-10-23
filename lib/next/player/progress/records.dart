import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/service_provider.dart';
import 'package:nipaplay/services/playback_position_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where resume positions and watch records are kept: the same store and
/// table Classic uses (D3).
abstract interface class PlaybackRecords {
  /// The watch record of [path] (or of the same media under another path).
  Future<WatchHistoryItem?> record(String path);

  /// Where [path] was left, in ms; 0 when it starts from the beginning.
  Future<int> resumeAt(String path);
  Future<void> savePosition(String path, int ms);

  /// Writes [item]. [publish]: the in-memory history (continue watching,
  /// Next's library) learns of it too; only when a session opens or
  /// closes, never while it plays.
  Future<void> saveRecord(WatchHistoryItem item, {bool publish = false});
}

/// Must stay top-level: the worker isolate gets the table and a path only.
int _positionIn((String, String) request) {
  final (table, path) = request;
  final value = (json.decode(table) as Map)[path];
  return value is num ? value.toInt() : 0;
}

/// [PlaybackRecords] over Classic's [PlaybackPositionStore] (its encoding
/// already off the main isolate) and its watch history database (sqflite
/// on its own isolate). Reading a position decodes the whole table, so
/// that runs on a worker isolate too.
final class SharedPlaybackRecords implements PlaybackRecords {
  const SharedPlaybackRecords();

  @override
  Future<WatchHistoryItem?> record(String path) =>
      WatchHistoryDatabase.instance.getHistoryByFilePath(path);

  @override
  Future<int> resumeAt(String path) async {
    await PlaybackPositionStore.instance.flush();
    final table =
        (await SharedPreferences.getInstance()).getString('video_positions');
    if (table == null || table.isEmpty) return 0;
    return compute(_positionIn, (table, path),
        debugLabel: 'nipaplay.playback_position.read');
  }

  @override
  Future<void> savePosition(String path, int ms) =>
      PlaybackPositionStore.instance.save(path, ms);

  @override
  Future<void> saveRecord(WatchHistoryItem item, {bool publish = false}) =>
      publish
          ? ServiceProvider.watchHistoryProvider.addOrUpdateHistory(item)
          : WatchHistoryDatabase.instance.insertOrUpdateWatchHistory(item);
}

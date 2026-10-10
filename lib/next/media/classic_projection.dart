import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/anime_deletion_tombstones.dart';

import 'identity_store.dart';

abstract interface class ClassicMetadataPort {
  Future<List<JsonMap>> history();
  Future<void> apply(String locator, JsonMap fields);
  Future<bool> verify(String locator, JsonMap fields);
}

final class WatchHistoryMetadataPort implements ClassicMetadataPort {
  const WatchHistoryMetadataPort({required this.changed});
  final Future<void> Function() changed;
  @override
  Future<List<JsonMap>> history() async {
    final history = WatchHistoryDatabase.instance;
    await history.migrateFromJson();
    return [
      for (final item in await history.getAllWatchHistory()) item.toJson()
    ];
  }

  @override
  Future<void> apply(String locator, JsonMap fields) async {
    final history = WatchHistoryDatabase.instance;
    if (fields['clear'] == true) {
      final current = await history.getHistoryByFilePath(locator);
      if (current != null &&
          fields['expectedAnimeId'] != null &&
          (current.animeId != fields['expectedAnimeId'] ||
              current.episodeId != fields['expectedEpisodeId'])) {
        throw const Failure(FailureCode.conflict,
            'Classic was rematched since this projection was queued.');
      }
      if (current != null) await history.clearMatchInfoForFile(current);
    } else {
      if ((await AnimeDeletionTombstones.deletedAnimeIds())
          .contains(fields['animeId'])) {
        throw const Failure(FailureCode.conflict,
            'Classic anime was deleted; restore it before projecting matching fields.');
      }
      final db = await history.database;
      final matching = {
        'anime_id': fields['animeId'],
        'episode_id': fields['episodeId'],
        'anime_name': fields['animeName'],
        'episode_title': fields['episodeTitle']
      };
      final changed = await db.update('watch_history', matching,
          where: 'file_path = ?', whereArgs: [locator]);
      if (changed == 0) {
        await history.mergeEpisodeMatchBatch([
          EpisodeMatchRestoreItem(
              filePath: locator,
              animeId: fields['animeId'] as int,
              episodeId: fields['episodeId'] as int,
              animeName: fields['animeName'] as String,
              episodeTitle: fields['episodeTitle'] as String)
        ]);
        await db.update('watch_history', matching,
            where: 'file_path = ? AND anime_id = ? AND episode_id = ?',
            whereArgs: [locator, fields['animeId'], fields['episodeId']]);
      }
    }
    await changed();
  }

  @override
  Future<bool> verify(String locator, JsonMap fields) async {
    final current =
        await WatchHistoryDatabase.instance.getHistoryByFilePath(locator);
    if (fields['clear'] == true) {
      return current == null ||
          (current.animeName.isEmpty && current.episodeTitle == null);
    }
    return current != null &&
        current.animeId == fields['animeId'] &&
        current.episodeId == fields['episodeId'] &&
        current.animeName == fields['animeName'] &&
        current.episodeTitle == fields['episodeTitle'];
  }
}

final class ClassicProjection {
  const ClassicProjection(this.store, this.port);
  final IdentityStore store;
  final ClassicMetadataPort port;
  Future<void> drain({String? fileId}) async {
    for (final row in await store.pendingProjections(fileId: fileId)) {
      final file = await store.entity(row['file_id'] as String);
      if (file['revision'] != row['file_revision'] ||
          (file['attributes'] as JsonMap)['bindingRevision'] !=
              row['binding_revision']) {
        await store.finishProjection(row['id'] as String, 'superseded');
        continue;
      }
      final fields = decodeMediaJson(row['payload']);
      for (final location in await store.locations(row['file_id'] as String)) {
        await port.apply(location['locator'] as String, fields);
        if (!await port.verify(location['locator'] as String, fields)) {
          throw const Failure(FailureCode.unavailable,
              'Classic metadata projection failed readback.');
        }
      }
      await store.finishProjection(row['id'] as String, 'delivered');
    }
  }
}

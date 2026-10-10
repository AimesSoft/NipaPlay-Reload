import 'package:nipa_harness/nipa_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/anime_deletion_tombstones.dart';

import 'identity_store.dart';

abstract interface class ClassicMetadataPort {
  Future<List<JsonMap>> history();
  Future<void> apply(String locator, JsonMap fields);
  Future<bool> verify(String locator, JsonMap fields);
}

final class WatchHistoryMetadataPort implements ClassicMetadataPort {
  const WatchHistoryMetadataPort({required this.changed, this.historyChanges});
  final Future<void> Function() changed;
  final Listenable? historyChanges;
  @override
  Future<List<JsonMap>> history() async {
    final history = WatchHistoryDatabase.instance;
    await history.migrateFromJson();
    final db = await history.database;
    // Read failure must not be mistaken for an empty library.
    return [
      for (final row in await db.query('watch_history'))
        {
          'filePath': row['file_path'],
          'animeId': row['anime_id'],
          'episodeId': row['episode_id'],
          'animeName': row['anime_name'],
          'episodeTitle': row['episode_title'],
          'videoHash': null,
          'watchProgress': row['watch_progress'],
          'lastPosition': row['last_position'],
          'duration': row['duration'],
          'lastWatchTime': row['last_watch_time'],
          'thumbnailPath': row['thumbnail_path'],
          'isFromScan': row['is_from_scan'] == 1,
          'mediaKey': row['media_key'],
        }
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
      await db.transaction((tx) async {
        final rows = await tx
            .query('watch_history', where: 'file_path=?', whereArgs: [locator]);
        if (rows.isNotEmpty) {
          final current = rows.single;
          if (current['anime_name'] != '' &&
              current['episode_title'] != null &&
              current['anime_id'] != null &&
              current['episode_id'] != null) {
            if (current['anime_id'] != fields['animeId'] ||
                current['episode_id'] != fields['episodeId']) {
              throw const Failure(FailureCode.conflict,
                  'Classic has a different match; both source facts are retained.');
            }
            return;
          }
          await tx.update('watch_history', matching,
              where: 'file_path=?', whereArgs: [locator]);
        } else {
          await tx.insert('watch_history', {
            ...matching,
            'file_path': locator,
            'watch_progress': 0.0,
            'last_position': 0,
            'duration': 0,
            'last_watch_time': DateTime.now().toUtc().toIso8601String(),
            'is_from_scan': 1
          });
        }
      });
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
        current.animeName.isNotEmpty &&
        current.episodeTitle != null;
  }
}

final class ClassicProjection {
  const ClassicProjection(this.store, this.port);
  final IdentityStore store;
  final ClassicMetadataPort port;
  Future<void> drain({String? fileId}) async {
    await store.importLegacy(await port.history());
    for (final row in await store.pendingProjections(fileId: fileId)) {
      final file = await store.entity(row['file_id'] as String);
      if (file['revision'] != row['file_revision'] ||
          (file['attributes'] as JsonMap)['bindingRevision'] !=
              row['binding_revision']) {
        await store.finishProjection(row['id'] as String, 'superseded');
        continue;
      }
      final fields = decodeMediaJson(row['payload']);
      try {
        for (final location in (await store.locations(row['file_id'] as String))
            .where((location) =>
                location['owner_device_id'] == store.ownerDeviceId)) {
          final observations = await store
              .classicObservations(row['file_id'] as String, currentOnly: true);
          final atLocation =
              observations.where((o) => o['locationId'] == location['id']);
          final current =
              atLocation.isEmpty ? <String, Object?>{} : atLocation.single;
          if (current['animeName'] != null &&
              current['animeName'] != '' &&
              current['episodeTitle'] != null &&
              current['animeId'] != null &&
              current['episodeId'] != null &&
              (current['animeId'] !=
                      (fields['animeId'] ?? fields['expectedAnimeId']) ||
                  current['episodeId'] !=
                      (fields['episodeId'] ?? fields['expectedEpisodeId']))) {
            throw const Failure(FailureCode.conflict,
                'Classic has a different match; inspect media.identity.get conflicts.');
          }
          await port.apply(location['locator'] as String, fields);
          if (!await port.verify(location['locator'] as String, fields)) {
            throw const Failure(FailureCode.unavailable,
                'Classic metadata projection failed readback.');
          }
        }
        await store.finishProjection(row['id'] as String, 'delivered');
      } on Failure catch (error) {
        if (error.code == FailureCode.conflict) {
          await store.finishProjection(row['id'] as String, 'conflict');
        }
        rethrow;
      }
    }
    await store.importLegacy(await port.history());
  }
}

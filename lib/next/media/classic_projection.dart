import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/anime_deletion_tombstones.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/services/emby_episode_mapping_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'identity_store.dart';
import 'classic_metadata_port.dart';
import 'remote_classic_projection.dart';

export 'classic_metadata_port.dart';
export 'projection.dart';

const _matchingColumns = [
  'anime_id',
  'episode_id',
  'anime_name',
  'episode_title'
];
JsonMap _matching(JsonMap row) =>
    {for (final key in _matchingColumns) key: row[key]};
bool _sameMatching(JsonMap a, JsonMap b) =>
    _matchingColumns.every((key) => a[key] == b[key]);

final class WatchHistoryMetadataPort implements ReversibleClassicMetadataPort {
  const WatchHistoryMetadataPort({required this.changed, this.historyChanges});
  final Future<void> Function() changed;
  final Listenable? historyChanges;
  @override
  Future<List<JsonMap>> history() async {
    final history = WatchHistoryDatabase.instance;
    await history.migrateFromJson();
    final db = await history.database;
    final prefs = await SharedPreferences.getInstance();
    JsonMap? cachedMetadata(int? animeId) {
      if (animeId == null) return null;
      final saved = prefs.getString('bangumi_detail_$animeId');
      final cache = saved == null ? null : jsonDecode(saved) as Map;
      final anime = BangumiService.instance.getAnimeDetailsFromMemory(animeId);
      final detail = anime?.toJson() ?? cache?['animeDetail'] as Map?;
      if (detail == null) return null;
      final background =
          prefs.getString('bangumi_custom_background_$animeId') ??
              detail['backgroundImageUrl'];
      return {
        'language': switch (detail['language']) {
          'zh' => 'zh-CN',
          'zh_Hant' => 'zh-TW',
          final String language => language,
          _ => 'und'
        },
        'fetchedAt': cache?['timestamp'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(cache!['timestamp'] as int)
                .toUtc()
                .toIso8601String(),
        'fields': {
          if (detail['name_cn'] ?? detail['name'] case final String title)
            if (title.isNotEmpty) 'title': title,
          if (detail['name'] case final String title)
            if (title.isNotEmpty) 'originalTitle': title,
          if (detail['summary'] case final String summary)
            if (summary.isNotEmpty) 'overview': summary,
          if (detail['imageUrl'] case final String image)
            if (image.isNotEmpty) 'imageUrl': image,
          if (background is String && background.isNotEmpty)
            'artworkUrls': {'backdrop': background},
          if (detail['totalEpisodes'] case final int count)
            if (count > 0) 'episodeCount': count,
          if (detail['tags'] case final List tags)
            if (tags.isNotEmpty) 'genres': tags,
        }
      };
    }

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
          'classicMetadata': cachedMetadata(row['anime_id'] as int?),
        }
    ];
  }

  @override
  Future<void> apply(String locator, JsonMap fields) async {
    if (fields['clear'] != true && fields['projectionId'] is! String) {
      throw const Failure(FailureCode.invalidInput,
          'Classic projection requires a durable projectionId.');
    }
    final history = WatchHistoryDatabase.instance;
    if (fields['clear'] != true &&
        (await AnimeDeletionTombstones.deletedAnimeIds())
            .contains(fields['animeId'])) {
      throw const Failure(FailureCode.conflict,
          'Classic anime was deleted; restore it before projecting matching fields.');
    }
    final db = await history.database;
    if (fields['remoteTarget'] != null) {
      await RemoteClassicProjection(db).apply(locator, fields);
      JellyfinEpisodeMappingService.instance.invalidateCache();
      EmbyEpisodeMappingService.instance.invalidateCache();
      await changed();
      return;
    }
    if (locator.startsWith('jellyfin://') || locator.startsWith('emby://')) {
      throw const Failure(FailureCode.conflict,
          'Remote server ownership is unknown; browse its source and bind that fileId.');
    }
    var earlierProjectionChanged = false;
    await db.transaction((tx) async {
      // The undo evidence commits atomically with the Classic write.
      await tx.execute(
          '''CREATE TABLE IF NOT EXISTS next_classic_projection_journal (
          projection_id TEXT NOT NULL, file_path TEXT NOT NULL,
          before_fields TEXT NOT NULL, after_fields TEXT NOT NULL,
          row_existed INTEGER NOT NULL, row_id INTEGER NOT NULL, state TEXT NOT NULL,
          PRIMARY KEY (projection_id, file_path))''');
      final rows = await tx
          .query('watch_history', where: 'file_path=?', whereArgs: [locator]);
      final current = rows.isEmpty ? <String, Object?>{} : rows.single;
      final projectionId = fields['clear'] == true
          ? fields['restoreProjectionId']
          : fields['projectionId'];
      final journal = projectionId == null
          ? <JsonMap>[]
          : await tx.query('next_classic_projection_journal',
              where: 'projection_id=? AND file_path=?',
              whereArgs: [projectionId, locator]);
      if (fields['clear'] == true) {
        if (journal.isEmpty) {
          if (fields['journalVersion'] == 1) return;
          throw const Failure(FailureCode.conflict,
              'Classic not restored: this older projection has no atomic undo evidence.');
        }
        final entry = journal.single;
        if (entry['state'] == 'unchanged') return;
        final before = decodeMediaJson(entry['before_fields']);
        final expected = decodeMediaJson(entry[
            entry['state'] == 'restored' ? 'before_fields' : 'after_fields']);
        if (rows.isEmpty ||
            current['id'] != entry['row_id'] ||
            !_sameMatching(current, expected)) {
          throw const Failure(FailureCode.conflict,
              'Classic not restored: matching fields changed or the row was deleted after projection; Classic was left untouched.');
        }
        if (entry['state'] != 'restored') {
          await tx.update('watch_history', before,
              where: 'file_path=?', whereArgs: [locator]);
          await tx.update(
              'next_classic_projection_journal', {'state': 'restored'},
              where: 'projection_id=? AND file_path=?',
              whereArgs: [projectionId, locator]);
        }
        return;
      }
      if (journal.isNotEmpty) {
        if (journal.single['state'] == 'written' &&
            current['id'] == journal.single['row_id'] &&
            _sameMatching(
                current, decodeMediaJson(journal.single['after_fields']))) {
          return;
        }
        if (journal.single['state'] == 'unchanged' &&
            current['id'] == journal.single['row_id'] &&
            current['anime_id'] == fields['animeId'] &&
            current['episode_id'] == fields['episodeId']) {
          return;
        }
        throw const Failure(FailureCode.conflict,
            'Classic changed after this projection; Classic was left untouched.');
      }
      var before = rows.isEmpty
          ? <String, Object?>{
              'anime_id': null,
              'episode_id': null,
              'anime_name': p.basename(locator),
              'episode_title': null
            }
          : _matching(current);
      var matching = <String, Object?>{};
      var state = 'written';
      var rowId = current['id'] as int?;
      var rowExisted = rows.isNotEmpty;
      var needsWrite = true;
      final previous = fields['previousProjectionId'] == null
          ? <JsonMap>[]
          : await tx.query('next_classic_projection_journal',
              where: 'projection_id=? AND file_path=?',
              whereArgs: [fields['previousProjectionId'], locator]);
      if (previous.isNotEmpty &&
          previous.single['state'] == 'written' &&
          (previous.single['row_id'] != rowId ||
              !_sameMatching(
                  current, decodeMediaJson(previous.single['after_fields'])))) {
        await tx.insert('next_classic_projection_journal',
            {...previous.single, 'projection_id': projectionId});
        earlierProjectionChanged = true;
        return;
      }
      if (rows.isNotEmpty) {
        if (current['anime_name'] != '' &&
            current['episode_title'] != null &&
            current['anime_id'] != null &&
            current['episode_id'] != null) {
          if (current['anime_id'] != fields['animeId'] ||
              current['episode_id'] != fields['episodeId']) {
            throw const Failure(FailureCode.conflict,
                'Classic has a different match; both source facts are retained.');
          }
          matching = _matching(current);
          state = 'unchanged';
          needsWrite = false;
          if (previous.isNotEmpty && previous.single['state'] == 'written') {
            before = decodeMediaJson(previous.single['before_fields']);
            rowExisted = previous.single['row_existed'] == 1;
            state = 'written';
          }
        }
      }
      if (needsWrite) {
        String title(String field, String column) {
          final provided = fields[field] as String?;
          final original = current[column] as String?;
          final value = provided != null && provided.trim().isNotEmpty
              ? provided
              : original;
          if (value == null || value.trim().isEmpty) {
            throw Failure(FailureCode.conflict,
                'Classic projection needs a nonempty evidenced $field; Classic was left untouched.');
          }
          return value;
        }

        matching = {
          'anime_id': fields['animeId'],
          'episode_id': fields['episodeId'],
          'anime_name': title('animeName', 'anime_name'),
          'episode_title': title('episodeTitle', 'episode_title')
        };
        if (rows.isNotEmpty) {
          await tx.update('watch_history', matching,
              where: 'file_path=?', whereArgs: [locator]);
        } else {
          rowId = await tx.insert('watch_history', {
            ...matching,
            'file_path': locator,
            'watch_progress': 0.0,
            'last_position': 0,
            'duration': 0,
            'last_watch_time': DateTime.now().toUtc().toIso8601String(),
            'is_from_scan': 1
          });
        }
      }
      if (projectionId != null) {
        await tx.insert('next_classic_projection_journal', {
          'projection_id': projectionId,
          'file_path': locator,
          'before_fields': jsonEncode(before),
          'after_fields': jsonEncode(matching),
          'row_existed': rowExisted ? 1 : 0,
          'row_id': rowId!,
          'state': state
        });
      }
    });
    if (earlierProjectionChanged) {
      throw const Failure(FailureCode.conflict,
          'Classic changed after the earlier projection; Classic was left untouched and its undo remains in conflict.');
    }
    await changed();
  }

  @override
  Future<JsonMap> projectionOutcome(String locator, JsonMap fields) async {
    final db = await WatchHistoryDatabase.instance.database;
    if (fields['remoteTarget'] != null) {
      return RemoteClassicProjection(db).outcome(locator, fields);
    }
    final id = fields['clear'] == true
        ? fields['restoreProjectionId']
        : fields['projectionId'];
    final table = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='next_classic_projection_journal'");
    final rows = table.isEmpty || id == null
        ? <JsonMap>[]
        : await db.query('next_classic_projection_journal',
            where: 'projection_id=? AND file_path=?', whereArgs: [id, locator]);
    return {
      'locator': locator,
      'status': rows.isEmpty
          ? (fields['clear'] == true && fields['journalVersion'] == 1
              ? 'not_written'
              : 'no_undo_evidence')
          : rows.single['state'],
      'restored': rows.isNotEmpty && rows.single['state'] == 'restored'
    };
  }

  @override
  Future<bool> verify(String locator, JsonMap fields) async {
    if (fields['remoteTarget'] != null) {
      return RemoteClassicProjection(
              await WatchHistoryDatabase.instance.database)
          .verify(locator, fields);
    }
    final current =
        await WatchHistoryDatabase.instance.getHistoryByFilePath(locator);
    if (fields['clear'] == true) {
      final outcome = await projectionOutcome(locator, fields);
      if (outcome['status'] == 'unchanged' ||
          outcome['status'] == 'not_written') {
        return true;
      }
      if (outcome['status'] != 'restored') return false;
      final db = await WatchHistoryDatabase.instance.database;
      final journal = (await db.query('next_classic_projection_journal',
              where: 'projection_id=? AND file_path=?',
              whereArgs: [fields['restoreProjectionId'], locator]))
          .single;
      final rows = await db
          .query('watch_history', where: 'file_path=?', whereArgs: [locator]);
      return rows.isNotEmpty &&
          rows.single['id'] == journal['row_id'] &&
          _sameMatching(rows.single, decodeMediaJson(journal['before_fields']));
    }
    final db = await WatchHistoryDatabase.instance.database;
    final journal = await db.query('next_classic_projection_journal',
        where: 'projection_id=? AND file_path=?',
        whereArgs: [fields['projectionId'], locator]);
    final rows = await db
        .query('watch_history', where: 'file_path=?', whereArgs: [locator]);
    return journal.isNotEmpty &&
        rows.isNotEmpty &&
        rows.single['id'] == journal.single['row_id'] &&
        _sameMatching(
            rows.single, decodeMediaJson(journal.single['after_fields'])) &&
        current != null &&
        current.animeId == fields['animeId'] &&
        current.episodeId == fields['episodeId'] &&
        current.animeName.isNotEmpty &&
        current.episodeTitle != null;
  }
}

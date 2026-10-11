import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nipaplay/services/scoped_media_server_mapping.dart';

import 'identity_store.dart';

/// Episode and catalogue rows share the transaction with their undo evidence.
final class RemoteClassicProjection {
  RemoteClassicProjection(this.db);
  final Database db;

  static const journalTable = 'next_remote_projection_journal';
  static const journalSql = '''CREATE TABLE IF NOT EXISTS $journalTable (
    projection_id TEXT NOT NULL, locator TEXT NOT NULL, type TEXT NOT NULL,
    episode_key TEXT NOT NULL, before_episode TEXT, after_episode TEXT NOT NULL,
    before_anime TEXT, after_anime TEXT NOT NULL, state TEXT NOT NULL,
    PRIMARY KEY(projection_id, locator))''';

  Future<List<JsonMap>> _journal(
          DatabaseExecutor tx, Object? id, String locator) async =>
      id == null
          ? []
          : tx.query(journalTable,
              where: 'projection_id=? AND locator=?', whereArgs: [id, locator]);

  bool _equal(Object? a, Object? b) =>
      stableMediaId('row', [a]) == stableMediaId('row', [b]);
  JsonMap? _decode(Object? value) =>
      value == null ? null : decodeMediaJson(value);
  Never _conflict(String message) => throw Failure(FailureCode.conflict,
      'Classic remote mapping $message; Classic was left untouched.');

  Future<void> apply(String locator, JsonMap fields) async {
    final target = fields['remoteTarget'] as JsonMap;
    final type = target['type'] as String;
    final sourceId = target['sourceId'] as String;
    final profileId = mediaServerScope(
        sourceId.substring(type.length + 1), target['serverId'] as String?);
    final itemId = target['itemId'] as String;
    final episodeKey = scopedMediaServerId(profileId, itemId);
    var earlierChanged = false;
    await db.transaction((tx) async {
      await ensureMediaServerMappingTables(tx, type);
      await tx.execute(journalSql);
      final episodeTable = '${type}_episode_mapping';
      final animeTable = '${type}_dandanplay_mapping';
      final rows = await tx.query(episodeTable,
          where: '${type}_episode_id=?', whereArgs: [episodeKey]);
      final current = rows.isEmpty ? null : rows.single;
      final id = fields[
          fields['clear'] == true ? 'restoreProjectionId' : 'projectionId'];
      final journals = await _journal(tx, id, locator);
      if (fields['clear'] == true) {
        if (journals.isEmpty) {
          if (fields['journalVersion'] == 1) return;
          _conflict('has no atomic undo evidence');
        }
        final journal = journals.single;
        if (journal['state'] == 'unchanged') return;
        final before = _decode(journal['before_episode']);
        final expected = _decode(journal[journal['state'] == 'restored'
            ? 'before_episode'
            : 'after_episode']);
        if (!_equal(current, expected)) _conflict('changed after projection');
        if (journal['state'] == 'restored') return;
        final anime = decodeMediaJson(journal['after_anime']);
        final animeRows =
            await tx.query(animeTable, where: 'id=?', whereArgs: [anime['id']]);
        if (animeRows.isEmpty || !_equal(animeRows.single, anime)) {
          _conflict('catalogue changed after projection');
        }
        if (before == null) {
          await tx
              .delete(episodeTable, where: 'id=?', whereArgs: [current!['id']]);
        } else {
          await tx.update(episodeTable, before,
              where: 'id=?', whereArgs: [current!['id']]);
        }
        final dependents = await tx.query(episodeTable,
            where: 'mapping_id=?', whereArgs: [anime['id']]);
        // Any episode may be the last to release a catalogue created by Next.
        final owners = await tx.query(journalTable,
            where:
                'type=? AND before_anime IS NULL AND json_extract(after_anime,\'\$.id\')=?',
            whereArgs: [type, anime['id']]);
        if (dependents.isEmpty && owners.isNotEmpty) {
          await tx.delete(animeTable, where: 'id=?', whereArgs: [anime['id']]);
        }
        await tx.update(journalTable, {'state': 'restored'},
            where: 'projection_id=? AND locator=?', whereArgs: [id, locator]);
        return;
      }
      if (journals.isNotEmpty) {
        final journal = journals.single;
        final anime = decodeMediaJson(journal['after_anime']);
        final animeRows =
            await tx.query(animeTable, where: 'id=?', whereArgs: [anime['id']]);
        if ((journal['state'] == 'written' ||
                journal['state'] == 'unchanged') &&
            _equal(current, _decode(journal['after_episode'])) &&
            animeRows.isNotEmpty &&
            _equal(animeRows.single, anime)) {
          return;
        }
        _conflict('changed after this projection');
      }
      final previous =
          await _journal(tx, fields['previousProjectionId'], locator);
      if (previous.isNotEmpty && previous.single['state'] == 'written') {
        final anime = decodeMediaJson(previous.single['after_anime']);
        final animeRows =
            await tx.query(animeTable, where: 'id=?', whereArgs: [anime['id']]);
        if (!_equal(current, _decode(previous.single['after_episode'])) ||
            animeRows.isEmpty ||
            !_equal(animeRows.single, anime)) {
          await tx
              .insert(journalTable, {...previous.single, 'projection_id': id});
          earlierChanged = true;
          return;
        }
      }
      final legacy = await tx.query(episodeTable,
          where: '${type}_episode_id=?', whereArgs: [itemId]);
      if (legacy.isNotEmpty) {
        _conflict(
            'has a legacy episode without server ownership; resolve it in Classic first');
      }
      JsonMap? beforeEpisode = current;
      JsonMap? beforeAnime;
      JsonMap anime;
      String state = 'written';
      if (current != null) {
        anime = (await tx.query(animeTable,
                where: 'id=?', whereArgs: [current['mapping_id']]))
            .single;
        if (current['dandanplay_episode_id'] != fields['episodeId'] ||
            anime['dandanplay_anime_id'] != fields['animeId']) {
          _conflict('has a different match; both source facts are retained');
        }
        beforeAnime = anime;
        state = 'unchanged';
        if (previous.isNotEmpty && previous.single['state'] == 'written') {
          beforeEpisode = _decode(previous.single['before_episode']);
          beforeAnime = _decode(previous.single['before_anime']);
          state = 'written';
        }
      } else {
        final series = target['seriesId'] as String? ?? 'item:$itemId';
        final seriesKey = scopedMediaServerId(profileId, series);
        final season = target['seasonId'] as String?;
        final matches = await tx.query(animeTable,
            where:
                '${type}_series_id=? AND ${type}_season_id ${season == null ? 'IS NULL' : '=?'} AND dandanplay_anime_id=?',
            whereArgs: [
              seriesKey,
              if (season != null) season,
              fields['animeId']
            ]);
        if (matches.isNotEmpty) {
          anime = matches.single;
          beforeAnime = anime;
        } else {
          for (final key in ['animeName', 'episodeTitle']) {
            if (fields[key] is! String ||
                (fields[key] as String).trim().isEmpty) {
              _conflict('needs a nonempty evidenced $key');
            }
          }
          final mappingId = await tx.insert(animeTable, {
            '${type}_series_id': seriesKey,
            '${type}_series_name': target['name'],
            '${type}_season_id': target['seasonId'],
            'dandanplay_anime_id': fields['animeId'],
            'dandanplay_anime_title': fields['animeName'],
          });
          anime = (await tx
                  .query(animeTable, where: 'id=?', whereArgs: [mappingId]))
              .single;
        }
        await tx.insert(episodeTable, {
          '${type}_episode_id': episodeKey,
          '${type}_index_number': target['number'],
          'dandanplay_episode_id': fields['episodeId'],
          'mapping_id': anime['id'],
          'confirmed': 1,
        });
      }
      final after = (await tx.query(episodeTable,
              where: '${type}_episode_id=?', whereArgs: [episodeKey]))
          .single;
      await tx.insert(journalTable, {
        'projection_id': id,
        'locator': locator,
        'type': type,
        'episode_key': episodeKey,
        'before_episode':
            beforeEpisode == null ? null : jsonEncode(beforeEpisode),
        'after_episode': jsonEncode(after),
        'before_anime': beforeAnime == null ? null : jsonEncode(beforeAnime),
        'after_anime': jsonEncode(anime),
        'state': state,
      });
    });
    if (earlierChanged) _conflict('changed after the earlier projection');
  }

  Future<JsonMap> outcome(String locator, JsonMap fields) async {
    final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name=?", [journalTable]);
    final id = fields[
        fields['clear'] == true ? 'restoreProjectionId' : 'projectionId'];
    final rows = tables.isEmpty ? <JsonMap>[] : await _journal(db, id, locator);
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

  Future<bool> verify(String locator, JsonMap fields) async {
    final result = await outcome(locator, fields);
    if (result['status'] == 'not_written') return true;
    if (fields['clear'] == true && result['status'] == 'unchanged') return true;
    final id = fields[
        fields['clear'] == true ? 'restoreProjectionId' : 'projectionId'];
    final rows = await _journal(db, id, locator);
    if (rows.isEmpty) return false;
    final journal = rows.single;
    final type = journal['type'] as String;
    final episodes = await db.query('${type}_episode_mapping',
        where: '${type}_episode_id=?', whereArgs: [journal['episode_key']]);
    final current = episodes.isEmpty ? null : episodes.single;
    final expected = _decode(journal[
        fields['clear'] == true && journal['state'] == 'restored'
            ? 'before_episode'
            : 'after_episode']);
    if (!_equal(current, expected)) return false;
    if (fields['clear'] == true) {
      return ['restored', 'unchanged'].contains(journal['state']);
    }
    final anime = decodeMediaJson(journal['after_anime']);
    final actual = await db.query('${type}_dandanplay_mapping',
        where: 'id=?', whereArgs: [anime['id']]);
    return ['written', 'unchanged'].contains(journal['state']) &&
        actual.isNotEmpty &&
        _equal(actual.single, anime) &&
        current?['dandanplay_episode_id'] == fields['episodeId'] &&
        anime['dandanplay_anime_id'] == fields['animeId'];
  }
}

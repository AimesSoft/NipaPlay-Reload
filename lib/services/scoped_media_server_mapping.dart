import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:nipaplay/models/server_profile_model.dart';

String mediaServerScope(String profileId, String? serverId) =>
    serverId == null ? profileId : jsonEncode([profileId, serverId]);

String? mediaServerProfileScope(ServerProfile? profile) =>
    profile == null ? null : mediaServerScope(profile.id, profile.serverId);

String scopedMediaServerId(String profileId, String itemId) =>
    'next:${Uri.encodeComponent(profileId)}:${Uri.encodeComponent(itemId)}';

Map<String, dynamic> mediaServerMappingForDisplay(
        String type, Map<String, Object?> row) =>
    {
      ...row,
      for (final key in ['${type}_episode_id', '${type}_series_id'])
        if (row[key] case final String value when value.startsWith('next:'))
          key: Uri.decodeComponent(value.split(':').last),
    };

Future<String> writableSeriesId(DatabaseExecutor db, String type,
    String? profileId, String seriesId) async {
  if (profileId == null) return seriesId;
  final scoped = scopedMediaServerId(profileId, seriesId);
  final rows = await db.query('${type}_dandanplay_mapping',
      where: '${type}_series_id=?', whereArgs: [scoped], limit: 1);
  return rows.isEmpty ? seriesId : scoped;
}

Future<String> writableEpisodeId(
    DatabaseExecutor db, String type, String episodeId, int mappingId,
    {String? profileScope}) async {
  if (profileScope != null) {
    final key = scopedMediaServerId(profileScope, episodeId);
    final existing = await db.query('${type}_episode_mapping',
        where: '${type}_episode_id=?', whereArgs: [key], limit: 1);
    if (existing.isNotEmpty) return key;
  }
  final row = (await db.query('${type}_dandanplay_mapping',
          where: 'id=?', whereArgs: [mappingId]))
      .single;
  final series = row['${type}_series_id'] as String;
  if (!series.startsWith('next:')) return episodeId;
  return scopedMediaServerId(
      Uri.decodeComponent(series.split(':')[1]), episodeId);
}

Future<void> ensureMediaServerMappingTables(
    DatabaseExecutor db, String type) async {
  if (type != 'jellyfin' && type != 'emby') {
    throw ArgumentError.value(type, 'type');
  }
  await db.execute('''CREATE TABLE IF NOT EXISTS ${type}_dandanplay_mapping (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ${type}_series_id TEXT NOT NULL, ${type}_series_name TEXT,
    ${type}_season_id TEXT, dandanplay_anime_id INTEGER NOT NULL,
    dandanplay_anime_title TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(${type}_series_id, ${type}_season_id, dandanplay_anime_id))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS ${type}_episode_mapping (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ${type}_episode_id TEXT NOT NULL UNIQUE, ${type}_index_number INTEGER,
    dandanplay_episode_id INTEGER NOT NULL, mapping_id INTEGER NOT NULL,
    confirmed BOOLEAN DEFAULT FALSE, created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (mapping_id) REFERENCES ${type}_dandanplay_mapping(id))''');
}

Future<Map<String, Object?>?> scopedEpisodeMapping(
    DatabaseExecutor db, String type, String? profileId, String itemId) async {
  if (profileId == null) return null;
  final rows = await db.rawQuery('''SELECT e.*, a.dandanplay_anime_id,
    a.dandanplay_anime_title FROM ${type}_episode_mapping e
    JOIN ${type}_dandanplay_mapping a ON a.id=e.mapping_id
    WHERE e.${type}_episode_id=?''', [scopedMediaServerId(profileId, itemId)]);
  return rows.isEmpty ? null : mediaServerMappingForDisplay(type, rows.single);
}

Future<Map<String, Object?>?> scopedAnimeMapping(DatabaseExecutor db,
    String type, String? profileId, String seriesId, String? seasonId) async {
  if (profileId == null) return null;
  final rows = await db.query('${type}_dandanplay_mapping',
      where:
          '${type}_series_id=? AND ${type}_season_id ${seasonId == null ? 'IS NULL' : '=?'}',
      whereArgs: [
        scopedMediaServerId(profileId, seriesId),
        if (seasonId != null) seasonId
      ],
      orderBy: 'updated_at DESC');
  return rows.isEmpty ? null : mediaServerMappingForDisplay(type, rows.first);
}

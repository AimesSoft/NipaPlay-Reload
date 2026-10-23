import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';

import 'package:nipaplay/services/dandanplay_http_client.dart' as http;
import 'package:nipaplay/services/intro_skip/aniskip_service.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

import '../../media/file_identity_merge.dart';
import '../../media/identity_store.dart';

/// The namespaces Nipa writes a MyAnimeList or AniList ID under, on a work, a
/// season (release) or an episode: `media.identity.bind_batch` in direct mode
/// with `ref: {provider, objectType: "anime", externalId, scope: ""}`.
const malProvider = 'https://myanimelist.net';
const anilistProvider = 'https://anilist.co';

typedef AniSkipFetch = Future<List<SkipSegment>> Function(
    {required int malId, required int episode, double? lengthSeconds});
typedef MalOfAniList = Future<({int? malId, bool definitive})> Function(int id);

/// What AniSkip gave for the playing file, and why not when it gave nothing.
final class AniSkipOutcome {
  const AniSkipOutcome(this.segments, this.facts);
  final List<SkipSegment> segments;
  final JsonMap facts;
}

/// Asks AniSkip about an episode only when Nipa has written down which anime
/// it is (a MAL ID, or an AniList ID that AniList turns into one by ID) and the
/// episode has its number bound. Nothing here searches by title or reads a
/// number from a file name: the identity is hers.
final class AniSkipLookup {
  AniSkipLookup(this._identities, {AniSkipFetch? fetch, MalOfAniList? malOf})
      : _fetch = fetch ?? _classicFetch,
        _malOf = malOf ?? malIdOfAniList;
  final IdentityStore Function() _identities;
  final AniSkipFetch _fetch;
  final MalOfAniList _malOf;

  static Future<List<SkipSegment>> _classicFetch(
          {required int malId,
          required int episode,
          double? lengthSeconds}) =>
      AniSkipService.instance.fetchSkipTimes(
          malId: malId, episodeNumber: episode, episodeLengthSeconds: lengthSeconds);

  static AniSkipOutcome _none(String reason, [JsonMap more = const {}]) =>
      AniSkipOutcome(const [], {'available': false, 'reason': reason, ...more});

  Future<AniSkipOutcome> lookup(String path, {double? lengthSeconds}) async {
    final identities = _identities();
    final db = identities.database;
    final String fileId;
    try {
      fileId = await canonicalFileId(db, await identities.ensureFile(path));
    } on Failure {
      return _none('file_unknown');
    }
    final links = await db.query('media_file_episodes',
        columns: ['episode_id', 'start_ms', 'end_ms'],
        where: 'file_id = ?',
        whereArgs: [fileId]);
    if (links.isEmpty) return _none('no_episode');
    // One file holding several episodes has no single episode number.
    if (links.length > 1) return _none('several_episodes');
    final episode = await identities.entity(links.single['episode_id'] as String);
    final attributes = episode['attributes'] as JsonMap;
    final number = RegExp(r'^\d+$').hasMatch('${attributes['number']}')
        ? int.parse('${attributes['number']}')
        : null;
    if (number == null || number <= 0) {
      return _none('no_episode_number',
          {'episodeNumber': attributes['number']});
    }
    // The nearest entity that carries an ID wins: the episode, its season, its work.
    final chain = <JsonMap>[episode];
    for (var parent = episode['parent_id'] as String?;
        parent != null && chain.length < 3;) {
      final entity = await identities.entity(parent);
      chain.add(entity);
      parent = entity['parent_id'] as String?;
    }
    final rows = await db.rawQuery(
        'SELECT b.entity_id, o.provider, o.external_id FROM media_bindings b '
        'JOIN media_external_objects o ON o.id = b.object_id '
        "WHERE b.status = 'accepted' AND o.object_type = 'anime' "
        'AND o.provider IN (?, ?) AND b.entity_id IN (${List.filled(chain.length, '?').join(',')})',
        [malProvider, anilistProvider, for (final e in chain) e['id']]);
    for (final entity in chain) {
      final mine = rows.where((r) => r['entity_id'] == entity['id']).toList();
      if (mine.isEmpty) continue;
      final mal = mine.where((r) => r['provider'] == malProvider).firstOrNull;
      final anilist =
          mine.where((r) => r['provider'] == anilistProvider).firstOrNull;
      final from = {'entityKind': entity['kind']};
      int? malId;
      if (mal != null) {
        malId = int.tryParse(mal['external_id'] as String);
        if (malId == null) {
          return _none('invalid_mal_id',
              {'idFrom': from, 'malId': mal['external_id']});
        }
      } else {
        final anilistId = int.tryParse(anilist!['external_id'] as String);
        if (anilistId == null) {
          return _none('invalid_anilist_id',
              {'idFrom': from, 'anilistId': anilist['external_id']});
        }
        final found = await _malOf(anilistId);
        if (found.malId == null) {
          return _none(
              found.definitive ? 'anilist_has_no_mal_id' : 'anilist_request_failed',
              {'idFrom': from, 'anilistId': anilistId});
        }
        malId = found.malId;
      }
      final segments = await _fetch(
          malId: malId!, episode: number, lengthSeconds: lengthSeconds);
      return AniSkipOutcome(segments, {
        'available': segments.isNotEmpty,
        if (segments.isEmpty) 'reason': 'no_segments_returned',
        'malId': malId,
        'episodeNumber': number,
        'idFrom': {
          ...from,
          'provider': mal != null ? malProvider : anilistProvider
        },
        'segments': segments.length,
      });
    }
    return _none('no_mal_id', {'episodeNumber': number});
  }
}

/// AniList's own record of an anime by its ID (not a search by title).
Future<({int? malId, bool definitive})> malIdOfAniList(int id) async {
  const query = r'query ($id: Int) { Media(id: $id, type: ANIME) { idMal } }';
  try {
    final response = await http
        .post(WebRemoteAccessService.proxyUri(Uri.parse('https://graphql.anilist.co')),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json'
            },
            body: jsonEncode({'query': query, 'variables': {'id': id}}))
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    Object? media;
    if (decoded is Map && decoded['data'] is Map) {
      media = (decoded['data'] as Map)['Media'];
    }
    // An ID AniList does not have answers 404 with an error body.
    final unknownId = response.statusCode == 404 ||
        (response.statusCode == 200 &&
            media == null &&
            decoded is Map &&
            decoded['errors'] != null);
    if (unknownId) return (malId: null, definitive: true);
    if (response.statusCode != 200 || media is! Map) {
      return (malId: null, definitive: false);
    }
    final mal = media['idMal'];
    return (malId: mal is num && mal > 0 ? mal.toInt() : null, definitive: true);
  } catch (error) {
    debugPrint('[NextSkip] AniList $id: $error');
    return (malId: null, definitive: false);
  }
}

import 'package:nipa_harness/nipa_harness.dart';

import 'metadata_provider.dart';
import 'provider_transport.dart';

List<JsonMap> _rows(JsonMap json, String key) {
  final rows = json[key];
  if (rows is! List || rows.any((row) => row is! Map)) {
    throw const Failure(FailureCode.unavailable,
        'Provider response is missing its object list.');
  }
  return [for (final row in rows) Map<String, Object?>.from(row as Map)];
}

String _id(JsonMap json, String key) {
  final id = json[key];
  if (id is! num && id is! String) {
    throw const Failure(FailureCode.unavailable, 'Provider object has no ID.');
  }
  return id.toString();
}

int? _year(Object? date) => date is String && date.length >= 4
    ? int.tryParse(date.substring(0, 4))
    : null;

/// A score out of ten, when the provider has one (zero means unrated).
JsonMap? _score(Object? value, Object? count) => value is num && value > 0
    ? {'value': value, 'max': 10, if (count is num && count > 0) 'count': count}
    : null;

int? _count(Object? value) => value is num && value > 0 ? value.toInt() : null;

MetadataRecord _verifyRef(MetadataRecord record, ExternalRef ref) {
  if (record.ref.provider != ref.provider ||
      record.ref.objectType != ref.objectType ||
      record.ref.externalId != ref.externalId) {
    throw const Failure(FailureCode.conflict,
        'Provider returned an object different from the requested stable ID.');
  }
  return record;
}

final class TmdbMetadataProvider implements MetadataProvider {
  const TmdbMetadataProvider(this.transport);
  final MetadataTransport transport;
  @override
  String get id => 'tmdb';
  @override
  Future<List<MetadataRecord>> search(String query,
      {String kind = 'tv', int? year}) async {
    if (!{'tv', 'movie'}.contains(kind)) {
      throw const Failure(
          FailureCode.invalidInput, 'TMDB kind must be tv or movie.');
    }
    final response = await transport.request('/3/search/$kind', query: {
      'query': query,
      'language': 'zh-CN',
      if (year != null) (kind == 'tv' ? 'first_air_date_year' : 'year'): '$year'
    });
    return [for (final row in _rows(response, 'results')) _record(row, kind)];
  }

  MetadataRecord _record(JsonMap row, String type,
          {String scope = '',
          String language = 'zh-CN',
          List<MetadataRecord> episodes = const []}) =>
      MetadataRecord(
          ref: ExternalRef(id, type, _id(row, 'id'), scope: scope),
          title: (row[type == 'movie' ? 'title' : 'name'] as String),
          kind: type,
          originalTitle:
              row[type == 'movie' ? 'original_title' : 'original_name']
                  as String?,
          overview: row['overview'] as String?,
          imageUrl: row['poster_path'] == null
              ? null
              : 'https://image.tmdb.org/t/p/w500${row['poster_path']}',
          year: _year(
              row['first_air_date'] ?? row['release_date'] ?? row['air_date']),
          season: row['season_number'] as int?,
          number: row['episode_number']?.toString(),
          episodeType: row['season_number'] == 0 ? 'special' : 'regular',
          episodes: episodes,
          language: language,
          rating: type == 'tv' || type == 'movie'
              ? _score(row['vote_average'], row['vote_count'])
              : null,
          episodeCount: type == 'tv' ? _count(row['number_of_episodes']) : null,
          fetchedAt: DateTime.now().toUtc());

  @override
  Future<MetadataRecord> get(ExternalRef ref,
      {String language = 'zh-CN'}) async {
    final String path;
    switch (ref.objectType) {
      case 'tv':
        path = '/3/tv/${ref.externalId}';
      case 'movie':
        path = '/3/movie/${ref.externalId}';
      case 'season':
        final parts = ref.scope.split('/');
        if (parts.length != 4 || parts[0] != 'tv' || parts[2] != 'season') {
          throw const Failure(FailureCode.invalidInput,
              'TMDB season scope must be tv/<seriesId>/season/<number>.');
        }
        path = '/3/tv/${parts[1]}/season/${parts[3]}';
      case 'episode':
        final parts = ref.scope.split('/');
        if (parts.length != 6 ||
            parts[0] != 'tv' ||
            parts[2] != 'season' ||
            parts[4] != 'episode') {
          throw const Failure(FailureCode.invalidInput,
              'TMDB episode scope must include its series, season and episode number.');
        }
        path = '/3/tv/${parts[1]}/season/${parts[3]}/episode/${parts[5]}';
      default:
        throw const Failure(
            FailureCode.invalidInput, 'Unsupported TMDB object type.');
    }
    final row = await transport.request(path, query: {'language': language});
    final episodes = ref.objectType == 'season'
        ? [
            for (final ep in _rows(row, 'episodes'))
              _record(ep, 'episode',
                  scope: '${ref.scope}/episode/${ep['episode_number']}',
                  language: language)
          ]
        : ref.objectType == 'tv'
            ? [
                for (final season in _rows(row, 'seasons'))
                  _record(season, 'season',
                      scope:
                          'tv/${ref.externalId}/season/${season['season_number']}',
                      language: language)
              ]
            : <MetadataRecord>[];
    // TMDB API routes use season/episode numbers; object identity uses the returned ID.
    return _verifyRef(
        _record(row, ref.objectType,
            scope: ref.scope, language: language, episodes: episodes),
        ref);
  }
}

final class BangumiMetadataProvider implements MetadataProvider {
  const BangumiMetadataProvider(this.transport);
  final MetadataTransport transport;
  @override
  String get id => 'bangumi';
  @override
  Future<List<MetadataRecord>> search(String query,
      {String kind = 'tv', int? year}) async {
    final response = await transport.request('/v0/search/subjects', body: {
      'keyword': query,
      'filter': {
        'type': [2]
      }
    });
    return [
      for (final row in _rows(response, 'data'))
        if (year == null || _year(row['date']) == year) _record(row, 'subject')
    ];
  }

  MetadataRecord _record(JsonMap row, String type,
      {String scope = '', List<MetadataRecord> episodes = const []}) {
    final images = row['images'] as Map?;
    final localized = row['name_cn'] as String?;
    final rating = row['rating'];
    final regular =
        episodes.where((episode) => episode.episodeType == 'regular').length;
    return MetadataRecord(
        ref: ExternalRef(id, type, _id(row, 'id'), scope: scope),
        title: localized != null && localized.isNotEmpty
            ? localized
            : row['name'] as String,
        originalTitle: row['name'] as String?,
        kind: type,
        overview: row['summary'] as String?,
        imageUrl: images?['large'] as String?,
        year: _year(row['date'] ?? row['airdate']),
        number: row['sort']?.toString(),
        episodeType:
            row['type'] == 0 || type == 'subject' ? 'regular' : 'special',
        order: 'subject',
        episodes: episodes,
        language: 'zh-CN',
        rating: type == 'subject' && rating is Map
            ? _score(rating['score'], rating['total'])
            : null,
        episodeCount: type == 'subject'
            ? _count(row['eps']) ??
                _count(row['total_episodes']) ??
                _count(regular)
            : null,
        fetchedAt: DateTime.now().toUtc());
  }

  @override
  Future<MetadataRecord> get(ExternalRef ref,
      {String language = 'zh-CN'}) async {
    if (ref.objectType == 'episode') {
      return _verifyRef(
          _record(await transport.request('/v0/episodes/${ref.externalId}'),
              'episode',
              scope: ref.scope),
          ref);
    }
    if (ref.objectType != 'subject') {
      throw const Failure(
          FailureCode.invalidInput, 'Unsupported Bangumi object type.');
    }
    final row = await transport.request('/v0/subjects/${ref.externalId}');
    final episodes = <MetadataRecord>[];
    var offset = 0;
    while (true) {
      final page = await transport.request('/v0/episodes', query: {
        'subject_id': ref.externalId,
        'limit': '100',
        'offset': '$offset'
      });
      final items = _rows(page, 'data');
      episodes.addAll([
        for (final ep in items)
          _record(ep, 'episode', scope: 'subject/${ref.externalId}')
      ]);
      final total = page['total'];
      if (total is! int) {
        throw const Failure(
            FailureCode.unavailable, 'Bangumi episode response has no total.');
      }
      offset += items.length;
      if (offset >= total) break;
      if (items.isEmpty) {
        throw const Failure(FailureCode.unavailable,
            'Bangumi episode catalogue is incomplete.');
      }
    }
    return _verifyRef(_record(row, 'subject', episodes: episodes), ref);
  }
}

final class DandanplayMetadataProvider implements HashMetadataProvider {
  const DandanplayMetadataProvider(this.transport);
  final MetadataTransport transport;
  @override
  String get id => 'dandanplay';
  @override
  Future<List<MetadataRecord>> search(String query,
      {String kind = 'tv', int? year}) async {
    final response = await transport
        .request('/api/v2/search/anime', query: {'keyword': query});
    return [for (final row in _rows(response, 'animes')) _series(row)];
  }

  MetadataRecord _series(JsonMap row,
          {List<MetadataRecord> episodes = const [], int? episodeCount}) =>
      MetadataRecord(
          ref: ExternalRef(id, 'anime', _id(row, 'animeId')),
          title: row['animeTitle'] as String,
          kind: 'anime',
          overview: row['summary'] as String?,
          imageUrl: row['imageUrl'] as String?,
          episodes: episodes,
          order: 'provider',
          rating: _score(row['rating'], null),
          episodeCount: episodeCount ?? _count(row['episodeCount']),
          fetchedAt: DateTime.now().toUtc());
  MetadataRecord _episode(JsonMap row, String animeId) => MetadataRecord(
      ref: ExternalRef(id, 'episode', _id(row, 'episodeId'),
          scope: 'anime/$animeId'),
      title: row['episodeTitle'] as String,
      kind: 'episode',
      number: row['episodeNumber']?.toString(),
      order: 'provider',
      fetchedAt: DateTime.now().toUtc());
  @override
  Future<MetadataRecord> get(ExternalRef ref,
      {String language = 'zh-CN'}) async {
    final animeId =
        ref.objectType == 'anime' ? ref.externalId : ref.scope.split('/').last;
    if (!{'anime', 'episode'}.contains(ref.objectType)) {
      throw const Failure(
          FailureCode.invalidInput, 'Unsupported Dandanplay object type.');
    }
    final response = await transport.request('/api/v2/bangumi/$animeId');
    final value = response['bangumi'];
    if (value is! Map) {
      throw const Failure(FailureCode.unavailable,
          'Dandanplay response has no bangumi object.');
    }
    final row = Map<String, Object?>.from(value);
    final episodes = [
      for (final ep in _rows(row, 'episodes')) _episode(ep, animeId)
    ];
    if (ref.objectType == 'episode') {
      final matches =
          episodes.where((ep) => ep.ref.externalId == ref.externalId).toList();
      if (matches.length != 1) {
        throw const Failure(
            FailureCode.notFound, 'Dandanplay episode is absent.');
      }
      return matches.single;
    }
    return _verifyRef(
        _series(row, episodes: episodes, episodeCount: _count(episodes.length)),
        ref);
  }

  @override
  Future<List<MetadataRecord>> matchHash(
      String filename, String hash, int size) async {
    final response = await transport.request('/api/v2/match', body: {
      'fileName': filename,
      'fileHash': hash,
      'fileSize': size,
      'matchMode': 'hashOnly'
    });
    if (response['isMatched'] is! bool) {
      throw const Failure(FailureCode.unavailable,
          'Dandanplay match response has no match status.');
    }
    final rows = _rows(response, 'matches');
    if (response['isMatched'] != true) return [];
    return [
      for (final row in rows)
        _series(row, episodes: [_episode(row, _id(row, 'animeId'))])
    ];
  }
}

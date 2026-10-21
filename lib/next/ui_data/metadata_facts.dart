import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';

import 'service.dart';
import '../subtitles/facts.dart';

extension UiMetadataFacts on UiDataService {
  Future<JsonMap> metadataFacts(String workId) async {
    final work = await this.work(workId);
    if (work == null) {
      throw const Failure(
          FailureCode.notFound, 'workId must identify a library work.');
    }
    final evidence = await meshLibrary?.evidence(workId);
    final metadata = evidence == null ? await media.store.mergedMetadata(workId) : evidence['metadata'] as JsonMap;
    final fields = metadata['fields'] as JsonMap;
    final provenance = metadata['provenance'] as JsonMap;
    final attrs = evidence == null ? (await media.store.entity(workId))['attributes'] as JsonMap : evidence['attributes'] as JsonMap;
    JsonMap text(String field, Object? value) {
      final source = provenance[field] as Map?;
      final declared = source?.containsKey('mode') == true
          ? fields['${field}Language']
          : source?['language'];
      final sources = fields['fieldSources'];
      final recorded = source?.containsKey('mode') == true && sources is Map
          ? sources[field]
          : null;
      final kana = value is String &&
          RegExp(r'[\u3041-\u3096\u30a1-\u30fa]').hasMatch(value);
      return {
        'available': value != null,
        'value': value,
        'source': source == null
            ? (value == null ? null : {'source': 'entity_attributes'})
            : recorded == null
                ? source
                : {...source, 'record': recorded},
        if (field == 'title' || field == 'overview') ...{
          'inChinese': declared is String &&
              declared.toLowerCase().startsWith('zh'),
          'language': kana ? 'ja' : declared ?? 'unknown',
          'declaredLanguage': declared,
          'languageBasis': kana
              ? 'observed_kana'
              : declared == null
                  ? 'unknown'
                  : 'declared',
        }
      };
    }

    JsonMap image(String kind, String? path, JsonMap metadata) {
      final f = metadata['fields'] as JsonMap;
      final p = metadata['provenance'] as JsonMap;
      final edit = f['artwork.$kind'] as Map?;
      final urls = f['artworkUrls'] as Map?;
      final url = edit != null ? edit['url'] : urls?[kind] ??
          ((kind == 'poster' || kind == 'still') ? f['imageUrl'] : null);
      return {
        'available': path != null,
        'path': path,
        'url': url,
        'source': edit == null
            ? (url == null ? null : p[urls?[kind] == null ? 'imageUrl' : 'artworkUrls'])
            : {
                'record': edit['source'],
                'edit': p['artwork.$kind'],
                if (edit['originalFile'] != null)
                  'originalFile': edit['originalFile']
              }
      };
    }

    // An edit's own source, when it was handed in with one.
    Object? editSource(JsonMap m, String field) {
      final edit = (m['provenance'] as Map)[field] as Map?;
      final sources = (m['fields'] as Map)['fieldSources'];
      return edit != null && edit.containsKey('mode') && sources is Map &&
              sources[field] != null
          ? {...edit, 'record': sources[field]}
          : edit;
    }

    final episodes = await this.episodes(workId);
    final episodeFacts = <JsonMap>[];
    for (final e in episodes) {
      final episodeEvidence = await meshLibrary?.evidence(e.episodeId);
      final m = episodeEvidence == null ? await media.store.mergedMetadata(e.episodeId) : episodeEvidence['metadata'] as JsonMap;
      final tracks = episodeEvidence == null ? await heat.tracks(e.episodeId) : <JsonMap>[];
      final danmaku = <JsonMap>[];
      if (episodeEvidence != null) danmaku.addAll((episodeEvidence['danmaku'] as List).cast<JsonMap>());
      final subtitleTracks = episodeEvidence == null ? await (subtitles ?? subtitleFacts(media, mediaRoot)).episodeTracks(e.episodeId) : (episodeEvidence['subtitles'] as List).cast<JsonMap>();
      for (final track in tracks) {
        final local = track['local_file'] as JsonMap?;
        final video = track['video'] as JsonMap;
        final count = local?['count'] ??
            (await heat.store.entries(track['cache_key'] as String)).length;
        danmaku.add({
          'bindingId': track['id'],
          'source': video['sourceId'],
          'platform': local?['platform'] ?? video['sourceId'],
          'platformVideoId': local?['platformVideoId'] ?? video['videoId'],
          'count': count,
          'enabled': track['enabled'] == 1,
          'origin': local != null
              ? 'sidecar'
              : track['bound_by'] == 'automatic' ? 'playback' : track['provenance'] != null
                  ? 'import'
                  : 'binding',
          if (local != null) 'file': {...local}..remove('timeCounts'),
        });
      }
      episodeFacts.add({
        'subtitles': {
          'files': episodeEvidence == null ? await (subtitles ?? subtitleFacts(media, mediaRoot)).episodeFiles(e.episodeId) : episodeEvidence['subtitleFiles'],
          'available': subtitleTracks.any((t) => t['available'] == true),
          'languages': subtitleTracks
              .where((t) => t['available'] == true)
              .map((t) => t['language'])
              .toSet()
              .toList(),
          'tracks': subtitleTracks,
        },
        'danmaku': {
          'available': danmaku.isNotEmpty,
          'tracks': danmaku,
          'count': danmaku.fold<int>(0, (n, t) => n + (t['count'] as int))
        },
        'episodeId': e.episodeId,
        if (episodeEvidence != null) 'deviceId': episodeEvidence['deviceId'],
        'number': e.number,
        'season': e.season,
        'title': {
          'available': e.title != null,
          'value': e.title,
          'source': (m['provenance'] as Map)['title'] == null
              ? (e.title == null ? null : {'source': 'entity_attributes'})
              : editSource(m, 'title')
        },
        'still': image('still', e.still, m)
      });
    }
    final fieldFacts = <String, Object?>{
        'title': {...text('title', work.title),
          'available': (fields['title'] ?? attrs['title']) is String &&
              ((fields['title'] ?? attrs['title']) as String).trim().isNotEmpty,
          'fallback': work.title == '未命名作品'},
        'originalTitle': text('originalTitle', work.originalTitle),
        'overview': text('overview', work.overview),
        'year': text('year', work.year),
        'genres': text('genres', work.genres.isEmpty ? null : work.genres),
        'episodeCount': {...text('episodeCount', work.episodeCount),
          if (provenance['episodeCount'] == null && work.episodeCount != null)
            'source': {'source': 'library_episode_count'}},
        'studio': text('studio', work.studio),
        'ratings': {
          'available': work.ratings.isNotEmpty,
          'value': [
            for (final r in work.ratings) {'source': r.source, 'value': r.value}
          ],
          'source': metadata['ratings']
        },
        'backdrop': image('backdrop', work.artwork.backdrop, metadata),
        'poster': image('poster', work.artwork.poster, metadata),
        'logo': image('logo', work.artwork.logo, metadata),
    };
    // Whether the work has a TMDB identity: backdrop, logo and episode
    // stills come from it.
    final bool? tmdb;
    if (evidence != null) {
      final keys = evidence['keys'];
      tmdb = keys is List
          ? keys.any((k) =>
              (k is String ? jsonDecode(k) as List : k as List).first == 'tmdb')
          : null;
    } else {
      tmdb = (await media.store.database.rawQuery(
              "SELECT 1 FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id "
              "JOIN media_entities e ON e.id=b.entity_id "
              "WHERE b.status='accepted' AND b.relation IN ('exact','contains') "
              "AND o.provider='tmdb' AND o.object_type IN ('tv','movie','work') "
              "AND (e.id=? OR (e.kind='release' AND e.parent_id=?)) LIMIT 1",
              [workId, workId]))
          .isNotEmpty;
    }
    return {
      'workId': workId,
      'fields': fieldFacts,
      'identities': {if (tmdb != null) 'tmdb': tmdb},
      // What the facts above lack, as plain lists; nothing else is implied.
      'missing': {
        'identities': [if (tmdb == false) 'tmdb'],
        'fields': [
          for (final e in fieldFacts.entries)
            if ((e.value as Map)['available'] != true) e.key
        ],
        'chinese': [
          for (final name in ['title', 'overview'])
            if ((fieldFacts[name] as Map)['inChinese'] != true) name
        ],
        'episodes': {
          'withoutTitle': [
            for (final e in episodes)
              if (e.title == null) e.episodeId
          ],
          'withoutStill': [
            for (final e in episodes)
              if (e.still == null) e.episodeId
          ],
        },
      },
      'heroImage': work.artwork.backdrop != null
          ? 'backdrop'
          : work.artwork.poster != null
              ? 'poster'
              : null,
      'tint': work.artwork.tint,
      'episodes': {
        'total': episodes.length,
        'titles': episodes.where((e) => e.title != null).length,
        'stills': episodes.where((e) => e.still != null).length,
        'danmaku': episodeFacts
            .where((e) => (e['danmaku'] as JsonMap)['available'] == true)
            .length,
        'subtitles': episodeFacts
            .where((e) => (e['subtitles'] as JsonMap)['available'] == true)
            .length,
        'items': episodeFacts
      }
    };
  }

  /// The part of [metadataFacts] that says what is missing.
  Future<JsonMap> metadataSummary(String workId) async {
    final facts = await metadataFacts(workId);
    final episodes = facts['episodes'] as Map;
    return {
      'identities': facts['identities'],
      'missing': facts['missing'],
      'heroImage': facts['heroImage'],
      'episodes': {
        'total': episodes['total'],
        'titles': episodes['titles'],
        'stills': episodes['stills'],
      },
    };
  }

  Future<JsonMap> setArtwork(JsonMap input, Invocation invocation) =>
      media.mutate(() async {
        final edits = <JsonMap>[];
        final seen = <String>{};
        final entries = (input['entries'] as List).cast<Map>();
        if (entries.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'entries must not be empty.');
        }
        for (final entry in entries) {
          final id = entry['entityId'] as String,
              kind = entry['kind'] as String;
          final entity = await media.store.entity(id);
          if (entity['kind'] != (kind == 'still' ? 'episode' : 'work')) {
            throw const Failure(FailureCode.invalidInput,
                'backdrop/poster/logo require a work; still requires an episode.');
          }
          if (!seen.add('$id/$kind')) {
            throw const Failure(
                FailureCode.invalidInput, 'Duplicate entityId/kind in batch.');
          }
          edits.add({
            'entityId': id,
            'field': 'artwork.$kind',
            'mode': 'persistent',
            'value': {
              ...await artwork.prepare(
                  url: entry['url'] as String?, file: entry['file'] as String?),
              'source': entry['source']
            }
          });
        }
        await media.store.overrideFields(edits, invocation);
        return {
          'entries': [
            for (final e in edits)
              {
                'entityId': e['entityId'],
                'kind': (e['field'] as String).substring(8),
                'saved': true,
                'effectiveKind': (e['field'] as String).substring(8),
                'path': (e['value'] as JsonMap)['file'] ??
                    (e['value'] as JsonMap)['cachedPath'],
                'sha256': (e['value'] as JsonMap)['sha256'],
                'source': (e['value'] as JsonMap)['source'],
              }
          ]
        };
      });
}

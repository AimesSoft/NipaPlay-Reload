import 'package:nipa_harness/nipa_harness.dart';

import 'service.dart';

extension UiMetadataFacts on UiDataService {
  Future<JsonMap> metadataFacts(String workId) async {
    final work = await this.work(workId);
    if (work == null) {
      throw const Failure(
          FailureCode.notFound, 'workId must identify a library work.');
    }
    final metadata = await media.store.mergedMetadata(workId);
    final fields = metadata['fields'] as JsonMap;
    final provenance = metadata['provenance'] as JsonMap;
    final attrs = (await media.store.entity(workId))['attributes'] as JsonMap;
    JsonMap text(String field, Object? value) {
      final source = provenance[field] as Map?;
      final declared = source?.containsKey('mode') == true
          ? fields['${field}Language']
          : source?['language'];
      final kana = value is String &&
          RegExp(r'[\u3041-\u3096\u30a1-\u30fa]').hasMatch(value);
      return {
        'available': value != null,
        'value': value,
        'source':
            source ?? (value == null ? null : {'source': 'entity_attributes'}),
        if (field == 'title' || field == 'overview') ...{
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

    final episodes = await this.episodes(workId);
    final episodeFacts = <JsonMap>[];
    for (final e in episodes) {
      final m = await media.store.mergedMetadata(e.episodeId);
      final tracks = await heat.tracks(e.episodeId);
      final danmaku = <JsonMap>[];
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
        'danmaku': {
          'available': danmaku.isNotEmpty,
          'tracks': danmaku,
          'count': danmaku.fold<int>(0, (n, t) => n + (t['count'] as int))
        },
        'episodeId': e.episodeId,
        'number': e.number,
        'season': e.season,
        'title': {
          'available': e.title != null,
          'value': e.title,
          'source': (m['provenance'] as Map)['title'] ??
              (e.title == null ? null : {'source': 'entity_attributes'})
        },
        'still': image('still', e.still, m)
      });
    }
    return {
      'workId': workId,
      'fields': {
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
        'items': episodeFacts
      }
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
                'saved': true
              }
          ]
        };
      });
}

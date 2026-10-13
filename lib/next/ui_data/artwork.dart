import 'dart:convert';
import 'dart:io';
import 'raster_io.dart' if (dart.library.ui) 'raster_flutter.dart';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/identity_store.dart';
import '../events/signals.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../media/providers.dart';
import 'ui_data.dart';

/// Images are source snapshots; downloaded files are a disposable projection.
final class ArtworkCache {
  ArtworkCache(this.media, this.root, this.vault);
  final MediaService media;
  final Directory root;
  final CredentialVault vault;
  final _client = http.Client();
  final _pending = <String, Future<JsonMap>>{};
  bool get busy => _pending.isNotEmpty;

  Future<JsonMap> cached(String entityId) async {
    final identities = await _identities(entityId);
    final fields =
        (await media.store.mergedMetadata(entityId))['fields'] as JsonMap;
    final fingerprint = jsonEncode([
      for (final o in identities) o['id'],
      fields['imageUrl'],
      fields['artworkUrls'],
      for (final kind in ['backdrop', 'poster', 'logo', 'still'])
        fields['artwork.$kind']
    ]);
    final rows = await media.store.database.query('ui_cache',
        where: 'id=? AND fingerprint=?',
        whereArgs: ['artwork:$entityId', fingerprint]);
    if (rows.isEmpty) return {};
    final result = decodeMediaJson(rows.single['payload']);
    return await _filesExist(result) ? result : {};
  }

  Future<JsonMap> load(String entityId) => _pending.putIfAbsent(
      entityId,
      () => _load(entityId).whenComplete(() {
            _pending.remove(entityId);
          }));

  Future<List<JsonMap>> _identities(String id) => media.store.database.rawQuery(
      'SELECT o.*,b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id '
      "WHERE b.entity_id=? AND b.status='accepted' AND b.relation IN ('exact','contains') ORDER BY CASE o.provider WHEN 'tmdb' THEN 0 WHEN 'bangumi' THEN 1 ELSE 2 END,o.id",
      [id]);

  Future<void> _snapshot(JsonMap object, JsonMap fields, String url) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await media.store.database.insert('media_snapshots', {
      'id': newMediaId('snapshot'),
      'object_id': object['id'],
      'language': 'zh-CN',
      'fetched_at': now,
      'fields': jsonEncode({
        'ref': ExternalRef(
                object['provider'] as String,
                object['object_type'] as String,
                object['external_id'] as String,
                scope: object['scope'] as String)
            .toJson(),
        'metadata': fields,
        'language': 'zh-CN',
        'fetchedAt': now,
        'receivedAt': now,
        'source': 'provider_snapshot',
        'origin': 'application',
        'url': url,
      })
    });
    BodySignals.changed('media.assets.changed', object['id'] as String,
        {'kind': 'artwork', 'changedFields': fields.keys.toList(), 'source': object['provider']});
  }

  Future<JsonMap> _load(String id) async {
    final identities = await _identities(id);
    final tmdb = identities.where((o) => o['provider'] == 'tmdb').firstOrNull;
    final metadata = await media.store.mergedMetadata(id);
    final fields = metadata['fields'] as JsonMap;
    final fingerprint = jsonEncode([
      for (final o in identities) o['id'],
      fields['imageUrl'],
      fields['artworkUrls'],
      for (final kind in ['backdrop', 'poster', 'logo', 'still'])
        fields['artwork.$kind']
    ]);
    final cacheId = 'artwork:$id';
    final saved = await media.store.database.query('ui_cache',
        where: 'id=? AND fingerprint=?', whereArgs: [cacheId, fingerprint]);
    if (saved.isNotEmpty) {
      final result = decodeMediaJson(saved.single['payload']);
      if (await _filesExist(result)) return result;
    }
    var urls = fields['artworkUrls'] is Map
        ? Map<String, Object?>.from(fields['artworkUrls'] as Map)
        : <String, Object?>{};
    if (tmdb != null &&
        await vault.read(const CredentialRef('metadata', 'tmdb')) != null) {
      final provider = media.providers['tmdb']! as TmdbMetadataProvider;
      final type = tmdb['object_type'] as String;
      final path = type == 'episode' || type == 'season'
          ? '/3/${tmdb['scope']}'
          : '/3/$type/${tmdb['external_id']}';
      if (urls['identity'] != tmdb['id']) {
        final row = await provider.transport.request(path, query: {
          'language': 'zh-CN',
          'append_to_response': 'images',
          'include_image_language': 'zh,ja,en,null'
        });
        final images = row['images'] as Map? ?? {};
        String? choose(String category, List<String?> languages) {
          final entries = (images[category] as List? ?? []).cast<Map>();
          for (final language in languages) {
            final matching = entries
                .where((r) => r['iso_639_1'] == language)
                .toList()
              ..sort((a, b) => ((b['vote_count'] as num? ?? 0) *
                      (b['vote_average'] as num? ?? 0))
                  .compareTo((a['vote_count'] as num? ?? 0) *
                      (a['vote_average'] as num? ?? 0)));
            if (matching.isNotEmpty) {
              return matching.first['file_path'] as String;
            }
          }
          return null;
        }

        String? image(Object? path, String size) =>
            path == null ? null : 'https://image.tmdb.org/t/p/$size$path';
        final fetched = <String, Object?>{
          'identity': tmdb['id'],
          'backdrop': image(
              choose('backdrops', [null, 'ja', 'zh', 'en']) ??
                  row['backdrop_path'],
              'w1280'),
          'poster': image(
              choose('posters', ['zh', 'ja', 'en', null]) ?? row['poster_path'],
              'w500'),
          'logo': image(choose('logos', ['zh', 'ja', 'en', null]), 'original'),
          'still': image(row['still_path'], 'w780'),
        };
        urls = {...urls, for (final entry in fetched.entries)
          if (entry.value != null) entry.key: entry.value};
        await _snapshot(
            tmdb,
            {
              'artworkUrls': urls,
              if (row['genres'] is List)
                'genres': [
                  for (final g in row['genres'] as List) (g as Map)['name']
                ],
              if (row['number_of_episodes'] != null)
                'episodeCount': row['number_of_episodes'],
              if (row['production_companies'] is List &&
                  (row['production_companies'] as List).isNotEmpty)
                'studio': (row['production_companies'] as List).first['name'],
              if (row['runtime'] is num)
                'runtimeMs': (row['runtime'] as num).toInt() * 60000,
              if (row['vote_average'] is num)
                'rating': {
                  'value': row['vote_average'],
                  'max': 10,
                  'count': row['vote_count'],
                  'source': 'tmdb'
                },
            },
            'https://api.themoviedb.org$path');
      }
    }
    if (fields['imageUrl'] is String) {
      final entity = await media.store.entity(id);
      final kind = entity['kind'] == 'episode' ? 'still' : 'poster';
      urls[kind] ??= fields['imageUrl'];
    }
    for (final kind in ['backdrop', 'poster', 'logo', 'still']) {
      if (fields['artwork.$kind'] case final Map edit) {
        urls[kind] = edit['url'] ?? Uri.file(edit['file'] as String).toString();
      }
    }
    final result = <String, Object?>{};
    for (final kind in ['backdrop', 'poster', 'logo', 'still']) {
      if (urls[kind] case final String url) result[kind] = await _download(url);
    }
    if (result['backdrop'] ?? result['poster'] case final String path) {
      result['tint'] = await _tint(path);
    }
    final updated = (await media.store.mergedMetadata(id))['fields'] as JsonMap;
    await media.store.database.insert(
        'ui_cache',
        {
          'id': cacheId,
          'fingerprint': jsonEncode([
            for (final o in identities) o['id'],
            updated['imageUrl'],
            updated['artworkUrls'],
            for (final kind in ['backdrop', 'poster', 'logo', 'still'])
              updated['artwork.$kind']
          ]),
          'payload': jsonEncode(result)
        },
        conflictAlgorithm: ConflictAlgorithm.replace);
    return result;
  }

  Future<bool> _filesExist(JsonMap result) async {
    for (final kind in ['backdrop', 'poster', 'logo', 'still']) {
      if (result[kind] case final String path) {
        if (!await File(path).exists()) return false;
      }
    }
    return true;
  }

  Future<String> _download(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme == 'file') return uri.toFilePath();
    if (!{'https', 'http'}.contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      throw const Failure(FailureCode.invalidInput,
          'Artwork must use an HTTP(S) URL without credentials.');
    }
    final file = File(
        '${root.path}/artwork/${sha256.convert(utf8.encode(url))}${uri.path.endsWith('.png') ? '.png' : '.jpg'}');
    if (await file.exists()) return file.path;
    final response =
        await _client.get(uri).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Failure(FailureCode.unavailable,
          'Artwork download returned HTTP ${response.statusCode}.');
    }
    // Verify raster data before publishing a path, including logos.
    await validateRaster(response.bodyBytes);
    await file.parent.create(recursive: true);
    final staging = File('${file.path}.pending');
    await staging.writeAsBytes(response.bodyBytes, flush: true);
    await staging.rename(file.path);
    return file.path;
  }

  /// Validate/copy before committing an edit; local inputs survive removal.
  Future<JsonMap> prepare({String? url, String? file}) async {
    if ((url == null) == (file == null)) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply exactly one url or file.');
    }
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        throw const Failure(
            FailureCode.invalidInput, 'url must be HTTP(S) without userinfo.');
      }
      await _download(url);
      return {'url': url};
    }
    if (!File(file!).isAbsolute || !await File(file).exists()) {
      throw const Failure(FailureCode.invalidInput,
          'file must be an existing absolute local path.');
    }
    final bytes = await File(file).readAsBytes();
    await validateRaster(bytes);
    final target = File('${root.path}/artwork/${sha256.convert(bytes)}.png');
    await target.parent.create(recursive: true);
    if (!await target.exists()) {
      final staging = File('${target.path}.pending');
      await staging.writeAsBytes(bytes, flush: true);
      await staging.rename(target.path);
    }
    return {'file': target.path, 'originalFile': file};
  }

  Future<int> _tint(String path) async => rasterTint(await File(path).readAsBytes());

  void close() => _client.close();
}

UiArtwork uiArtwork(JsonMap row) => UiArtwork(
    backdrop: row['backdrop'] as String?,
    poster: row['poster'] as String?,
    logo: row['logo'] as String?,
    tint: row['tint'] as int?);

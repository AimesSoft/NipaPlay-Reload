import 'dart:async';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';

import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../media/provider_transport.dart';
import '../media/providers.dart';
import '../mesh/library.dart';
import 'found.dart';
import 'work_files.dart';
import 'work_more.dart';

/// What a work's page reads beyond the library: its sections, and the
/// pictures and people it opens onto. Pictures and people come from TMDB
/// and Bangumi when asked for and are kept for the session, so going back
/// and forth between pages does not ask again.
final class WorkDetailsReader {
  WorkDetailsReader(this.media, this.meshLibrary);
  final MediaService media;
  final MeshLibrary? Function() meshLibrary;
  final _galleries = <String, Future<UiGallery>>{};
  final _people = <String, Future<UiPerson?>>{};
  final _related = <String, Future<List<(ExternalRef, UiPersonWork)>>>{};

  Future<UiWorkFiles> files(String workId) async {
    if (Found.isFoundId(workId) || workId.startsWith('source-work:')) {
      return UiWorkFiles.empty;
    }
    List<JsonMap>? rows;
    if (meshLibrary() case final mesh?) {
      try {
        rows = await mesh.workFiles(workId);
      } on Failure catch (error) {
        if (error.code != FailureCode.notFound) rethrow;
      }
    }
    rows ??= await localWorkFiles(media.store.database, workId);
    final unread = [
      for (final row in rows)
        if (row['unread'] == true && row['fileId'] is String)
          row['fileId'] as String
    ];
    // Read again in the background; the library's change brings them.
    if (unread.isNotEmpty) unawaited(media.readStreams(unread));
    return UiWorkFiles([for (final row in rows) UiFileFacts.fromJson(row)],
        reading: unread.isNotEmpty);
  }

  /// The relatives the sources list are read once a session; which of them
  /// the library holds is asked each time.
  Future<List<UiPersonWork>> related(UiRelatedRef ref) async {
    final found = await _relatives(ref);
    final library =
        await media.acceptedWorkIds([for (final (ref, _) in found) ref]);
    final seen = <String>{};
    return [
      for (final (i, (_, work)) in found.indexed)
        if (seen.add(library[i] ?? work.workId))
          (
            workId: library[i] ?? work.workId,
            title: work.title,
            role: work.role,
            year: work.year,
            poster: work.poster,
          )
    ];
  }

  Future<List<(ExternalRef, UiPersonWork)>> _relatives(UiRelatedRef ref) {
    return _related[ref.key] ??= () async {
      try {
        final found = <(ExternalRef, UiPersonWork)>[];
        if (ref.bangumi case final id?) {
          if (_transport('bangumi') case final bangumi?) {
            found.addAll(bangumiRelated((await bangumi
                    .request('/v0/subjects/$id/subjects'))['data'] as List? ??
                const []));
          }
        }
        if (ref.tmdbCollection case final id?) {
          if (_transport('tmdb') case final tmdb?) {
            found.addAll(tmdbCollectionParts(
                await tmdb
                    .request('/3/collection/$id', query: {'language': 'zh-CN'}),
                self: ref.tmdbMovie));
          }
        }
        // Dandanplay's list says no relation: it fills in when the others
        // know none.
        if (found.isEmpty) {
          for (final d in ref.dandanplay) {
            found.add((
              ExternalRef('dandanplay', 'anime', d.id),
              (
                workId: Found.id('dandanplay', d.id),
                title: d.title,
                role: null,
                year: null,
                poster: d.image,
              )
            ));
          }
        }
        return found;
      } catch (error) {
        developer.log('related ${ref.key}: ${error.runtimeType}',
            name: 'NextUi');
        _related.remove(ref.key);
        return const <(ExternalRef, UiPersonWork)>[];
      }
    }();
  }

  Future<UiWorkMore> workMore(String workId) async {
    // A found work's page builds this from the record it already read.
    if (Found.isFoundId(workId)) {
      return UiWorkMore.empty;
    }
    if (meshLibrary() case final mesh?
        when !workId.startsWith('source-work:')) {
      try {
        return UiWorkMore.fromJson(await mesh.workMore(workId));
      } on Failure catch (error) {
        if (error.code != FailureCode.notFound) rethrow;
      }
    }
    final store = media.store;
    final metadata = await store.mergedMetadata(workId);
    final film = await store.workIsFilm(workId);
    return UiWorkMore.fromJson(
        await Isolate.run(() => buildWorkMore(metadata, film: film)));
  }

  MetadataTransport? _transport(String provider) =>
      switch (media.providers[provider]) {
        TmdbMetadataProvider(:final transport) => transport,
        BangumiMetadataProvider(:final transport) => transport,
        _ => null,
      };

  Future<UiGallery> gallery(UiGalleryRef ref) {
    final key = '${ref.objectType}:${ref.id}';
    return _galleries[key] ??= () async {
      final tmdb = _transport('tmdb');
      if (tmdb == null) return const UiGallery();
      try {
        return tmdbGallery(await tmdb.request(
            '/3/${ref.objectType}/${ref.id}/images',
            query: {'include_image_language': 'zh,ja,en,null'}));
      } catch (error) {
        developer.log('gallery $key: ${error.runtimeType}', name: 'NextUi');
        _galleries.remove(key);
        return const UiGallery();
      }
    }();
  }

  Future<UiPerson?> person(UiPersonRef ref) {
    final key = '${ref.provider}:${ref.id}';
    return _people[key] ??= () async {
      try {
        final person = await _read(ref);
        if (person == null) return null;
        final library =
            await meshLibrary()?.worksCrediting(ref.provider, ref.id) ??
                const <String>[];
        return person.withLibrary(library);
      } catch (error) {
        developer.log('person $key: ${error.runtimeType}', name: 'NextUi');
        _people.remove(key);
        return null;
      }
    }();
  }

  Future<UiPerson?> _read(UiPersonRef ref) async {
    final transport = _transport(ref.provider);
    if (transport == null) return null;
    switch (ref.provider) {
      case 'tmdb':
        final row = await transport.request('/3/person/${ref.id}', query: {
          'language': 'zh-CN',
          'append_to_response': 'combined_credits,external_ids',
        });
        String? english;
        if ('${row['biography'] ?? ''}'.trim().isEmpty) {
          english = (await transport.request('/3/person/${ref.id}',
              query: {'language': 'en-US'}))['biography'] as String?;
        }
        return tmdbPerson(row,
            biography: english,
            foundId: (type, id) => Found.id('tmdb', id, objectType: type));
      case 'bangumi':
        final row = await transport.request('/v0/persons/${ref.id}');
        Future<List> list(String path) async {
          try {
            return (await transport.request(path))['data'] as List? ?? const [];
          } on Failure {
            return const [];
          }
        }

        return bangumiPerson(row,
            subjects: await list('/v0/persons/${ref.id}/subjects'),
            characters: await list('/v0/persons/${ref.id}/characters'),
            foundId: (id) => Found.id('bangumi', id));
    }
    return null;
  }
}

/// Bangumi's related subjects (`/v0/subjects/{id}/subjects`): the anime and
/// live-action ones, with how they relate (前传, 续集, 剧场版…).
List<(ExternalRef, UiPersonWork)> bangumiRelated(List rows) => [
      for (final r in rows.whereType<Map>())
        if ((r['type'] == 2 || r['type'] == 6) && r['id'] != null)
          if (_name(r['name_cn']) ?? _name(r['name']) case final title?)
            (
              ExternalRef('bangumi', 'subject', '${r['id']}'),
              (
                workId: Found.id('bangumi', r['id']),
                title: title,
                role: _name(r['relation']),
                year: null,
                poster: switch (r['images']) {
                  final Map images => _name(images['common']) ??
                      _name(images['medium']) ??
                      _name(images['large']),
                  _ => null,
                },
              )
            )
    ];

/// The films of a TMDB collection but [self], in the order they came out.
List<(ExternalRef, UiPersonWork)> tmdbCollectionParts(Map row, {String? self}) {
  final parts = [
    for (final p in (row['parts'] as List? ?? const []).whereType<Map>())
      if (p['id'] != null && '${p['id']}' != self)
        if (_name(p['title']) ?? _name(p['name']) case final title?) (p, title)
  ]..sort((a, b) => '${a.$1['release_date'] ?? ''}'
      .compareTo('${b.$1['release_date'] ?? ''}'));
  return [
    for (final (p, title) in parts)
      (
        ExternalRef('tmdb', 'movie', '${p['id']}'),
        (
          workId: Found.id('tmdb', p['id'], objectType: 'movie'),
          title: title,
          role: null,
          year: int.tryParse('${p['release_date'] ?? ''}'.split('-').first),
          poster: _name(p['poster_path']) == null
              ? null
              : 'https://image.tmdb.org/t/p/w342${p['poster_path']}',
        )
      )
  ];
}

String? _name(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

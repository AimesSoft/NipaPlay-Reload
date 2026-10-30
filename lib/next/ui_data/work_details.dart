import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:nipa_harness/nipa_harness.dart';

import '../media/media_service.dart';
import '../media/provider_transport.dart';
import '../media/providers.dart';
import '../mesh/library.dart';
import 'found.dart';
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

  Future<UiWorkMore> workMore(String workId) async {
    // A found work's page builds this from the record it already read.
    if (Found.isFoundId(workId) || workId.startsWith('source-work:')) {
      return UiWorkMore.empty;
    }
    if (meshLibrary() case final mesh?) {
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

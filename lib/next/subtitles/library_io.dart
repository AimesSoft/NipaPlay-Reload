import 'dart:convert';
import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/media_service.dart';
import 'facts.dart';

/// Headless reads saved subtitle facts without attaching a Classic player.
final class SubtitleLibrary implements SubtitleFacts {
  SubtitleLibrary(this.media, this.root);
  final MediaService media;
  final Directory root;
  Future<JsonMap> _facts(String id) async {
    final rows = await media.store.database
        .query('file_subtitles', where: 'file_id=?', whereArgs: [id]);
    return rows.isEmpty
        ? {
            'fileId': id,
            'tracks': <JsonMap>[],
            'embeddedStatus': 'unavailable',
            'selection': null
          }
        : jsonDecode(rows.single['facts'] as String) as JsonMap;
  }

  @override
  Future<List<JsonMap>> episodeTracks(String id) async {
    final tracks = <JsonMap>[];
    for (final file in await media.store.database
        .query('media_file_episodes', where: 'episode_id=?', whereArgs: [id])) {
      final facts = await _facts(file['file_id'] as String);
      tracks.addAll((facts['tracks'] as List).cast<JsonMap>().map((t) => {
            ...t,
            'fileId': file['file_id'],
            'selected': (facts['selection'] as Map?)?['trackId'] == t['id'],
            'selectionBasis': (facts['selection'] as Map?)?['basis']
          }));
    }
    return tracks;
  }

  @override
  Future<List<JsonMap>> episodeFiles(String id) async => [
        for (final file in await media.store.database.query(
            'media_file_episodes',
            where: 'episode_id=?',
            whereArgs: [id]))
          {...await _facts(file['file_id'] as String)}..remove('tracks')
      ];
}

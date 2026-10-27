import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/identity_store.dart';
import '../media/file_identity_merge.dart';

/// An episode's subtitle tracks and its files' subtitle facts (the facts
/// without their tracks), from one query: what [SubtitleFacts.episodeTracks]
/// and [SubtitleFacts.episodeFiles] give, for a caller that wants both.
Future<({List<JsonMap> tracks, List<JsonMap> files})> readEpisodeSubtitles(
    DatabaseExecutor db, String episodeId) async {
  episodeId = await canonicalFileId(db, episodeId);
  final tracks = <JsonMap>[], files = <JsonMap>[];
  for (final row in await db.rawQuery(
      'SELECT fe.file_id AS asked, '
      'COALESCE((SELECT file_id FROM media_file_aliases WHERE old_id=fe.file_id), fe.file_id) AS id, '
      's.facts FROM media_file_episodes fe '
      'LEFT JOIN file_subtitles s ON s.file_id = '
      'COALESCE((SELECT file_id FROM media_file_aliases WHERE old_id=fe.file_id), fe.file_id) '
      'WHERE fe.episode_id=?',
      [episodeId])) {
    final facts = row['facts'] == null
        ? <String, Object?>{
            'fileId': row['id'],
            'revision': 0,
            'tracks': <JsonMap>[],
            'embeddedStatus': 'pending',
            'selection': null
          }
        : decodeMediaJson(row['facts']);
    for (final track in (facts['tracks'] as List).cast<JsonMap>()) {
      tracks.add({
        ...track,
        'fileId': row['asked'],
        'selected': (facts['selection'] as Map?)?['trackId'] == track['id'],
        'selectionBasis': (facts['selection'] as Map?)?['basis']
      });
    }
    files.add({...facts}..remove('tracks'));
  }
  return (tracks: tracks, files: files);
}

import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import '../../utils/subtitle_file_utils.dart';
import '../ui_data/service.dart';
import '../media/identity_store.dart';

Future<List<JsonMap>> subtitleCompanions(
    UiDataService ui, String fileId, String path) async {
  final rows = await ui.db
      .query('file_subtitles', where: 'file_id=?', whereArgs: [fileId]);
  final facts = rows.isEmpty
      ? <String, Object?>{}
      : decodeMediaJson(rows.single['facts']);
  final tracks = [
    for (final t in (facts['tracks'] as List? ?? []).cast<JsonMap>())
      {
        ...t,
        'selected': (facts['selection'] as Map?)?['trackId'] == t['id'],
        'selectionBasis': (facts['selection'] as Map?)?['basis']
      }
  ];
  await for (final entry in File(path).parent.list()) {
    if (entry is! File ||
        !{...supportedSubtitleExtensions, '.vtt'}
            .contains(p.extension(entry.path).toLowerCase()) ||
        !subtitleMatchesVideo(p.basenameWithoutExtension(path),
            p.basenameWithoutExtension(entry.path)) ||
        !isVobSubPairComplete(entry.path)) continue;
    final canonical = canonicalSubtitlePath(entry.path);
    if (!tracks.any((t) => t['path'] == canonical))
      tracks.add({
        'id': canonical,
        'path': canonical,
        'title': p.basename(canonical),
        'origin': 'sidecar',
        'available': true,
        'selected': false
      });
  }
  return tracks;
}

import 'package:nipa_harness/nipa_harness.dart';
import '../ui_data/service.dart';
import 'library.dart';

Future<List<JsonMap>> subtitleCompanions(
    UiDataService ui, String fileId, String path) async {
  final library = ui.subtitles as SubtitleLibrary;
  await library.inspect(fileId, path);
  final facts = await library.facts(fileId);
  return [
    for (final t in (facts['tracks'] as List).cast<JsonMap>())
      {
        ...t,
        'selected': (facts['selection'] as Map?)?['trackId'] == t['id'],
        'selectionBasis': (facts['selection'] as Map?)?['basis']
      }
  ];
}

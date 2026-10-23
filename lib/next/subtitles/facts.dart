import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';
import '../media/media_service.dart';
import 'facts_io.dart' if (dart.library.ui) 'facts_flutter.dart' as host;

abstract interface class SubtitleFacts {
  Future<List<JsonMap>> episodeTracks(String id);
  Future<List<JsonMap>> episodeFiles(String id);

  /// Both of the above, read once.
  Future<({List<JsonMap> tracks, List<JsonMap> files})> episodeSubtitles(String id);
}
SubtitleFacts subtitleFacts(MediaService media, Directory root) => host.createSubtitleFacts(media, root);

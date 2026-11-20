import 'package:path/path.dart' as p;

Future<List<Entry>> collectMediaLibraryVideos<Entry>(
  String root, {
  required Future<List<Entry>> Function(String path) listDirectory,
  required String Function(Entry entry) nameOf,
  required String Function(Entry entry) pathOf,
  required bool Function(Entry entry) isDirectory,
  required bool Function(String name) isVideoFile,
  required void Function(Object error) onListError,
}) async {
  final videos = <Entry>[];

  Future<List<Entry>> readEntries(String path) async {
    try {
      return await listDirectory(path);
    } catch (error) {
      onListError(error);
      return [];
    }
  }

  bool hasBdmvMarker(List<Entry> entries) => entries.any((entry) {
        final name = nameOf(entry).toLowerCase();
        return (name == 'index.bdmv' || name == 'movieobject.bdmv') &&
            !isDirectory(entry);
      });

  Future<void> visit(List<Entry> entries) async {
    final bdmvListings = <String, List<Entry>>{};
    final structures = <String>{};
    for (final entry in entries) {
      if (isDirectory(entry) && nameOf(entry).toLowerCase() == 'bdmv') {
        final path = pathOf(entry);
        final listing = await readEntries(path);
        if (hasBdmvMarker(listing)) {
          structures.add(path);
        } else {
          bdmvListings[path] = listing;
        }
      }
    }

    for (final entry in entries) {
      if (isDirectory(entry)) {
        final path = pathOf(entry);
        final name = nameOf(entry).toLowerCase();
        if (structures.contains(path) ||
            (structures.isNotEmpty &&
                (name == 'certificate' || name == 'menu'))) {
          continue;
        }
        await visit(bdmvListings[path] ?? await readEntries(path));
      } else if (isVideoFile(nameOf(entry))) {
        videos.add(entry);
      }
    }
  }

  final entries = await readEntries(root);
  if (p.posix.basename(root).toLowerCase() != 'bdmv' ||
      !hasBdmvMarker(entries)) {
    await visit(entries);
  }
  return videos;
}

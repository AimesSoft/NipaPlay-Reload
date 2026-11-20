import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

final class ScanDiscStructure {
  ScanDiscStructure(this.root);

  final String root;
  final _markers = <String, List<String>>{};

  Future<JsonMap?> fileFacts(String path) async {
    for (var directory = p.dirname(path);
        p.isWithin(root, directory);
        directory = p.dirname(directory)) {
      final name = p.basename(directory).toLowerCase();
      if (name != 'bdmv' && name != 'menu' && name != 'certificate') continue;
      final discRoot = p.dirname(directory);
      final bdmv = name == 'bdmv' ? directory : p.join(discRoot, 'BDMV');
      final markers = _markers[bdmv] ??= await _findMarkers(bdmv);
      if (markers.isNotEmpty) {
        return {
          'kind': 'bluray',
          'root': discRoot,
          'directory': directory,
          'markers': markers,
        };
      }
    }
    return null;
  }

  Future<List<String>> _findMarkers(String directory) async {
    if (await FileSystemEntity.type(directory, followLinks: false) !=
        FileSystemEntityType.directory) return const [];
    final markers = <String>[];
    for (final name in ['index.bdmv', 'MovieObject.bdmv']) {
      final path = p.join(directory, name);
      if (await FileSystemEntity.type(path, followLinks: false) ==
          FileSystemEntityType.file) markers.add(path);
    }
    return markers;
  }
}

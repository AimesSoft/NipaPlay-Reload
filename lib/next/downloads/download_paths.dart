import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

void validateDownloadDirectory(String directory) {
  if (directory.trim().isEmpty ||
      !p.isAbsolute(directory) ||
      directory != directory.trim()) {
    throw const Failure(FailureCode.invalidInput,
        'Use an absolute download directory without surrounding whitespace.');
  }
}

/// Check both lexical containment and existing symlink ancestors. Missing
/// descendants are allowed so partially downloaded torrents can be deleted.
Future<String> checkedDownloadPath(String output, String path) async {
  if (output.trim().isEmpty || !p.isAbsolute(output)) {
    throw const Failure(
        FailureCode.invalidInput, 'Invalid download output directory.');
  }
  final root = p.normalize(output);
  final target = p.normalize(path);
  if (!p.isWithin(root, target)) {
    throw const Failure(FailureCode.invalidInput,
        'Download file escapes its output directory.');
  }
  final canonicalRoot = await Directory(root).resolveSymbolicLinks();
  var ancestor = target;
  while (await FileSystemEntity.type(ancestor, followLinks: false) ==
      FileSystemEntityType.notFound) {
    ancestor = p.dirname(ancestor);
  }
  final canonicalAncestor = await File(ancestor).resolveSymbolicLinks();
  if (canonicalAncestor != canonicalRoot &&
      !p.isWithin(canonicalRoot, canonicalAncestor)) {
    throw const Failure(FailureCode.invalidInput,
        'Download file resolves outside its output directory.');
  }
  return target;
}

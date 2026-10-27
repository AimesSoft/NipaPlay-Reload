import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

/// Startup only submits file-indexing jobs. Identity and metadata decisions
/// remain explicit Agent operations after the files have been discovered.
Future<JsonMap> submitStartupIndex({
  required bool enabled,
  required Iterable<String> roots,
  required Future<void> Function(String root) submit,
}) async {
  if (!enabled) return {'state': 'disabled', 'submitted': <String>[]};
  final submitted = <String>[];
  final skipped = <JsonMap>[];
  for (final root in roots.toSet()) {
    if (!p.isAbsolute(root) ||
        Uri.tryParse(root)?.hasScheme == true &&
            !RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(root)) {
      skipped.add({'root': root, 'reason': 'not_local_directory'});
      continue;
    }
    try {
      if (!await Directory(root).exists()) {
        skipped.add({'root': root, 'reason': 'directory_unavailable'});
        continue;
      }
      await submit(root);
      submitted.add(root);
    } catch (error) {
      skipped.add({
        'root': root,
        'reason': 'submission_failed',
        'error': error.toString()
      });
    }
  }
  return {'state': 'submitted', 'submitted': submitted, 'skipped': skipped};
}

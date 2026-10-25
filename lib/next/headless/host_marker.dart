import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Makes [root] a headless data directory when it is empty or new, and refuses
/// a directory that has other contents but no `headless.json` marker.
Future<void> ensureHeadlessMarker(Directory root) async {
  final marker = File(p.join(root.path, 'headless.json'));
  if (await marker.exists()) return;
  if (await root.exists() && !await root.list().isEmpty) {
    throw StateError(
        'Refusing a nonempty directory without a headless.json marker.');
  }
  await root.create(recursive: true);
  await marker
      .writeAsString(jsonEncode({'format': 1, 'host': 'nipaplay-headless'}));
}

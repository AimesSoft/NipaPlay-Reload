import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Move the task registry out of user-selected download folders. Media files
/// stay in place; old registries remain available as backups.
class TorrentSessionStorage {
  static Future<String> prepare(
    Directory destination,
    Iterable<String> legacyDownloadDirectories,
  ) async {
    await destination.create(recursive: true);
    final database = File(p.join(destination.path, 'session.json'));
    final marker = File(p.join(destination.path, 'legacy-imports.json'));
    final imported = await marker.exists()
        ? (jsonDecode(await marker.readAsString()) as List)
            .cast<String>()
            .toSet()
        : <String>{};
    final data = await database.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await database.readAsString()) as Map)
        : <String, dynamic>{'torrents': <String, dynamic>{}};
    final torrents = Map<String, dynamic>.from(data['torrents'] as Map);
    final hashes = torrents.values
        .map((value) => (value as Map)['info_hash'] as String)
        .toSet();
    var nextId = torrents.keys.fold<int>(0, (next, id) {
      final value = int.parse(id) + 1;
      return value > next ? value : next;
    });
    var changed = false;
    for (final directory in legacyDownloadDirectories.toSet()) {
      final legacy =
          p.normalize(p.join(directory, '.nipaplay_torrent_session'));
      if (imported.contains(legacy) || p.equals(legacy, destination.path)) {
        continue;
      }
      final oldDatabase = File(p.join(legacy, 'session.json'));
      if (!await oldDatabase.exists()) continue;
      final old = jsonDecode(await oldDatabase.readAsString()) as Map;
      for (final value in (old['torrents'] as Map).values) {
        final task = Map<String, dynamic>.from(value as Map);
        final hash = task['info_hash'] as String;
        if (!RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(hash)) {
          throw FormatException('Invalid torrent hash in $legacy');
        }
        if (!hashes.add(hash)) continue;
        for (final extension in ['torrent', 'bitv']) {
          final source = File(p.join(legacy, '$hash.$extension'));
          final target = File(p.join(destination.path, '$hash.$extension'));
          if (await source.exists() && !await target.exists()) {
            final copy = await source.copy('${target.path}.migrating');
            await copy.rename(target.path);
          }
        }
        torrents['${nextId++}'] = task;
      }
      imported.add(legacy);
      changed = true;
    }
    if (changed) {
      data['torrents'] = torrents;
      // Save tasks before the marker. Re-running after interruption deduplicates
      // hashes; once imported, removing a task must not resurrect it next launch.
      await _writeAtomically(database, data);
      await _writeAtomically(marker, imported.toList());
    }
    return destination.path;
  }

  static Future<void> _writeAtomically(File file, Object value) async {
    final temporary = File('${file.path}.migrating');
    await temporary.writeAsString(jsonEncode(value), flush: true);
    await temporary.rename(file.path);
  }
}

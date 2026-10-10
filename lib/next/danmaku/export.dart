import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'store.dart';

/// The composition root supplies MA's configured local media-folder boundary.
final class DanmakuExporter {
  const DanmakuExporter(this.store, this.authorizeDirectory);
  final DanmakuStore store;
  final Future<String> Function(String path) authorizeDirectory;
  Future<JsonMap> export(String bindingId, String path, String view) async {
    if (!p.isAbsolute(path) || p.extension(path).toLowerCase() != '.json') {
      throw const Failure(
          FailureCode.invalidInput, 'Export requires an absolute .json path.');
    }
    final directory = await authorizeDirectory(p.dirname(path));
    final target = File(p.join(directory, p.basename(path)));
    if (await FileSystemEntity.type(target.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const Failure(
          FailureCode.conflict, 'Export destination already exists.');
    }
    final b = await store.binding(bindingId);
    final key = b['cache_key'] as String?;
    if (key == null) {
      throw const Failure(
          FailureCode.unavailable, 'Binding has no committed cache.');
    }
    final entries = await store.entries(key);
    final bytes = utf8.encode(jsonEncode({
      'platform': (b['video'] as JsonMap)['sourceId'],
      'platformVideoId': (b['video'] as JsonMap)['videoId'],
      'video': b['video'],
      'view': view,
      'offsetMs': b['offset_ms'],
      'comments': view == 'raw'
          ? [
              for (final e in entries) {...e.toJson(), ...e.toPlayer()}
            ]
          : [
              for (final e in entries)
                {
                  ...e.toPlayer(),
                  'time': (e.sourceTimeMs - (b['offset_ms'] as int)) / 1000
                }
            ]
    }));
    // Exclusive creation rejects a concurrent destination or symlink insertion.
    await target.create(exclusive: true);
    await target.writeAsBytes(bytes, flush: true);
    final digest = sha256.convert(bytes).toString();
    if (sha256.convert(await target.readAsBytes()).toString() != digest) {
      throw const Failure(
          FailureCode.conflict, 'Export readback differs from source data.');
    }
    return {
      'path': target.path,
      'count': entries.length,
      'bytes': bytes.length,
      'sha256': digest,
      'view': view
    };
  }
}

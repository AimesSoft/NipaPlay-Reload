import 'dart:convert';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../media/media_service.dart';
import 'download_backend.dart';

/// Records verified download files without choosing any media identity.
/// The download executor verifies containment and size before calling this
/// adapter. Probing and identification remain separate media capabilities.
final class IndexedDownloadLibrary implements DownloadLibrary {
  IndexedDownloadLibrary(MediaService service) : this.lazy(() => service);
  IndexedDownloadLibrary.lazy(this.media);
  final MediaService Function() media;

  @override
  Future<bool> get enabled async => true;
  @override
  bool get isBusy => false;

  // Separate from Classic's scanned-torrent markers: registering a file in
  // Next must not certify that Classic matched it (or vice versa).
  @override
  Future<bool> wasImported(String key) async =>
      (await media().store.database.query('ui_cache',
              columns: ['id'],
              where: 'id=?',
              whereArgs: ['download-import:$key']))
          .isNotEmpty;

  @override
  Future<void> markImported(String key) async {
    final service = media();
    await service.mutate(() => service.store.database.insert(
        'ui_cache',
        {
          'id': 'download-import:$key',
          'fingerprint': 'verified',
          'payload': 'true',
        },
        conflictAlgorithm: ConflictAlgorithm.replace));
  }

  @override
  Future<JsonMap?> lookup(String path) async {
    final service = media();
    final id = await service
        .mutate(() => service.store.ensureFile(path, via: 'download_import'));
    return _entry(service, path, id);
  }

  @override
  Future<JsonMap?> registered(String path) async {
    final service = media();
    final id = await service.store.registeredFileId(path);
    return id == null ? null : _entry(service, path, id);
  }

  Future<JsonMap> _entry(MediaService service, String path, String id) async {
    final episodes = await service.store.database.rawQuery(
        'SELECT e.id AS episodeId, r.parent_id AS workId, e.attributes '
        'FROM media_file_episodes fe '
        'JOIN media_entities e ON e.id=fe.episode_id '
        'JOIN media_entities r ON r.id=e.parent_id WHERE fe.file_id=?',
        [id]);
    final sources = await service.store.linkSources(id);
    return {
      'path': path,
      'fileId': id,
      'workIds': episodes.map((e) => e['workId']).toSet().toList(),
      'episodeIds': [for (final e in episodes) e['episodeId']],
      'episodes': [
        for (final e in episodes)
          {
            'episodeId': e['episodeId'],
            'workId': e['workId'],
            'facts': jsonDecode(e['attributes'] as String),
            'identitySources': sources[e['episodeId']] ?? <JsonMap>[],
          }
      ],
      'identificationPending': episodes.isEmpty,
    };
  }

  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    for (final path in paths) {
      await lookup(path);
    }
    return true;
  }
}

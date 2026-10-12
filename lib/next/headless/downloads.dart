import 'package:nipa_harness/nipa_harness.dart';
import '../downloads/download_backend.dart';
import '../media/media_service.dart';

/// The current native initializer has global DHT persistence and wildcard UDP.
final class HeadlessDownloadBackend implements DownloadBackend {
  static const reason = 'Headless downloads require a Rust initializer with '
      'isolated DHT persistence and explicit listener policy. The current '
      'Classic initializer cannot be used under the headless isolation contract.';
  @override
  DownloadBackendRef get reference => const DownloadBackendRef.builtin();
  @override
  String? get credentialRef => null;
  Never _unavailable() => throw const Failure(FailureCode.unavailable, reason);
  @override
  Future<void> initialize() async => _unavailable();
  @override
  Future<List<DownloadSnapshot>> list() async => _unavailable();
  @override
  Future<DownloadSnapshot> read(String handle) async => _unavailable();
  @override
  Future<DownloadSnapshot> add(DownloadRequest request,
          {Future<void>? stopRequested}) async =>
      _unavailable();
  @override
  Future<void> pause(String handle) async => _unavailable();
  @override
  Future<void> resume(String handle) async => _unavailable();
  @override
  Future<void> remove(String handle) async => _unavailable();
  @override
  Future<void> delete(String handle) async => _unavailable();
  @override
  Future<int?> readSize(DownloadFile file) async => _unavailable();
}

final class HeadlessDownloadLibrary implements DownloadLibrary {
  HeadlessDownloadLibrary(this.media);
  final MediaService media;
  @override
  Future<bool> get enabled async => true;
  @override
  bool get isBusy => false;
  @override
  Future<bool> wasImported(String key) async =>
      (await media.store.database.query('ui_cache',
              where: 'id=?', whereArgs: ['download-import:$key']))
          .isNotEmpty;
  @override
  Future<void> markImported(String key) =>
      media.store.database.insert('ui_cache', {
        'id': 'download-import:$key',
        'fingerprint': 'verified',
        'payload': 'true'
      }).then((_) {});
  @override
  Future<JsonMap?> lookup(String path) async {
    final id = await media.store.ensureFile(path);
    final works = await media.store.database.rawQuery(
        'SELECT DISTINCT e.parent_id AS workId FROM media_file_episodes fe '
        'JOIN media_entities e ON e.id=fe.episode_id WHERE fe.file_id=?',
        [id]);
    return {
      'path': path,
      'fileId': id,
      'workIds': [for (final w in works) w['workId']],
      'identificationPending': works.isEmpty
    };
  }

  @override
  Future<bool> importFiles(List<String> paths, String outputDirectory) async {
    for (final path in paths) {
      await media.index(path);
    }
    return true;
  }
}

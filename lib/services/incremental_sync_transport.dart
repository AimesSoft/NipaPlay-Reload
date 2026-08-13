import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;

abstract class IncrementalSyncTransport {
  Future<void> ensureDirectory(String path);

  Future<List<String>> listFileNames(String path);

  Future<Uint8List?> read(String path);

  Future<void> write(String path, Uint8List bytes, {bool atomic = false});
}

class WebDavIncrementalSyncTransport implements IncrementalSyncTransport {
  WebDavIncrementalSyncTransport({
    required String serverUrl,
    required String username,
    required String password,
  }) : _client = webdav.newClient(
          serverUrl.trim(),
          user: username.trim(),
          password: password,
          debug: false,
        ) {
    _client.setHeaders({
      'accept-charset': 'utf-8',
      'user-agent': 'NipaPlay-IncrementalSync/1.0',
    });
    _client.setConnectTimeout(15000);
    _client.setSendTimeout(60000);
    _client.setReceiveTimeout(60000);
  }

  final webdav.Client _client;

  @override
  Future<void> ensureDirectory(String path) => _client.mkdirAll(path);

  @override
  Future<List<String>> listFileNames(String path) async {
    final files = await _client.readDir(path);
    return files
        .where((file) => file.isDir != true)
        .map((file) => file.name ?? '')
        .where((name) => name.isNotEmpty)
        .toList();
  }

  @override
  Future<Uint8List?> read(String path) async {
    try {
      return Uint8List.fromList(await _client.read(path));
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> write(
    String path,
    Uint8List bytes, {
    bool atomic = false,
  }) async {
    if (!atomic) {
      await _client.write(path, bytes);
      return;
    }

    final temporaryPath = '$path.tmp-${DateTime.now().microsecondsSinceEpoch}';
    await _client.write(temporaryPath, bytes);
    try {
      await _client.rename(temporaryPath, path, true);
    } catch (_) {
      // A few WebDAV implementations do not expose MOVE. The immutable
      // snapshot/patch objects remain safe; only the small manifest falls back
      // to a direct PUT.
      await _client.write(path, bytes);
      try {
        await _client.remove(temporaryPath);
      } catch (_) {}
    }
  }
}

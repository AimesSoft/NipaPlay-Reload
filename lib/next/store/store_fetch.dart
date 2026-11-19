import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

import 'package:crypto/crypto.dart';

/// Why nothing usable came from any address of a file.
final class StoreFetchException implements Exception {
  const StoreFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Fetches a store file whole, trying [sources] in order, and holds it to
/// what was promised: a SHA-256 (the official list), npm's `sha512-`
/// integrity (a package someone named), and at most [maxBytes]. A mirror can
/// change where bytes come from, never what they are.
///
/// Store files are small (a skill's scripts, a plugin's tarball), so there is
/// no resuming; a failed address is left for the next.
final class StoreFetch {
  StoreFetch(this.client);
  final HttpClient Function() client;

  Future<List<int>> bytes(List<Uri> sources,
      {String? sha256Hex,
      String? integrity,
      int? size,
      required int maxBytes,
      Map<String, String> headers = const {}}) async {
    if (sources.isEmpty) throw const StoreFetchException('没有可用的下载地址');
    final failures = <String>[];
    for (final source in sources) {
      try {
        final body = await _get(source, maxBytes, headers);
        if (size != null && body.length != size) {
          failures.add('${source.host}：大小与预期不符');
          continue;
        }
        if (sha256Hex != null && sha256.convert(body).toString() != sha256Hex) {
          failures.add('${source.host}：SHA-256 与预期不符');
          continue;
        }
        if (integrity != null && !matchesIntegrity(body, integrity)) {
          failures.add('${source.host}：完整性校验不符');
          continue;
        }
        return body;
      } on StoreFetchException catch (error) {
        failures.add('${source.host}：${error.message}');
      } on SocketException catch (error) {
        failures.add('${source.host}：连接失败（${error.osError?.message ?? error.message}）');
      } on TimeoutException {
        failures.add('${source.host}：响应超时');
      } on HandshakeException {
        failures.add('${source.host}：服务器证书无法验证');
      } on HttpException catch (error) {
        failures.add('${source.host}：${error.message}');
      }
    }
    throw StoreFetchException(failures.join('；'));
  }

  Future<String> text(List<Uri> sources,
          {required int maxBytes, Map<String, String> headers = const {}}) async =>
      utf8.decode(await bytes(sources, maxBytes: maxBytes, headers: headers));

  Future<List<int>> _get(
      Uri uri, int maxBytes, Map<String, String> headers) async {
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (!await file.exists()) throw const StoreFetchException('文件不存在');
      if (await file.length() > maxBytes) {
        throw const StoreFetchException('文件过大');
      }
      return file.readAsBytes();
    }
    final http = client()
      ..connectionTimeout = const Duration(seconds: 20)
      ..autoUncompress = true;
    try {
      final request = await http.getUrl(uri);
      headers.forEach(request.headers.set);
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw StoreFetchException('HTTP ${response.statusCode}');
      }
      final out = BytesBuilder(copy: false);
      await for (final chunk
          in response.timeout(const Duration(seconds: 30))) {
        out.add(chunk);
        if (out.length > maxBytes) throw const StoreFetchException('文件过大');
      }
      return out.takeBytes();
    } finally {
      http.close(force: true);
    }
  }
}

/// Whether [body] has npm's Subresource Integrity [integrity]
/// (`sha512-<base64>`; any one of several space-separated values).
bool matchesIntegrity(List<int> body, String integrity) {
  final digest = base64.encode(sha512.convert(body).bytes);
  return integrity
      .split(RegExp(r'\s+'))
      .any((value) => value == 'sha512-$digest');
}

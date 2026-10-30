import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import 'download_backend.dart';

final class DownloadSources {
  DownloadSources(this.cache, {HttpClient Function()? clientFactory})
      : _clientFactory = clientFactory ?? HttpClient.new;
  final Directory cache;
  final HttpClient Function() _clientFactory;
  static const maxTorrentBytes = 16 * 1024 * 1024;

  /// Prepared torrent bytes are already local and hash-validated. Preview never
  /// creates a native task or needs a writable media/download directory.
  Future<Map<String, Object?>> previewTorrent(DownloadRequest request) async =>
      torrentManifest(await File(request.source).readAsBytes());

  Future<DownloadRequest> prepare(String source) async {
    try {
      return await _prepare(source);
    } on SocketException catch (error) {
      throw Failure(FailureCode.unavailable, error.toString(), retryable: true);
    } on HttpException catch (error) {
      throw Failure(FailureCode.unavailable, error.toString(), retryable: true);
    } on TimeoutException catch (error) {
      throw Failure(FailureCode.unavailable, error.toString(), retryable: true);
    } on FileSystemException catch (error) {
      throw Failure(FailureCode.unavailable, error.toString(), retryable: true);
    } on FormatException catch (error) {
      throw Failure(FailureCode.invalidInput, error.toString());
    }
  }

  Future<DownloadRequest> _prepare(String source) async {
    final uri = Uri.tryParse(source);
    if (uri == null || source.trim().isEmpty) {
      throw const Failure(FailureCode.invalidInput, 'Invalid download source.');
    }
    if (uri.scheme == 'magnet') {
      final hashes = (uri.queryParametersAll['xt'] ?? [])
          .where((value) => value.startsWith('urn:btih:'))
          .map((value) => magnetInfoHash(value.substring(9)))
          .toSet();
      if (hashes.length != 1) {
        throw const Failure(FailureCode.invalidInput,
            'Magnet must contain one BT v1 infoHash.');
      }
      if (uri.queryParameters['dn'] == '') {
        throw const Failure(
            FailureCode.invalidInput, 'Magnet display name must not be empty.');
      }
      return DownloadRequest(
          source: source,
          infoHash: hashes.single,
          title: uri.queryParameters['dn'] ?? hashes.single);
    }
    Uint8List bytes;
    String localPath;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      if (uri.host.isEmpty) {
        throw const Failure(
            FailureCode.invalidInput, 'Torrent URL must contain a host.');
      }
      final client = _clientFactory();
      try {
        final response = await (await client.getUrl(uri))
            .close()
            .timeout(const Duration(seconds: 30));
        if (response.statusCode != HttpStatus.ok) {
          throw Failure(FailureCode.unavailable,
              'Torrent URL returned HTTP ${response.statusCode}.',
              retryable: true);
        }
        final builder = BytesBuilder(copy: false);
        await for (final chunk
            in response.timeout(const Duration(seconds: 30))) {
          if (builder.length + chunk.length > maxTorrentBytes) {
            throw const Failure(
                FailureCode.invalidInput, 'Torrent metadata exceeds 16 MiB.');
          }
          builder.add(chunk);
        }
        bytes = builder.takeBytes();
      } finally {
        client.close(force: true);
      }
      await cache.create(recursive: true);
      localPath = p.join(cache.path, '${torrentInfoHash(bytes)}.torrent');
      await File(localPath).writeAsBytes(bytes, flush: true);
    } else {
      if (uri.scheme.isNotEmpty &&
          uri.scheme != 'file' &&
          !p.isAbsolute(source)) {
        throw const Failure(FailureCode.invalidInput,
            'Expected magnet, HTTP torrent URL, or local torrent path.');
      }
      if (uri.scheme == 'file' &&
          (uri.hasQuery ||
              uri.hasFragment ||
              uri.host.isNotEmpty && uri.host != 'localhost')) {
        throw const Failure(FailureCode.invalidInput,
            'Expected a local file URI without query or fragment.');
      }
      localPath = uri.scheme == 'file' ? uri.toFilePath() : source;
      final file = File(localPath);
      if (!await file.exists() || await file.length() > maxTorrentBytes) {
        throw const Failure(FailureCode.invalidInput,
            'Torrent file is missing or exceeds 16 MiB.');
      }
      bytes = await file.readAsBytes();
      // Persist local metadata too: recovery cannot depend on the picker path.
      await cache.create(recursive: true);
      final cached = p.join(cache.path, '${torrentInfoHash(bytes)}.torrent');
      await File(cached).writeAsBytes(bytes, flush: true);
      localPath = cached;
    }
    final hash = torrentInfoHash(bytes);
    final name = torrentManifest(bytes)['name'] as String;
    return DownloadRequest(source: localPath, infoHash: hash, title: name);
  }
}

String magnetInfoHash(String value) {
  if (RegExp(r'^[a-fA-F0-9]{40}$').hasMatch(value)) return value.toLowerCase();
  if (!RegExp(r'^[A-Za-z2-7]{32}$').hasMatch(value)) {
    throw const Failure(FailureCode.invalidInput, 'Invalid BT infoHash.');
  }
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  var bits = 0, buffer = 0;
  final bytes = <int>[];
  for (final character in value.toUpperCase().split('')) {
    buffer = (buffer << 5) | alphabet.indexOf(character);
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      bytes.add((buffer >> bits) & 255);
      buffer &= (1 << bits) - 1;
    }
  }
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Hash the exact bencoded info bytes, without decoding/reencoding strings.
String torrentInfoHash(Uint8List bytes) {
  final parser = _Bencode(bytes);
  parser.expect(100);
  Uint8List? info;
  final keys = <String>{};
  while (parser.peek != 101) {
    final key = latin1.decode(parser.string());
    if (!keys.add(key)) parser.invalid();
    final start = parser.offset;
    if (key == 'info' && parser.peek != 100) parser.invalid();
    parser.skip(0);
    if (key == 'info') {
      info = Uint8List.sublistView(bytes, start, parser.offset);
    }
  }
  parser.expect(101);
  if (parser.offset != bytes.length || info == null) parser.invalid();
  return sha1.convert(info).toString();
}

final class _Bencode {
  _Bencode(this.bytes);
  final Uint8List bytes;
  int offset = 0;
  Never invalid() => throw const Failure(
      FailureCode.invalidInput, 'Malformed torrent metadata.');
  int get peek => offset < bytes.length ? bytes[offset] : invalid();
  void expect(int value) {
    if (peek != value) invalid();
    offset++;
  }

  Uint8List string() {
    final start = offset;
    while (peek >= 48 && peek <= 57) {
      offset++;
    }
    if (offset == start) invalid();
    final length = int.tryParse(ascii.decode(bytes.sublist(start, offset)));
    expect(58);
    if (length == null || length < 0 || offset + length > bytes.length) {
      invalid();
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  void skip(int depth) {
    if (depth > 64) invalid();
    if (peek == 100 || peek == 108) {
      final dictionary = peek == 100;
      offset++;
      while (peek != 101) {
        if (dictionary) string();
        skip(depth + 1);
      }
      offset++;
    } else if (peek == 105) {
      offset++;
      final start = offset;
      if (peek == 45) offset++;
      final digits = offset;
      while (peek >= 48 && peek <= 57) {
        offset++;
      }
      if (digits == offset ||
          int.tryParse(ascii.decode(bytes.sublist(start, offset))) == null) {
        invalid();
      }
      expect(101);
    } else {
      string();
    }
  }

  Object value(int depth) {
    if (depth > 64) invalid();
    if (peek == 100) {
      offset++;
      final result = <String, Object>{};
      while (peek != 101) {
        final key = latin1.decode(string());
        if (result.containsKey(key)) invalid();
        result[key] = value(depth + 1);
      }
      offset++;
      return result;
    }
    if (peek == 108) {
      offset++;
      final result = <Object>[];
      while (peek != 101) { result.add(value(depth + 1)); }
      offset++;
      return result;
    }
    if (peek == 105) {
      final start = ++offset;
      while (peek != 101) { offset++; }
      final result = int.tryParse(ascii.decode(bytes.sublist(start, offset)));
      expect(101);
      return result ?? invalid();
    }
    return string();
  }
}

/// BT v1 manifest using the same bencoded bytes used for add's info hash.
JsonMap torrentManifest(Uint8List bytes) {
  torrentInfoHash(bytes);
  try {
    final info = (_Bencode(bytes).value(0) as Map)['info'] as Map;
    String component(Object? value) {
      final text = utf8.decode(value as Uint8List);
      if (text.isEmpty || text == '.' || text == '..' ||
          text.contains(RegExp(r'[/\\\x00-\x1f]')) || p.windows.isAbsolute(text) ||
          text.contains(':')) {
        throw const FormatException('Invalid torrent path component.');
      }
      return text;
    }
    final name = component(info['name.utf-8'] ?? info['name']);
    final files = <JsonMap>[];
    void file(String path, Object? size) {
      if (size is! int || size < 0) throw const FormatException();
      files.add({'index': files.length, 'path': path, 'length': size});
    }
    if (info['files'] case final List entries) {
      if (entries.isEmpty || info.containsKey('length')) throw const FormatException();
      for (final entry in entries.cast<Map>()) {
        final path = (entry['path.utf-8'] ?? entry['path']) as List;
        if (path.isEmpty) throw const FormatException();
        file([name, ...path.map(component)].join('/'), entry['length']);
      }
    } else {
      file(name, info['length']);
    }
    if ((info['piece length'] as int) <= 0 || (info['pieces'] as Uint8List).length % 20 != 0) {
      throw const FormatException();
    }
    final total = files.fold<int>(0, (sum, f) => sum + (f['length'] as int));
    if ((info['pieces'] as Uint8List).length ~/ 20 !=
        (total / (info['piece length'] as int)).ceil()) throw const FormatException();
    return {'name': name,
      'suggestedFolderName': p.posix.basenameWithoutExtension(name)
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim().replaceAll(RegExp(r'^\.+|\.+$'), '').trim(),
      'totalSize': total, 'files': files};
  } on FormatException {
    throw const Failure(FailureCode.invalidInput, 'Malformed torrent manifest.');
  } on TypeError {
    throw const Failure(FailureCode.invalidInput, 'Malformed torrent manifest.');
  }
}

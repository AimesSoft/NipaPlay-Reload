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

  Future<DownloadRequest> prepare(String source) async {
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
      return DownloadRequest(
          source: source,
          infoHash: hashes.single,
          title: uri.queryParameters['dn'] ?? hashes.single);
    }
    Uint8List bytes;
    String localPath;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
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
    return DownloadRequest(
        source: localPath,
        infoHash: torrentInfoHash(bytes),
        title: p.basename(uri.path));
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
}

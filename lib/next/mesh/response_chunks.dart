import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';

const meshChunkMarker = r'$meshResponse';

/// Completed responses stay available briefly for authenticated continuation
/// reads. Continuation never re-executes the original Action.
final class MeshResponseChunks {
  MeshResponseChunks({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  final _random = Random.secure();
  final _saved = <String, ({String peer, List<int> bytes, DateTime expires})>{};
  static const chunkBytes = 192 * 1024;
  static const maxBytes = 64 * 1024 * 1024;

  JsonMap describe(String peer, List<int> bytes) {
    _saved.removeWhere((_, value) => !value.expires.isAfter(_clock()));
    if (bytes.length > maxBytes) {
      throw const Failure(FailureCode.unavailable,
          'Completed response exceeds the transfer budget; request a smaller batch.');
    }
    while (_saved.isNotEmpty &&
        (_saved.length >= 8 || _saved.values.fold<int>(0, (n, v) => n + v.bytes.length) + bytes.length > maxBytes)) {
      _saved.remove(_saved.keys.first);
    }
    final token = base64Url.encode(List.generate(32, (_) => _random.nextInt(256))).replaceAll('=', '');
    _saved[token] = (peer: peer, bytes: bytes,
        expires: _clock().add(const Duration(minutes: 5)));
    return {'token': token, 'bytes': bytes.length, 'sha256': sha256.convert(bytes).toString()};
  }

  JsonMap read(String peer, JsonMap input) {
    final entry = _saved[input['token']];
    if (entry == null || entry.peer != peer || !entry.expires.isAfter(_clock())) {
      throw const Failure(FailureCode.notFound, 'Response continuation expired or unavailable.');
    }
    final offset = input['offset'];
    if (offset is! int || offset < 0 || offset >= entry.bytes.length) {
      throw const Failure(FailureCode.invalidInput, 'Invalid response byte offset.');
    }
    final end = (offset + chunkBytes).clamp(0, entry.bytes.length);
    return {'data': base64Encode(entry.bytes.sublist(offset, end)),
      'next': end == entry.bytes.length ? null : end};
  }

  void clear() => _saved.clear();
}

Future<JsonMap> readMeshResponse(JsonMap descriptor,
    Future<JsonMap> Function(JsonMap input) fetch) async {
  final length = descriptor['bytes'];
  if (descriptor['token'] is! String || length is! int || length < 1 ||
      length > MeshResponseChunks.maxBytes || descriptor['sha256'] is! String) {
    throw const FormatException('Invalid response continuation.');
  }
  final bytes = BytesBuilder(copy: false);
  while (bytes.length < length) {
    final page = await fetch({'token': descriptor['token'], 'offset': bytes.length});
    final chunk = base64Decode(page['data'] as String);
    if (chunk.isEmpty || bytes.length + chunk.length > length) {
      throw const FormatException('Invalid response chunk length.');
    }
    bytes.add(chunk);
    if (page['next'] != (bytes.length == length ? null : bytes.length)) {
      throw const FormatException('Incomplete response continuation.');
    }
  }
  final body = bytes.takeBytes();
  if (sha256.convert(body).toString() != descriptor['sha256']) {
    throw const FormatException('Response continuation integrity mismatch.');
  }
  return Map<String, Object?>.from(jsonDecode(utf8.decode(body)) as Map);
}

import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:nipa_harness/nipa_harness.dart';

const librarySnapshotEncoding = 'json-base64-v1';

/// Byte pages can split a single rich work record, unlike record-count pages.
/// Base64 keeps each page valid JSON even across a multibyte UTF-8 character.
final class EncodedLibrarySnapshot {
  EncodedLibrarySnapshot(this.version, List<JsonMap> records)
      : bytes = utf8.encode(jsonEncode(records));
  final String version;
  final List<int> bytes;
  static const pageBytes = 192 * 1024;

  JsonMap page(int offset) {
    if (offset < 0 || offset > bytes.length) {
      throw const FormatException('Invalid catalogue byte offset.');
    }
    final end = (offset + pageBytes).clamp(0, bytes.length);
    return {
      'version': version,
      'encoding': librarySnapshotEncoding,
      'totalBytes': bytes.length,
      'data': base64Encode(bytes.sublist(offset, end)),
      'next': end == bytes.length ? null : end,
    };
  }
}

Future<List<JsonMap>> readLibrarySnapshot(JsonMap first,
    Future<JsonMap> Function(JsonMap input) fetch) async {
  final encoded = first['encoding'] == librarySnapshotEncoding;
  final records = <JsonMap>[];
  final chunks = <String>[];
  var page = first, offset = 0;
  while (true) {
    if (page['version'] != first['version'] ||
        (page['encoding'] == librarySnapshotEncoding) != encoded) {
      throw const Failure(FailureCode.conflict,
          'Library changed during pagination.');
    }
    if (encoded) {
      chunks.add(page['data'] as String);
    } else {
      records.addAll((page['records'] as List).cast<JsonMap>());
    }
    final next = page['next'] as int?;
    if (next == null) break;
    if (next <= offset) {
      throw const FormatException('Catalogue pagination did not advance.');
    }
    offset = next;
    page = await fetch({
      'offset': offset,
      'version': first['version'],
      if (encoded) 'encoding': librarySnapshotEncoding,
    });
  }
  if (!encoded) return records;
  final expectedBytes = first['totalBytes'];
  return Isolate.run(() {
    final data = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      data.add(base64Decode(chunk));
    }
    if (data.length != expectedBytes) {
      throw const FormatException('Incomplete catalogue snapshot.');
    }
    return [
      for (final record in jsonDecode(utf8.decode(data.takeBytes())) as List)
        Map<String, Object?>.from(record as Map)
    ];
  });
}

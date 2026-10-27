import 'dart:async';
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

/// A failed, cancelled or oversized transfer never returns partial records.
Future<List<JsonMap>> readLibrarySnapshot(
  JsonMap first,
  Future<JsonMap> Function(JsonMap input) fetch, {
  int maxBytes = 64 * 1024 * 1024,
  int maxPages = 1024,
  Duration timeout = const Duration(minutes: 2),
  bool Function()? cancelled,
}) async {
  final encoded = first['encoding'] == librarySnapshotEncoding;
  final expectedBytes = first['totalBytes'];
  final deadline = DateTime.now().add(timeout);
  Never refused(String reason) => throw Failure(
          FailureCode.unavailable, 'Catalogue transfer stopped: $reason.',
          details: {
            'reason': reason,
            'stage': 'catalogue_transfer',
            'partialPublished': false,
            'maxBytes': maxBytes,
            'maxPages': maxPages,
          });
  void check() {
    if (cancelled?.call() == true) refused('cancelled');
    if (!DateTime.now().isBefore(deadline)) refused('deadline_exceeded');
  }

  if (encoded &&
      (expectedBytes is! int ||
          expectedBytes < 2 ||
          expectedBytes > maxBytes)) {
    refused('invalid_or_excessive_size');
  }
  final records = <JsonMap>[];
  final data = BytesBuilder(copy: false);
  var page = first, offset = 0, pages = 0, received = 0;
  while (true) {
    check();
    if (++pages > maxPages) refused('page_budget_exceeded');
    if (page['version'] != first['version'] ||
        (page['encoding'] == librarySnapshotEncoding) != encoded) {
      throw const Failure(
          FailureCode.conflict, 'Library changed during pagination.', details: {
        'reason': 'catalogue_version_changed',
        'partialPublished': false
      });
    }
    if (encoded) {
      final raw = page['data'];
      if (page['totalBytes'] != expectedBytes ||
          raw is! String ||
          raw.length > ((EncodedLibrarySnapshot.pageBytes + 2) ~/ 3) * 4) {
        refused('invalid_page');
      }
      final bytes = base64Decode(raw);
      if (bytes.isEmpty || received + bytes.length > (expectedBytes as int)) {
        refused('invalid_page_length');
      }
      data.add(bytes);
      received += bytes.length;
    } else {
      final bytes = utf8.encode(jsonEncode(page['records'])).length;
      received += bytes;
      if (received > maxBytes) refused('byte_budget_exceeded');
      records.addAll((page['records'] as List).cast<JsonMap>());
    }
    final next = page['next'] as int?;
    if (encoded && next != (received == expectedBytes ? null : received)) {
      refused('invalid_page_offset');
    }
    if (next == null) break;
    if (next <= offset) {
      throw const FormatException('Catalogue pagination did not advance.');
    }
    offset = next;
    try {
      page = await fetch({
        'offset': offset,
        'version': first['version'],
        if (encoded) 'encoding': librarySnapshotEncoding,
        if (first['progressSeparately'] == true) 'progressSeparately': true,
      }).timeout(deadline.difference(DateTime.now()));
    } on TimeoutException {
      refused('deadline_exceeded');
    }
  }
  check();
  if (!encoded) return records;
  final bytes = data.takeBytes();
  final result = await _decodeSnapshot(bytes);
  check();
  return result;
}

// A separate closure scope keeps the caller's network/cancellation objects
// (and their timers/native handles) out of the isolate message.
Future<List<JsonMap>> _decodeSnapshot(Uint8List bytes) => Isolate.run(() => [
      for (final record in jsonDecode(utf8.decode(bytes)) as List)
        Map<String, Object?>.from(record as Map)
    ]);

/// A bounded cache of immutable publications. Active readers keep their version
/// until their two-minute lease ends; pressure rejects a new version instead of
/// silently replacing one in the middle of a transfer.
final class LibraryPublications {
  LibraryPublications(
      {this.maxBytes = 128 * 1024 * 1024,
      this.maxEntries = 4,
      DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;
  final int maxBytes, maxEntries;
  final DateTime Function() _clock;
  final _saved = <String,
      ({
    EncodedLibrarySnapshot snapshot,
    DateTime at,
    Map<String, DateTime> leases
  })>{};
  void _expire() {
    final now = _clock();
    for (final value in _saved.values) {
      value.leases.removeWhere((_, until) => !until.isAfter(now));
    }
    _saved.removeWhere((_, value) =>
        value.leases.isEmpty &&
        now.difference(value.at) > const Duration(minutes: 5));
  }

  JsonMap? read(String version, int offset, String peer) {
    _expire();
    final saved = _saved[version];
    if (saved == null) return null;
    if (!saved.leases.containsKey(peer) && saved.leases.length >= 16) {
      throw const Failure(
          FailureCode.unavailable, 'Catalogue reader budget exhausted.',
          details: {
            'reason': 'catalogue_reader_capacity',
            'partialPublished': false
          });
    }
    final page = saved.snapshot.page(offset);
    if (page['next'] == null) {
      saved.leases.remove(peer);
    } else {
      saved.leases[peer] = _clock().add(const Duration(minutes: 2));
    }
    return page;
  }

  JsonMap publish(
      String version, List<JsonMap> records, int offset, String peer) {
    final existing = read(version, offset, peer);
    if (existing != null) return existing;
    final snapshot = EncodedLibrarySnapshot(version, records);
    if (snapshot.bytes.length > 64 * 1024 * 1024 ||
        snapshot.bytes.length > maxBytes) {
      throw const Failure(
          FailureCode.unavailable, 'Catalogue exceeds the transfer budget.',
          details: {
            'reason': 'catalogue_byte_capacity',
            'partialPublished': false
          });
    }
    while (_saved.length >= maxEntries ||
        _saved.values.fold<int>(0, (n, v) => n + v.snapshot.bytes.length) +
                snapshot.bytes.length >
            maxBytes) {
      final evictable =
          _saved.entries.where((e) => e.value.leases.isEmpty).firstOrNull;
      if (evictable == null) {
        throw const Failure(FailureCode.unavailable,
            'Active catalogue transfers occupy the publication budget.',
            retryable: true,
            details: {
              'reason': 'catalogue_publication_capacity',
              'partialPublished': false
            });
      }
      _saved.remove(evictable.key);
    }
    _saved[version] = (snapshot: snapshot, at: _clock(), leases: {});
    return read(version, offset, peer)!;
  }
}

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:nipa_harness/nipa_harness.dart';
import 'classic_metadata_port.dart';
import 'identity_store.dart';

final class ClassicProjection {
  const ClassicProjection(this.store, this.port);
  final IdentityStore store;
  final ClassicMetadataPort port;
  ClassicProjectionLookup lookup() => ClassicProjectionLookup(port.history);

  Future<void> drain({String? fileId, ClassicProjectionLookup? targets}) async {
    targets ??= lookup();
    for (final row in await store.pendingProjections(fileId: fileId)) {
      if (port is DetachedClassicMetadataPort) {
        await store.finishProjection(row['id'] as String, 'not_applicable');
        continue;
      }
      final file = await store.entity(row['file_id'] as String);
      if (file['revision'] != row['file_revision'] ||
          (file['attributes'] as JsonMap)['bindingRevision'] !=
              row['binding_revision']) {
        await store.finishProjection(row['id'] as String, 'superseded');
        continue;
      }
      final fields = decodeMediaJson(row['payload']);
      try {
        for (final location in (await store.locations(row['file_id'] as String))
            .where((location) =>
                location['owner_device_id'] == store.ownerDeviceId)) {
          final locator =
              await _deliveryLocator(row, location, fields, targets);
          // A projection delivers the Agent's committed identity to Classic.
          // Read fresh matching facts for legacy ports; never import them into
          // Next. Reversible ports check their own journal atomically in apply.
          final current = port is ReversibleClassicMetadataPort
              ? <String, Object?>{}
              : (await port.history())
                      .where((o) => o['filePath'] == locator)
                      .firstOrNull ??
                  <String, Object?>{};
          if (port is! ReversibleClassicMetadataPort &&
              fields['clear'] != true &&
              current['animeName'] != null &&
              current['animeName'] != '' &&
              current['episodeTitle'] != null &&
              current['animeId'] != null &&
              current['episodeId'] != null &&
              (current['animeId'] !=
                      (fields['animeId'] ?? fields['expectedAnimeId']) ||
                  current['episodeId'] !=
                      (fields['episodeId'] ?? fields['expectedEpisodeId']))) {
            throw const Failure(FailureCode.conflict,
                'Classic has a different match; inspect media.identity.get conflicts.');
          }
          final delivery = {...fields, 'projectionId': row['id']};
          await port.apply(locator, delivery);
          if (!await port.verify(locator, delivery)) {
            throw const Failure(FailureCode.unavailable,
                'Classic metadata projection failed readback.');
          }
        }
        // The durable outbox and Classic's journal are the delivery evidence.
        // No Classic observation or accepted identity is created by readback.
        await store.finishProjection(row['id'] as String, 'delivered');
      } on Failure catch (error) {
        if (error.code == FailureCode.conflict) {
          await store.finishProjection(row['id'] as String, 'conflict');
        }
        rethrow;
      }
    }
  }

  Future<String> _deliveryLocator(JsonMap projection, JsonMap location,
      JsonMap fields, ClassicProjectionLookup targets) async {
    final locationId = location['id'] as String;
    final source = location['locator'] as String;
    var recorded = (fields['deliveryLocators'] as Map?)?[locationId] as Map?;
    final previousId =
        fields['restoreProjectionId'] ?? fields['previousProjectionId'];
    if (recorded == null && previousId is String) {
      final previous = await store.database.query('media_projection_outbox',
          where: 'id=?', whereArgs: [previousId]);
      if (previous.isNotEmpty) {
        recorded =
            (decodeMediaJson(previous.single['payload'])['deliveryLocators']
                as Map?)?[locationId] as Map?;
      }
    }
    if (recorded == null) {
      final target = location['source'] == 'local'
          ? await targets.resolve(source)
          : (locator: source, canonical: null);
      recorded = {
        'locator': target.locator,
        if (target.canonical != null) 'canonicalPath': target.canonical
      };
    }
    // An alias is evidence only while both paths still resolve to the file
    // selected before delivery. Never follow a retargeted or removed symlink.
    if (recorded['canonicalPath'] case final String canonical) {
      try {
        if (await File(source).resolveSymbolicLinks() != canonical ||
            await File(recorded['locator'] as String).resolveSymbolicLinks() !=
                canonical) {
          throw const Failure(FailureCode.conflict,
              'The Classic projection path now identifies a different file.');
        }
      } on FileSystemException {
        throw const Failure(FailureCode.conflict,
            'The Classic projection path is no longer available for identity verification.');
      }
    }
    await store.recordProjectionLocator(projection['id'] as String, locationId,
        Map<String, Object?>.from(recorded));
    return recorded['locator'] as String;
  }
}

/// One binding batch shares a history snapshot and its lazily built path index.
/// Indexing never registers files or accepts Classic identities. Chosen aliases
/// are revalidated immediately before delivery by ClassicProjection.
final class ClassicProjectionLookup {
  ClassicProjectionLookup(this.readHistory, {this.resolvePath = _resolvePath});
  final Future<List<JsonMap>> Function() readHistory;
  final Future<String> Function(String) resolvePath;
  Future<Set<String>>? _paths;
  Future<Map<String, Set<String>>>? _aliases;

  static Future<String> _resolvePath(String path) =>
      File(path).resolveSymbolicLinks();

  Future<Set<String>> _historyPaths() => _paths ??= () async {
        return {
          for (final row in await readHistory())
            if (row['filePath'] is String) row['filePath'] as String
        };
      }();

  Future<Map<String, Set<String>>> _index() => _aliases ??= () async {
        final result = <String, Set<String>>{};
        for (final path in await _historyPaths()) {
          if (!p.isAbsolute(path)) continue;
          try {
            (result[await resolvePath(path)] ??= {}).add(path);
          } on FileSystemException {
            // Unavailable paths cannot prove equivalence to this local file.
          }
        }
        return result;
      }();

  Future<({String locator, String? canonical})> resolve(String source) async {
    if (!p.isAbsolute(source) || (await _historyPaths()).contains(source)) {
      return (locator: source, canonical: null);
    }
    final String canonical;
    try {
      canonical = await resolvePath(source);
    } on FileSystemException {
      return (locator: source, canonical: null);
    }
    final aliases = (await _index())[canonical] ?? const <String>{};
    if (aliases.length > 1) {
      throw const Failure(FailureCode.conflict,
          'Multiple Classic paths identify this file; no projection target was chosen.');
    }
    return aliases.isEmpty
        ? (locator: source, canonical: null)
        : (locator: aliases.single, canonical: canonical);
  }
}

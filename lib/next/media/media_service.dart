import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import 'classic_metadata_port.dart';
import 'projection.dart';
import 'media_probe.dart';
import 'identity_store.dart';
import 'file_identity_merge.dart';
import 'metadata_provider.dart';

final class MediaService {
  MediaService(
      {required this.store,
      required Iterable<MetadataProvider> providers,
      required this.classic,
      required this.authorizedRoots,
      this.durationProbe = probeMediaDuration})
      : providers = {for (final provider in providers) provider.id: provider},
        projection = ClassicProjection(store, classic);
  final IdentityStore store;
  final Map<String, MetadataProvider> providers;
  final ClassicMetadataPort classic;
  final ClassicProjection projection;
  final Iterable<String> Function() authorizedRoots;
  final Future<int?> Function(String path) durationProbe;
  String? Function()? currentPath;
  Future<String> resolveEntity(JsonMap input,
      {String idField = 'entityId'}) async {
    final id = input[idField] as String?;
    final path = input['path'] as String?;
    if (id != null && path != null ||
        input['current'] == true && (id != null || path != null)) {
      throw const Failure(
          FailureCode.invalidInput, 'Choose ID, path or current.');
    }
    if (id != null && id != 'current')
      return canonicalFileId(store.database, id);
    final locator = path ?? currentPath?.call();
    if (locator == null) {
      throw const Failure(FailureCode.notFound, 'No current video.');
    }
    return store.ensureFile(locator);
  }

  late TaskEngine engine;
  Future<void> _tail = Future.value();
  Future<void> _submissions = Future.value();

  // Serializes identity changes with delivery to the separate Classic database.
  Future<T> mutate<T>(Future<T> Function() operation) async {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      return await operation();
    } finally {
      done.complete();
    }
  }

  MetadataProvider provider(String id) {
    final result = providers[id];
    if (result == null) {
      throw Failure(FailureCode.invalidInput, 'Unknown metadata provider $id.');
    }
    return result;
  }

  ({DateTime at, List<String> roots, Set<String> downloads})? _shown;

  /// Whether a recorded local [locator] may be shown, mostly without
  /// touching the files: queries list many rows, and on a busy network
  /// share every path lookup waits behind the reads. Inside a configured
  /// folder (resolved at most every few seconds) or a verified download is
  /// enough; anything else is decided by [authorizedPath].
  Future<bool> mayShow(String locator) async {
    final now = DateTime.now();
    var shown = _shown;
    if (shown == null ||
        now.difference(shown.at) > const Duration(seconds: 5)) {
      final roots = <String>[];
      for (final root in authorizedRoots()) {
        if (!p.isAbsolute(root)) continue;
        try {
          roots.add(await Directory(root).resolveSymbolicLinks());
        } on FileSystemException {
          continue;
        }
      }
      final rows = await store.database.rawQuery(r'''
        SELECT coalesce(json_extract(f.value, '$.canonicalPath'), json_extract(f.value, '$.path')) AS path
        FROM jobs j, json_each(j.snapshot, '$.receipt.details.files') f
        WHERE j.type='download' AND j.state='succeeded'
        AND json_extract(j.snapshot, '$.receipt.verification')='verified'
        AND json_extract(j.snapshot, '$.receipt.details.downloadComplete')=1
        AND json_extract(f.value, '$.local')=1
        AND json_extract(f.value, '$.included')=1
        AND json_extract(f.value, '$.actualSize')=json_extract(f.value, '$.expectedSize')
      ''');
      shown = _shown = (
        at: now,
        roots: roots,
        downloads: {
          for (final r in rows)
            if (r['path'] is String) r['path'] as String
        }
      );
    }
    if (shown.roots
            .any((root) => locator == root || p.isWithin(root, locator)) ||
        shown.downloads.contains(locator)) {
      return true;
    }
    try {
      await authorizedPath(locator);
      return true;
    } on Failure {
      return false;
    }
  }

  Future<String> authorizedPath(String locator,
      {bool directory = false}) async {
    try {
      if (!p.isAbsolute(locator)) {
        throw const Failure(FailureCode.unavailable,
            'MA filesystem scanning requires a native local path.');
      }
      final path = await (directory
          ? Directory(locator).resolveSymbolicLinks()
          : File(locator).resolveSymbolicLinks());
      var allowed = false;
      for (final root in authorizedRoots()) {
        if (!p.isAbsolute(root)) continue;
        final canonical = await Directory(root).resolveSymbolicLinks();
        if (path == canonical || p.isWithin(canonical, path)) allowed = true;
      }
      if (!allowed && !directory) {
        final completed = await store.database.rawQuery(r'''
          SELECT 1 FROM jobs j, json_each(j.snapshot, '$.receipt.details.files') f
          WHERE j.type='download' AND j.state='succeeded'
          AND json_extract(j.snapshot, '$.receipt.verification')='verified'
          AND json_extract(j.snapshot, '$.receipt.details.downloadComplete')=1
          AND json_extract(f.value, '$.local')=1
          AND json_extract(f.value, '$.included')=1
          AND json_extract(f.value, '$.actualSize')=json_extract(f.value, '$.expectedSize')
          AND coalesce(json_extract(f.value, '$.canonicalPath'), json_extract(f.value, '$.path'))=? LIMIT 1
        ''', [path]);
        allowed = completed.isNotEmpty;
      }
      if (!allowed) {
        throw const Failure(FailureCode.unavailable,
            'Path is outside the configured media folders.');
      }
      return path;
    } on FileSystemException catch (error) {
      throw _fileFailure(error);
    }
  }

  Future<JsonMap> probe(String locator, {bool includeDuration = true}) async {
    try {
      final path = await authorizedPath(locator);
      final file = File(path);
      final before = await file.stat();
      final stream = await file.open();
      final List<int> bytes;
      try {
        bytes = await stream.read(math.min(before.size, 16 * 1024 * 1024));
      } finally {
        await stream.close();
      }
      final duration = includeDuration ? await durationProbe(path) : null;
      final after = await file.stat();
      if (before.size != after.size || before.modified != after.modified) {
        throw const Failure(
            FailureCode.conflict, 'File changed during probing.');
      }
      return {
        'size': after.size,
        'modifiedAt': after.modified.toUtc().toIso8601String(),
        'headMd5': md5.convert(bytes).toString(),
        'durationMs': duration
      };
    } on FileSystemException catch (error) {
      throw _fileFailure(error);
    }
  }

  Failure _fileFailure(FileSystemException error) => Failure(
      error.osError?.errorCode == 2
          ? FailureCode.notFound
          : FailureCode.unavailable,
      'Media path is inaccessible: ${error.message}');

  Future<String> index(String locator) async {
    final path = await authorizedPath(locator);
    final info = await probe(path);
    return mutate(() async {
      final id = await store.registerFile(path, info);
      await projection.drain(fileId: id);
      return id;
    });
  }

  Future<Job> submit(String type, JsonMap input, {String? key}) async {
    final previous = _submissions;
    final done = Completer<void>();
    _submissions = done.future;
    await previous;
    try {
      if (key != null) {
        final existing = await engine.store.get(key);
        if (existing != null) return existing;
      }
      return await engine.submit(
          type: type,
          title: switch (type) {
            'media.scan' => 'Scan media folder',
            'media.project' => 'Deliver Classic metadata',
            _ => 'Refresh media metadata'
          },
          input: input,
          jobId: key);
    } finally {
      done.complete();
    }
  }

  Future<void> recoverProjections() async {
    final pending = await store.pendingProjections();
    for (final fileId
        in pending.map((row) => row['file_id'] as String).toSet()) {
      await submit('media.project', {'fileId': fileId});
    }
  }

  Future<int> syncClassicHistory() =>
      mutate(() async => store.importLegacy(await classic.history()));

  Future<List<String>> directoryFiles(String locator) async {
    final root = await authorizedPath(locator, directory: true);
    final paths = <String>[];
    try {
      await for (final entry
          in Directory(root).list(recursive: true, followLinks: false)) {
        if (await FileSystemEntity.isFile(entry.path) &&
            {
              '.mkv',
              '.mp4',
              '.avi',
              '.mov',
              '.m4v',
              '.ts',
              '.webm',
              '.wmv',
              '.flv'
            }.contains(p.extension(entry.path).toLowerCase())) {
          paths.add(entry.path);
        }
      }
    } on FileSystemException catch (error) {
      throw _fileFailure(error);
    }
    paths.sort();
    return paths;
  }

  Future<({String path, String? fileId, JsonMap probe})> readFile(JsonMap input,
      {bool includeDuration = true}) async {
    String path;
    String? id = input['entityId'] as String?;
    if (id != null) {
      final entity = await store.entity(id);
      id = entity['id'] as String;
      if (entity['kind'] != 'file') {
        throw const Failure(
            FailureCode.invalidInput, 'entityId must reference a file.');
      }
      final local = (await store.locations(id))
          .where((row) =>
              row['source'] == 'local' &&
              row['owner_device_id'] == store.ownerDeviceId)
          .toList();
      if (local.isEmpty) {
        throw const Failure(FailureCode.unavailable,
            'File has no local location on this device.');
      }
      path = local.first['locator'] as String;
    } else {
      final locator = input['path'] as String;
      path = await authorizedPath(locator);
      var locations = await store.database.query('media_locations',
          where: 'owner_device_id=? AND locator=?',
          whereArgs: [store.ownerDeviceId, locator]);
      if (locations.isEmpty && locator != path) {
        locations = await store.database.query('media_locations',
            where: 'owner_device_id=? AND locator=?',
            whereArgs: [store.ownerDeviceId, path]);
      }
      if (locations.isNotEmpty) id = locations.first['file_id'] as String;
    }
    return (
      path: path,
      fileId: id,
      probe: await probe(path, includeDuration: includeDuration)
    );
  }

  Future<JsonMap> listFiles(JsonMap input) async {
    final result = <JsonMap>[];
    if (input['root'] case final String root) {
      for (final path in await directoryFiles(root)) {
        final info = await readFile({'path': path});
        result.add(await _fileDescription(info.fileId, path, info.probe));
      }
    } else {
      final workId = input['workId'] as String;
      if ((await store.entity(workId))['kind'] != 'work') {
        throw const Failure(
            FailureCode.invalidInput, 'workId must reference a work.');
      }
      final rows = await store.database.rawQuery(
          'SELECT DISTINCT f.id FROM media_entities f JOIN media_file_episodes fe ON fe.file_id=f.id '
          'JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE r.parent_id=? ORDER BY f.id',
          [workId]);
      for (final row in rows) {
        final id = row['id'] as String;
        final file = await store.entity(id);
        final locations = await store.locations(id);
        for (final location in locations) {
          result.add(await _fileDescription(id, location['locator'] as String,
              (file['attributes'] as JsonMap)['probe'] as JsonMap));
        }
      }
    }
    return {'files': result, 'total': result.length};
  }

  Future<JsonMap> _fileDescription(
      String? id, String path, JsonMap probe) async {
    final identity = id == null ? null : await store.identity(id);
    return {
      'fileId': id,
      'path': path,
      'size': probe['size'],
      'durationMs': probe['durationMs'],
      'headMd5': probe['headMd5'],
      'modifiedAt': probe['modifiedAt'],
      'bindings': [
        for (final row in (identity?['bindings'] as List<JsonMap>?) ?? [])
          if (row['status'] == 'accepted')
            {
              'bindingId': row['id'],
              'ref': {
                'provider': row['provider'],
                'objectType': row['object_type'],
                'externalId': row['external_id'],
                'scope': row['object_scope']
              },
              'relation': row['relation'],
              'scope': row['scope'],
              'boundBy': row['bound_by'],
              'source': row['source']
            }
      ],
      'episodes': [
        for (final row in (identity?['episodes'] as List<JsonMap>?) ?? [])
          {
            'episodeId': row['episode_id'],
            'relation': row['relation'],
            'ordinal': row['ordinal'],
            'startMs': row['start_ms'],
            'endMs': row['end_ms']
          }
      ]
    };
  }

  Future<JsonMap> matchHashes(List<JsonMap> files) async {
    final source = provider('dandanplay');
    if (source is! HashMetadataProvider) {
      throw const Failure(
          FailureCode.unavailable, 'Dandanplay hash matching is unavailable.');
    }
    final results = <JsonMap>[];
    for (var index = 0; index < files.length; index++) {
      try {
        final info = await readFile(files[index], includeDuration: false);
        final matches = await source.matchHash(p.basename(info.path),
            info.probe['headMd5'] as String, info.probe['size'] as int);
        results.add({
          'index': index,
          'fileId': info.fileId,
          'path': info.path,
          'headMd5': info.probe['headMd5'],
          'candidates': [for (final record in matches) record.toJson()]
        });
      } on Failure catch (error) {
        results.add({'index': index, 'error': error.toJson()});
      } on ProviderRetry catch (error) {
        results.add({
          'index': index,
          'error': Failure(FailureCode.unavailable,
                  '${error.provider}: ${error.reason} Retry after ${error.at.toUtc().toIso8601String()}.',
                  retryable: true)
              .toJson()
        });
      }
    }
    return {'files': results};
  }

  Future<({String path, String? fileId, JsonMap probe, bool locationOnly})>
      _bindingFile(JsonMap entry) async {
    String? id = entry['entityId'] as String?;
    final uri =
        entry['path'] == null ? null : Uri.tryParse(entry['path'] as String);
    if (id == null &&
        !p.isAbsolute(entry['path'] as String? ?? '') &&
        uri != null &&
        uri.scheme.isNotEmpty &&
        uri.scheme != 'file') {
      final locations = await store.database.query('media_locations',
          where: 'owner_device_id=? AND locator=?',
          whereArgs: [store.ownerDeviceId, entry['path']]);
      if (locations.length > 1) {
        throw const Failure(FailureCode.conflict,
            'This path belongs to multiple sources; use the source browse fileId.');
      }
      if (locations.isEmpty) {
        throw const Failure(FailureCode.notFound,
            'Remote path is not indexed; browse its source or use an indexed fileId.');
      }
      id = locations.single['file_id'] as String;
    }
    if (id != null) {
      final file = await store.entity(id);
      if (file['kind'] != 'file') {
        throw const Failure(
            FailureCode.invalidInput, 'entityId must reference a file.');
      }
      final locations = (await store.locations(id))
          .where((row) => row['owner_device_id'] == store.ownerDeviceId)
          .toList();
      if (locations.isEmpty) {
        throw const Failure(
            FailureCode.unavailable, 'File has no location on this device.');
      }
      if (locations.every((row) => row['source'] != 'local')) {
        return (
          path: locations.first['locator'] as String,
          fileId: id,
          probe: (file['attributes'] as JsonMap)['probe'] as JsonMap,
          locationOnly: true
        );
      }
    }
    final info = await readFile(entry);
    return (
      path: info.path,
      fileId: info.fileId,
      probe: info.probe,
      locationOnly: false
    );
  }

  Future<JsonMap> bindBatch(JsonMap input, Invocation invocation) =>
      mutate(() async {
        await store.importLegacy(await classic.history());
        final key = stableMediaId(
            'bind-operation', [invocation.origin, input['requestId']]);
        final fingerprint = stableMediaId('input', input);
        final existing = await store.operation(key, fingerprint);
        if (existing != null) {
          await _deliverBindings(existing);
          await _saveProjectionReceipt(key, existing);
          return existing;
        }
        final records = <String, Future<MetadataRecord>>{};
        Future<MetadataRecord> get(ExternalRef ref) => records.putIfAbsent(
            stableMediaId('ref', ref.toJson()),
            () => provider(ref.provider).get(ref));
        ExternalRef ref(Object? json) =>
            ExternalRef.fromJson(Map<String, Object?>.from(json as Map));
        bool same(ExternalRef a, ExternalRef b) =>
            stableMediaId('ref', a.toJson()) ==
            stableMediaId('ref', b.toJson());
        final entries = (input['entries'] as List).cast<JsonMap>();
        if (entries.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'entries must not be empty.');
        }
        final prepared = <JsonMap>[];
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          try {
            final kind = entry['kind'] as String;
            if (entry.containsKey('ref')) {
              if (!entry.containsKey('entityId') ||
                  (kind == 'file'
                      ? (entry['localEpisodeIds'] is! List ||
                          (entry['localEpisodeIds'] as List).length != 1)
                      : entry.containsKey('localEpisodeIds')) ||
                  entry.keys.any((key) => const {
                        'path',
                        'workRef',
                        'releaseRef',
                        'episodeRefs',
                        'workId',
                        'releaseId',
                        'startMs',
                        'endMs'
                      }.contains(key))) {
                throw const Failure(FailureCode.invalidInput,
                    'Direct ref bindings require an existing entityId without catalogue fields; files also require exactly one localEpisodeIds target with that accepted ref.');
              }
              final info = kind == 'file' ? await _bindingFile(entry) : null;
              prepared.add({
                ...entry,
                if (info != null) ...{
                  'probe': info.probe,
                  'verifiedPath': info.path,
                  'locationOnly': info.locationOnly
                },
                'ref': canonicalExternalRef(
                        Map<String, Object?>.from(entry['ref'] as Map))
                    .toJson()
              });
              continue;
            }
            if (!entry.containsKey('workRef')) {
              throw const Failure(
                  FailureCode.invalidInput,
                  'Expected workRef to create/reuse a catalogue hierarchy, '
                  'or ref + entityId to bind an existing entity directly. '
                  'An episode catalogue entry requires workRef + exactly one episodeRefs; '
                  'Dandanplay/Bangumi reuse workRef as release, TMDB TV also requires releaseRef.');
            }
            final unsupported = switch (kind) {
              'work' => const {
                  'workId',
                  'releaseId',
                  'releaseRef',
                  'localEpisodeIds',
                  'startMs',
                  'endMs'
                },
              'release' => const {
                  'releaseId',
                  'localEpisodeIds',
                  'startMs',
                  'endMs'
                },
              'episode' => const {'localEpisodeIds', 'startMs', 'endMs'},
              _ => const <String>{},
            };
            final ignored = entry.keys.where(unsupported.contains).toList();
            if (ignored.isNotEmpty) {
              throw Failure(
                  FailureCode.invalidInput,
                  'kind=$kind cannot use $ignored. entityId identifies the existing $kind itself; '
                  'workId is the parent work for release/episode/file; releaseId is the parent release for episode/file; '
                  'localEpisodeIds is for file links. Omit local IDs to create/reuse by catalogue refs.');
            }
            if ((kind == 'file' &&
                    (entry.containsKey('entityId') ==
                        entry.containsKey('path'))) ||
                kind != 'file' && entry.containsKey('path')) {
              throw const Failure(FailureCode.invalidInput,
                  'Files require exactly one entityId or path; other entities cannot use path.');
            }
            final workRef = ref(entry['workRef']);
            if (!{'tv', 'movie', 'subject', 'anime'}
                .contains(workRef.objectType)) {
              throw const Failure(
                  FailureCode.invalidInput,
                  'Expected workRef with provider/objectType tmdb/tv or tmdb/movie, '
                  'bangumi/subject, or dandanplay/anime, and scope="". '
                  'An episode ref belongs in episodeRefs, not workRef.');
            }
            if (workRef.scope.isNotEmpty) {
              throw const Failure(
                  FailureCode.invalidInput,
                  'Expected workRef.scope="" for a root work catalogue; '
                  'episode namespaces belong in episodeRefs[].scope.');
            }
            final work = await get(workRef);
            final releaseRef = entry['releaseRef'] == null
                ? workRef
                : ref(entry['releaseRef']);
            if (kind != 'work' &&
                workRef.objectType == 'tv' &&
                entry['releaseRef'] == null) {
              throw const Failure(FailureCode.invalidInput,
                  'TMDB TV bindings require an explicit releaseRef.');
            }
            if (kind != 'work' &&
                (workRef.objectType == 'tv'
                    ? releaseRef.objectType != 'season'
                    : !same(releaseRef, workRef))) {
              throw const Failure(FailureCode.invalidInput,
                  'TV releaseRef must identify a season; other catalogues use workRef as their release.');
            }
            if (kind != 'work' &&
                !same(releaseRef, workRef) &&
                !work.episodes.any((record) => same(record.ref, releaseRef))) {
              throw const Failure(FailureCode.invalidInput,
                  'releaseRef does not belong to workRef.');
            }
            final release = kind == 'work' || same(workRef, releaseRef)
                ? work
                : await get(releaseRef);
            final refs =
                ((entry['episodeRefs'] as List?) ?? []).map(ref).toList();
            if ((kind == 'file' && refs.isEmpty) ||
                (kind == 'episode' && refs.length != 1) ||
                {'work', 'release'}.contains(kind) && refs.isNotEmpty ||
                refs
                        .map((r) => stableMediaId('ref', r.toJson()))
                        .toSet()
                        .length !=
                    refs.length) {
              throw const Failure(FailureCode.invalidInput,
                  'Files require distinct episodeRefs; episode requires one; work/release requires none.');
            }
            final catalogue =
                workRef.objectType == 'movie' ? [work] : release.episodes;
            final selected = <MetadataRecord>[];
            for (final episodeRef in refs) {
              if (episodeRef.objectType !=
                  (workRef.objectType == 'movie' ? 'movie' : 'episode')) {
                throw const Failure(FailureCode.invalidInput,
                    'episodeRefs must identify episodes, or the selected movie.');
              }
              final members =
                  catalogue.where((ep) => same(ep.ref, episodeRef)).toList();
              if (members.length != 1) {
                final expected = catalogue
                    .where((ep) => ep.ref.externalId == episodeRef.externalId)
                    .map((ep) => ep.ref.toJson())
                    .toList();
                throw Failure(
                    FailureCode.invalidInput,
                    'Episode ref ${jsonEncode(episodeRef.toJson())} is not a member of '
                    'the selected release catalogue ${jsonEncode(release.ref.toJson())}. '
                    '${expected.isEmpty ? 'Expected an actual episode object ID and its exact provider/objectType/scope from this catalogue, not an episode number; media.metadata.get_batch returns its episode refs.' : 'Expected episodeRefs to contain ${jsonEncode(expected)}; scope is the provider namespace string, not a local release ID.'}',
                    violations: [
                      SchemaViolation(
                          '/entries/$index/episodeRefs/${selected.length}',
                          expected.isEmpty
                              ? 'Expected a ref from the selected release catalogue.'
                              : 'Expected ${jsonEncode(expected)}.')
                    ]);
              }
              selected.add(members.single);
            }
            if (entry['localEpisodeIds'] case final List ids
                when ids.length != refs.length) {
              throw const Failure(FailureCode.invalidInput,
                  'localEpisodeIds must correspond one-to-one to episodeRefs.');
            }
            final start = entry['startMs'] as num?,
                end = entry['endMs'] as num?;
            if (start != null && end != null && end <= start) {
              throw const Failure(FailureCode.invalidInput,
                  'endMs must be greater than startMs.');
            }
            final info = kind == 'file' ? await _bindingFile(entry) : null;
            final id = info == null ? entry['entityId'] : info.fileId;
            prepared.add({
              ...entry,
              'entityId': id,
              'work': work.toJson(),
              'release': release.toJson(),
              'episodes': [for (final ep in selected) ep.toJson()],
              if (info != null) ...{
                'probe': info.probe,
                'verifiedPath': info.path,
                'locationOnly': info.locationOnly
              }
            });
          } on Failure catch (error) {
            throw Failure(error.code, 'Entry $index: ${error.message}',
                violations: error.violations.isNotEmpty
                    ? error.violations
                    : [SchemaViolation('/entries/$index', error.message)]);
          }
        }
        for (var index = 0; index < prepared.length; index++) {
          final entry = prepared[index];
          if (entry['kind'] != 'file') continue;
          if (entry['locationOnly'] == true) continue;
          try {
            final fresh = await probe(entry['verifiedPath'] as String,
                includeDuration: false);
            final previous = entry['probe'] as JsonMap;
            if (['size', 'modifiedAt', 'headMd5']
                .any((key) => fresh[key] != previous[key])) {
              throw const Failure(FailureCode.conflict,
                  'File changed during batch validation.');
            }
          } on Failure catch (error) {
            throw Failure(error.code, 'Entry $index: ${error.message}',
                violations: [
                  SchemaViolation('/entries/$index', error.message)
                ]);
          }
        }
        final result =
            await store.bindBatch(prepared, key, fingerprint, invocation);
        await _deliverBindings(result);
        await _saveProjectionReceipt(key, result);
        return result;
      });

  Future<JsonMap> unbindBatch(JsonMap input, Invocation invocation) =>
      mutate(() async {
        await store.importLegacy(await classic.history());
        final key = stableMediaId(
            'unbind-operation', [invocation.origin, input['requestId']]);
        final fingerprint = stableMediaId('input', input);
        final entries = (input['entries'] as List).cast<JsonMap>();
        if (entries.isEmpty) {
          throw const Failure(
              FailureCode.invalidInput, 'entries must not be empty.');
        }
        final result =
            await store.unbindBatch(entries, key, fingerprint, invocation);
        await _deliverBindings(result, revoked: true);
        await _saveProjectionReceipt(key, result);
        return result;
      });

  Future<void> _saveProjectionReceipt(String key, JsonMap result) async {
    await store.database.update(
        'media_binding_operations', {'result': jsonEncode(result)},
        where: 'id=?', whereArgs: [key]);
  }

  Future<void> _deliverBindings(JsonMap result, {bool revoked = false}) async {
    for (final row in (result['entries'] as List).cast<JsonMap>()) {
      if (row.containsKey('classicProjection')) continue;
      final id = (row['fileId'] ?? row['entityId']) as String?;
      if (id == null || (await store.entity(id))['kind'] != 'file') continue;
      try {
        await projection.drain(fileId: id);
        if (classic case final ReversibleClassicMetadataPort reversible) {
          final projections = row['classicProjectionId'] == null
              ? <JsonMap>[]
              : await store.database.query('media_projection_outbox',
                  where: 'id=? AND state=?',
                  whereArgs: [row['classicProjectionId'], 'delivered']);
          row['classicProjection'] = [
            for (final queued in projections)
              for (final location in await store.locations(id))
                if (location['owner_device_id'] == store.ownerDeviceId)
                  await reversible.projectionOutcome(
                      location['locator'] as String, {
                    ...decodeMediaJson(queued['payload']),
                    'projectionId': queued['id']
                  })
          ];
        }
      } on Failure catch (error) {
        throw Failure(error.code,
            'Entry ${row['index']}: ${revoked ? 'Next bindings revoked' : 'Identity committed'}; Classic projection is ${error.code == FailureCode.conflict ? 'in conflict' : 'pending'}: ${error.message}',
            retryable: true,
            violations: [
              SchemaViolation('/entries/${row['index']}', error.message)
            ]);
      }
    }
  }
}

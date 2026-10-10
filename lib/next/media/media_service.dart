import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;

import 'classic_projection.dart';
import 'filename_parser.dart';
import 'identity_store.dart';
import 'metadata_provider.dart';

final class MediaService {
  MediaService(
      {required this.store,
      required Iterable<MetadataProvider> providers,
      required this.classic,
      required this.authorizedRoots,
      this.parser = const RuleFilenameParser()})
      : providers = {for (final provider in providers) provider.id: provider},
        projection = ClassicProjection(store, classic);
  final IdentityStore store;
  final Map<String, MetadataProvider> providers;
  final ClassicMetadataPort classic;
  final ClassicProjection projection;
  final Iterable<String> Function() authorizedRoots;
  final FilenameParserPort parser;
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
    if (id != null && id != 'current') return id;
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

  Future<String> authorizedPath(String locator,
      {bool directory = false}) async {
    if (!p.isAbsolute(locator) || Uri.tryParse(locator)?.hasScheme == true) {
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
    if (!allowed) {
      throw const Failure(FailureCode.unavailable,
          'Path is outside the configured media folders.');
    }
    return path;
  }

  Future<JsonMap> probe(String locator) async {
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
    final after = await file.stat();
    if (before.size != after.size || before.modified != after.modified) {
      throw const Failure(FailureCode.conflict, 'File changed during probing.');
    }
    return {
      'size': after.size,
      'modifiedAt': after.modified.toUtc().toIso8601String(),
      'headMd5': md5.convert(bytes).toString()
    };
  }

  Future<String> index(String locator) async {
    final path = await authorizedPath(locator);
    final info = await probe(path);
    return mutate(() async {
      final id = await store.registerFile(path, info);
      await projection.drain(fileId: id);
      return id;
    });
  }

  Future<void> validateFile(String fileId) async {
    final file = await store.entity(fileId);
    final local = (await store.locations(fileId))
        .where((l) =>
            l['source'] == 'local' &&
            l['owner_device_id'] == store.ownerDeviceId)
        .toList();
    if (local.isEmpty) {
      throw const Failure(
          FailureCode.unavailable, 'No accessible local file location.');
    }
    final info = await probe(local.first['locator'] as String);
    final previous = (file['attributes'] as JsonMap)['probe'] as JsonMap;
    if (isLocationOnlyMediaProbe(previous)) {
      await mutate(
          () => store.registerFile(local.first['locator'] as String, info));
      return;
    }
    if (info['size'] != previous['size'] ||
        info['modifiedAt'] != previous['modifiedAt'] ||
        info['headMd5'] != previous['headMd5']) {
      await mutate(
          () => store.registerFile(local.first['locator'] as String, info));
      throw const Failure(FailureCode.conflict,
          'File content changed. Start a new identification.');
    }
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
            'media.identify' => 'Identify media file',
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

  Future<Job> identify(String fileId,
      {List<String>? sources,
      int? expectedRevision,
      String? releaseId,
      String? requestId}) async {
    final file = await store.entity(fileId);
    if (file['kind'] != 'file') {
      throw const Failure(
          FailureCode.invalidInput, 'Identification requires a file entity.');
    }
    if (expectedRevision != null && file['revision'] != expectedRevision) {
      throw const Failure(FailureCode.conflict, 'Stale file revision.');
    }
    final selected = List<String>.of(sources ?? providers.keys);
    for (final source in selected) {
      provider(source);
    }
    if (selected.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Choose at least one metadata source.');
    }
    selected.sort();
    final key = stableMediaId('identify', [
      fileId,
      file['revision'],
      (file['attributes'] as JsonMap)['bindingRevision'],
      selected,
      releaseId,
      requestId,
      'rules-1'
    ]);
    return submit(
        'media.identify',
        {
          'fileId': fileId,
          'fileRevision': file['revision'],
          'sources': selected,
          if (releaseId != null) 'releaseId': releaseId,
        },
        key: key);
  }

  Future<JsonMap> accept(
      String jobId, String candidateId, String actor, Invocation invocation,
      {Future<void> Function()? committed}) async {
    final identification = await store.identification(jobId);
    if (identification['state'] != 'accepted') {
      await validateFile(identification['file_id'] as String);
    }
    return mutate(() async {
      final result =
          await store.acceptCandidate(jobId, candidateId, actor, invocation);
      await committed?.call();
      await projection.drain(fileId: identification['file_id'] as String);
      return result;
    });
  }

  Future<JsonMap> candidate(MetadataRecord work, FilenameSignals signals,
      {ExternalRef? releaseRef,
      MetadataRecord? confirmedRelease,
      List<String>? episodeIds,
      String? workId,
      String reason = 'Filename search requires confirmation.',
      String? url}) async {
    final source = provider(work.ref.provider);
    var detail = work;
    var release = confirmedRelease ?? work;
    if (confirmedRelease != null) {
      detail = work;
    } else if (releaseRef != null) {
      if (releaseRef.provider != work.ref.provider) {
        throw const Failure(FailureCode.invalidInput,
            'Work and release must come from the same source.');
      }
      detail = await source.get(work.ref);
      if (work.ref.provider == 'tmdb' &&
          !detail.episodes.any((ep) =>
              ep.ref.externalId == releaseRef.externalId &&
              ep.ref.scope == releaseRef.scope)) {
        throw const Failure(FailureCode.invalidInput,
            'Selected release does not belong to the work.');
      }
      release = await source.get(releaseRef);
    } else if (work.ref.objectType == 'tv') {
      detail = await source.get(work.ref);
      final matches = detail.episodes
          .where((s) => s.season == (signals.season ?? 1))
          .toList();
      if (matches.length != 1) {
        throw const Failure(FailureCode.notFound,
            'No unique TMDB season corresponds to the filename.');
      }
      release = await source.get(matches.single.ref);
    } else if (work.ref.objectType != 'movie' && work.episodes.isEmpty) {
      detail = await source.get(work.ref);
      release = detail;
    }
    var episodes = release.episodes;
    if (work.ref.objectType == 'movie') episodes = [release];
    List<MetadataRecord> selected;
    if (episodeIds != null) {
      if (episodeIds.isEmpty ||
          episodeIds.toSet().length != episodeIds.length) {
        throw const Failure(
            FailureCode.invalidInput, 'Select distinct catalogue episodes.');
      }
      selected = [
        for (final id in episodeIds)
          ...episodes.where((ep) => ep.ref.externalId == id)
      ];
      if (selected.length != episodeIds.length) {
        throw const Failure(FailureCode.invalidInput,
            'Episode selection is outside the verified release catalogue.');
      }
    } else if (work.ref.objectType == 'movie') {
      selected = episodes;
    } else {
      final start = double.tryParse(signals.number ?? ''),
          end = double.tryParse(signals.endNumber ?? '');
      selected = episodes.where((ep) {
        final n = double.tryParse(ep.number ?? '');
        return n != null &&
            start != null &&
            (end == null ? n == start : n >= start && n <= end) &&
            (signals.episodeType == 'regular'
                ? ep.episodeType == 'regular'
                : ep.episodeType != 'regular');
      }).toList();
      if (selected.isEmpty) {
        throw const Failure(FailureCode.notFound,
            'No catalogue episode corresponds to the parsed number and type.');
      }
      if (end == null && selected.length != 1) {
        throw const Failure(
            FailureCode.conflict, 'Episode numbering is ambiguous.');
      }
    }
    return {
      'work': detail.toJson(),
      'release': release.toJson(),
      'episodes': [for (final ep in selected) ep.toJson()],
      'workId': workId,
      'relation': selected.length > 1 ? 'combined' : 'exact',
      'scope': {
        'order': release.order,
        'season': release.season,
        'cour': signals.cour,
        'numbers': [for (final ep in selected) ep.number],
        'startMs': null,
        'endMs': null
      },
      'evidence': {'reason': reason, 'url': url}
    };
  }

  Future<JsonMap> releaseCandidate(
      String releaseId, FilenameSignals signals) async {
    final release = await store.entity(releaseId);
    if (release['kind'] != 'release') {
      throw const Failure(
          FailureCode.invalidInput, 'releaseId must identify a local release.');
    }
    Future<MetadataRecord> record(String id) async {
      final rows = await store.database.rawQuery(
          'SELECT s.fields FROM media_snapshots s JOIN media_bindings b ON b.object_id=s.object_id WHERE b.entity_id = ? AND b.status = ? ORDER BY b.created_at DESC, s.fetched_at DESC LIMIT 1',
          [id, 'accepted']);
      if (rows.isEmpty) {
        throw const Failure(FailureCode.unavailable,
            'Release context requires accepted identity and a cached catalogue.');
      }
      return MetadataRecord.fromJson(decodeMediaJson(rows.single['fields']));
    }

    final workId = release['parent_id'] as String;
    final work = await record(workId);
    final catalogue = await record(releaseId);
    return candidate(work, signals,
        confirmedRelease: catalogue,
        workId: workId,
        reason:
            'Accepted local release with a unique catalogue number and matching episode type.');
  }
}

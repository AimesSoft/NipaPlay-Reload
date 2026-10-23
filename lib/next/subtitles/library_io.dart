import 'dart:async';
import 'episode_subtitles.dart';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import '../media/media_service.dart';
import '../media/media_probe_io.dart';
import '../media/file_identity_merge.dart';
import '../media/identity_store.dart';
import '../state/change_history.dart';
import '../public_url.dart';
import '../platform/report_error.dart';
import 'operations.dart';
import 'detection.dart';
import 'webvtt.dart';
import 'mutations.dart';
import 'storage_lock.dart';

/// Uses the same persisted facts and filename matcher, without Classic/player.
final class SubtitleLibrary implements SubtitleOperations {
  SubtitleLibrary(this.media, this.root);
  final MediaService media;
  @override
  final Directory root;
  @override
  Database get db => media.store.database;
  Future<void> _pending = Future.value();
  StreamSubscription<JsonMap>? _events;
  Timer? _timer;
  bool _closed = false;
  Future<T> _serial<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<JsonMap> facts(String fileId) async {
    final id = await canonicalFileId(db, fileId);
    final rows =
        await db.query('file_subtitles', where: 'file_id=?', whereArgs: [id]);
    return rows.isEmpty
        ? {
            'fileId': id,
            'revision': 0,
            'tracks': <JsonMap>[],
            'embeddedStatus':
                headlessFfprobe == null ? 'unavailable' : 'pending',
            'selection': null
          }
        : decodeMediaJson(rows.single['facts']);
  }

  Future<void> _save(String id, JsonMap value) async {
    final old = await facts(id);
    value['revision'] = (old['revision'] as int? ?? 0) + 1;
    await db.insert(
        'file_subtitles', {'file_id': id, 'facts': jsonEncode(value)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    BodyChanges.observe('subtitle:$id', [
      {'id': id, ...value}
    ]);
  }

  void start() {
    // A file registered or changed is looked at alone; every file is looked
    // at once now and again by indexers.reconcile.
    _events = media.store.fileChanges.listen((f) => unawaited(
        _serial(() => _inspect(f['fileId'] as String, f['path'] as String))
            .catchError((Object error, StackTrace stack) {
      reportNextError(error, stack, 'Next headless subtitle indexing');
    })));
    _reconcile();
  }

  void _reconcile() {
    if (_closed) return;
    unawaited(reconcile().catchError((Object error, StackTrace stack) {
      reportNextError(error, stack, 'Next headless subtitle indexing');
    }));
  }

  Future<void> reconcile() => _serial(() async {
        if (_closed) return;
        for (final row in await db.query('media_locations',
            where: 'source=? AND owner_device_id=?',
            whereArgs: ['local', media.store.ownerDeviceId])) {
          await _inspect(row['file_id'] as String, row['locator'] as String);
        }
      });
  Future<void> _inspect(String id, String path) async {
    final value = await facts(id);
    final old = jsonEncode(value);
    final before = await File(path).stat();
    final fingerprint =
        '${before.size}:${before.modified.toUtc().toIso8601String()}';
    final exists = before.type == FileSystemEntityType.file;
    final oldTracks = (value['tracks'] as List).cast<JsonMap>();
    final tracks = <JsonMap>[];
    if (exists && headlessFfprobe != null) {
      if (value['fingerprint'] == fingerprint &&
          value['embeddedStatus'] == 'ready') {
        tracks.addAll(oldTracks.where((t) => t['origin'] == 'embedded'));
      } else {
        final probe = await probeMediaInfo(path);
        for (final t in (probe['subtitles'] as List? ?? []).cast<JsonMap>()) {
          tracks.add({
            'id': 'embedded:${t['index']}',
            'origin': 'embedded',
            ...t,
            'language': subtitleLanguage(t['language'] as String),
            'declaredLanguage': t['language'],
            'languageBasis': 'container',
            'available': true,
            'source': {'label': 'container probe'}
          });
        }
        value['embeddedStatus'] =
            probe['subtitles'] is List ? 'ready' : 'unavailable';
      }
    } else {
      value['embeddedStatus'] = 'unavailable';
      tracks.addAll(oldTracks
          .where((t) => t['origin'] == 'embedded')
          .map((t) => {...t, 'available': false}));
    }
    if (exists) {
      for (final candidate in await subtitleCandidates(path)) {
        final stat = await File(candidate.path).stat();
        tracks.add({
          'id': stableMediaId('subtitle', candidate.path),
          'origin': 'sidecar',
          'path': candidate.path,
          'title': p.basename(candidate.path),
          'format': p.extension(candidate.path).substring(1).toLowerCase(),
          'language': subtitleLanguage(p.basename(candidate.path)),
          'languageBasis': 'filename',
          'available': true,
          'matchScore': candidate.score,
          'matchBasis': 'classic_filename_match',
          'size': stat.size,
          'modifiedAt': stat.modified.toUtc().toIso8601String(),
          'source': {'label': 'adjacent subtitle'}
        });
      }
    }
    for (final t in oldTracks.where((t) => t['origin'] != 'embedded')) {
      if (!tracks.any((x) => x['id'] == t['id'])) {
        tracks.add({
          ...t,
          'available': t['origin'] != 'sidecar' &&
              await File(t['path'] as String).exists()
        });
      }
    }
    value['tracks'] = tracks;
    value['fingerprint'] = fingerprint;
    if (old != jsonEncode(value)) {
      value['checkedAt'] = DateTime.now().toUtc().toIso8601String();
      await _save(id, value);
    }
  }

  @override
  Future<JsonMap> importSubtitle(JsonMap input, Invocation invocation) =>
      withSubtitleStorage(root, () => _importSubtitle(input, invocation));
  Future<JsonMap> _importSubtitle(JsonMap input, Invocation invocation) =>
      _serial(() async {
        final id = await canonicalFileId(db, input['fileId'] as String);
        await media.readFile({'entityId': id}, includeDuration: false);
        final sourcePath = input['filePath'] as String;
        final source = input['source'] as JsonMap;
        final url = source['url'] as String?;
        if (!RegExp(r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$')
                .hasMatch(input['language'] as String) ||
            url != null &&
                (!url.startsWith('https://') ||
                    redactPrivateUrls(url) != url)) {
          throw const Failure(FailureCode.invalidInput,
              'Declare a BCP-47 language and a public HTTPS source.');
        }
        if (!p.isAbsolute(sourcePath) ||
            !subtitleFormats.contains(p.extension(sourcePath).toLowerCase()) ||
            !isVobSubPairComplete(sourcePath)) {
          throw const Failure(FailureCode.invalidInput,
              'Use an absolute supported subtitle; VobSub requires idx/sub.');
        }
        final canonical = canonicalSubtitlePath(sourcePath);
        final format = p.extension(canonical).substring(1).toLowerCase();
        Future<List<int>> read(String path) async {
          if (await File(path).length() > 33554432) {
            throw const Failure(
                FailureCode.invalidInput, 'Subtitle exceeds 32 MiB.');
          }
          final bytes = await File(path).readAsBytes();
          if (bytes.isEmpty || bytes.length > 33554432) {
            throw const Failure(FailureCode.invalidInput,
                'Subtitle must contain 1 to 33554432 bytes.');
          }
          return bytes;
        }

        final bytes = await read(canonical);
        final companions = <String, List<int>>{
          if (format == 'idx')
            'sub': await read(vobSubCompanionPath(canonical, '.sub')!)
        };
        // Without a native subtitle parser binary tracks remain declared facts.
        if (format != 'idx' && format != 'sup') {
          final text = utf8.decode(bytes, allowMalformed: true);
          final cues = format == 'vtt' ? webVttToSrt(text) : text;
          if (!RegExp(
                  r'\d+:\d+(?::\d+)?[,.]\d+\s*-->|^Dialogue\s*:|^\{\d+\}\{\d+\}|\d+:\d+:\d+[,.]\d+\s*,',
                  multiLine: true)
              .hasMatch(cues)) {
            throw const Failure(FailureCode.invalidInput,
                'Subtitle has no recognizable timed cues.');
          }
        }
        final hash = sha256.convert(
            [...bytes, ...companions.values.expand((b) => b)]).toString();
        final dir =
            await Directory('${root.path}/subtitles').create(recursive: true);
        final saved = '${dir.path}/$hash.$format';
        await File(saved).writeAsBytes(bytes, flush: true);
        for (final entry in companions.entries) {
          await File('${dir.path}/$hash.${entry.key}')
              .writeAsBytes(entry.value, flush: true);
        }
        final track = <String, Object?>{
          'id': 'import:$hash',
          'origin': 'import',
          'path': saved,
          'format': format,
          'title': input['title'] ?? p.basename(canonical),
          if (format == 'vtt') 'playbackPath': await prepareWebVtt(saved, root),
          'cueValidation':
              {'idx', 'sup'}.contains(format) ? 'not_probed' : 'timing_syntax',
          'language': subtitleLanguage(input['language'] as String),
          'declaredLanguage': input['language'],
          'languageBasis': 'declared',
          'available': true,
          'size': bytes.length,
          'source': source,
          'importedAt': DateTime.now().toUtc().toIso8601String(),
          'actor': invocation.origin == 'gui' ? 'user' : 'agent',
          'originInvocation': invocation.origin,
          'invocationId': invocation.id
        };
        final value = await facts(id);
        value['tracks'] = [
          ...(value['tracks'] as List)
              .cast<JsonMap>()
              .where((t) => t['id'] != track['id']),
          track
        ];
        await _save(id, value);
        return {'fileId': id, 'track': track, 'saved': true};
      });
  @override
  Future<void> select(String fileId, String? trackId) => _serial(() async {
        final id = await canonicalFileId(db, fileId);
        final value = await facts(id);
        if (trackId != null &&
            !(value['tracks'] as List)
                .cast<JsonMap>()
                .any((t) => t['id'] == trackId && t['available'] == true)) {
          throw const Failure(FailureCode.invalidInput,
              'Select an available subtitle of this file.');
        }
        value['selection'] = {
          'trackId': trackId,
          'basis': 'explicit',
          'selectedAt': DateTime.now().toUtc().toIso8601String()
        };
        await _save(id, value);
      });
  @override
  Future<JsonMap> mutateFacts(String fileId, String operation, JsonMap input, Invocation invocation) =>
      _serial(() async => {...await mutateSubtitleFacts(this,fileId,operation,input,invocation),
        'factsCommitted': true, 'playerApplied': null, 'playerUnsupportedReason': 'headless_host'});
  @override
  Future<List<JsonMap>> episodeTracks(String id) async {
    final result = <JsonMap>[];
    for (final file in await db
        .query('media_file_episodes', where: 'episode_id=?', whereArgs: [id])) {
      final value = await facts(file['file_id'] as String);
      for (final track in (value['tracks'] as List).cast<JsonMap>()) {
        result.add({
          ...track,
          'fileId': file['file_id'],
          'selected': (value['selection'] as Map?)?['trackId'] == track['id'],
          'selectionBasis': (value['selection'] as Map?)?['basis']
        });
      }
    }
    return result;
  }

  @override
  Future<({List<JsonMap> tracks, List<JsonMap> files})> episodeSubtitles(String id) =>
      readEpisodeSubtitles(db, id);

  @override
  Future<List<JsonMap>> episodeFiles(String id) async => [
        for (final file in await db.query('media_file_episodes',
            where: 'episode_id=?', whereArgs: [id]))
          {...await facts(file['file_id'] as String)}..remove('tracks')
      ];
  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _events?.cancel();
    await _pending;
  }
}

import 'dart:async';
import 'episode_subtitles.dart';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:nipaplay/services/subtitle_service.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/subtitle_parser.dart';

import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/media_probe.dart';
import '../media/file_identity_merge.dart';
import '../state/change_history.dart';
import '../public_url.dart';
import '../player/next_playback.dart';
import 'webvtt.dart';
import 'operations.dart';
import 'detection.dart';
import 'mutations.dart';
import 'storage_lock.dart';

export 'detection.dart';

final class SubtitleLibrary implements SubtitleOperations {
  SubtitleLibrary(this.media, this.root, {this.probe = probeMediaInfo});
  final MediaService media;
  @override
  final Directory root;
  final Future<JsonMap> Function(String) probe;
  IdentityStore get identities => media.store;
  @override
  Database get db => identities.database;
  final _pending = <String, String>{};
  final _reads = <String, Future<void>>{};
  StreamSubscription<JsonMap>? _events;
  Timer? _timer;
  Future<void>? _worker;
  SubtitleTarget? _player;
  Future<bool> Function(SubtitleTarget, String)? remoteLoader;
  bool _closed = false;
  bool enabled = true;
  String? lastRun, lastError;
  JsonMap get status => {'kind': 'subtitle.probe', 'enabled': enabled,
    'running': _worker != null, 'queue': _pending.length, 'lastRun': lastRun,
    'nextRun': enabled ? 'on file change or indexers.reconcile' : null, 'error': lastError};
  Future<void> setEnabled(bool value) async {
    enabled = value;
    if (value) {
      await reconcile();
      if (_pending.isNotEmpty && _worker == null) _worker = _drain().whenComplete(() => _worker = null);
    }
  }
  final _mutations = <String, Future<void>>{};

  Future<T> _serial<T>(String id, Future<T> Function() operation) async {
    final before = _mutations[id] ?? Future<void>.value();
    final result = before.then((_) => operation());
    final tail =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    _mutations[id] = tail;
    try {
      return await result;
    } finally {
      if (identical(_mutations[id], tail)) _mutations.remove(id);
    }
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
            'embeddedStatus': 'pending',
            'selection': null
          }
        : decodeMediaJson(rows.single['facts']);
  }

  Future<void> _save(String id, JsonMap facts) async {
    final old = await this.facts(id);
    facts['revision'] = (old['revision'] as int? ?? 0) + 1;
    await db.insert(
        'file_subtitles', {'file_id': id, 'facts': jsonEncode(facts)},
        conflictAlgorithm: ConflictAlgorithm.replace);
    BodyChanges.observe('subtitle:$id', [
      {'id': id, ...facts}
    ]);
  }

  void start() {
    _events = identities.fileChanges
        .listen((f) => enqueue(f['fileId'] as String, f['path'] as String));
    // Every file is looked at once now; after that a file is looked at when it
    // is registered or changes, and indexers.reconcile looks at all again.
    unawaited(reconcile());
  }

  Future<void> reconcile() async {
    if (!enabled || _closed) return;
    for (final row in await db.query('media_locations',
        where: 'source=? AND owner_device_id=?',
        whereArgs: ['local', identities.ownerDeviceId])) {
      enqueue(row['file_id'] as String, row['locator'] as String);
    }
  }

  void enqueue(String id, String path) {
    if (_closed || path.contains('://')) return;
    _pending[id] = path;
    if (!enabled) return;
    _worker ??= _drain().whenComplete(() {
      _worker = null;
    });
  }

  Future<void> _drain() async {
    while (!_closed && enabled && _pending.isNotEmpty) {
      final id = _pending.keys.first,
          path = _pending.remove(_pending.keys.first)!;
      try {
        await inspect(id, path);
        lastRun = DateTime.now().toUtc().toIso8601String();
        lastError = null;
      } catch (error, stack) {
        lastError = error.runtimeType.toString();
        FlutterError.reportError(FlutterErrorDetails(
            exception: error, stack: stack, library: 'Next subtitle indexing'));
      }
    }
  }

  Future<void> inspect(String id, String path) => _reads.putIfAbsent(
      id,
      () => _serial(id, () => _inspect(id, path)).whenComplete(() {
            _reads.remove(id);
          }));

  Future<void> _inspect(String id, String path) async {
    final before = await File(path).stat();
    final old = await facts(id);
    final tracks = (old['tracks'] as List).cast<JsonMap>();
    final fingerprint =
        '${before.size}:${before.modified.toUtc().toIso8601String()}';
    final exists = before.type == FileSystemEntityType.file;
    final entity = await identities.entity(id);
    final indexed = (entity['attributes'] as JsonMap)['probe'] as JsonMap;
    final indexedFingerprint = '${indexed['size']}:${indexed['modifiedAt']}';
    final embedded = old['fingerprint'] == fingerprint &&
            old['embeddedStatus'] == 'ready'
        ? null
        : exists
            ? indexed['subtitles'] != null && indexedFingerprint == fingerprint
                ? indexed
                : await probe(path)
            : <String, Object?>{};
    final updated = <JsonMap>[
      if (embedded == null)
        ...tracks.where((t) => t['origin'] == 'embedded')
      else if (embedded['subtitles'] is! List)
        ...tracks
            .where((t) => t['origin'] == 'embedded')
            .map((t) => {...t, 'available': false})
      else
        for (final t in (embedded['subtitles'] as List).cast<Map>())
          {
            'id': 'embedded:${t['index']}',
            'origin': 'embedded',
            ...t,
            'language': subtitleLanguage(t['language'] as String),
            'declaredLanguage': t['language'],
            'languageBasis': 'container',
            'available': true,
            'source': {'label': 'container probe'}
          },
    ];
    if (exists) {
      for (final candidate in await subtitleCandidates(path)) {
        final stat = await File(candidate.path).stat();
        final title = p.basename(candidate.path);
        updated.add({
          'id': stableMediaId('subtitle', candidate.path),
          'origin': 'sidecar',
          'path': candidate.path,
          if (p.extension(candidate.path).toLowerCase() == '.vtt')
            'playbackPath': await prepareWebVtt(candidate.path, root),
          'title': title,
          'format': p.extension(candidate.path).substring(1).toLowerCase(),
          'language': subtitleLanguage(title),
          'languageBasis': 'filename',
          'available': true,
          'matchScore': candidate.score,
          'matchBasis': p.dirname(candidate.path) == p.dirname(path)
              ? 'classic_filename_match'
              : 'single_video_subdirectory',
          'size': stat.size,
          'modifiedAt': stat.modified.toUtc().toIso8601String(),
          'source': {'label': 'adjacent subtitle'}
        });
      }
    }
    for (final t in tracks.where((t) => t['origin'] != 'embedded')) {
      if (updated.any((x) => x['id'] == t['id'])) continue;
      updated.add({
        ...t,
        'available': t['origin'] == 'sidecar'
            ? false
            : await File(t['path'] as String).exists()
      });
    }
    // Classic saved choices outside the media directory remain discoverable.
    if (exists) {
      for (final t
          in (await SubtitleService().readExternalSubtitlePreferences(path))
              .subtitles) {
        final subPath = t['path'] as String;
        if ((old['detachedPaths'] as List? ?? []).contains(subPath)) continue;
        if (updated
            .any((x) => x['path'] == subPath || x['playbackPath'] == subPath)) {
          continue;
        }
        updated.add({
          'id': stableMediaId('subtitle', subPath),
          'origin': 'classic',
          'path': subPath,
          'title': t['name'] ?? p.basename(subPath),
          'format': p.extension(subPath).substring(1),
          'available': await File(subPath).exists(),
          'language':
              subtitleLanguage(t['name'] as String? ?? p.basename(subPath)),
          'languageBasis': 'filename',
          'source': {'label': 'Classic saved subtitle'}
        });
      }
    }
    final value = <String, Object?>{
      ...old,
      'fileId': id,
      'fingerprint': fingerprint,
      'embeddedStatus': !exists
          ? 'unavailable'
          : embedded == null || embedded.containsKey('subtitles')
              ? 'ready'
              : 'unavailable',
      'tracks': updated
    };
    value['selection'] = await _defaultSelection(path, value);
    if (jsonEncode(old) != jsonEncode(value)) {
      value['checkedAt'] = DateTime.now().toUtc().toIso8601String();
      await _save(id, value);
    }
  }

  Future<JsonMap?> _defaultSelection(String path, JsonMap facts) async {
    final old = facts['selection'] as JsonMap?;
    final tracks = (facts['tracks'] as List)
        .cast<JsonMap>()
        .where((t) => t['available'] == true)
        .toList();
    if (old?['basis'] == 'explicit' &&
        (old?['trackId'] == null ||
            tracks.any((t) => t['id'] == old?['trackId']))) {
      return old;
    }
    final prefs = await SharedPreferences.getInstance();
    final mapping =
        jsonDecode(prefs.getString('video_subtitle_map') ?? '{}') as Map;
    final preferences =
        await SubtitleService().readExternalSubtitlePreferences(path);
    final classic = preferences.subtitles;
    final active = preferences.activeIndex;
    final previous = tracks
        .where((t) =>
            (mapping[path] is String &&
                (t['path'] == mapping[path] ||
                    t['playbackPath'] == mapping[path])) ||
            (active != null &&
                active >= 0 &&
                active < classic.length &&
                (t['path'] == classic[active]['path'] ||
                    t['playbackPath'] == classic[active]['path'])))
        .firstOrNull;
    if (previous != null && facts['automaticSelection'] != true &&
        !(old?['basis'] == 'language_preference' &&
            old?['trackId'] == previous['id'])) {
      return {'trackId': previous['id'], 'basis': 'classic_choice'};
    }
    // Classic's filename score already includes its simplified/traditional language preference.
    final external = tracks
        .where((t) =>
            t['origin'] != 'embedded' &&
            t['format'] != 'idx' &&
            t['format'] != 'sup' &&
            (t['format'] != 'sub' || !isVobSubBinaryFile(t['path'] as String)))
        .toList();
    final mode = prefs.getString(SettingsKeys.appLanguageMode) ?? 'auto';
    final locale = PlatformDispatcher.instance.locale;
    final traditional = mode == 'traditional' ||
        mode == 'auto' &&
            locale.languageCode == 'zh' &&
            (locale.scriptCode == 'Hant' ||
                {'TW', 'HK', 'MO'}.contains(locale.countryCode));
    final preferred = [
      traditional ? 'zh-Hant' : 'zh-Hans',
      traditional ? 'zh-Hans' : 'zh-Hant',
      'zh',
      'en'
    ];
    int rank(JsonMap t) {
      final index = preferred.indexOf(t['language'] as String);
      return index < 0 ? 0 : (preferred.length - index) * 100;
    }

    external.sort((a, b) {
      final score = (rank(b) + (b['matchScore'] as int? ?? 0))
          .compareTo(rank(a) + (a['matchScore'] as int? ?? 0));
      return score == 0
          ? (a['id'] as String).compareTo(b['id'] as String)
          : score;
    });
    final embedded = tracks.where((t) => t['origin'] == 'embedded').toList()
      ..sort((a, b) => rank(b).compareTo(rank(a)));
    final chosen = external.firstOrNull ?? embedded.firstOrNull;
    return chosen == null
        ? null
        : {
            'trackId': chosen['id'],
            'basis': 'language_preference',
            'preferredLanguages': preferred,
            'languageMode': mode,
            'externalTextFirst': true
          };
  }

  @override
  Future<JsonMap> importSubtitle(JsonMap input, Invocation invocation) =>
      withSubtitleStorage(root, () => _importSubtitle(input, invocation));

  Future<JsonMap> _importSubtitle(JsonMap input, Invocation invocation) async {
    final id = await canonicalFileId(db, input['fileId'] as String);
    final target =
        (await media.readFile({'entityId': id}, includeDuration: false)).path;
    final sourcePath = input['filePath'] as String;
    final source = input['source'] as JsonMap;
    final sourceUrl = source['url'] as String?;
    if (!RegExp(r'^[a-zA-Z]{2,3}(?:-[a-zA-Z0-9]{2,8})*$')
            .hasMatch(input['language'] as String) ||
        (sourceUrl != null &&
            (!sourceUrl.startsWith('https://') ||
                redactPrivateUrls(sourceUrl) != sourceUrl))) {
      throw const Failure(FailureCode.invalidInput,
          'Declare a BCP-47 language (und for unknown) and a public HTTPS source URL without credentials.');
    }
    if (!p.isAbsolute(sourcePath) ||
        !subtitleFormats.contains(p.extension(sourcePath).toLowerCase()) ||
        !isVobSubPairComplete(sourcePath)) {
      throw const Failure(FailureCode.invalidInput,
          'Use an absolute supported subtitle file; VobSub requires both idx and sub.');
    }
    final canonical = canonicalSubtitlePath(sourcePath);
    final size = await File(canonical).length();
    if (size == 0 || size > 32 * 1024 * 1024) {
      throw const Failure(FailureCode.invalidInput,
          'Subtitle must contain 1 to 33554432 bytes.');
    }
    final format = p.extension(canonical).substring(1).toLowerCase();
    final playable =
        format == 'vtt' ? await prepareWebVtt(canonical, root) : canonical;
    if (format != 'idx' &&
        format != 'sup' &&
        (await SubtitleParser.parseAssFile(playable)).isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Subtitle has no parseable timed cues.');
    }
    final bytes = await File(canonical).readAsBytes();
    if (bytes.isEmpty || bytes.length > 32 * 1024 * 1024) {
      throw const Failure(FailureCode.invalidInput,
          'Subtitle must contain 1 to 33554432 bytes.');
    }
    final companions = <String, List<int>>{};
    if (format == 'idx') {
      final companion = File(vobSubCompanionPath(canonical, '.sub')!);
      if (await companion.length() > 32 * 1024 * 1024) {
        throw const Failure(FailureCode.invalidInput,
            'VobSub companion exceeds 33554432 bytes.');
      }
      companions['sub'] = await companion.readAsBytes();
    }
    final hash = sha256
        .convert([...bytes, ...companions.values.expand((b) => b)]).toString();
    final directory = Directory('${root.path}/subtitles');
    await directory.create(recursive: true);
    final saved = '${directory.path}/$hash.$format';
    await File(saved).writeAsBytes(bytes, flush: true);
    for (final entry in companions.entries) {
      await File('${directory.path}/$hash.${entry.key}')
          .writeAsBytes(entry.value, flush: true);
    }
    final track = <String, Object?>{
      'id': 'import:$hash',
      'origin': 'import',
      'path': saved,
      if (format == 'vtt') 'playbackPath': playable,
      'format': format,
      'title': input['title'] ?? p.basename(canonical),
      'language': subtitleLanguage(input['language'] as String),
      'declaredLanguage': input['language'],
      'languageBasis': 'declared',
      'available': true,
      'size': bytes.length,
      'source': input['source'],
      'importedAt': DateTime.now().toUtc().toIso8601String(),
      'actor': invocation.origin == 'gui' ? 'user' : 'agent',
      'originInvocation': invocation.origin,
      'invocationId': invocation.id
    };
    await _serial(id, () async {
      final value = await facts(id);
      final tracks = (value['tracks'] as List)
          .cast<JsonMap>()
          .where((t) => t['id'] != track['id'])
          .toList();
      value['tracks'] = [...tracks, track];
      value['detachedPaths'] = (value['detachedPaths'] as List? ?? [])
          .where((path) => path != track['path'] && path != track['playbackPath']).toList();
      value['selection'] = await _defaultSelection(target, value);
      await _save(id, value);
    });
    return {'fileId': id, 'track': track, 'saved': true};
  }

  @override
  Future<void> select(String fileId, String? trackId,
      {String basis = 'explicit'}) async {
    final id = await canonicalFileId(db, fileId);
    await _serial(id, () async {
      final value = await facts(id);
      if (trackId != null &&
          !(value['tracks'] as List)
              .cast<Map>()
              .any((t) => t['id'] == trackId && t['available'] == true)) {
        throw const Failure(FailureCode.invalidInput,
            'trackId must identify an available subtitle of this file.');
      }
      value['selection'] = {
        'trackId': trackId,
        'basis': basis,
        'selectedAt': DateTime.now().toUtc().toIso8601String()
      };
      await _save(id, value);
    });
    await _refreshPlayer(id);
  }

  @override
  Future<JsonMap> mutateFacts(String fileId, String operation, JsonMap input, Invocation invocation) async {
    final id = await canonicalFileId(db, fileId);
    final path = (await media.readFile({'entityId':id}, includeDuration:false)).path;
    final result = await _serial(id, () => mutateSubtitleFacts(this,id,operation,input,invocation,
      defaultSelection:(value) => _defaultSelection(path,value)));
    await _refreshPlayer(id);
    result['factsCommitted'] = true;
    result['playerApplied'] = _player?.path == path;
    return result;
  }

  Future<void> _refreshPlayer(String id) async {
    final player = _player;
    final path = player?.path;
    if (player == null || path == null) return;
    final locations = await db.query('media_locations',
        where: 'file_id=? AND locator=?', whereArgs: [id, path]);
    if (locations.isEmpty) return;
    final value = await facts(id);
    final selected = (value['selection'] as Map?)?['trackId'];
    final tracks = (value['tracks'] as List).cast<JsonMap>();
    await player.reapply(
        id, tracks, tracks.where((t) => t['id'] == selected).firstOrNull);
  }

  @override
  Future<List<JsonMap>> episodeTracks(String id) async {
    final tracks = <JsonMap>[];
    for (final file in await db
        .query('media_file_episodes', where: 'episode_id=?', whereArgs: [id])) {
      final facts = await this.facts(file['file_id'] as String);
      tracks.addAll((facts['tracks'] as List).cast<JsonMap>().map((t) => {
            ...t,
            'fileId': file['file_id'],
            'selected': (facts['selection'] as Map?)?['trackId'] == t['id'],
            'selectionBasis': (facts['selection'] as Map?)?['basis']
          }));
    }
    return tracks;
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

  void attachPlayer(SubtitleTarget player) {
    detachPlayer();
    _player = player;
    player.loader = (path) => loadForPlayback(player, path);
    player.selection = (path, index, external) async {
      final id = await identities.ensureFile(path);
      final value = await facts(id);
      final track = (value['tracks'] as List)
          .cast<JsonMap>()
          .where((t) => external != null
              ? t['path'] == external || t['playbackPath'] == external
              : t['origin'] == 'embedded' && t['index'] == index)
          .firstOrNull;
      if (track != null || index == -1) {
        await select(id, track?['id'] as String?);
      }
    };
  }

  void detachPlayer() {
    _player?.loader = null;
    _player?.selection = null;
    _player = null;
  }

  Future<bool> loadForPlayback(SubtitleTarget player, String path) async {
    if (await remoteLoader?.call(player, path) == true) return true;
    if (path.contains('://')) return false;
    final id = await identities.ensureFile(path);
    await inspect(id, path);
    if (player.path != path) return true;
    final value = await facts(id);
    for (final track in (value['tracks'] as List).cast<JsonMap>()) {
      if (track['origin'] != 'embedded' && track['available'] == true) {
        await player.offer(
            track['playbackPath'] as String? ?? track['path'] as String,
            track['title'] as String);
        if (player.path != path) return true;
      }
    }
    final selection = value['selection'] as Map?;
    final track = (value['tracks'] as List)
        .cast<JsonMap>()
        .where(
            (t) => t['id'] == selection?['trackId'] && t['available'] == true)
        .firstOrNull;
    if (track != null) {
      if (track['origin'] == 'embedded') {
        await player.applyEmbedded(track['index'] as int);
      } else {
        await player.applyExternal(
            track['playbackPath'] as String? ?? track['path'] as String,
            track['title'] as String);
      }
    } else if (selection?['basis'] == 'explicit') {
      await player.clear();
    }
    return true;
  }

  /// Not following files until [start] again.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    await _events?.cancel();
    _events = null;
    await _worker;
  }

  Future<void> close() async {
    _closed = true;
    detachPlayer();
    _timer?.cancel();
    await _events?.cancel();
    await _worker;
    await Future.wait(_reads.values);
    await Future.wait(_mutations.values);
  }
}

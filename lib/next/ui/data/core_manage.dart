import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:nipa_harness/nipa_harness.dart';

import '../../ui_data/ui_data.dart';
import 'work_manage.dart';

/// [NextWorkManage] through the harness, as the person (`origin: gui`).
///
/// The interface knows works and episodes by their merged library IDs;
/// most media Actions take the local catalogue's. A work's local IDs are
/// read the way the agent would: `media.library.readable` names each
/// episode's local episode and file, `media.identity.get` walks up to the
/// release and the work. Nothing is inferred from names.
final class CoreWorkManage implements NextWorkManage {
  CoreWorkManage(this.harness, this.data);

  /// The runtime's, read at each call (it may come later).
  final Harness Function() harness;
  final NextUiData data;

  Invocation get _gui => Invocation(origin: 'gui');

  Future<Outcome<JsonEncodable>> _invoke(String action, JsonMap input) =>
      harness().invokeJson(action, input, _gui);

  Future<JsonMap> _call(String action, JsonMap input) async {
    final outcome = await _invoke(action, input);
    return switch (outcome) {
      Completed(:final value) => value.toJson(),
      Failed(:final failure) => throw _error(failure),
      NeedsDecision() =>
        throw const UiManageError(message: 'asked for a decision'),
    };
  }

  static UiManageError _error(Failure failure) => UiManageError(
      conflict: failure.code == FailureCode.conflict,
      message: failure.message);

  /// Batch outcomes report each entry; any that failed fails the whole.
  static void _entries(JsonMap result, String key) {
    for (final e in _maps(result[key])) {
      final error = e['error'];
      if (e['status'] == 'failed' || e['saved'] == false || error is Map) {
        throw UiManageError(
            conflict: error is Map && error['code'] == 'conflict',
            message: error is Map ? '${error['message']}' : null);
      }
    }
  }

  static final _random = math.Random.secure();
  static String _id(String prefix) =>
      '$prefix-${List.generate(12, (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';

  static List<Map> _maps(Object? v) =>
      v is List ? v.whereType<Map>().toList() : const [];
  static String? _text(Object? v) =>
      v is String && v.trim().isNotEmpty ? v.trim() : null;
  static int? _int(Object? v) =>
      v is int ? v : (v is String ? int.tryParse(v) : null);

  static const _providers = {
    'dandanplay': UiProvider.dandanplay,
    'tmdb': UiProvider.tmdb,
    'bangumi': UiProvider.bangumi,
  };

  // —— Reading a work ——

  Future<JsonMap?> _identity(String entityId) async {
    final outcome = await _invoke('media.identity.get', {'entityId': entityId});
    return switch (outcome) {
      Completed(:final value) => value.toJson()['identity'] as JsonMap,
      Failed(failure: Failure(code: FailureCode.notFound)) => null,
      Failed(:final failure) => throw _error(failure),
      NeedsDecision() => null,
    };
  }

  /// Each episode's local file on this device (`media.library.readable`).
  Future<Map<String, Map>> _readable(List<String> episodeIds) async {
    if (episodeIds.isEmpty) return const {};
    final result =
        await _call('media.library.readable', {'episodeIds': episodeIds});
    return {
      for (final e in _maps(result['entries']))
        if (e['error'] == null && e['local'] != false && e['path'] is String)
          e['episodeId'] as String: e
    };
  }

  /// The work entity above a local episode: episode → release → work.
  Future<JsonMap?> _workAbove(String localEpisodeId) async {
    var node = await _identity(localEpisodeId);
    for (var i = 0; i < 2 && node != null; i++) {
      if (node['kind'] == 'work') return node;
      final parent = node['parentId'] as String?;
      node = parent == null ? null : await _identity(parent);
    }
    return node?['kind'] == 'work' ? node : null;
  }

  static List<Map> _accepted(JsonMap identity) => [
        for (final b in _maps(identity['bindings']))
          if (b['status'] == 'accepted') b
      ];

  /// Whether the catalogue would remove it as its own: a local work.
  Future<bool> _isLocal(String workId) async {
    final outcome = await _invoke('media.entities.remove_batch', {
      'entityIds': [workId],
      'requestId': _id('gui-preview'),
      'reason': 'Viewer opened the work sheet.',
      'preview': true,
    });
    return outcome is Completed;
  }

  static UiText _textFact(Object? fact) {
    final f = fact is Map ? fact : const {};
    final source = f['source'];
    final value = f['value'];
    return UiText(value is String ? value : null,
        edited: source is Map && source.containsKey('mode'));
  }

  static UiArt _artFact(Object? fact) {
    final f = fact is Map ? fact : const {};
    final source = f['source'];
    return UiArt(f['path'] as String?,
        edited: source is Map && source['edit'] != null);
  }

  @override
  Future<UiManagedWork> work(UiWork work) async {
    final facts = (await _call('media.metadata.ui_facts', {
      'workId': work.workId
    }));
    final fields = facts['fields'] as Map;
    final items = _maps((facts['episodes'] as Map)['items']);
    final shown = {
      for (final e in await data.episodes(work.workId)) e.episodeId: e
    };
    final files =
        await _readable([for (final e in items) e['episodeId'] as String]);

    var entity = await _identity(work.workId);
    if (entity != null && entity['kind'] != 'work') entity = null;
    for (final f in files.values) {
      if (entity != null) break;
      if (f['sourceEpisodeId'] case final String id) {
        entity = await _workAbove(id);
      }
    }
    final workId = entity?['id'] as String?;
    final bindings = entity == null ? const <Map>[] : _accepted(entity);
    final provider = [
      for (final b in bindings)
        if (_providers[(b['ref'] as Map)['provider']] case final p?) (p, b)
    ].firstOrNull;
    final kind = workId == null
        ? UiWorkKind.files
        : provider != null
            ? UiWorkKind.matched
            : await _isLocal(workId)
                ? UiWorkKind.local
                : UiWorkKind.loose;

    final sizes = <String, Map>{};
    if (workId != null) {
      final listed = await _invoke('media.files.list', {'workId': workId});
      if (listed case Completed(:final value)) {
        for (final f in _maps(value.toJson()['files'])) {
          sizes[f['path'] as String] = f;
        }
      }
    }

    final episodes = <UiManagedEpisode>[];
    for (final item in items) {
      final id = item['episodeId'] as String;
      final file = files[id];
      if (file == null) continue;
      final local = file['sourceEpisodeId'] as String?;
      final path = file['path'] as String;
      final listed = sizes[path];
      final title = item['title'] as Map?;
      episodes.add(UiManagedEpisode(
        episode: shown[id],
        number: '${item['number'] ?? ''}',
        season: _int(item['season']),
        title: title?['value'] as String?,
        titleEdited:
            title?['source'] is Map && (title!['source'] as Map).containsKey('mode'),
        files: [
          UiFile(
            path: path,
            size: _int(listed?['size']),
            duration: _int(listed?['durationMs']) == null
                ? null
                : Duration(milliseconds: _int(listed!['durationMs'])!),
            modified: DateTime.tryParse('${listed?['modifiedAt']}'),
            handle: _FileRef(file['fileId'] as String?, local),
          )
        ],
        handle: _EpisodeRef(id, local),
      ));
    }

    final devices = work.devices.where((d) => d.name.isNotEmpty);
    return UiManagedWork(
      work: work,
      kind: kind,
      match: provider == null
          ? null
          : UiMatch(
              provider: provider.$1,
              title: _textFact(fields['title']).value ?? work.title,
              year: work.year,
              image: work.artwork.poster,
              candidate: UiMatchCandidate(
                provider: provider.$1,
                title: work.title,
                ref: Map<String, Object?>.from(provider.$2['ref'] as Map),
                current: true,
              ),
            ),
      text: {
        UiTextField.title: _textFact(fields['title']),
        UiTextField.originalTitle: _textFact(fields['originalTitle']),
        UiTextField.overview: _textFact(fields['overview']),
      },
      art: {
        UiArtKind.backdrop: _artFact(fields['backdrop']),
        UiArtKind.poster: _artFact(fields['poster']),
        UiArtKind.logo: _artFact(fields['logo']),
      },
      episodes: episodes,
      editable: workId != null || episodes.isNotEmpty,
      elsewhere: workId == null && episodes.isEmpty
          ? devices.firstOrNull?.name
          : null,
      handle: _WorkRef(workId, [for (final b in bindings) b]),
    );
  }

  _WorkRef _work(UiManagedWork work) {
    final ref = work.handle as _WorkRef;
    if (ref.workId == null) throw const UiManageError(message: 'no local work');
    return ref;
  }

  // —— 匹配 ——

  @override
  Future<List<UiMatchCandidate>> search(
      UiProvider provider, String query) async {
    final result = await _call('media.metadata.search',
        {'provider': provider.name, 'query': query});
    return [
      for (final r in _maps(result['results']))
        if (_text(r['title']) case final title?)
          UiMatchCandidate(
            provider: provider,
            title: title,
            ref: Map<String, Object?>.from(r['ref'] as Map),
            originalTitle: _text(r['originalTitle']),
            year: _int(r['year']),
            image: _text(r['imageUrl']),
            movie: r['kind'] == 'movie',
            elsewhere: r['workId'] != null,
          )
    ];
  }

  @override
  Future<List<UiCandidateEpisode>> candidateEpisodes(
      UiMatchCandidate candidate) async {
    final record = (await _call('media.metadata.get', {'ref': candidate.ref}))[
        'record'] as Map;
    final out = <UiCandidateEpisode>[];
    void add(Map e, Map? release, int? season) {
      out.add(UiCandidateEpisode(
        number: '${e['number'] ?? e['order'] ?? ''}',
        season: _int(e['season']) ?? season,
        title: _text(e['title']),
        ref: Map<String, Object?>.from(e['ref'] as Map),
        release: release == null ? null : Map<String, Object?>.from(release),
      ));
    }

    for (final e in _maps(record['episodes'])) {
      final ref = e['ref'] as Map;
      if (ref['objectType'] == 'season') {
        for (final inner in _maps(e['episodes'])) {
          add(inner, ref, _int(e['number']) ?? _int(e['season']));
        }
      } else {
        add(e, null, null);
      }
    }
    return out;
  }

  /// Files linked to episodes of another identity are let go first; the
  /// catalogue refuses to relink them silently.
  Future<void> _releaseFiles(Iterable<UiFile> files, String reason) async {
    final entries = <JsonMap>[];
    for (final file in files) {
      final id = (file.handle as _FileRef).fileId;
      if (id == null) continue;
      final identity = await _identity(id);
      if (identity == null) continue;
      final accepted = _accepted(identity);
      if (accepted.isEmpty) continue;
      entries.add({
        'entityId': id,
        'reason': reason,
        'bindingIds': [for (final b in accepted) b['bindingId']],
      });
    }
    if (entries.isEmpty) return;
    await _call('media.identity.unbind_batch',
        {'requestId': _id('gui-unbind'), 'entries': entries});
  }

  @override
  Future<void> match(UiManagedWork work, UiMatchCandidate candidate,
      Map<UiFile, UiCandidateEpisode> files) async {
    if (files.isEmpty) throw const UiManageError(message: 'no files');
    const reason = 'Viewer matched the work in its sheet.';
    await _releaseFiles(files.keys, reason);
    await _call('media.identity.bind_batch', {
      'requestId': _id('gui-bind'),
      'entries': [
        for (final MapEntry(key: file, value: episode) in files.entries)
          {
            'kind': 'file',
            'reason': reason,
            'entityId': (file.handle as _FileRef).fileId,
            'workRef': candidate.ref,
            if (episode.release != null) 'releaseRef': episode.release,
            'episodeRefs': [episode.ref],
          }
      ],
    });
  }

  @override
  Future<void> unmatch(UiManagedWork work) async {
    final ref = _work(work);
    await _call('media.identity.unbind_batch', {
      'requestId': _id('gui-unbind'),
      'entries': [
        {
          'entityId': ref.workId,
          'reason': 'Viewer let go of the match in the work sheet.',
          'bindingIds': [for (final b in ref.bindings) b['bindingId']],
        }
      ],
    });
  }

  // —— 本地作品 ——

  @override
  Future<String> createLocal(UiManagedWork from, String title) async {
    const reason = 'Viewer made a work of its own.';
    final files = from.files;
    await _releaseFiles(files, reason);
    final work = _id('local-work'), release = _id('local-release');
    await _call('media.entities.put_batch', {
      'requestId': _id('gui-put'),
      'reason': reason,
      'entries': [
        {'entityId': work, 'kind': 'work', 'title': title},
        {
          'entityId': release,
          'kind': 'release',
          'parentId': work,
          'title': title
        },
        for (final (i, file) in files.indexed)
          {
            'entityId': _id('local-episode'),
            'kind': 'episode',
            'parentId': release,
            'title': file.name.replaceFirst(RegExp(r'\.[^.]+$'), ''),
            'number': '${i + 1}',
            'fileIds': [(file.handle as _FileRef).fileId],
          }
      ],
    });
    return work;
  }

  /// Puts entries in two steps: the preview's plan, then the change.
  Future<JsonMap> _put(List<JsonMap> entries, String reason) async {
    final requestId = _id('gui-put');
    final preview = await _call('media.entities.put_batch', {
      'requestId': requestId,
      'reason': reason,
      'entries': entries,
      'preview': true,
    });
    return _call('media.entities.put_batch', {
      'requestId': requestId,
      'reason': reason,
      'entries': entries,
      if (preview['expectedPlan'] != null)
        'expectedPlan': preview['expectedPlan'],
    });
  }

  /// The release local episodes hang from, made when the work has none.
  Future<String> _release(UiManagedWork work, List<JsonMap> entries) async {
    for (final e in work.episodes) {
      final local = (e.handle as _EpisodeRef).localId;
      if (local == null) continue;
      final parent = (await _identity(local))?['parentId'] as String?;
      if (parent != null) return parent;
    }
    final release = _id('local-release');
    entries.add({
      'entityId': release,
      'kind': 'release',
      'parentId': _work(work).workId,
      'title': work.work.title,
    });
    return release;
  }

  @override
  Future<void> saveLocal(
      UiManagedWork work, List<UiLocalEpisodeEdit> edits) async {
    final entries = <JsonMap>[];
    final release = await _release(work, entries);
    for (final edit in edits) {
      final local = (edit.handle as _EpisodeRef?)?.localId;
      final identity = local == null ? null : await _identity(local);
      entries.add({
        'entityId': local ?? _id('local-episode'),
        'kind': 'episode',
        'parentId': identity?['parentId'] ?? release,
        'title': edit.title ?? edit.number,
        'number': edit.number,
        if (edit.season != null) 'season': edit.season,
        'fileIds': [
          for (final f in edit.files)
            if ((f.handle as _FileRef).fileId case final id?) id
        ],
        if (identity != null) 'expectedRevision': identity['revision'],
      });
    }
    await _put(entries, 'Viewer edited the episodes of a work of its own.');
  }

  @override
  Future<void> addFile(UiManagedWork work, String path) async {
    final outcome = await _invoke('media.identity.get', {'path': path});
    final file = switch (outcome) {
      Completed(:final value) => value.toJson()['identity'] as JsonMap,
      Failed(:final failure) => throw _error(failure),
      NeedsDecision() => throw const UiManageError(),
    };
    final entries = <JsonMap>[];
    final release = await _release(work, entries);
    final numbers = [for (final e in work.episodes) int.tryParse(e.number) ?? 0];
    final next = numbers.isEmpty ? 1 : numbers.reduce(math.max) + 1;
    entries.add({
      'entityId': _id('local-episode'),
      'kind': 'episode',
      'parentId': release,
      'title': path
          .split(RegExp(r'[\\/]'))
          .last
          .replaceFirst(RegExp(r'\.[^.]+$'), ''),
      'number': '$next',
      'fileIds': [file['id']],
    });
    await _put(entries, 'Viewer added a file to a work of its own.');
  }

  @override
  Future<UiUndo> removeLocal(UiManagedWork work,
      {UiManagedEpisode? episode}) async {
    final id = episode == null
        ? _work(work).workId!
        : (episode.handle as _EpisodeRef).localId!;
    const reason = 'Viewer removed it from the catalogue.';
    final requestId = _id('gui-remove');
    final preview = await _call('media.entities.remove_batch', {
      'entityIds': [id],
      'requestId': requestId,
      'reason': reason,
      'preview': true,
    });
    final result = await _call('media.entities.remove_batch', {
      'entityIds': [id],
      'requestId': requestId,
      'reason': reason,
      'preview': false,
      'expectedPlan': preview['expectedPlan'],
    });
    return UiUndo(result['undoId'] as String);
  }

  @override
  Future<void> restore(UiUndo undo) =>
      _call('media.entities.restore', {'undoId': undo.handle});

  // —— 资料与图片 ——

  @override
  Future<void> editText(
      UiManagedWork work, Map<UiTextField, String?> values) async {
    if (values.isEmpty) return;
    final id = _work(work).workId;
    await _call('media.metadata.override_batch', {
      'entries': [
        for (final MapEntry(key: field, value: value) in values.entries)
          {'entityId': id, 'field': field.name, 'value': value}
      ]
    });
  }

  @override
  Future<void> editEpisodeTitles(Map<UiManagedEpisode, String?> titles) async {
    final entries = [
      for (final MapEntry(key: e, value: title) in titles.entries)
        if ((e.handle as _EpisodeRef).localId case final id?)
          {'entityId': id, 'field': 'title', 'value': title}
    ];
    if (entries.isEmpty) return;
    await _call('media.metadata.override_batch', {'entries': entries});
  }

  @override
  Future<void> clearText(UiManagedWork work, UiTextField field) =>
      _call('media.metadata.override', {
        'entityId': _work(work).workId,
        'field': field.name,
        'value': null,
        'mode': 'clear',
      });

  @override
  Future<void> setArt(UiManagedWork work, UiArtKind kind, String file) async {
    final result = await _call('media.artwork.set', {
      'entries': [
        {
          'entityId': _work(work).workId,
          'kind': kind.name,
          'file': file,
          'source': {'label': '本地文件'},
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> clearArt(UiManagedWork work, UiArtKind kind) =>
      _call('media.artwork.clear', {
        'entries': [
          {'entityId': _work(work).workId, 'kind': kind.name}
        ]
      });

  @override
  Future<void> refresh(UiManagedWork work) async {
    final refs = [for (final b in _work(work).bindings) b['ref']];
    if (refs.isEmpty) throw const UiManageError(message: 'no match');
    final result = await _call('media.metadata.refresh_batch', {
      'entries': [
        for (final ref in refs) {'ref': ref, 'requestId': _id('gui-refresh')}
      ]
    });
    _entries(result, 'entries');
  }

  // —— 剧集 ——

  @override
  Future<UiManagedEpisode> episode(UiWork work, UiEpisode episode) async {
    final file = (await _readable([episode.episodeId]))[episode.episodeId];
    final local = file?['sourceEpisodeId'] as String?;
    final fileId = file?['fileId'] as String?;
    final path = file?['path'] as String?;

    Map? listed;
    if (local != null && path != null) {
      final owner = await _workAbove(local);
      if (owner != null) {
        final outcome =
            await _invoke('media.files.list', {'workId': owner['id']});
        if (outcome case Completed(:final value)) {
          listed = _maps(value.toJson()['files'])
              .where((f) => f['path'] == path)
              .firstOrNull;
        }
      }
    }
    final uiFile = path == null
        ? null
        : UiFile(
            path: path,
            size: _int(listed?['size']),
            duration: _int(listed?['durationMs']) == null
                ? null
                : Duration(milliseconds: _int(listed!['durationMs'])!),
            modified: DateTime.tryParse('${listed?['modifiedAt']}'),
            handle: _FileRef(fileId, local),
          );

    final tracks = <UiDanmakuTrack>[];
    final seen = <Object>{};
    for (final entity in [local, fileId].whereType<String>()) {
      final result = await _call('danmaku.tracks', {'entityId': entity});
      for (final t in _maps(result['tracks'])) {
        final key = t['bindingId'] ?? t['trackId'];
        if (key == null || !seen.add(key)) continue;
        tracks.add(_track(t));
      }
    }

    final subtitles = <UiSubtitles>[];
    if (fileId != null && uiFile != null) {
      final result = await _call('subtitle.tracks', {
        'fileIds': [fileId]
      });
      for (final facts in _maps(result['files'])) {
        subtitles.add(_subtitles(facts, uiFile));
      }
    }

    return UiManagedEpisode(
      episode: episode,
      number: '${episode.number}',
      season: episode.season,
      title: episode.title,
      files: [if (uiFile != null) uiFile],
      danmaku: tracks,
      subtitles: subtitles,
      handle: _EpisodeRef(episode.episodeId, local),
    );
  }

  static const _platforms = {
    'dandanplay': '弹弹play',
    'local': '本地文件',
    'bilibili': 'B 站',
    'youku': '优酷',
    'iqiyi': '爱奇艺',
    'tencent': '腾讯视频',
  };

  static String _platform(Object? p) =>
      _platforms['$p'] ?? (p is String && p.isNotEmpty ? p : '弹幕');

  UiDanmakuTrack _track(Map t) {
    var count = _int(t['count']);
    if (count == null) {
      final chunks = _maps(t['coverage']);
      if (chunks.isNotEmpty) {
        count = chunks.fold<int>(0, (n, c) => n + (_int(c['entry_count']) ?? 0));
      }
    }
    final origin = '${t['origin']}';
    return UiDanmakuTrack(
      source: _platform(origin == 'sidecar' || origin.endsWith('import')
          ? (t['platform'] == null || t['platform'] == 'local'
              ? 'local'
              : t['platform'])
          : t['platform'] ?? t['source']),
      name: _text((t['video'] as Map?)?['title']) ?? _text(t['name']),
      count: count,
      enabled: t['enabled'] != false,
      offset: Duration(milliseconds: _int(t['offsetMs']) ?? 0),
      loading: t['status'] == 'pending' || t['stale'] == true && count == null,
      removable: t['bindingId'] != null,
      handle: _TrackRef(t['bindingId'] as String?, t['trackId'] as String?,
          _int(t['revision'])),
    );
  }

  static UiSubtitles _subtitles(Map facts, UiFile file) {
    final selection = facts['selection'] as Map?;
    return UiSubtitles(
      file: file,
      tracks: [
        for (final t in _maps(facts['tracks']))
          UiSubtitleTrack(
            id: t['id'] as String,
            kind: switch (t['origin']) {
              'embedded' => UiSubtitleKind.embedded,
              'import' => UiSubtitleKind.imported,
              _ => UiSubtitleKind.external,
            },
            language: t['language'] as String?,
            title: _text(t['title']),
            format: _text(t['format']),
            available: t['available'] != false,
          )
      ],
      selected: selection?['trackId'] as String?,
      explicit: selection?['basis'] == 'explicit',
      detached: [
        for (final p in facts['detachedPaths'] is List
            ? facts['detachedPaths'] as List
            : const [])
          if (p is String) p
      ],
      handle: _SubtitleRef(facts['fileId'] as String, _int(facts['revision']) ?? 0),
    );
  }

  @override
  Future<void> setDanmaku(UiDanmakuTrack track,
      {bool? enabled, Duration? offset}) async {
    final ref = track.handle as _TrackRef;
    final result = await _call('danmaku.update', {
      'changes': [
        {
          if (ref.bindingId != null) ...{
            'bindingId': ref.bindingId,
            'expectedRevision': ref.revision,
          } else
            'trackId': ref.trackId,
          if (enabled != null) 'enabled': enabled,
          if (offset != null) 'offsetMs': offset.inMilliseconds,
        }
      ]
    });
    _entries(result, 'results');
  }

  @override
  Future<List<UiDanmakuCandidate>> searchDanmaku(String query) async {
    final sources = await _call('danmaku.sources', {});
    final out = <UiDanmakuCandidate>[];
    for (final s in _maps(sources['sources'])) {
      if (s['search'] != true) continue;
      final result = await _call(
          'danmaku.search', {'sourceId': s['sourceId'], 'query': query});
      for (final v in _maps(result['results'])) {
        out.add(UiDanmakuCandidate(
          title: _text(v['title']) ?? '',
          source: _platform(s['platform'] ?? s['sourceId']),
          handle: Map<String, Object?>.from(v),
        ));
      }
    }
    return out;
  }

  @override
  Future<void> addDanmaku(
      UiManagedEpisode episode, UiDanmakuCandidate found) async {
    final ref = episode.handle as _EpisodeRef;
    final duration = episode.files.firstOrNull?.duration ??
        episode.episode?.runtime;
    final video = Map<String, Object?>.from(found.handle as Map);
    if (duration != null && (video['durationMs'] as num? ?? 0) <= 0) {
      video['durationMs'] = duration.inMilliseconds;
    }
    final entity = ref.localId ??
        (episode.files.firstOrNull?.handle as _FileRef?)?.fileId;
    await _call('danmaku.attach', {
      'video': video,
      'reason': 'Viewer added comments in the episode sheet.',
      'requestId': _id('gui-attach'),
      if (entity != null) 'entityId': entity,
    });
  }

  @override
  Future<void> importDanmaku(UiManagedEpisode episode, String path) async {
    final ref = episode.handle as _EpisodeRef;
    final entity = ref.localId ??
        (episode.files.firstOrNull?.handle as _FileRef?)?.fileId;
    await _call('danmaku.import', {
      'filePath': path,
      'platform': 'local',
      'platformVideoId': path.split(RegExp(r'[\\/]')).last,
      if (entity != null) 'entityId': entity,
    });
  }

  @override
  Future<void> removeDanmaku(UiDanmakuTrack track) async {
    final ref = track.handle as _TrackRef;
    await _call('danmaku.detach',
        {'bindingId': ref.bindingId, 'revision': ref.revision});
  }

  @override
  Future<void> selectSubtitle(UiSubtitles file, String? trackId) =>
      _call('subtitle.select', {
        'fileId': (file.handle as _SubtitleRef).fileId,
        'trackId': trackId,
      });

  @override
  Future<void> automaticSubtitle(UiSubtitles file) async {
    final result = await _call('subtitle.reset_selection', {
      'entries': [
        {'fileId': (file.handle as _SubtitleRef).fileId}
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> importSubtitle(UiSubtitles file, String path) async {
    final result = await _call('subtitle.import', {
      'entries': [
        {
          'fileId': (file.handle as _SubtitleRef).fileId,
          'filePath': path,
          'language': 'und',
          'source': {'label': '本地文件'},
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> editSubtitle(UiSubtitles file, UiSubtitleTrack track,
      {String? language, String? title}) async {
    final ref = file.handle as _SubtitleRef;
    final result = await _call('subtitle.update', {
      'entries': [
        {
          'fileId': ref.fileId,
          'trackId': track.id,
          'expectedRevision': ref.revision,
          'patch': {
            if (language != null) 'language': language,
            if (title != null) 'title': title,
          },
        }
      ]
    });
    _entries(result, 'entries');
  }

  @override
  Future<void> detachSubtitle(UiSubtitles file, UiSubtitleTrack track) async {
    final ref = file.handle as _SubtitleRef;
    final result = await _call('subtitle.remove', {
      'entries': [
        {
          'fileId': ref.fileId,
          'trackId': track.id,
          'expectedRevision': ref.revision
        }
      ]
    });
    _entries(result, 'entries');
  }

  /// A destructive Action's question as the sheet asks it: [items], and
  /// running the option NipaPlay offered.
  Future<UiConfirm> _decision(
      String action, JsonMap input, List<String> items) async {
    final outcome = await _invoke(action, input);
    return switch (outcome) {
      NeedsDecision(:final decision) when decision.options.isNotEmpty =>
        UiConfirm(
          items: items,
          run: () async {
            final call = decision.options.first.call;
            final done = await _invoke(call.actionId, call.input);
            if (done case Failed(:final failure)) throw _error(failure);
          },
        ),
      Failed(:final failure) => throw _error(failure),
      _ => throw const UiManageError(message: 'no decision offered'),
    };
  }

  @override
  Future<UiConfirm> deleteSubtitleCopies(UiSubtitles file) => _decision(
      'subtitle.copy_delete',
      {'paths': file.detached},
      [for (final p in file.detached) p.split(RegExp(r'[\\/]')).last]);

  @override
  Future<void> reveal(UiFile file) async {
    if (!Platform.isMacOS) return;
    await Process.run('open', ['-R', file.path]);
  }

  @override
  Future<UiConfirm> deleteFile(UiFile file) => _decision(
      'media.mesh_files.delete',
      {
        'paths': [file.path]
      },
      [file.name]);

  @override
  Future<String?> pickFile(List<String> kinds) async =>
      (await openFile(acceptedTypeGroups: [XTypeGroup(extensions: kinds)]))
          ?.path;
}

final class _WorkRef {
  const _WorkRef(this.workId, this.bindings);

  /// The local work entity; null when there is none on this device.
  final String? workId;
  final List<Map> bindings;
}

final class _EpisodeRef {
  const _EpisodeRef(this.episodeId, this.localId);
  final String episodeId;
  final String? localId;
}

/// A file on this device (other devices' files are changed there).
final class _FileRef {
  const _FileRef(this.fileId, this.localEpisodeId);
  final String? fileId;
  final String? localEpisodeId;
}

final class _TrackRef {
  const _TrackRef(this.bindingId, this.trackId, this.revision);
  final String? bindingId;
  final String? trackId;
  final int? revision;
}

final class _SubtitleRef {
  const _SubtitleRef(this.fileId, this.revision);
  final String fileId;
  final int revision;
}

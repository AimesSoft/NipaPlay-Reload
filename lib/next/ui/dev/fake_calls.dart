part of 'fake_world.dart';

final _fakeCalls = Expando<FakeCalls>('FakeCalls');

extension FakeWorldCalls on FakeWorld {
  /// The Actions the pages call directly, against the scripted world.
  FakeCalls get calls => _fakeCalls[this] ??= FakeCalls._(this);
}

/// Development-only: the Actions behind downloads, background work,
/// history, collections, folders, caches, updates, plugins and sync, with
/// the real contracts' shapes and the world's own tasks. A harness of its
/// own, so nothing real is touched.
final class FakeCalls {
  FakeCalls._(this.world) {
    _seed();
  }
  final FakeWorld world;

  /// Who is signed in, from the scripted settings.
  Future<Map<String, bool>> Function() accounts =
      () async => {'dandanplay': true, 'bangumi': true};

  late final harness = Harness([_FakeCapability(_actions())]);

  /// Debug: Actions that fail until cleared, and how limits behave
  /// (`on`, `stopped`, `unsupported`).
  final failing = <String>{};
  String limitsMode = 'on';

  static const _home = '/Users/hikari';

  final _downloads = <String, _FakeDownload>{};
  int _added = 0;
  int _down = 0, _up = 0;
  final _capacity = {'scan': 1, 'metadata': 4, 'helper': 2};
  final _decisions = <String, Decision>{};
  final _history = <JsonMap>[];
  final _collections = <String, (String, int?)>{
    'frieren': ('doing', 9),
    'bocchi': ('done', 10),
    'dungeon': ('wish', null),
    'lycoris': ('onHold', 7),
    'edgerunners': ('done', 9),
    'violet': ('done', 10),
    'oshinoko': ('dropped', 5),
    'kusuriya': ('doing', 8),
  };
  final _caches = <String, int>{
    'images': 812 << 20,
    'nextArtwork': 431 << 20,
    'classicDanmaku': 96 << 20,
    'nextDanmaku': 188 << 20,
    'thumbnails': 154 << 20,
    'timeline': 61 << 20,
  };
  _FakeUpdate _update = const _FakeUpdate();
  final _plugins = <String, JsonMap>{
    'danmaku-filter': {
      'id': 'danmaku-filter',
      'name': '弹幕屏蔽词',
      'version': '1.2.0',
      'builtin': true,
      'enabled': true,
      'loaded': true,
      'description': '按词语和用户屏蔽弹幕',
      'actions': [
        {'id': 'export', 'title': '导出屏蔽词', 'description': '列出当前的屏蔽词'},
      ],
    },
    'bilibili-danmaku': {
      'id': 'bilibili-danmaku',
      'name': 'B 站弹幕',
      'version': '0.9.1',
      'builtin': false,
      'enabled': true,
      'loaded': true,
      'description': '从哔哩哔哩取弹幕',
      'actions': [
        {'id': 'login', 'title': '登录哔哩哔哩', 'description': '扫码登录'},
        {'id': 'clear', 'title': '清空缓存', 'description': '删除已取的弹幕'},
        {'id': 'refresh', 'title': '刷新 Cookie', 'description': '重新取 Cookie'},
      ],
    },
    'spoiler-guard': {
      'id': 'spoiler-guard',
      'name': '防剧透',
      'version': '0.3.0',
      'builtin': false,
      'enabled': false,
      'loaded': false,
      'description': '藏起剧透的弹幕',
    },
    'old-subtitles': {
      'id': 'old-subtitles',
      'name': '字幕组索引',
      'version': '0.1.0',
      'builtin': false,
      'enabled': true,
      'loaded': false,
      'error': 'SyntaxError: Unexpected token',
      'description': '',
    },
  };
  static const _market = [
    {
      'id': 'bilibili-danmaku',
      'name': 'B 站弹幕',
      'version': '1.0.0',
      'description': '从哔哩哔哩取弹幕'
    },
    {
      'id': 'acfun-danmaku',
      'name': 'A 站弹幕',
      'version': '0.4.2',
      'description': '从 AcFun 取弹幕'
    },
    {
      'id': 'gamer-danmaku',
      'name': '巴哈姆特弹幕',
      'version': '0.2.0',
      'description': '从动画疯取弹幕'
    },
  ];
  var _sync = <String, Object?>{
    'url': 'https://dav.example.net/remote.php/dav/files/hikari',
    'username': 'hikari',
    'remotePath': '/NipaPlay',
    'intervalMinutes': 30,
    'categories': ['watchHistory', 'mediaLibraries', 'episodeMatches'],
    'syncOnRecordChange': true,
  };
  bool _syncEnabled = true, _syncing = false, _syncKey = true;

  /// Debug: whether a sync password is saved.
  set syncPassword(bool saved) => _syncKey = saved;
  DateTime? _synced = DateTime.now().subtract(const Duration(minutes: 42));
  final _roots = ['$_home/Movies/番剧', '/Volumes/NAS/动画'];
  int _scans = 0;

  // —— the world ——

  void _seed() {
    final now = DateTime.now();
    void add(String key, String name, UiTaskState state, double progress,
        {String? error, Duration ago = Duration.zero}) {
      final id = 'fake-dl-$key';
      final task = _FakeTask(id, world.sample(key).title,
          world.sample(key).artwork, progress)
        ..state = state;
      world._tasks[id] = task;
      _downloads[id] = _FakeDownload.of(world, key, name,
          error: error, created: now.subtract(ago));
    }

    add('bocchi', '[LoliHouse] Bocchi the Rock! [01-12][WebRip 1080p HEVC]',
        UiTaskState.finished, 1,
        ago: const Duration(days: 2));
    add('edgerunners', '[ANi] Cyberpunk Edgerunners [01-10][1080P]',
        UiTaskState.failed, 0.38,
        error: 'No space left on device', ago: const Duration(days: 1));
    if (world._ticker != null) {
      add('lycoris', '[Nekomoe kissaten] Lycoris Recoil [01-13][1080p]',
          UiTaskState.paused, 0.31,
          ago: const Duration(hours: 5));
    }
    final samples = (world._meta.keys.toList()..remove('sintel'));
    final random = math.Random(7);
    var at = now.subtract(const Duration(minutes: 40));
    for (var i = 0; i < 110; i++) {
      final key = samples[(i * 5 + i ~/ 3) % samples.length];
      final work = world.sample(key);
      final number = 1 + (i * 3 + 2) % (work.episodeCount ?? 12);
      final progress = i % 4 == 0 ? 1.0 : 0.15 + random.nextDouble() * 0.8;
      const duration = 24 * 60 * 1000;
      // One file the library never took in: no work, no pictures.
      final loose = i == 3;
      _history.add({
        'entryId': 'history-$i',
        'fileId': loose ? null : 'fake-file-$key-$number',
        'workId': loose ? null : work.workId,
        'libraryEpisodeId': loose ? null : 'fake:$key:$number',
        'poster': loose ? null : work.artwork.poster,
        'still': loose ? null : world._episode(key, number).still,
        'locator': i == 1
            ? null
            : loose
                ? '$_home/Downloads/[SweetSub] Hibike - 05 [1080p].mkv'
                : '$_home/Movies/番剧/${work.originalTitle ?? work.title}/'
                    '${work.title} - ${number.toString().padLeft(2, '0')}.mkv',
        'animeId': loose ? null : 17000 + samples.indexOf(key),
        'episodeId': null,
        'title': loose ? null : work.title,
        'episodeTitle': loose ? null : '第$number话',
        'positionMs': (progress * duration).round(),
        'durationMs': duration,
        'progress': progress,
        'lastWatchedAt': at.toUtc().toIso8601String(),
      });
      at = at.subtract(Duration(
          minutes: 25 + random.nextInt(i < 6 ? 80 : 60 * 30)));
    }
    world._taskStream.add(world._taskList());
  }

  _FakeDownload? _download(String id) {
    if (_downloads[id] case final d?) return d;
    if (!id.startsWith('fake-task-') || !world._tasks.containsKey(id)) {
      return null;
    }
    final key = id.substring('fake-task-'.length);
    final title = world.sample(key).originalTitle ?? world.sample(key).title;
    return _downloads[id] = _FakeDownload.of(
        world, key, '[Nekomoe kissaten] $title [1080p][CHT]',
        created: DateTime.now().subtract(const Duration(minutes: 12)));
  }

  static String _wire(UiTaskState s) => switch (s) {
        UiTaskState.running => 'running',
        UiTaskState.queued => 'queued',
        UiTaskState.paused => 'paused',
        UiTaskState.finished => 'succeeded',
        UiTaskState.failed => 'failed',
      };

  JsonMap _job(String id) {
    if (_refreshes.containsKey(id)) return _refreshJob(id);
    final t = world._tasks[id];
    final d = _download(id);
    final helper = world._helpers.where((h) => h.id == id).firstOrNull;
    return {
      'jobId': id,
      'type': t?.type ?? 'agent.helper',
      'title': t?.title ?? helper?.title ?? '',
      'state': _decisions.containsKey(id)
          ? 'waiting_user'
          : helper != null
              ? (helper.cancelled
                  ? 'cancelled'
                  : _wire(helper.state))
              : _wire(t?.state ?? UiTaskState.finished),
      'progress': {
        'completed': ((t?.progress ?? 0) * 1000).round(),
        'total': 1000
      },
      'createdAt': (d?.created ?? DateTime.now()).toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'revision': 1,
      if (d?.error != null)
        'error': {'code': 'unavailable', 'message': d!.error},
      if (_decisions[id] case final decision?) 'decision': decision.toJson(),
    };
  }

  Iterable<String> get _ids => [
        ...world._tasks.keys,
        for (final h in world._helpers) h.id,
        ..._decisions.keys,
      ];

  JsonMap _read(String id) {
    final d = _download(id);
    final t = world._tasks[id];
    if (d == null || t == null) {
      throw const Failure(FailureCode.notFound, 'No such download.');
    }
    final selected = [
      for (final (i, f) in d.files.indexed)
        if (d.selected.contains(i)) f.$2
    ];
    final total = selected.fold<int>(0, (n, s) => n + s);
    var left = (total * t.progress).round();
    final running = t.state == UiTaskState.running && t.progress < 1;
    final jitter = math.Random(DateTime.now().second);
    final files = <JsonMap>[];
    for (final (i, (name, size, video)) in d.files.indexed) {
      final included = d.selected.contains(i);
      final done = included ? math.min(size, left) : 0;
      if (included) left -= done;
      final complete = included && done == size;
      files.add({
        'index': i,
        'path': '${d.folder}/${d.name}/$name',
        'local': true,
        'expectedSize': size,
        'included': included,
        'isVideo': video,
        'completedBytes': done,
        'complete': complete,
        'playable': complete && video,
        'streamable': included && video && running,
      });
    }
    return {
      'job': _job(id),
      'task': {
        'handle': id,
        'infoHash': id.hashCode.toRadixString(16),
        'title': d.name,
        'outputDirectory': d.folder,
        'local': true,
        'completedBytes': (total * t.progress).round(),
        'totalBytes': total,
        'finished': t.progress >= 1,
        'paused': t.state == UiTaskState.paused,
        'error': d.error,
        'state': running ? 'live' : 'paused',
        'downloadSpeedBytesPerSecond':
            running ? 3900000 + jitter.nextInt(900000) : 0,
        'uploadSpeedBytesPerSecond': t.progress >= 1 && d.error == null
            ? 86000 + jitter.nextInt(30000)
            : running
                ? 210000 + jitter.nextInt(90000)
                : 0,
        'health': {
          'connectedPeers': running ? 21 + jitter.nextInt(6) : 0,
          'seenPeers': 64,
          'secondsWithoutProgress': running ? 0 : 900,
        },
        'disk': {'availableBytes': d.error != null ? 0 : 212 << 30},
        'files': files,
      },
    };
  }

  static const _preview = (
    '[Nekomoe kissaten] Sousou no Frieren S2 [01-12][1080p][CHS]',
    12
  );

  /// A magnet is the one sample; a torrent's address or file is named by
  /// its file.
  static String _torrentName(String source) => source.startsWith('magnet:')
      ? _preview.$1
      : Uri.decodeComponent(source.split('/').last)
          .replaceAll(RegExp(r'\.torrent$'), '');

  JsonMap _previewOf(String source) {
    if (source.contains('bad')) {
      throw Failure(
          FailureCode.invalidInput,
          source.startsWith('magnet:')
              ? 'Invalid magnet URI.'
              : 'Invalid torrent.');
    }
    final name = _torrentName(source);
    final files = _FakeDownload.manifest(_preview.$2, 1180 << 20);
    return {
      'name': name,
      'suggestedFolderName': name,
      'totalSize': files.fold<int>(0, (n, f) => n + f.$2),
      'files': [
        for (final (i, (file, size, _)) in files.indexed)
          {'index': i, 'path': '$name/$file', 'length': size}
      ],
    };
  }

  /// The download each `download.delete` preview showed, until it is
  /// requested (once).
  final _deletePreviews = <String, String>{};
  int _deletions = 0;

  /// `download.delete` as the interface gets it: the files, and the one
  /// option that asks for their deletion.
  Outcome<_FakeJson> _askDelete(JsonMap input) {
    final id = input['jobId'] as String;
    final d = _download(id);
    if (d == null) {
      throw const Failure(FailureCode.notFound, 'No such download.');
    }
    final preview = 'fake-delete-preview-${++_deletions}';
    _deletePreviews[preview] = id;
    final manifest = {
      'downloads': [
        {
          'jobId': id,
          'infoHash': null,
          'outputDirectory': d.folder,
          'files': [
            for (final (i, (name, size, _)) in d.files.indexed)
              {
                'path': '${d.folder}/${d.name}/$name',
                'local': true,
                'expectedSize': size,
                'included': d.selected.contains(i),
              }
          ],
        }
      ]
    };
    return NeedsDecision(Decision(
        prompt: '删除这些下载文件：${jsonEncode(manifest)}',
        options: [
          DecisionOption(
              label: '请求删除',
              call: ActionCall(
                  'download.delete.request', {'previewId': preview})),
        ]));
  }

  /// `download.delete.request`: a deletion task of its own, waiting for
  /// the person; here its question stands for NipaPlay's own window.
  JsonMap _requestDelete(JsonMap input) {
    final download = _deletePreviews.remove(input['previewId']);
    if (download == null || _download(download) == null) {
      throw const Failure(FailureCode.conflict,
          'Deletion preview is missing or belongs to another caller.');
    }
    final id = 'fake-delete-dl-$_deletions';
    _decisions[id] = Decision(
      prompt: '将删除下载的文件，无法恢复。要删除吗？',
      options: [
        DecisionOption(
            label: '删除',
            call: ActionCall('fake.consent',
                {'jobId': id, 'download': download, 'approve': true})),
        DecisionOption(
            label: '保留',
            call: ActionCall('fake.consent',
                {'jobId': id, 'download': download, 'approve': false})),
      ],
    );
    world._tasks[id] = _FakeTask(id, '等待你确认删除', const UiArtwork(), 0,
        type: 'disk_deletion')
      ..state = UiTaskState.paused;
    world._taskStream.add(world._taskList());
    return {'job': _job(id)};
  }

  String _addDownload(JsonMap input) {
    final source = input['source'] as String;
    if (failing.contains('download.add')) {
      throw const Failure(FailureCode.unavailable, 'Downloader is disabled.');
    }
    if (source.contains('bad')) {
      throw const Failure(FailureCode.invalidInput, 'Invalid torrent.');
    }
    final name = _torrentName(source);
    final id = 'fake-dl-new-${++_added}';
    world._tasks[id] = _FakeTask(id, name, const UiArtwork(), 0.01);
    final d = _FakeDownload(
        name,
        _FakeDownload.manifest(_preview.$2, 1180 << 20),
        folder: input['downloadDirectory'] as String? ??
            '$_home/Movies/NipaPlay',
        created: DateTime.now());
    final indices = (input['fileIndices'] as List?)?.cast<int>();
    if (indices != null) {
      d.selected
        ..clear()
        ..addAll(indices);
    }
    _downloads[id] = d;
    world._ticker ??=
        Timer.periodic(const Duration(seconds: 1), (_) => world._tick());
    world._taskStream.add(world._taskList());
    return id;
  }

  JsonMap _control(String id, String command) {
    final helper = world._helpers.where((h) => h.id == id).firstOrNull;
    if (helper != null && command != 'cancel') {
      return {
        'jobId': id,
        'command': command,
        'accepted': false,
        'controlSupported': false,
        'reason': 'codex_native_helper'
      };
    }
    switch (command) {
      case 'pause':
        world._tasks[id]?.state = UiTaskState.paused;
      case 'resume':
        world._tasks[id]?.state = UiTaskState.running;
      default:
        if (helper != null) helper.cancel();
        world._tasks.remove(id);
        _decisions.remove(id);
    }
    world._taskStream.add(world._taskList());
    return {
      'jobId': id,
      'command': command,
      'accepted': true,
      'controlSupported': true,
      'job': _job(id)
    };
  }

  /// Debug: a deletion waiting for the person in the background.
  void askToDelete() {
    const id = 'fake-delete-1';
    _decisions[id] = const Decision(
      prompt: '删除 3 个文件？',
      options: [
        DecisionOption(
            label: '删除',
            detail: '2.4 GB',
            call: ActionCall('fake.decide', {'jobId': id, 'choice': 'delete'})),
        DecisionOption(
            label: '保留',
            call: ActionCall('fake.decide', {'jobId': id, 'choice': 'keep'})),
      ],
    );
    world._tasks[id] = _FakeTask(id, '等待你确认删除', const UiArtwork(), 0,
        type: 'disk_deletion')
      ..state = UiTaskState.paused;
    world._taskStream.add(world._taskList());
  }

  List<JsonMap> _rows(JsonMap input) {
    final view = input['view'];
    final filter = (input['filter'] as Map?) ?? const {};
    bool matches(JsonMap row) => filter.entries.every((e) {
          final p = e.value as Map;
          final v = row[e.key];
          if (p.containsKey('eq')) return '$v' == '${p['eq']}';
          if (p.containsKey('in')) {
            return (p['in'] as List).map((x) => '$x').contains('$v');
          }
          return true;
        });
    if (view == 'history.entries') return _history;
    if (view == 'media.bindings') {
      final keys = world._meta.keys.toList();
      return [
        for (final (i, key) in keys.indexed) ...[
          {
            'entityId': 'fake:$key',
            'provider': 'dandanplay',
            'objectType': 'anime',
            'externalId': '${17000 + i}',
            'status': 'accepted'
          },
          if (key != 'sintel')
            {
              'entityId': 'fake:$key',
              'provider': 'bangumi',
              'objectType': 'subject',
              'externalId': '${400000 + i}',
              'status': 'accepted'
            },
        ]
      ].where(matches).toList();
    }
    if (view == 'mesh.devices') {
      return [
        for (final MapEntry(key: name, value: online) in world._online.entries)
          {
            'deviceId': 'device:$name',
            'name': name,
            'platform': 'macos',
            'online': online
          }
      ].where(matches).toList();
    }
    throw const Failure(FailureCode.notFound, 'Unknown view.');
  }

  String? _keyOf(String provider, int id) {
    final keys = world._meta.keys.toList();
    final i = id - (provider == 'bangumi' ? 400000 : 17000);
    return i >= 0 && i < keys.length ? keys[i] : null;
  }

  JsonMap _collection(String provider, int id) {
    final key = _keyOf(provider, id);
    final c = key == null ? null : _collections[key];
    if (provider == 'bangumi') {
      return {
        'provider': provider,
        'workId': id,
        'collection': c == null
            ? null
            : {
                'subject_id': id,
                'type': const ['wish', 'done', 'doing', 'onHold', 'dropped']
                        .indexOf(c.$1) +
                    1,
                'rate': c.$2 ?? 0,
              },
      };
    }
    final status = switch (c?.$1) {
      null => null,
      'done' => 'finished',
      'dropped' => 'abandoned',
      _ => 'favorited',
    };
    return {
      'provider': provider,
      'workId': id,
      'collection': status == null
          ? null
          : {'animeId': id, 'favoriteStatus': status},
      'rating': c?.$2 ?? 0,
    };
  }

  void _setCollection(String provider, JsonMap item) {
    final key = _keyOf(provider, item['workId'] as int);
    if (key == null) {
      throw const Failure(FailureCode.notFound, 'Unknown work.');
    }
    final had = _collections[key];
    var status = item['status'] as String? ?? had?.$1;
    if (provider == 'dandanplay' && item.containsKey('status')) {
      // 弹弹play's three; Bangumi's own wins where both are written.
      status = had?.$1 ??
          switch (status) {
            'finished' => 'done',
            'abandoned' => 'dropped',
            _ => 'doing',
          };
    }
    if (status == null) {
      throw const Failure(
          FailureCode.invalidInput, 'A new Bangumi collection requires status.');
    }
    _collections[key] = (status, item['rating'] as int? ?? had?.$2);
  }

  JsonMap _plan(List<String> kinds) {
    final entries = [
      for (final k in kinds)
        if ((_caches[k] ?? 0) > 0) {'kind': k, 'bytes': _caches[k]}
    ];
    return {
      'planId': kinds.join('+'),
      'entries': entries,
      'retained': [
        if (kinds.contains('nextDanmaku'))
          {'kind': 'nextDanmaku', 'bytes': 12 << 20, 'reason': 'unique_import'},
        if (kinds.contains('nextArtwork'))
          {
            'kind': 'nextArtwork',
            'bytes': 38 << 20,
            'reason': 'unique_or_source_unknown'
          },
      ],
      'reclaimableBytes':
          entries.fold<int>(0, (n, e) => n + (e['bytes'] as int)),
    };
  }

  JsonMap _syncStatus() => {
        'configuration': _sync,
        'enabled': _syncEnabled,
        'syncing': _syncing,
        'phase': _syncing ? 'uploading' : 'idle',
        'completedRunCount': 12,
        'lastSyncAt': _synced?.toIso8601String(),
        'lastError': _syncKey ? null : 'Unauthorized',
        'hasPassword': _syncKey,
      };

  Future<JsonMap> _runSync() async {
    if (!_syncEnabled) {
      throw const Failure(FailureCode.conflict, 'Sync is disabled.');
    }
    _syncing = true;
    Timer(const Duration(seconds: 3), () {
      _syncing = false;
      _synced = DateTime.now();
    });
    return {'jobId': 'fake-sync-${DateTime.now().millisecondsSinceEpoch}'};
  }

  JsonMap _rootsState() => {
        'roots': _roots,
        'scanning': world._tasks.entries.any((e) =>
            e.key.startsWith('fake-scan-') &&
            e.value.state == UiTaskState.running &&
            e.value.progress < 1),
        'progress': 0,
        'message': '',
        'totalFilesFound': 0,
        'failedFiles': [
          {'path': '/Volumes/NAS/动画/broken.mkv', 'reason': 'unreadable'}
        ],
      };

  // —— 片库多选 ——

  /// Debug: what the library's batch sheets meet. `refresh`: some
  /// refreshes cannot start, some fail later; `conflict`: the next change
  /// finds the matches changed (once); `bind` / `unbind`: changing fails.
  final batchFaults = <String>{};

  /// Works' matches as the batch sheets left them (null: let go of).
  /// Untouched, the unrecognised files have none and every other work one.
  final _matches = <String, JsonMap?>{};
  /// Each device's revision of its matches ('' here): a change on one
  /// device leaves the plans for another as they were.
  final _matchRevisions = <String, int>{};
  int _matchRevision(String? device) => _matchRevisions[device ?? ''] ?? 0;
  void _matchChanged(String? device) =>
      _matchRevisions[device ?? ''] = _matchRevision(device) + 1;
  final _refreshes = <String, (DateTime, bool)>{};

  /// Each device's own work IDs: the merged ID here, `<merged>@<device>`
  /// on another device.
  static String _merged(String ownId) => ownId.split('@').first;
  static String? _deviceOf(String ownId) =>
      ownId.contains('@') ? ownId.split('@').last : null;

  /// A file's own ID, `file:<own work>#<episode>`, and the work it is of.
  static String _fileOf(String ownWork, UiEpisode e) =>
      'file:$ownWork#${e.episodeId}';
  static String _ownWork(String id) =>
      id.startsWith('file:') ? id.substring(5).split('#').first : id;

  List<UiEpisode> _episodesOfKey(String key) => world.catalog.owns(key)
      ? world.catalog.episodes(key)
      : world._episodesOf(key);

  /// [workId]'s own ID on [device] (null: here), when that device has it.
  String? _ownOn(String workId, String? device) {
    final (from, name) =
        FakeWorld._elsewhere[workId.substring(5)] ?? (1 << 30, '');
    if (device == null) return from > 1 ? workId : null;
    return name == device ? '$workId@$device' : null;
  }

  /// Where a merged work is, as `media.management.targets` reports it.
  JsonMap _targets(String workId) {
    if (!workId.startsWith('fake:')) {
      return {
        'workId': workId,
        'targets': const [],
        'error':
            const Failure(FailureCode.notFound, 'Unknown merged work.').toJson(),
      };
    }
    final key = workId.substring(5);
    final episodes = _episodesOfKey(key);
    final (_, elsewhere) = FakeWorld._elsewhere[key] ?? (0, '');
    JsonMap target(String? device) {
      final online = device == null || world._online[device]!;
      return {
        'deviceId': device == null ? 'this-mac' : 'device:$device',
        'workId': device == null ? workId : '$workId@$device',
        'local': device == null,
        'online': online,
        'reason': online ? null : 'source_device_offline',
        'episodes': [
          for (final e in episodes)
            if (e.device?.name == device)
              {
                'episodeId':
                    device == null ? e.episodeId : '${e.episodeId}@$device',
                'mergedEpisodeId': e.episodeId,
                'fileIds': [
                  _fileOf(device == null ? workId : '$workId@$device', e)
                ],
              }
        ],
      };
    }

    return {
      'workId': workId,
      'targets': [
        if (_ownOn(workId, null) != null) target(null),
        if (elsewhere.isNotEmpty) target(elsewhere),
      ],
    };
  }

  JsonMap _animeRef(String workId) => {
        'provider': 'dandanplay',
        'objectType': 'anime',
        'externalId': '${17000 + _merged(workId).hashCode.abs() % 9000}',
        'scope': '',
      };

  JsonMap? _matchOf(String ownId) => _matches.containsKey(ownId)
      ? _matches[ownId]
      : ownId.startsWith('fake:raw:')
          ? null
          : _animeRef(ownId);

  /// The works matched to [ref] on every device (own IDs): the samples,
  /// and any the sheets changed.
  Iterable<String> _matchedTo(Map ref) => {
        for (final k in world._meta.keys) ...[
          if (_ownOn('fake:$k', null) case final id?) id,
          if (FakeWorld._elsewhere[k] case (_, final device))
            'fake:$k@$device',
        ],
        ..._matches.keys,
      }.where((id) => switch (_matchOf(id)) {
            final m? => m['provider'] == ref['provider'] &&
                m['objectType'] == ref['objectType'] &&
                m['externalId'] == ref['externalId'],
            null => false,
          });

  JsonMap _binding(String workId, JsonMap ref) => {
        'bindingId': 'fake-binding-${ref['externalId']}-$workId',
        'ref': ref,
        'relation': 'contains',
        'scope': {
          'order': 'provider',
          'season': null,
          'cour': null,
          'numbers': const [],
          'startMs': null,
          'endMs': null
        },
        'status': 'accepted',
        'source': 'explicit_binding',
        'boundBy': 'user',
        'revision': 1,
        'invocationId': null,
        'jobId': null,
        'createdAt': '2026-09-30T12:00:00.000Z',
      };

  /// A search's record of the sample [key] at [provider].
  JsonMap _refOf(String provider, String key) => switch (provider) {
        'dandanplay' => _animeRef('fake:$key'),
        'bangumi' => {
            'provider': 'bangumi',
            'objectType': 'subject',
            'externalId': '${400000 + key.hashCode.abs() % 90000}',
            'scope': ''
          },
        _ => {
            'provider': 'tmdb',
            'objectType': 'tv',
            'externalId': '${200000 + key.hashCode.abs() % 90000}',
            'scope': ''
          },
      };

  /// A provider's record of the sample [ref] is of, with its episodes
  /// (`media.metadata.get`). Bangumi knows only the first eight.
  JsonMap _catalogue(Map ref) {
    final provider = ref['provider'] as String;
    final key = world._meta.keys
        .where((k) => _refOf(provider, k)['externalId'] == ref['externalId'])
        .firstOrNull;
    if (key == null) {
      throw const Failure(FailureCode.notFound, 'Unknown external object.');
    }
    final count = math.min(world.sample(key).episodeCount ?? 12,
        provider == 'bangumi' ? 8 : 1 << 30);
    final id = ref['externalId'];
    final episodes = [
        for (var n = 1; n <= count; n++)
          {
            'ref': {
              'provider': provider,
              'objectType': 'episode',
              'externalId': '$id${'$n'.padLeft(4, '0')}',
              'scope': switch (provider) {
                'dandanplay' => 'anime/$id',
                'bangumi' => 'subject/$id',
                _ => 'tv/$id/season/1/episode/$n',
              },
            },
            'title': '第 $n 集',
            'kind': 'episode',
            'number': '$n',
            'season': 1,
            'episodeType': 'regular',
            'order': 'provider',
            'language': 'zh-CN',
            'fetchedAt': DateTime.now().toUtc().toIso8601String(),
            'episodes': const [],
          }
      ];
    return {
      ..._record(provider, key)..remove('workId'),
      // TMDB's episodes are within their seasons.
      'episodes': provider == 'tmdb'
          ? [
              {
                'ref': {
                  'provider': 'tmdb',
                  'objectType': 'season',
                  'externalId': '${id}01',
                  'scope': 'tv/$id/season/1',
                },
                'title': '第 1 季',
                'kind': 'season',
                'number': '1',
                'season': 1,
                'episodeType': 'regular',
                'order': 'provider',
                'language': 'zh-CN',
                'fetchedAt': DateTime.now().toUtc().toIso8601String(),
                'episodes': episodes,
              }
            ]
          : episodes,
    };
  }

  JsonMap _record(String provider, String key) {
    final work = world.sample(key);
    final ref = _refOf(provider, key);
    return {
      'ref': ref,
      'workId': switch (_matchedTo(ref).firstOrNull) {
        final id? => _merged(id),
        null => null,
      },
      'title': work.title,
      'kind': 'tv',
      'originalTitle': work.originalTitle,
      'overview': work.overview,
      'imageUrl': work.artwork.poster,
      'year': work.year,
      'number': null,
      'season': null,
      'episodeType': 'regular',
      'order': 'provider',
      'language': 'zh-CN',
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'episodes': const [],
    };
  }

  /// What binding or letting go of [request]'s entries touches, as
  /// `media.management.*_batch` previews it: each work with its release,
  /// episodes and files, and the works already matched to the refs.
  JsonMap _impact(JsonMap request) {
    final entries = (request['entries'] as List).cast<Map>();
    final device = _deviceOf(_ownWork(entries.first['entityId'] as String));
    final ids = <String>{
      for (final e in entries) ...[
        _ownWork(e['entityId'] as String),
        if (e['workRef'] case final Map ref)
          ..._matchedTo(ref).where((id) => _deviceOf(id) == device),
      ]
    };
    return {
      'entities': [for (final id in ids.toList()..sort()) ..._subtree(id)],
      'diskFilesDeleted': false,
      'progressChanged': false,
    };
  }

  List<JsonMap> _subtree(String workId) {
    final device = _deviceOf(workId);
    final key = _merged(workId).substring(5);
    final work = world.catalog.work(key);
    final episodes = _episodesOfKey(key);
    final release = '$workId:release';
    JsonMap row(String id, String kind, String? parent,
            {List<JsonMap> associations = const [],
            List<JsonMap> sources = const [],
            List<JsonMap> locations = const [],
            List<JsonMap> progress = const [],
            JsonMap attributes = const {}}) =>
        {
          'entity': {
            'id': id,
            'kind': kind,
            'parent_id': parent,
            'revision': _matchRevision(device),
            'attributes': attributes,
          },
          'associations': associations,
          'sources': sources,
          'locations': locations,
          'progress': progress,
        };
    final ref = _matchOf(workId);
    final rows = [
      row(workId, 'work', null, attributes: {
        'title': work.title
      }, sources: [
        if (ref != null)
          {
            'id': 'fake-binding-${ref['externalId']}-$workId',
            'entity_id': workId,
            'object_id': 'object:${ref['provider']}:${ref['externalId']}',
            'relation': 'contains',
            'scope': '{"order":"provider"}',
            'status': 'accepted',
            'source': 'explicit_binding',
            'bound_by': 'user',
            'revision': 1,
            'supersedes': null,
            'invocation_id': null,
            'job_id': null,
            'created_at': '2026-09-30T12:00:00.000Z',
            'provider': ref['provider'],
            'object_type': ref['objectType'],
            'external_id': ref['externalId'],
            'object_scope': ref['scope'],
          }
      ]),
      row(release, 'release', workId, attributes: {'title': work.title}),
    ];
    for (final e in episodes) {
      if (e.device?.name != device) continue;
      final episode = device == null ? e.episodeId : '${e.episodeId}@$device';
      final file = _fileOf(workId, e);
      final link = {
        'file_id': file,
        'episode_id': episode,
        'relation': 'primary',
        'ordinal': 0,
        'start_ms': null,
        'end_ms': null
      };
      rows.add(row(episode, 'episode', release,
          attributes: {'title': e.title, 'number': '${e.number}'},
          associations: [link]));
      final watched = e.progress ?? 0;
      rows.add(row(file, 'file', null, associations: [
        link
      ], locations: [
        {
          'id': 'location:$episode',
          'file_id': file,
          'source': 'local',
          'owner_device_id': device == null ? 'this-mac' : 'device:$device',
          'locator': '$_home/Movies/${work.title}/'
              '${'${e.number}'.padLeft(2, '0')}.mkv',
          'available': 1,
        }
      ], progress: [
        {
          'lastPosition': watched > 0 ? (watched * 1440000).round() : null,
          'duration': 1440000,
          'watchProgress': watched > 0 ? watched : null,
          'lastWatchTime': watched > 0 ? '2026-10-12T21:30:00.000Z' : null,
        }
      ]));
    }
    return rows;
  }

  /// Carries out a bind or unbind entry of a batch, as the identity
  /// primitives report it.
  JsonMap _associate(String op, int index, Map entry) {
    final id = entry['entityId'] as String;
    final work = _ownWork(id);
    final before = _matchOf(work);
    if (op == 'bind') {
      final ref = Map<String, Object?>.from(entry['workRef'] as Map);
      _matches[work] = ref;
      return {
        'index': index,
        'workId': work,
        'releaseId': '$work:release',
        'episodeIds': [
          if (id.startsWith('file:')) id.split('#').last,
        ],
        'fileId': id.startsWith('file:') ? id : null,
        'classicProjectionId': null,
        'bindingIds': [_binding(id, ref)['bindingId']],
        'classicProjection': const [],
      };
    }
    // Letting go of a file's match leaves the work's.
    if (id == work) _matches[id] = null;
    return {
      'index': index,
      'entityId': id,
      'bindingIds': (entry['bindingIds'] as List?) ??
          [if (before != null) _binding(id, before)['bindingId']],
      'classicProjectionId': null,
      'classicProjection': const [],
    };
  }

  String _startRefresh({required bool fails}) {
    final id = 'fake-refresh-${_refreshes.length + 1}';
    _refreshes[id] = (DateTime.now(), fails);
    return id;
  }

  /// A refresh's job: queued a moment, running a few seconds, then done
  /// (or failed, when the debug asks).
  JsonMap _refreshJob(String id) {
    final (at, fails) = _refreshes[id]!;
    final ms = DateTime.now().difference(at).inMilliseconds;
    final state = ms < 1200
        ? 'queued'
        : ms < 3500 + id.hashCode.abs() % 3000
            ? 'running'
            : fails
                ? 'failed'
                : 'succeeded';
    return {
      'jobId': id,
      'type': 'media.metadata.refresh',
      'title': '更新作品资料',
      'state': state,
      'progress': {'completed': state == 'succeeded' ? 1 : 0, 'total': 1},
      'createdAt': at.toUtc().toIso8601String(),
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'revision': 1,
      if (state == 'failed')
        'error': const Failure(
                FailureCode.unavailable, 'Provider did not answer.',
                retryable: true)
            .toJson(),
    };
  }

  // —— the Actions ——

  List<Action> _actions() {
    Action a(String id, FutureOr<Object> Function(JsonMap input) run) =>
        _FakeAction(id, (input) async {
          // A failed update check is a result with its error, not a failure.
          if (failing.contains(id) && id != 'app.update.check') {
            throw const Failure(FailureCode.unavailable, 'Scripted failure.');
          }
          final out = await run(input);
          return out;
        });
    Future<T> slow<T>(int ms, T Function() then) =>
        Future<T>.delayed(Duration(milliseconds: ms), then);
    JsonMap batch(JsonMap input, String one, String many,
        JsonMap Function(String) each) {
      if (!input.containsKey(many)) return each(input[one] as String);
      return {
        'results': [
          for (final (i, id) in (input[many] as List).cast<String>().indexed)
            () {
              try {
                return {'index': i, 'status': 'completed', ...each(id)};
              } on Failure catch (f) {
                return {'index': i, 'status': 'failed', 'error': f.toJson()};
              }
            }()
        ]
      };
    }

    return [
      // Background work.
      a('task.list', (input) {
        final type = input['type'];
        return {
          'jobs': [
            for (final id in _ids)
              if (type == null || _job(id)['type'] == type) _job(id)
          ]
        };
      }),
      a('task.get', (input) => {'job': _job(input['jobId'] as String)}),
      a('task.control', (input) => {
            'results': [
              for (final (i, e) in (input['entries'] as List).cast<Map>().indexed)
                {'index': i, ..._control('${e['jobId']}', '${e['command']}')}
            ]
          }),
      a('task.resources', (_) {
        int active(bool Function(String) of) => world._tasks.entries
            .where((e) => of(e.key) && e.value.state == UiTaskState.running)
            .length;
        return {
          'pools': [
            {
              'type': 'media.scan',
              'capacity': _capacity['scan'],
              'active': 0,
              'queued': 0
            },
            {
              'type': 'media.scan_classic',
              'capacity': 1,
              'active': active((id) => id.startsWith('fake-scan-')),
              'queued': 0
            },
            {
              'type': 'media.metadata.refresh',
              'capacity': _capacity['metadata'],
              'active': 2,
              'queued': 5
            },
            {
              'type': 'agent.helper',
              'capacity': _capacity['helper'],
              'active': world._helpers
                  .where((h) => h.state == UiTaskState.running)
                  .length,
              'queued': 0
            },
          ],
        };
      }),
      a('settings.set', (input) {
        final key = input['key'] as String;
        final kind = RegExp(r'^tasks\.(\w+)Concurrency$').firstMatch(key)?[1];
        final value = input['value'];
        if (kind == null || value is! int || value < 1) {
          throw const Failure(FailureCode.invalidInput, 'Invalid value.');
        }
        _capacity[kind] = value;
        return {'key': key, 'value': value};
      }),
      a('fake.decide', (input) {
        final id = input['jobId'] as String;
        _decisions.remove(id);
        world._tasks.remove(id);
        world._taskStream.add(world._taskList());
        return {'jobId': id, 'choice': input['choice']};
      }),
      // Downloads.
      a('download.read',
          (input) => batch(input, 'jobId', 'jobIds', (id) => _read(id))),
      a('download.preview',
          (input) => slow(900, () => _previewOf(input['source'] as String))),
      a('download.directories', (_) => {
            'defaultDirectory': '$_home/Movies/NipaPlay',
            'recentDirectories': ['/Volumes/NAS/下载', '$_home/Downloads'],
          }),
      a('download.add', (input) => slow(700, () {
            final id = _addDownload(input);
            return {'job': _job(id)};
          })),
      a('download.set_paused', (input) {
        final paused = input['paused'] as bool;
        return batch(input, 'jobId', 'jobIds', (id) {
          if (_download(id) == null) {
            throw const Failure(FailureCode.notFound, 'No such download.');
          }
          final t = world._tasks[id]!;
          if (t.state != UiTaskState.finished && t.state != UiTaskState.failed) {
            t.state = paused ? UiTaskState.paused : UiTaskState.running;
          }
          world._taskStream.add(world._taskList());
          return {'job': _job(id)};
        });
      }),
      a('download.select_files', (input) => slow(500, () {
            final id = input['jobId'] as String;
            final d = _download(id)!;
            d.selected
              ..clear()
              ..addAll((input['fileIndices'] as List).cast<int>());
            return _read(id);
          })),
      a('download.remove', (input) => slow(400, () {
            final id = input['jobId'] as String;
            final job = _job(id);
            world._tasks.remove(id);
            _downloads.remove(id);
            world._taskStream.add(world._taskList());
            return {'job': job};
          })),
      _FakeAction.outcome('download.delete', (input) async {
        await slow(400, () {});
        if (failing.contains('download.delete')) {
          throw const Failure(FailureCode.unavailable, 'Scripted failure.');
        }
        return _askDelete(input);
      }),
      a('download.delete.request',
          (input) => slow(400, () => _requestDelete(input))),
      // NipaPlay's own window, answered: the download and its files go, or
      // stay.
      a('fake.consent', (input) {
        final id = input['jobId'] as String;
        _decisions.remove(id);
        world._tasks.remove(id);
        if (input['approve'] == true) {
          final download = input['download'] as String;
          world._tasks.remove(download);
          _downloads.remove(download);
        }
        world._taskStream.add(world._taskList());
        return {'jobId': id};
      }),
      a('download.play', (input) {
        debugPrint('[NextUi dev] play ${input['jobId']} #${input['fileIndex']}');
        return {'opened': true};
      }),
      a('download.limits.get', (_) => _limits(false)),
      a('download.limits.set', (input) {
        for (final v in input.values.cast<int>()) {
          if (v != 0 && v < 16384) {
            throw const Failure(FailureCode.invalidInput,
                'Use 0 for unlimited, or 16384..4294967295 bytes/second.');
          }
        }
        if (limitsMode == 'on') {
          _down = input['downloadBytesPerSecond'] as int? ?? _down;
          _up = input['uploadBytesPerSecond'] as int? ?? _up;
        }
        return _limits(true);
      }),
      // History.
      a('state.query', (input) {
        var rows = _rows(input);
        final limit = (input['limit'] as int?) ?? 50;
        final cursor = input['cursor'] as String?;
        final List<JsonMap> page;
        final String? next;
        if (input['view'] == 'history.entries') {
          // As the real view: latest first, and the cursor keeps the last
          // row's place in that order, so forgotten rows shift nothing.
          int order(Map a, Map b) {
            final when =
                '${b['lastWatchedAt']}'.compareTo('${a['lastWatchedAt']}');
            return when != 0
                ? when
                : '${a['entryId']}'.compareTo('${b['entryId']}');
          }

          rows = [...rows]..sort(order);
          if (cursor != null) {
            final anchor =
                jsonDecode(utf8.decode(base64Url.decode(cursor))) as List;
            final last = {'lastWatchedAt': anchor[0], 'entryId': anchor[1]};
            rows = [
              for (final r in rows)
                if (order(last, r) < 0) r
            ];
          }
          page = rows.take(limit).toList();
          next = rows.length > page.length
              ? base64Url.encode(utf8.encode(jsonEncode(
                  [page.last['lastWatchedAt'], page.last['entryId']])))
              : null;
        } else {
          final offset = int.tryParse('${cursor ?? 0}') ?? 0;
          page = rows.skip(offset).take(limit).toList();
          next = offset + page.length < rows.length
              ? '${offset + page.length}'
              : null;
        }
        return {
          'schemaVersion': 1,
          'snapshotId': null,
          'observedAt': DateTime.now().toUtc().toIso8601String(),
          'consistency': 'live',
          'sources': {},
          'rows': page,
          'nextCursor': next,
          'truncated': next != null,
          'warnings': [],
        };
      }),
      a('history.remove', (input) {
        if (!['paths', 'entryIds', 'animeIds'].any(input.containsKey)) {
          throw const Failure(
              FailureCode.invalidInput, 'Supply entryIds, paths or animeIds.');
        }
        final paths = ((input['paths'] as List?) ?? const []).toSet();
        final entryIds = ((input['entryIds'] as List?) ?? const []).toSet();
        final ids = ((input['animeIds'] as List?) ?? const []).toSet();
        final removed = [
          for (final e in _history)
            if (paths.contains(e['locator']) ||
                entryIds.contains(e['entryId']) ||
                ids.contains(e['animeId']))
              e
        ];
        _history.removeWhere(removed.contains);
        return {
          'removedPaths': [
            for (final e in removed)
              if (paths.contains(e['locator'])) e['locator']
          ],
          'removedEntryIds': [for (final e in removed) e['entryId']],
          'removedCount': removed.length,
        };
      }),
      _FakeAction.outcome('playback.open', (input) async {
        final path = input['path'] as String;
        if (path == _history.first['locator']) {
          return NeedsDecision(Decision(prompt: '播放哪一个？', options: [
            DecisionOption(
                label: '1080p',
                detail: '这台电脑',
                call: ActionCall('playback.open', {'path': '$path#local'})),
            DecisionOption(
                label: '2160p',
                detail: 'NAS',
                call: ActionCall('playback.open', {'path': '$path#nas'})),
          ]));
        }
        debugPrint('[NextUi dev] play $path');
        return Completed(_FakeJson({'path': path, 'state': 'playing'}));
      }),
      // Collections.
      a('accounts.status', (_) async => {
            'accounts': [
              for (final e in (await accounts()).entries)
                {'provider': e.key, 'loggedIn': e.value}
            ]
          }),
      a('accounts.collections.get', (input) => slow(350, () {
            final provider = input['provider'] as String;
            return {
              'results': [
                for (final (i, id) in (input['workIds'] as List).cast<int>().indexed)
                  {
                    'index': i,
                    'status': 'completed',
                    'result': _collection(provider, id)
                  }
              ]
            };
          })),
      a('accounts.collections.update', (input) => slow(450, () {
            final provider = input['provider'] as String;
            return {
              'results': [
                for (final (i, item) in (input['items'] as List).cast<Map>().indexed)
                  () {
                    try {
                      _setCollection(provider, Map<String, Object?>.from(item));
                      return {
                        'index': i,
                        'status': 'completed',
                        'result': {'acknowledged': true}
                      };
                    } on Failure catch (f) {
                      return {'index': i, 'status': 'failed', 'error': f.toJson()};
                    }
                  }()
              ]
            };
          })),
      a('accounts.collections.list', (input) async {
        final provider = input['provider'] as String;
        if ((await accounts())[provider] != true) {
          throw const Failure(
              FailureCode.unavailable, 'Log in to this account first.');
        }
        final bangumi = provider == 'bangumi';
        final statuses =
            ((input['statuses'] as List?) ?? const []).cast<String>();
        final valid = bangumi
            ? const ['wish', 'done', 'doing', 'onHold', 'dropped']
            : const ['favorited', 'finished', 'abandoned'];
        if (statuses.any((s) => !valid.contains(s))) {
          throw const Failure(FailureCode.invalidInput,
              'Use statuses belonging to this provider.');
        }
        final limit = input['limit'] as int? ?? 100;
        var position = int.parse(input['cursor'] as String? ?? '0');
        final keys = world._meta.keys.toList();
        final all = [
          for (final e in _collections.entries)
            {
              'workId': (bangumi ? 400000 : 17000) + keys.indexOf(e.key),
              'status': bangumi
                  ? e.value.$1
                  : switch (e.value.$1) {
                      'done' => 'finished',
                      'dropped' => 'abandoned',
                      _ => 'favorited',
                    },
              'rating': bangumi ? e.value.$2 ?? 0 : e.value.$2,
            }
        ];
        bool accepts(Map item) =>
            statuses.isEmpty || statuses.contains(item['status']);
        final List<JsonMap> items;
        final bool more;
        if (bangumi) {
          // The account's own pages, filtered after: short here, so a
          // page left empty by the filter still goes on.
          final rows = all.skip(position).take(math.min(limit, 3)).toList();
          items = rows.where(accepts).toList();
          position += rows.length;
          more = position < all.length;
        } else {
          final rows = [
            for (final item in all)
              if ((item['workId'] as int) > position && accepts(item)) item
          ]..sort((a, b) => (a['workId'] as int).compareTo(b['workId'] as int));
          items = rows.take(limit).toList();
          if (items.isNotEmpty) position = items.last['workId'] as int;
          more = rows.length > items.length;
        }
        return {'items': items, 'nextCursor': more ? '$position' : null};
      }),
      // Space, caches, updates.
      a('storage.status', (_) => {
            'directories': [
              {
                'role': 'app',
                'path': '$_home/Library/Application Support/NipaPlay',
                'bytes': (3200 << 20) +
                    _caches.values.fold<int>(0, (n, b) => n + b)
              },
              {
                'role': 'downloads',
                'path': '$_home/Movies/NipaPlay',
                'bytes': 48 << 30
              },
            ],
            'volumes': [
              {'path': _home, 'availableBytes': 212 << 30, 'totalBytes': 994 << 30}
            ],
          }),
      a('cache.plan', (input) =>
          _plan((input['kinds'] as List? ?? _caches.keys.toList()).cast<String>())),
      a('cache.prune', (input) => slow(900, () {
            final kinds = (input['planId'] as String).split('+');
            var removed = 0;
            for (final k in kinds) {
              removed += _caches[k] ?? 0;
              _caches[k] = 0;
            }
            return {'planId': input['planId'], 'removedBytes': removed};
          })),
      a('app.update.check', (_) => slow(900, () {
            _update = _FakeUpdate(
                checked: true, failed: failing.contains('app.update.check'));
            return _update.json;
          })),
      a('app.update.status', (_) => {
            'checking': false,
            'checked': _update.checked,
            'result': _update.checked ? _update.json : null
          }),
      a('app.update.open', (_) => {'opened': true}),
      // Plugins.
      a('plugins.list', (_) => {'plugins': _plugins.values.toList()}),
      a('plugins.market', (input) => slow(input['refresh'] == true ? 900 : 0, () => {
            'plugins': _market,
            'updates': {
              for (final p in _plugins.values)
                p['id']: _market
                    .where((m) => m['id'] == p['id'] && m['version'] != p['version'])
                    .map((m) => m['version'])
                    .firstOrNull
            },
          })),
      a('plugins.install', (input) => slow(800, () {
            final remote = input['remoteId'] as String?;
            final m = _market.where((m) => m['id'] == remote).firstOrNull;
            final id = m?['id'] ?? 'local-plugin';
            _plugins[id] = {
              ...?_plugins[id],
              'id': id,
              'name': m?['name'] ?? '本地插件',
              'version': m?['version'] ?? '1.0.0',
              'description': m?['description'] ?? '',
              'builtin': false,
              'enabled': true,
              'loaded': true,
              'error': null,
            };
            return _plugins[id]!;
          })),
      a('plugins.set_enabled', (input) {
        final p = _plugins[input['id']]!;
        final on = input['enabled'] as bool;
        p['enabled'] = on;
        p['loaded'] = on && p['error'] == null;
        return p;
      }),
      a('plugins.delete', (input) {
        final id = input['id'] as String;
        if (_plugins[id]?['builtin'] == true) {
          throw const Failure(
              FailureCode.invalidInput, 'Builtin plugins cannot be deleted.');
        }
        _plugins.remove(id);
        return {'id': id, 'deleted': true};
      }),
      // A plugin's own actions: one answers with text, one asks first, one
      // fails.
      _FakeAction.outcome('plugins.invoke', (input) async {
        final id = input['id'] as String;
        final actionId = input['actionId'] as String;
        if (failing.contains('plugins.invoke')) {
          throw const Failure(FailureCode.unavailable, 'Scripted failure.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
        Completed<_FakeJson> answer(JsonMap? result) => Completed(_FakeJson(
            {'id': id, 'actionId': actionId, 'result': result}));
        return switch (actionId) {
          'export' => answer({
              'type': 'text',
              'title': '屏蔽词',
              'content': '剧透\n前方高能\n空降指挥部',
            }),
          'login' => answer({'type': 'text', 'title': '已登录', 'content': ''}),
          'clear' => NeedsDecision(Decision(prompt: '清空 B 站弹幕缓存？', options: [
              DecisionOption(
                  label: '清空',
                  detail: '86 MB',
                  call: ActionCall('plugins.invoke',
                      {'id': id, 'actionId': 'clear-confirmed'})),
            ])),
          'clear-confirmed' => answer(null),
          'refresh' =>
            throw const Failure(FailureCode.unavailable, 'Cookie expired.'),
          _ => throw const Failure(
              FailureCode.notFound, 'Plugin action not found.'),
        };
      }),
      // Sync.
      a('sync.status', (_) => _syncStatus()),
      a('sync.configure', (input) {
        if (input.containsKey('url') && input['url'] != _sync['url'] ||
            input.containsKey('username') &&
                input['username'] != _sync['username']) {
          _syncKey = false;
        }
        _sync = {..._sync, ...input};
        return {'configuration': _sync};
      }),
      a('sync.login', (_) => slow(600, () {
            _syncKey = true;
            return {'jobId': 'fake-sync-login'};
          })),
      a('sync.enable', (input) {
        _syncEnabled = input['enabled'] as bool;
        if (_syncEnabled) unawaited(_runSync());
        return {'jobId': 'fake-sync-enable'};
      }),
      a('sync.test', (_) => slow(700, () => {'connected': _syncKey})),
      a('sync.run', (_) => _runSync()),
      // Folders and shares.
      a('media.library.roots.list', (_) => _rootsState()),
      a('media.library.roots.add', (input) {
        final paths = (input['paths'] as List?)?.cast<String>() ??
            ['$_home/Movies/电影'];
        for (final p in paths) {
          if (!_roots.contains(p)) _roots.add(p);
        }
        return {'selected': paths, ..._rootsState()};
      }),
      a('media.library.roots.remove', (input) {
        final paths = (input['paths'] as List).cast<String>();
        _roots.removeWhere(paths.contains);
        return {'removed': paths, ..._rootsState()};
      }),
      a('media.library.scan_classic', (input) {
        final id = 'fake-scan-${++_scans}';
        world._tasks[id] = _FakeTask(id, '整理片库', const UiArtwork(), 0.05,
            type: 'media.scan_classic');
        world._ticker ??=
            Timer.periodic(const Duration(seconds: 1), (_) => world._tick());
        world._taskStream.add(world._taskList());
        return {'jobId': id, 'job': _job(id)};
      }),
      a('media.sources.discover', (_) => slow(1500, () => {
            'candidates': [
              {
                'address': 'http://192.168.1.20:1180',
                'kind': 'nipaplay_shared',
                'name': '客厅的 Mac mini',
                'discovery': 'udp_unverified'
              }
            ],
            'observedAt': DateTime.now().toUtc().toIso8601String(),
          })),
      // The library's batches: where a work is and what it is on each
      // device, searching a provider, refreshing and changing matches
      // (preview, then the plan); another device's part through
      // mesh.invoke, against the same world.
      a('media.management.targets', (input) => {
            'entries': [
              for (final id in (input['workIds'] as List).cast<String>())
                _targets(id)
            ]
          }),
      a('media.files.list', (input) {
        final own = input['workId'] as String;
        final device = _deviceOf(own);
        final key = _merged(own).substring(5);
        final work = world.catalog.work(key);
        final ref = _matchOf(own);
        final files = [
          for (final e in _episodesOfKey(key))
            if (e.device?.name == device)
              {
                'fileId': _fileOf(own, e),
                'path': '$_home/Movies/${work.title}/'
                    '${'${e.number}'.padLeft(2, '0')}.mkv',
                'size': 1400000000 + e.number * 7340032,
                'durationMs': 1440000,
                'headMd5': '${e.episodeId.hashCode.abs()}'.padLeft(32, '0'),
                'modifiedAt': '2026-09-30T12:00:00.000Z',
                'bindings': [
                  if (ref != null)
                    {
                      'bindingId': 'fake-file-binding-${e.episodeId}@$own',
                      'ref': {
                        'provider': ref['provider'],
                        'objectType': 'episode',
                        'externalId':
                            '${ref['externalId']}${'${e.number}'.padLeft(4, '0')}',
                        'scope': 'anime/${ref['externalId']}',
                      },
                      'relation': 'exact',
                      'scope': '{"order":"provider"}',
                      'boundBy': 'user',
                      'source': 'explicit_binding',
                    }
                ],
                'episodes': [
                  {
                    'episodeId':
                        device == null ? e.episodeId : '${e.episodeId}@$device',
                    'relation': 'primary',
                    'ordinal': 0,
                    'startMs': null,
                    'endMs': null,
                  }
                ],
              }
        ];
        return {'files': files, 'total': files.length};
      }),
      a('media.metadata.get',
          (input) => slow(400, () => {'record': _catalogue(input['ref'] as Map)})),
      _FakeAction.outcome('mesh.invoke', (input) async {
        final device = (input['deviceId'] as String).substring(7);
        if (world._online[device] != true) {
          return const Failed(
              Failure(FailureCode.unavailable, 'Mesh device is unreachable.'));
        }
        return switch (await harness.invokeJson(
            input['action'] as String,
            Map<String, Object?>.from(input['input'] as Map),
            Invocation(origin: 'mesh'))) {
          Completed(:final value) => Completed(_FakeJson(value.toJson())),
          Failed(:final failure) => Failed(failure),
          NeedsDecision(:final decision) => NeedsDecision(decision),
        };
      }),
      a('media.library.refresh', (_) {
        world._changes.add(null);
        return {'works': world._meta.length};
      }),
      a('media.identity.get', (input) {
        final id = input['entityId'] as String;
        if (!id.startsWith('fake:')) {
          throw Failure(FailureCode.notFound, 'Media entity $id not found.');
        }
        return {
          'identity': {
            'id': id,
            'kind': 'work',
            'parentId': null,
            'revision': _matchRevision(_deviceOf(id)),
            'bindingRevision': _matchRevision(_deviceOf(id)),
            'metadata': const [],
            'bindings': [
              if (_matchOf(id) case final ref?) _binding(id, ref)
            ],
            'locations': const [],
            'episodes': const [],
            'evidence': const [],
            'classicObservations': const [],
            'conflicts': const [],
            'legacyEvidence': const [],
          }
        };
      }),
      a('media.metadata.search', (input) => slow(450, () {
            final provider = input['provider'] as String;
            final query = (input['query'] as String).replaceAll(' ', '');
            if (RegExp(r'^(VID_|录屏)').hasMatch(query)) {
              return {'results': const []};
            }
            final keys = world._meta.keys.toList();
            final like = [
              for (final k in keys)
                if (query.contains(world.sample(k).title.replaceAll(' ', '')) ||
                    world.sample(k).title.contains(query))
                  k
            ];
            final near = [
              for (var i = 0; i < 3; i++)
                keys[(query.hashCode.abs() + i * 5) % keys.length]
            ];
            return {
              'results': [
                for (final k in {...like, ...near}.take(5))
                  _record(provider, k)
              ]
            };
          })),
      a('media.metadata.refresh_batch', (input) {
        final entries = (input['entries'] as List).cast<Map>();
        if (entries.isEmpty || entries.length > 100) {
          throw const Failure(
              FailureCode.invalidInput, 'Batch must contain 1 to 100 entries.');
        }
        final faulty = batchFaults.contains('refresh');
        return {
          'atomic': false,
          'entries': [
            for (var i = 0; i < entries.length; i++)
              if (faulty && i % 3 == 1)
                {
                  'index': i,
                  'status': 'failed',
                  'error': const Failure(
                          FailureCode.unavailable, 'dandanplay: rate limited.',
                          retryable: true)
                      .toJson(),
                }
              else
                {
                  'index': i,
                  'status': 'completed',
                  'result': {
                    'job': _refreshJob(
                        _startRefresh(fails: faulty && i % 3 == 2))
                  },
                }
          ],
        };
      }),
      for (final op in ['bind', 'unbind'])
        a('media.management.${op}_batch', (input) => slow(700, () {
              final request = {...input}..remove('expectedPlan');
              final entries = (request['entries'] as List).cast<Map>();
              final device =
                  _deviceOf(_ownWork(entries.first['entityId'] as String));
              String plan() => 'association-plan-${_matchRevision(device)}-'
                  '${jsonEncode(request).hashCode}';
              if (input['expectedPlan'] == null) {
                return {'preview': _impact(request), 'expectedPlan': plan()};
              }
              if (batchFaults.remove('conflict')) _matchChanged(device);
              if (input['expectedPlan'] != plan()) {
                throw const Failure(FailureCode.conflict,
                    'Association preview is stale; preview again.');
              }
              if (batchFaults.contains(op)) {
                throw const Failure(
                    FailureCode.unavailable, 'Scripted failure.');
              }
              _matchChanged(device);
              return {
                'entries': [
                  for (final (i, e) in entries.indexed) _associate(op, i, e)
                ]
              };
            })),
    ];
  }

  JsonMap _limits(bool set) => switch (limitsMode) {
        'unsupported' => {
            'supported': false,
            'applied': false,
            'reason': 'backend_has_no_bandwidth_control'
          },
        'stopped' => {
            'supported': true,
            'sessionInitialized': false,
            'applied': false,
            'reason': 'session_not_initialized',
            'actual': null
          },
        _ => {
            'supported': true,
            'sessionInitialized': true,
            'applied': set,
            'actual': {
              'downloadBytesPerSecond': _down,
              'uploadBytesPerSecond': _up
            }
          },
      };
}

final class _FakeUpdate {
  const _FakeUpdate({this.checked = false, this.failed = false});
  final bool checked;
  final bool failed;

  JsonMap get json => {
        'currentVersion': '1.9.3',
        'latestVersion': failed ? null : '1.9.4',
        'hasUpdate': failed ? null : true,
        'releaseName': 'NipaPlay 1.9.4',
        'publicReleaseUrl': failed
            ? null
            : 'https://github.com/AimesSoft/NipaPlay-Reload/releases/tag/v1.9.4',
        'checkedAt': DateTime.now().toUtc().toIso8601String(),
        'error': failed
            ? {'code': 'update_check_failed', 'retryable': true}
            : null,
      };
}

final class _FakeDownload {
  _FakeDownload(this.name, this.files,
      {this.error, required this.folder, required this.created})
      : selected = {
          for (final (i, f) in files.indexed)
            if (f.$3) i
        };

  factory _FakeDownload.of(FakeWorld world, String key, String name,
          {String? error, required DateTime created}) =>
      _FakeDownload(
          name, manifest(world.sample(key).episodeCount ?? 12, 1240 << 20),
          error: error, folder: '/Users/hikari/Movies/NipaPlay', created: created);

  final String name;
  final List<(String, int, bool)> files;
  final Set<int> selected;
  final String? error;
  final String folder;
  final DateTime created;

  /// [count] episodes of about [size] bytes, with the usual extras.
  static List<(String, int, bool)> manifest(int count, int size) => [
        for (var i = 1; i <= math.min(count, 24); i++)
          (
            '${i.toString().padLeft(2, '0')} [1080p].mkv',
            size + (i * 7919 % 97) * (1 << 20),
            true
          ),
        ('SPs/NCOP [1080p].mkv', 182 << 20, true),
        ('SPs/NCED [1080p].mkv', 176 << 20, true),
        ('Fonts.7z', 23 << 20, false),
        ('Scans/BD Booklet.zip', 312 << 20, false),
      ];
}

final class _FakeJson implements JsonEncodable {
  const _FakeJson(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _FakeAction extends Action<_FakeJson, _FakeJson> {
  _FakeAction(String id, Future<Object> Function(JsonMap) run)
      : this.outcome(id, (input) async {
          final out = await run(input);
          return Completed(_FakeJson(Map<String, Object?>.from(out as Map)));
        });
  _FakeAction.outcome(this.id, this.execute);
  final String id;
  final Future<Outcome<_FakeJson>> Function(JsonMap) execute;

  @override
  ActionSpec get spec => ActionSpec(
        id: id,
        title: id,
        description: 'Scripted.',
        effect: Effect.write,
        input: const ObjectSchema({}, additionalProperties: true),
        output: const ObjectSchema({}, additionalProperties: true),
      );

  @override
  _FakeJson decodeInput(JsonMap json) => _FakeJson(json);

  @override
  Future<Outcome<_FakeJson>> run(_FakeJson input, Invocation invocation) async {
    try {
      return await execute(input.value);
    } on Failure catch (f) {
      return Failed(f);
    }
  }
}

final class _FakeCapability implements Capability {
  _FakeCapability(this.actions);
  @override
  final List<Action> actions;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/store.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../state/query.dart';
import '../state/views.dart';
import '../settings/registry.dart';
import 'artwork.dart';
import 'airing.dart';
import 'heat.dart';
import '../subtitles/library.dart';
import 'ui_data.dart';

/// Application-owned projections. Stored presentations contain no task state.
final class UiDataService implements NextUiData {
  UiDataService(this.media, this.engine, this.state, this.sources,
      Directory root, CredentialVault vault)
      : mediaRoot = root,
        artwork = ArtworkCache(media, root, vault),
        heat = EpisodeHeat(DanmakuStore(media.store));
  final MediaService media;
  final TaskEngine engine;
  final StateCapability state;
  final StateSources sources;
  final ArtworkCache artwork;
  final EpisodeHeat heat;
  SubtitleLibrary? subtitles;
  Database get db => media.store.database;
  static const _openingKey = 'preference:hero-opening-seconds';
  Future<int> _openingSeconds() async {
    final rows = await db.query('ui_cache', where: 'id=?', whereArgs: [_openingKey]);
    return rows.isEmpty ? 180 : jsonDecode(rows.single['payload'] as String) as int;
  }
  SettingEntry get openingSetting => SettingEntry(
      key: 'next.heroOpeningSeconds', title: '开头弹幕时长',
      description: '从每集开头多少秒里挑选首页弹幕。',
      schema: const IntegerSchema(minimum: 30, maximum: 300), defaultValue: 180,
      storageKey: _openingKey, storageKind: 'sqlite',
      reader: 'UiDataService', writer: 'UiDataService',
      read: _openingSeconds, decodeStorage: (value) => value ?? 180,
      write: (value) async {
        await db.insert('ui_cache', {'id': _openingKey, 'fingerprint': 'preference', 'payload': jsonEncode(value)}, conflictAlgorithm: ConflictAlgorithm.replace);
        _changed();
      });
  final _changes = StreamController<void>.broadcast();
  final _tasks = StreamController<List<UiTask>>.broadcast();
  StreamSubscription<Job>? _jobs;
  Timer? _timer;
  String? _observed;
  Future<void> _polling = Future.value(), _publishing = Future.value();
  bool _closed = false;
  @override
  Stream<void> get changes => _changes.stream;

  Future<void> start() async {
    _observed = await _fingerprint();
    _jobs = engine.changes.listen((_) {
      _changed();
      if (!_tasks.hasListener) {
        return;
      }
      _publishing = _publishing.then((_) async {
        final tasks = await _taskList();
        if (!_closed) _tasks.add(tasks);
      });
      unawaited(_publishing.then<void>((_) {},
          onError: (Object e, StackTrace s) =>
              Zone.current.handleUncaughtError(e, s)));
    });
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _polling = _polling.then((_) async {
        final fingerprint = await _fingerprint();
        if (fingerprint != _observed) {
          _observed = fingerprint;
          _changed();
        }
      });
      unawaited(_polling.then<void>((_) {},
          onError: (Object e, StackTrace s) =>
              Zone.current.handleUncaughtError(e, s)));
    });
  }

  Future<String> _fingerprint() async => jsonEncode([
        await db.rawQuery('SELECT total_changes() AS total'),
        await db.rawQuery('PRAGMA data_version'),
        sources.history?.call(),
        sources.continueWatching?.call(),
        DateTime.now().toIso8601String().substring(0, 10),
        await sources.calendar?.call()
      ]);
  void _changed() {
    if (!_closed) _changes.add(null);
  }

  @override
  Stream<List<UiTask>> tasks() => Stream.multi((controller) {
        final sub = _tasks.stream.listen(controller.add,
            onError: controller.addError, onDone: controller.close);
        unawaited(
            _taskList().then(controller.add, onError: controller.addError));
        controller.onCancel = sub.cancel;
      }, isBroadcast: true);

  Future<List<JsonMap>> _view(String name) async {
    final view = state.views[name]!;
    return view.readAll != null
        ? (await view.readAll!()).rows
        : view.read(0, 1 << 30);
  }

  @override
  Future<UiWork?> work(String workId) async {
    final rows = await db.query('media_entities',
        where: "id=? AND kind='work'", whereArgs: [workId]);
    if (rows.isEmpty) return null;
    final art = await artwork.load(workId);
    final metadata = await media.store.mergedMetadata(workId);
    final fields = metadata['fields'] as JsonMap;
    final attrs = decodeMediaJson(rows.single['attributes']);
    final episodes = await this.episodes(workId);
    final next = episodes
            .where((e) =>
                e.playable &&
                e.progress != null &&
                e.progress! > 0 &&
                e.progress! < 1)
            .firstOrNull ??
        episodes
            .where((e) => e.playable && (e.progress ?? 0) < 1)
            .firstOrNull ??
        episodes.where((e) => (e.progress ?? 0) < 1).firstOrNull;
    return UiWork(
        workId: workId,
        title: _display(fields['title'] ?? attrs['title']) ?? '未命名作品',
        originalTitle: _display(fields['originalTitle']),
        year: fields['year'] as int?,
        genres: [
          for (final g in fields['genres'] as List? ?? [])
            if (_display(g) != null) _display(g)!
        ],
        episodeCount: (fields['episodeCount'] as num?)?.toInt() ??
            (episodes.isEmpty ? null : episodes.length),
        studio: _display(fields['studio']),
        overview: _display(fields['overview']),
        ratings: [
          for (final r in (metadata['ratings'] as List).cast<Map>())
            UiRating(_ratingSource(r['source'] as String),
                (r['value'] as num).toDouble())
        ],
        artwork: uiArtwork(art),
        next: next,
        danmaku: await heat.comments([for (final e in episodes) (e.episodeId, e.runtime?.inMilliseconds)],
            openingWindow: Duration(seconds: await _openingSeconds())));
  }

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async {
    final rows = await db.rawQuery(
        "SELECT e.*,r.attributes AS release_attributes FROM media_entities e JOIN media_entities r ON r.id=e.parent_id WHERE e.kind='episode' AND r.parent_id=?",
        [workId]);
    final files = await _view('library.files');
    final result = <UiEpisode>[];
    for (final row in rows) {
      final attrs = decodeMediaJson(row['attributes']),
          release = decodeMediaJson(row['release_attributes']);
      final s = attrs['season'] as int? ?? release['season'] as int?;
      if (season != null && s != season) continue;
      final id = row['id'] as String;
      final art = await artwork.load(id);
      final fields =
          (await media.store.mergedMetadata(id))['fields'] as JsonMap;
      final locations = files.where((f) => f['episodeId'] == id).toList();
      int? duration = (fields['runtimeMs'] as num?)?.toInt();
      double? progress;
      var playable = false;
      for (final f in locations) {
        final fileAttrs = decodeMediaJson(f['attributes']);
        final p = f['progress'] as Map?;
        final start = f['startMs'] as int? ?? 0, end = f['endMs'] as int?;
        final allLinks = files
            .where((other) => other['fileId'] == f['fileId'])
            .map((f) => f['episodeId'])
            .toSet();
        final timed = allLinks.length <= 1 || end != null;
        if (timed) {
          duration ??= end != null
              ? end - start
              : (fileAttrs['durationMs'] as num?)?.toInt() ??
                  (p?['durationMs'] as num?)?.toInt();
          if (p != null) {
            final d =
                end != null ? end - start : (p['durationMs'] as num?)?.toInt();
            final position = (p['positionMs'] as num?)?.toDouble();
            final value = (p['progress'] as num?) == 1
                ? 1.0
                : d != null && d > 0 && position != null
                    ? ((position - start) / d).clamp(0.0, 1.0)
                    : (p['progress'] as num?)?.toDouble().clamp(0.0, 1.0);
            if (value != null && (progress == null || value > progress)) {
              progress = value;
            }
          }
        }
        if (f['available'] == true && f['locator'] is String) {
          playable |= f['source'] != 'local' ||
              await File(f['locator'] as String).exists();
        }
      }
      result.add(UiEpisode(
          episodeId: id,
          workId: workId,
          number: (num.tryParse(attrs['number'] as String? ?? '') ??
              int.tryParse(RegExp(r'第\s*(\d+)\s*[集话話]').firstMatch(
                  (fields['title'] ?? attrs['title']) as String? ?? '')?.group(1) ?? '') ?? 0).toInt(),
          season: s,
          title: _display(fields['title'] ?? attrs['title']),
          runtime: duration == null ? null : Duration(milliseconds: duration),
          still: art['still'] as String?,
          progress: progress,
          heat: await heat.load(id, duration),
          playable: playable));
    }
    result.sort((a, b) => (a.season ?? 0).compareTo(b.season ?? 0) != 0
        ? (a.season ?? 0).compareTo(b.season ?? 0)
        : a.number.compareTo(b.number));
    return result;
  }

  Future<List<UiTask>> _taskList() async =>
      [for (final job in await engine.list()) await _task(job)];
  Future<UiTask> _task(Job job) async {
    final workId = await _jobWork(job);
    final title = workId == null
        ? null
        : (await media.store.mergedMetadata(workId))['fields'] as Map;
    final art = workId == null ? null : await artwork.cached(workId);
    final name = _display(title?['title']);
    return UiTask(
        taskId: job.jobId,
        title: job.type == 'agent.helper' ? job.title :
            job.state == JobState.waitingUser ? '等待你确认删除' :
            '${_taskVerb(job.type)}${name == null ? '' : '《$name》'}',
        state: switch (job.state) {
          JobState.queued || JobState.waitingRetry => UiTaskState.queued,
          JobState.paused ||
          JobState.waitingUser ||
          JobState.needsDecision ||
          JobState.interrupted =>
            UiTaskState.paused,
          JobState.succeeded => UiTaskState.finished,
          JobState.failed || JobState.cancelled => UiTaskState.failed,
          _ => UiTaskState.running,
        },
        artwork: art == null ? null : uiArtwork(art),
        kind: job.type == 'agent.helper' ? UiTaskKind.helper : UiTaskKind.background,
        startedAt: job.details['startedAt'] == null ? null :
            DateTime.parse(job.details['startedAt'] as String),
        currentActivity: job.details['currentActivity'] as String?,
        summary: job.receipt?.details['summary'] as String?,
        threadId: job.details['threadId'] as String?,
        parentThreadId: job.input['parentThreadId'] as String?,
        cancelled: job.state == JobState.cancelled,
        source: job.details['source'] as String?,
        progress: job.type == 'agent.helper' ? null : _progress(job));
  }

  double? _progress(Job job) => job.state == JobState.succeeded
      ? 1
      : job.progress.total != null && job.progress.total! > 0
          ? (job.progress.completed / job.progress.total!).clamp(0.0, 1.0)
          : null;
  Future<String?> _jobWork(Job job) async {
    final ids = [
      job.input['workId'],
      job.input['entityId'],
      job.input['fileId'],
      ...?job.receipt?.details['workIds'] as List?,
      ...?job.receipt?.details['fileIds'] as List?
    ];
    for (final id in ids.whereType<String>()) {
      final work = await _parentWork(id);
      if (work != null) return work;
    }
    return null;
  }

  Future<String?> _parentWork(String id) async {
    final rows = await db.rawQuery(
        'WITH RECURSIVE parents AS (SELECT * FROM media_entities WHERE id=? UNION ALL SELECT e.* FROM media_entities e JOIN parents p ON e.id=p.parent_id) SELECT id FROM parents WHERE kind=\'work\'',
        [id]);
    if (rows.isNotEmpty) return rows.first['id'] as String;
    final links = await db.query('media_file_episodes',
        where: 'file_id=?', whereArgs: [id], limit: 1);
    return links.isEmpty
        ? null
        : _parentWork(links.first['episode_id'] as String);
  }

  @override
  Future<UiHome> home() async {
    final shelves = <UiShelf>[];
    final continuing = <UiShelfItem>[];
    final seen = <String>{};
    if (sources.continueWatching != null) {
      for (final row in await _view('history.continue_watching')) {
        if (row['fileId'] is! String) continue;
        final workId = await _parentWork(row['fileId'] as String);
        if (workId == null || !seen.add(workId)) continue;
        final work = (await this.work(workId))!;
        final links = await db.query('media_file_episodes',
            where: 'file_id=?', whereArgs: [row['fileId']]);
        final eps = await episodes(workId);
        final ep = eps
            .where((e) =>
                links.any((l) => l['episode_id'] == e.episodeId) &&
                (e.progress ?? 0) < 1)
            .firstOrNull;
        continuing.add(UiShelfItem(work, episode: ep, caption: _caption(ep)));
      }
    }
    if (continuing.isNotEmpty) {
      shelves.add(UiShelf(
          id: 'continue',
          title: '继续观看',
          kind: UiShelfKind.continueWatching,
          items: continuing));
    }
    final following = Set<String>.of(seen);
    for (final row in sources.history?.call() ?? <JsonMap>[]) {
      final progress = (row['watchProgress'] as num?)?.toDouble() ?? 0;
      if (progress <= 0 || progress >= .95) continue;
      final fileId = await media.store.ensureFile(row['filePath'] as String);
      final id = await _parentWork(fileId);
      if (id != null) following.add(id);
    }
    final airing = <UiShelfItem>[];
    for (final update in sources.calendar == null ? <JsonMap>[] :
        await todayUpdates(media.store, following, await sources.calendar!())) {
      final work = (await this.work(update['workId'] as String))!;
      final matches = await db.rawQuery(
        "SELECT b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.status='accepted' AND o.provider='dandanplay' AND o.object_type='episode' AND o.external_id=?",
        [update['externalEpisodeId']]);
      final ep = (await episodes(work.workId)).where((e) => matches.any((m) => m['entity_id']==e.episodeId)).firstOrNull;
      airing.add(UiShelfItem(work, episode: ep, caption: update['caption'] as String));
    }
    if (airing.isNotEmpty) shelves.add(UiShelf(id: 'airing', title: '今天更新', kind: UiShelfKind.airing, items: airing));
    UiHero? hero;
    for (final row in await db.query('ui_shelves', orderBy: 'rowid')) {
      final shelf = decodeMediaJson(row['payload']);
      final items = <UiShelfItem>[];
      for (final item in (shelf['items'] as List).cast<Map>()) {
        final work = await this.work(item['workId'] as String);
        if (work == null) continue;
        if (shelf['placement'] == 'hero') {
          hero = UiHero(work, note: shelf['note'] as String?);
        } else {
          items.add(UiShelfItem(work,
              episode: work.next,
              caption: item['note'] as String? ?? _caption(work.next)));
        }
      }
      if (shelf['placement'] == 'shelf') {
        shelves.add(UiShelf(
            id: row['id'] as String,
            title: shelf['title'] as String,
            kind: UiShelfKind.agent,
            items: items));
      }
    }
    final recent = <UiShelfItem>[];
    for (final row in await db.query('media_entities',
        where: "kind='work'", orderBy: 'rowid DESC', limit: 20)) {
      final work = (await this.work(row['id'] as String))!;
      recent.add(
          UiShelfItem(work, episode: work.next, caption: _caption(work.next)));
    }
    if (recent.isNotEmpty) {
      shelves.add(UiShelf(
          id: 'recent',
          title: '最近添加',
          kind: UiShelfKind.recent,
          items: recent));
    }
    if (hero == null) {
      final jobs = await engine.list();
      jobs.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      for (final job in jobs.where((j) => j.state == JobState.succeeded)) {
        final workId = await _jobWork(job);
        if (workId == null) continue;
        final work = await this.work(workId);
        if (work?.next?.playable == true) {
          hero = UiHero(work!);
          break;
        }
      }
      if (hero == null) {
        // A newly available local episode is also a preparation result.
        final ready = await db.rawQuery(
            "SELECT r.parent_id AS work_id FROM media_locations l JOIN media_file_episodes fe ON fe.file_id=l.file_id JOIN media_entities e ON e.id=fe.episode_id JOIN media_entities r ON r.id=e.parent_id WHERE l.available=1 ORDER BY l.rowid DESC");
        for (final row in ready) {
          final work = await this.work(row['work_id'] as String);
          if (work?.next?.playable == true) {
            hero = UiHero(work!);
            break;
          }
        }
      }
      if (hero == null) {
        final updated = recent
            .where((i) =>
                i.work.next?.playable == true &&
                continuing.any((c) => c.work.workId == i.work.workId))
            .firstOrNull;
        final work = updated?.work ?? continuing.firstOrNull?.work;
        if (work != null) hero = UiHero(work);
      }
    }
    return UiHome(hero: hero, shelves: shelves);
  }

  Future<JsonMap> putShelf(JsonMap input, Invocation invocation) =>
      media.mutate(() => _putShelf(input, invocation));

  Future<JsonMap> _putShelf(JsonMap input, Invocation invocation,
      {bool removal = false}) async {
    final placement = input['placement'] as String;
    final id = placement == 'hero' ? 'hero' : input['id'] as String?;
    if (id == null ||
        id.trim().isEmpty ||
        placement == 'shelf' &&
            const {'hero', 'continue', 'airing', 'recent'}.contains(id)) {
      throw const Failure(FailureCode.invalidInput,
          'For a shelf supply a stable id other than hero, continue or recent, and a short title.');
    }
    final items = (input['items'] as List).cast<Map>();
    if (placement == 'hero' && items.length > 1) {
      throw const Failure(FailureCode.invalidInput,
          'hero accepts zero or one item: items:[{workId:"…"}].');
    }
    if (placement == 'shelf' && items.isNotEmpty && input['title'] == null) {
      throw const Failure(FailureCode.invalidInput,
          'A non-empty shelf requires title, e.g. 适合今晚.');
    }
    for (final item in items) {
      await _requireEntity(item['workId'] as String, 'work', 'items[].workId');
    }
    for (final value in [
      input['title'],
      input['note'],
      for (final i in items) i['note']
    ]) {
      if (value != null) validateViewerText(value as String);
    }
    await db.transaction((tx) async {
      final previous =
          await tx.query('ui_shelves', where: 'id=?', whereArgs: [id]);
      final beforeItems = previous.isEmpty
          ? <Map>[]
          : (decodeMediaJson(previous.single['payload'])['items'] as List)
              .cast<Map>();
      final affected = removal || items.isEmpty
          ? beforeItems
              .where((old) => !items.any((i) => i['workId'] == old['workId']))
          : items;
      if (items.isEmpty) {
        await tx.delete('ui_shelves', where: 'id=?', whereArgs: [id]);
      } else {
        await tx.insert(
            'ui_shelves',
            {
              'id': id,
              'payload': jsonEncode(input),
              'updated_at': DateTime.now().toUtc().toIso8601String()
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      if (items.isNotEmpty || previous.isNotEmpty) {
        await tx.insert('body_changes', {
          'at': DateTime.now().toUtc().toIso8601String(),
          'type':
              removal || items.isEmpty ? 'ui.shelf_removed' : 'ui.shelf_put',
          'subject_id': id,
          'actor': invocation.origin == 'gui' ? 'user' : 'agent',
          'origin': invocation.origin,
          'invocation_id': invocation.id,
          'facts': jsonEncode({
            'title': removal || items.isEmpty ? '已从首页移除' : '已放到首页',
            'before': previous.isEmpty
                ? null
                : decodeMediaJson(previous.single['payload']),
            'after': items.isEmpty ? null : input,
            'entityIds': [for (final i in affected) i['workId']]
          })
        });
      }
    });
    _changed();
    return {'id': id, 'removed': items.isEmpty};
  }

  /// A GUI can remove one item or the entire shelf without an Agent round trip.
  Future<void> removeShelf(String id,
          {String? workId, Invocation? invocation}) =>
      media.mutate(() async {
        final rows =
            await db.query('ui_shelves', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) {
          throw const Failure(FailureCode.notFound,
              'Shelf does not exist; use its UiShelf.id.');
        }
        final input = decodeMediaJson(rows.single['payload']);
        if (workId != null &&
            !(input['items'] as List)
                .any((i) => (i as Map)['workId'] == workId)) {
          throw const Failure(FailureCode.notFound,
              'workId is not on this shelf; use one of its UiShelfItem.work.workId values.');
        }
        input['items'] = workId == null
            ? []
            : (input['items'] as List)
                .where((i) => (i as Map)['workId'] != workId)
                .toList();
        await _putShelf(input, invocation ?? Invocation(origin: 'gui'),
            removal: true);
      });

  Future<JsonMap> present(JsonMap input, Invocation invocation) async {
    if (!invocation.origin.startsWith('harness_cli:chat:') &&
        !invocation.origin.startsWith('harness_cli:helper:')) {
      throw const Failure(FailureCode.invalidInput,
          'ui.present requires NIPAPLAY_CHAT from the current embedded chat; do not supply threadId or turnId.');
    }
    final journal = File('${mediaRoot.path}/journal.jsonl');
    JsonMap? boundary;
    if (await journal.exists()) {
      for (final line in await journal.readAsLines()) {
        if (line.isEmpty) continue;
        final row = decodeMediaJson(line);
        if (row['event'] == 'chat.turn_boundary' &&
            row['origin'] == invocation.origin) {
          boundary = row;
        }
      }
    }
    if (boundary == null || boundary['phase'] != 'started') {
      throw const Failure(FailureCode.invalidInput,
          'NIPAPLAY_CHAT has no active turn; call ui.present inside that chat turn.');
    }
    final cards = (input['cards'] as List).cast<Map>();
    if (cards.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one card in cards.');
    }
    for (final card in cards) {
      await _validateCard(Map<String, Object?>.from(card));
    }
    final id = await db.insert('ui_presentations', {
      'thread_id': boundary['threadId'],
      'turn_id': boundary['turnId'],
      'cards': jsonEncode(cards),
      'origin': invocation.origin,
      'invocation_id': invocation.id,
      'created_at': DateTime.now().toUtc().toIso8601String()
    });
    _changed();
    return {
      'presentationId': id,
      'threadId': boundary['threadId'],
      'turnId': boundary['turnId'],
      'count': cards.length
    };
  }

  final Directory mediaRoot;

  Future<void> _requireEntity(String id, String? kind, String field) async {
    final rows =
        await db.query('media_entities', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty || kind != null && rows.single['kind'] != kind) {
      throw Failure(FailureCode.invalidInput,
          '$field must reference an existing ${kind ?? 'work or episode'}. Use state.query library.${kind == 'episode' ? 'episodes' : 'works'} and copy the row id; an external provider ID or episode number is not a local ID.');
    }
    if (kind == null && !{'work', 'episode'}.contains(rows.single['kind'])) {
      throw const Failure(FailureCode.invalidInput,
          'steps[].entityId must reference a work or episode.');
    }
  }

  Future<void> _validateCard(JsonMap card) async {
    void shape(Set<String> allowed, Set<String> required) {
      if (card.keys.any((k) => !allowed.contains(k)) ||
          required.any((k) => !card.containsKey(k))) {
        throw Failure(FailureCode.invalidInput,
            '${card['kind']} card expects only ${allowed.join(', ')}; required: ${required.join(', ')}. States/progress are read from referenced objects.');
      }
    }

    switch (card['kind']) {
      case 'work':
        shape({'kind', 'workId'}, {'kind', 'workId'});
        await _requireEntity(card['workId'] as String, 'work', 'workId');
      case 'episode':
        shape({'kind', 'episodeId'}, {'kind', 'episodeId'});
        await _requireEntity(
            card['episodeId'] as String, 'episode', 'episodeId');
      case 'task':
        shape({'kind', 'taskId'}, {'kind', 'taskId'});
        await _requireTask(card['taskId'] as String);
      case 'candidates':
        shape({'kind', 'items'}, {'kind', 'items'});
        if ((card['items'] as List).isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'candidates requires at least one item with workId.');
        }
        for (final item in (card['items'] as List).cast<Map>()) {
          if (item.keys.any((k) => !{'workId', 'reason'}.contains(k))) {
            throw const Failure(FailureCode.invalidInput,
                'candidates.items accept workId and optional reason.');
          }
          await _requireEntity(
              item['workId'] as String, 'work', 'items[].workId');
          if (item['reason'] != null) {
            validateViewerText(item['reason'] as String);
          }
        }
      case 'preparation':
        shape({'kind', 'title', 'workId', 'steps'}, {'kind', 'title', 'steps'});
        validateViewerText(card['title'] as String);
        if ((card['steps'] as List).isEmpty) {
          throw const Failure(FailureCode.invalidInput,
              'preparation requires at least one referenced step.');
        }
        if (card['workId'] != null) {
          await _requireEntity(card['workId'] as String, 'work', 'workId');
        }
        for (final step in (card['steps'] as List).cast<Map>()) {
          if (step.keys.any((k) => !{
                    'label',
                    'detail',
                    'taskId',
                    'entityId',
                    'followupId'
                  }.contains(k)) ||
              !step.containsKey('label')) {
            throw const Failure(FailureCode.invalidInput,
                'steps accept label, optional detail, and exactly one taskId, entityId or followupId.');
          }
          validateViewerText(step['label'] as String);
          if (step['detail'] != null) {
            validateViewerText(step['detail'] as String);
          }
          final refs = ['taskId', 'entityId', 'followupId']
              .where(step.containsKey)
              .toList();
          if (refs.length != 1) {
            throw const Failure(FailureCode.invalidInput,
                'Each step requires exactly one taskId, entityId or followupId; do not write state or progress.');
          }
          if (refs.single == 'taskId') {
            await _requireTask(step['taskId'] as String);
          }
          if (refs.single == 'entityId') {
            await _requireEntity(
                step['entityId'] as String, null, 'steps[].entityId');
          }
          if (refs.single == 'followupId' &&
              (await db.query('followups',
                      where: 'id=?', whereArgs: [step['followupId']]))
                  .isEmpty) {
            throw const Failure(FailureCode.invalidInput,
                'followupId must be an existing followup.register result id; use followup.list.');
          }
        }
      default:
        throw const Failure(FailureCode.invalidInput,
            'kind must be work, episode, candidates, preparation or task.');
    }
  }

  Future<void> _requireTask(String id) async {
    try {
      await engine.get(id);
    } on Failure {
      throw const Failure(FailureCode.invalidInput,
          'taskId must be an existing task.list/task.get jobId, not a download handle or work ID.');
    }
  }

  @override
  Future<List<UiCard>> cards({required String threadId, String? turnId}) async {
    final rows = await db.query('ui_presentations',
        where: turnId == null ? 'thread_id=?' : 'thread_id=? AND turn_id=?',
        whereArgs: [threadId, if (turnId != null) turnId],
        orderBy: 'id');
    final result = <UiCard>[];
    for (final row in rows)
      for (final card
          in (jsonDecode(row['cards'] as String) as List).cast<Map>()) {
        switch (card['kind']) {
          case 'work':
            result.add(UiWorkCard((await work(card['workId'] as String))!));
          case 'episode':
            final workId = (await _parentWork(card['episodeId'] as String))!;
            result.add(UiEpisodeCard(
                (await work(workId))!,
                (await episodes(workId))
                    .singleWhere((e) => e.episodeId == card['episodeId'])));
          case 'task':
            result.add(UiTaskCard(
                await _task(await engine.get(card['taskId'] as String))));
          case 'candidates':
            result.add(UiCandidatesCard([
              for (final item in (card['items'] as List).cast<Map>())
                UiCandidate((await work(item['workId'] as String))!,
                    reason: item['reason'] as String?)
            ]));
          case 'preparation':
            final steps = <UiStep>[];
            for (final step in (card['steps'] as List).cast<Map>()) {
              var status = UiStepState.done;
              double? progress;
              if (step['taskId'] case final String id) {
                final task = await _task(await engine.get(id));
                status = switch (task.state) {
                  UiTaskState.finished => UiStepState.done,
                  UiTaskState.failed => UiStepState.failed,
                  UiTaskState.running => UiStepState.running,
                  _ => UiStepState.waiting
                };
                progress = task.progress;
              } else if (step['followupId'] case final String id) {
                final followup = decodeMediaJson((await db
                        .query('followups', where: 'id=?', whereArgs: [id]))
                    .single['snapshot']);
                status = switch (followup['state']) {
                  'completed' => UiStepState.done,
                  'started' || 'dispatching' => UiStepState.running,
                  'cancelled' || 'execution_failed' => UiStepState.failed,
                  _ => UiStepState.waiting
                };
              }
              steps.add(UiStep(step['label'] as String, status,
                  detail: step['detail'] as String?, progress: progress));
            }
            result.add(UiPreparationCard(card['title'] as String, steps,
                work: card['workId'] == null
                    ? null
                    : await work(card['workId'] as String)));
        }
      }
    return result;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    await _jobs?.cancel();
    await _polling;
    await _publishing;
    artwork.close();
    await _changes.close();
    await _tasks.close();
  }
}

String _ratingSource(String source) => switch (source) {
      'tmdb' => 'TMDB',
      'bangumi' => 'Bangumi',
      'dandanplay' => '弹弹play',
      'https://movie.douban.com' => '豆瓣',
      _ => Uri.tryParse(source)?.host ?? '评分'
    };
String _taskVerb(String type) => switch (type) {
      'disk_deletion' => '删除文件',
      'download' => '下载',
      'danmaku.fetch' => '准备弹幕',
      'danmaku.align' => '对齐弹幕',
      'media.scan' => '整理片库',
      'media.metadata.refresh' => '更新作品资料',
      'harness.hook' => '处理后续',
      _ => '准备作品'
    };
String? _caption(UiEpisode? e) {
  if (e == null) return null;
  final left = e.runtime != null &&
          e.progress != null &&
          e.progress! > 0 &&
          e.progress! < 1
      ? (e.runtime!.inMilliseconds * (1 - e.progress!) / 60000).ceil()
      : null;
  return '第 ${e.number} 集${left == null ? '' : ' · 剩 $left 分钟'}';
}

final _machineText = RegExp(
    r'(?:https?://|(?:work|episode|job|followup|file|inv)-[a-zA-Z0-9]|harness_cli|invocationId|StackTrace|Exception|/Users/|/tmp/)');
String? _display(Object? value) =>
    value is String && value.trim().isNotEmpty && !_machineText.hasMatch(value)
        ? value.trim()
        : null;
void validateViewerText(String value) {
  if (value.trim().isEmpty ||
      value.length > 160 ||
      value.contains('\n') ||
      _machineText.hasMatch(value)) {
    throw const Failure(FailureCode.invalidInput,
        'Viewer text must be one natural short sentence (1–160 characters), without IDs, URLs, paths or debugging details. Put IDs only in reference fields.');
  }
}

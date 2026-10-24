import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../danmaku/store.dart';
import '../media/library_reads.dart';
import '../media/identity_store.dart';
import '../media/media_service.dart';
import '../media/metadata_provider.dart';
import '../state/query.dart';
import '../state/views.dart';
import '../settings/registry.dart';
import 'artwork.dart';
import 'found.dart';
import 'no_airing.dart' if (dart.library.ui) 'airing.dart';
import 'heat.dart';
import '../subtitles/facts.dart';
import 'ui_data.dart';
import 'library_service.dart';
import '../mesh/library.dart';
import '../chat/turn_boundaries.dart';
import '../util/slicer.dart';

/// The `library.files` rows, found by episode and by file.
final class LocalFiles {
  LocalFiles(this.rows) {
    for (final row in rows) {
      (_byEpisode[row['episodeId']] ??= []).add(row);
      (_episodes[row['fileId']] ??= {}).add(row['episodeId']);
    }
  }
  final List<JsonMap> rows;
  final _byEpisode = <Object?, List<JsonMap>>{};
  final _episodes = <Object?, Set<Object?>>{};

  /// The rows of an episode.
  List<JsonMap> ofEpisode(Object? episodeId) =>
      _byEpisode[episodeId] ?? const [];

  /// The episodes a file is linked to.
  Set<Object?> episodesOf(Object? fileId) => _episodes[fileId] ?? const {};
}

/// Application-owned projections. Stored presentations contain no task state.
final class UiDataService implements NextUiData, NextNowPlaying {
  UiDataService(this.media, this.engine, this.state, this.sources,
      Directory root, CredentialVault vault,
      {http.Client? artworkClient})
      : mediaRoot = root,
        artwork = ArtworkCache(media, root, vault, client: artworkClient),
        heat = EpisodeHeat(DanmakuStore(media.store));
  final MediaService media;
  final TaskEngine engine;
  final StateCapability state;
  final StateSources sources;
  final ArtworkCache artwork;
  final EpisodeHeat heat;
  SubtitleFacts? subtitles;
  MeshLibrary? meshLibrary;
  LibraryDataService? libraryData;
  void notifyLibraryChanged() => _changed();
  Future<LocalFiles> localFiles() async =>
      LocalFiles(await _view('library.files'));
  Database get db => media.store.database;
  static const _openingKey = 'preference:hero-opening-seconds';
  Future<int> _openingSeconds() async {
    final rows =
        await db.query('ui_cache', where: 'id=?', whereArgs: [_openingKey]);
    return rows.isEmpty
        ? 180
        : jsonDecode(rows.single['payload'] as String) as int;
  }

  SettingEntry get openingSetting => SettingEntry(
      key: 'next.heroOpeningSeconds',
      title: '开头弹幕时长',
      description: '从每集开头多少秒里挑选首页弹幕。',
      schema: const IntegerSchema(minimum: 30, maximum: 300),
      defaultValue: 180,
      storageKey: _openingKey,
      storageKind: 'sqlite',
      reader: 'UiDataService',
      writer: 'UiDataService',
      read: _openingSeconds,
      decodeStorage: (value) => value ?? 180,
      write: (value) async {
        await db.insert(
            'ui_cache',
            {
              'id': _openingKey,
              'fingerprint': 'preference',
              'payload': jsonEncode(value)
            },
            conflictAlgorithm: ConflictAlgorithm.replace);
        _changed();
      });
  final _changes = StreamController<void>.broadcast();
  final _tasks = StreamController<List<UiTask>>.broadcast();
  StreamSubscription<Job>? _jobs;
  StreamSubscription<void>? _classic;
  Timer? _timer, _midnight;
  String? _observed;
  Future<void> _polling = Future.value(), _publishing = Future.value();
  bool _closed = false;
  @override
  Stream<void> get changes => _changes.stream;

  /// What the catalogue and the interface are made from, told by two
  /// integers however much there is: the database's change epoch (moved by
  /// triggers on the tables they read, whoever writes them, see
  /// `db/epochs.dart`) and Classic's state pushed through [StateSources].
  Future<String> catalogueStamp() async {
    final library = meshLibrary;
    final epoch = library == null || library.worker.isClosed
        ? await _catalogueEpoch()
        : await library.worker.catalogueEpoch();
    return '$epoch:${sources.revision}';
  }

  Future<int> _catalogueEpoch() async {
    final epoch = await db.rawQuery(
        "SELECT COALESCE((SELECT n FROM change_epochs WHERE name='catalogue'),0) AS n");
    return epoch.single['n'] as int;
  }

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
    // The history, what to continue and the calendar tell when they move.
    _classic = sources.changes.listen((_) => _changed());
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
    _scheduleMidnight();
  }

  /// "Today" moves once a day: the airing shelf is read again then.
  void _scheduleMidnight() {
    final now = DateTime.now();
    final next = DateTime(now.year, now.month, now.day + 1);
    _midnight = Timer(next.difference(now) + const Duration(seconds: 1), () {
      _changed();
      if (!_closed) _scheduleMidnight();
    });
  }

  Future<String> _fingerprint() async =>
      '${await catalogueStamp()}:${await libraryData?.sourceStamp()}';
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
    if (workId.startsWith('source-work:')) {
      return libraryData!.sourceWork(workId);
    }
    if (meshLibrary != null) return meshLibrary!.work(workId);
    return localWork(workId);
  }

  /// [files] ([localFiles]) and [episodes] ([localEpisodes]) may be given
  /// when the caller already holds them.
  Future<UiWork?> localWork(String workId,
      {LocalFiles? files,
      List<UiEpisode>? episodes,
      LibraryReads? reads}) async {
    final rows = await db.query('media_entities',
        where: "id=? AND kind='work'", whereArgs: [workId]);
    if (rows.isEmpty) return null;
    final art = await artwork.load(workId, reads: reads);
    final metadata =
        await (reads?.metadata(workId) ?? media.store.mergedMetadata(workId));
    final fields = metadata['fields'] as JsonMap;
    final attrs = decodeMediaJson(rows.single['attributes']);
    episodes ??= await localEpisodes(workId, files: files, reads: reads);
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
    final film = await media.store.workIsFilm(workId);
    final runtime = fields['runtimeMs'];
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
        film: film,
        // Its own length, or a film's one episode's.
        runtime: runtime is num && runtime > 0
            ? Duration(milliseconds: runtime.toInt())
            : film
                ? episodes.singleOrNull?.runtime
                : null,
        studio: _display(fields['studio']),
        overview: _display(fields['overview']),
        ratings: [
          for (final r in (metadata['ratings'] as List).cast<Map>())
            UiRating(_ratingSource(r['source'] as String),
                (r['value'] as num).toDouble())
        ],
        artwork: uiArtwork(art),
        next: next,
        danmaku: await heat.comments([
          for (final e in episodes) (e.episodeId, e.runtime?.inMilliseconds)
        ],
            openingWindow: Duration(
                seconds: await (reads?.once('opening', _openingSeconds) ??
                    _openingSeconds())),
            reads: reads));
  }

  @override
  Future<List<UiEpisode>> episodes(String workId, {int? season}) async {
    if (workId.startsWith('source-work:')) {
      return libraryData!.sourceEpisodes(workId, season: season);
    }
    if (meshLibrary != null) {
      return meshLibrary!.episodes(workId, season: season);
    }
    return localEpisodes(workId, season: season);
  }

  Future<List<UiEpisode>> localEpisodes(String workId,
      {int? season, LocalFiles? files, LibraryReads? reads}) async {
    final rows = await db.rawQuery(
        "SELECT e.*,r.attributes AS release_attributes FROM media_entities e JOIN media_entities r ON r.id=e.parent_id WHERE e.kind='episode' AND r.parent_id=? ORDER BY e.rowid",
        [workId]);
    files ??= await localFiles();
    final result = <UiEpisode>[];
    // A length of nothing is not known.
    int? positive(Object? ms) => ms is num && ms > 0 ? ms.toInt() : null;
    for (final row in rows) {
      final attrs = decodeMediaJson(row['attributes']),
          release = decodeMediaJson(row['release_attributes']);
      final s = attrs['season'] as int? ?? release['season'] as int?;
      if (season != null && s != season) continue;
      final id = row['id'] as String;
      final art = await artwork.load(id, reads: reads);
      final fields = (await (reads?.metadata(id) ??
          media.store.mergedMetadata(id)))['fields'] as JsonMap;
      final locations = files.ofEpisode(id);
      int? duration = positive(fields['runtimeMs']);
      double? progress;
      var playable = false;
      for (final f in locations) {
        final fileAttrs = decodeMediaJson(f['attributes']);
        final p = f['progress'] as Map?;
        final start = f['startMs'] as int? ?? 0, end = f['endMs'] as int?;
        final allLinks = files.episodesOf(f['fileId']);
        final timed = allLinks.length <= 1 || end != null;
        if (timed) {
          duration ??= end != null
              ? positive(end - start)
              : positive(fileAttrs['durationMs']) ?? positive(p?['durationMs']);
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
          number: num.tryParse(attrs['number'] as String? ?? '')?.toInt(),
          season: s,
          title: _display(fields['title'] ?? attrs['title']),
          runtime: duration == null ? null : Duration(milliseconds: duration),
          still: art['still'] as String?,
          progress: progress,
          heat: await heat.load(id, duration, reads: reads),
          playable: playable));
    }
    sortEpisodes(result);
    return result;
  }

  /// What the shell can show: every task still under way, the latest tasks
  /// for the background panel, and recent helper jobs whose threads belong to
  /// the panel and session menu. Older settled history is audit data, not live
  /// UI; decoding all of it on each subscription used to walk the whole task
  /// table at startup.
  Future<List<UiTask>> _taskList() async {
    final jobs = <String, Job>{
      for (final job in await engine.listActive()) job.jobId: job,
    };
    for (final job in await engine.listRecent(limit: _recentJobs)) {
      jobs.putIfAbsent(job.jobId, () => job);
    }
    for (final job in await engine.listRecent(
        type: 'agent.helper', limit: _recentHelperJobs)) {
      jobs.putIfAbsent(job.jobId, () => job);
    }
    return [for (final job in jobs.values) await _task(job)];
  }

  static const _recentJobs = 64;
  static const _recentHelperJobs = 64;
  Future<UiTask> _task(Job job) async {
    Map? title;
    JsonMap? art;
    try {
      final workId = await _jobWork(job);
      if (workId != null) {
        title = (await media.store.mergedMetadata(workId))['fields'] as Map;
        art = await artwork.cached(workId);
      }
    } on Failure catch (failure) {
      if (failure.code != FailureCode.notFound) rethrow;
    }
    final name = _display(title?['title']);
    return UiTask(
        taskId: job.jobId,
        type: job.type,
        title: job.type == 'agent.helper'
            ? job.title
            : job.state == JobState.waitingUser
                ? '等待你确认删除'
                : name != null
                    ? '${_taskVerb(job.type)}《$name》'
                    : job.type == 'download'
                        ? _downloadTitle(job.title)
                        : _taskVerb(job.type),
        workTitle: job.type == 'agent.helper' ? null : name,
        action: job.type == 'agent.helper' ? null : _taskVerb(job.type),
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
        kind: job.type == 'agent.helper'
            ? UiTaskKind.helper
            : UiTaskKind.background,
        startedAt: job.details['startedAt'] == null
            ? null
            : DateTime.parse(job.details['startedAt'] as String),
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
  @override
  Future<UiNowPlaying?> nowPlaying(String path) async {
    final rows = await media.store.database.rawQuery(
        "SELECT fe.episode_id AS episode, r.parent_id AS work FROM media_locations l "
        'JOIN media_file_episodes fe ON fe.file_id=l.file_id '
        'JOIN media_entities e ON e.id=fe.episode_id '
        'JOIN media_entities r ON r.id=e.parent_id '
        // This device's files, or a media source's item (smb://, webdav…),
        // which the player opens by the same locator.
        "WHERE l.locator=? AND (l.source<>'local' OR l.owner_device_id=?) "
        'ORDER BY fe.ordinal LIMIT 1',
        [path, media.store.ownerDeviceId]);
    if (rows.isEmpty) return null;
    final workId = rows.single['work'] as String;
    final work = _display(
        ((await media.store.mergedMetadata(workId))['fields'] as Map)['title']);
    if (work == null) return null;
    final episodeId = rows.single['episode'] as String;
    final fields =
        (await media.store.mergedMetadata(episodeId))['fields'] as Map;
    final attrs = (await media.store.entity(episodeId))['attributes'] as Map;
    // A film's episode goes without its number.
    final number = await media.store.workIsFilm(workId)
        ? null
        : num.tryParse(attrs['number'] as String? ?? '');
    final title = _display(fields['title'] ?? attrs['title']);
    final label = [
      if (number != null) '第 ${number % 1 == 0 ? number.toInt() : number} 集',
      if (title != null && title != work) title,
    ].join(' ');
    // With the mesh, works and episodes go by their merged names.
    final mesh = meshLibrary;
    return UiNowPlaying(
        workId: mesh == null ? workId : await mesh.canonical(workId),
        work: work,
        episodeId: mesh == null ? episodeId : await mesh.canonical(episodeId),
        episode: label.isEmpty ? null : label);
  }

  Future<String?> _jobWork(Job job) async {
    final ids = [
      job.input['workId'],
      job.input['entityId'],
      job.input['fileId'],
      ...?job.receipt?.details['workIds'] as List?,
      ...?job.receipt?.details['fileIds'] as List?,
      // A download under way knows its work by the files already in.
      for (final f in job.checkpoint['completedFiles'] as List? ?? [])
        if (f is Map && f['media'] is Map) (f['media'] as Map)['fileId'],
    ];
    for (final id in ids.whereType<String>()) {
      final work = await _parentWork(id);
      if (work != null) return work;
    }
    return null;
  }

  Future<String?> _parentWork(String id) async {
    if (id.startsWith('source-')) return libraryData!.sourceParent(id);
    if (meshLibrary != null) {
      final merged = await meshLibrary!.parent(id);
      if (merged != null) return merged;
    }
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
  Future<List<UiWork>> library() async {
    if (meshLibrary != null) return meshLibrary!.library();
    return [
      for (final row in await db.query('media_entities',
          where: "kind='work'", orderBy: 'rowid DESC'))
        (await localWork(row['id'] as String))!
    ];
  }

  Future<Map<String, ({String fileId, String workId, List<String> episodeIds})>>
      _readLocatorLinks(Set<String> wanted) async {
    if (wanted.isEmpty) return const {};
    final slice = Slicer();
    final byLocator =
        <String, ({String fileId, String workId, List<String> episodeIds})>{};
    final locators = wanted.toList(growable: false);
    for (var start = 0; start < locators.length; start += 250) {
      final wantedPage =
          locators.sublist(start, (start + 250).clamp(0, locators.length));
      final rows = await db.rawQuery(
          'SELECT l.locator, l.file_id AS fileId, fe.episode_id AS episodeId, r.parent_id AS workId '
          'FROM media_locations l '
          'JOIN media_file_episodes fe ON fe.file_id = l.file_id '
          'JOIN media_entities e ON e.id = fe.episode_id '
          'JOIN media_entities r ON r.id = e.parent_id '
          'WHERE l.owner_device_id = ? AND l.locator IN (${List.filled(wantedPage.length, '?').join(',')}) '
          'ORDER BY l.id, fe.ordinal',
          [media.store.ownerDeviceId, ...wantedPage]);
      for (final row in rows) {
        final locator = row['locator'] as String;
        final existing = byLocator[locator];
        if (existing == null) {
          byLocator[locator] = (
            fileId: row['fileId'] as String,
            workId: row['workId'] as String,
            episodeIds: [row['episodeId'] as String],
          );
        } else {
          existing.episodeIds.add(row['episodeId'] as String);
        }
      }
      await slice();
    }
    return byLocator;
  }

  @override
  Future<UiHome> home() async {
    final mesh = meshLibrary;
    if (mesh != null) {
      return mesh.home();
    }
    final shelves = <UiShelf>[];
    final continuing = <UiShelfItem>[];
    final seen = <String>{};
    // Classic's watch history already carries both in-progress items and the
    // work each one maps to. Walking every work and rebuilding every episode
    // here duplicates that answer on the UI isolate; keep the catalogue scan
    // only for hosts with no Classic state.
    if (meshLibrary != null &&
        sources.continueWatching == null &&
        sources.history == null) {
      for (final work in await library()) {
        final ep = (await episodes(work.workId))
            .where((e) => (e.progress ?? 0) > 0 && (e.progress ?? 0) < 1)
            .firstOrNull;
        if (ep != null && seen.add(work.workId)) {
          continuing
              .add(UiShelfItem(work, episode: ep, caption: _caption(work, ep)));
        }
      }
    }
    final continueRows = sources.continueWatching?.call() ?? const <JsonMap>[];
    final historyRows = sources.history?.call() ?? const <JsonMap>[];
    final sourcePaths = <String>{
      for (final row in <JsonMap>[...continueRows, ...historyRows])
        if (row['filePath'] case final String path) path
    };
    final byLocator = sourcePaths.isEmpty
        ? const <String,
            ({String fileId, String workId, List<String> episodeIds})>{}
        : await _readLocatorLinks(sourcePaths);
    Future<({String fileId, String workId, List<String> episodeIds})?> link(
        String path) async {
      var found = byLocator[path];
      if (found == null && byLocator.isNotEmpty) {
        final resolved = await visibleLocator(path, media);
        if (resolved != null && resolved != path) {
          found = byLocator[resolved];
          if (found == null) {
            final extra = await _readLocatorLinks({resolved});
            byLocator.addAll(extra);
            found = extra[resolved];
          }
        }
      }
      return found;
    }

    if (continueRows.isNotEmpty) {
      for (final row in continueRows) {
        final path = row['filePath'] as String?;
        if (path == null) continue;
        final linked = await link(path);
        if (linked == null) continue;
        final workId = linked.workId;
        if (!seen.add(workId)) continue;
        final work = (await this.work(workId))!;
        final linkedIds = linked.episodeIds.toSet();
        final eps = await episodes(workId);
        final ep = eps
            .where(
                (e) => linkedIds.contains(e.episodeId) && (e.progress ?? 0) < 1)
            .firstOrNull;
        continuing
            .add(UiShelfItem(work, episode: ep, caption: _caption(work, ep)));
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
    for (final link in byLocator.values) {
      if (seen.contains(link.workId)) following.add(link.workId);
    }
    for (final row in historyRows) {
      final progress = (row['watchProgress'] as num?)?.toDouble() ?? 0;
      if (progress <= 0 || progress >= .95) continue;
      final path = row['filePath'] as String?;
      if (path == null) continue;
      final linked = await link(path);
      if (linked != null) {
        following.add(linked.workId);
      }
    }
    final airing = <UiShelfItem>[];
    for (final update in sources.calendar == null
        ? <JsonMap>[]
        : await todayUpdates(
            media.store, following, await sources.calendar!())) {
      final work = (await this.work(update['workId'] as String))!;
      final matches = await db.rawQuery(
          "SELECT b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.status='accepted' AND o.provider='dandanplay' AND o.object_type='episode' AND o.external_id=?",
          [update['externalEpisodeId']]);
      final matchingIds = <String>{
        for (final match in matches)
          await meshLibrary?.canonical(match['entity_id'] as String) ??
              match['entity_id'] as String
      };
      final ep = (await episodes(work.workId))
          .where((e) => matchingIds.contains(e.episodeId))
          .firstOrNull;
      airing.add(
          UiShelfItem(work, episode: ep, caption: update['caption'] as String));
    }
    if (airing.isNotEmpty) {
      shelves.add(UiShelf(
          id: 'airing',
          title: '今天更新',
          kind: UiShelfKind.airing,
          items: airing));
    }
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
              caption: item['note'] as String? ?? _caption(work, work.next)));
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
    for (final work in (await library()).take(20)) {
      recent.add(UiShelfItem(work,
          episode: work.next, caption: _caption(work, work.next)));
    }
    if (recent.isNotEmpty) {
      shelves.add(UiShelf(
          id: 'recent',
          title: '最近添加',
          kind: UiShelfKind.recent,
          items: recent));
    }
    if (hero == null) {
      for (var offset = 0; hero == null; offset += 20) {
        final jobs = await engine.listRecent(
            state: JobState.succeeded, limit: 20, offset: offset);
        if (jobs.isEmpty) break;
        for (final job in jobs) {
          final workId = await _jobWork(job);
          if (workId == null) continue;
          final work = await this.work(workId);
          if (work?.next?.playable == true) {
            hero = UiHero(work!);
            break;
          }
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
        !invocation.origin.startsWith('harness_cli:helper:') &&
        !invocation.origin.startsWith('codex_native:')) {
      throw const Failure(FailureCode.invalidInput,
          'ui.present requires NIPAPLAY_CHAT from the current embedded chat; do not supply threadId or turnId.');
    }
    // The chat host keeps the current turn in memory; a boundary it did not
    // write is looked for in the journal, off the main isolate.
    final journal = File('${mediaRoot.path}/journal.jsonl');
    final boundary = TurnBoundaries.latest(journal, invocation.origin) ??
        await lastTurnBoundary(journal, invocation.origin);
    if (boundary == null || boundary['phase'] != 'started') {
      throw const Failure(FailureCode.invalidInput,
          'NIPAPLAY_CHAT has no active turn; call ui.present inside that chat turn.');
    }
    final cards = [
      for (final card in input['cards'] as List)
        Map<String, Object?>.from(jsonDecode(jsonEncode(card)) as Map)
    ];
    if (cards.isEmpty) {
      throw const Failure(
          FailureCode.invalidInput, 'Supply at least one card in cards.');
    }
    final refs = <String, Future<_RefWork>>{};
    for (final card in cards) {
      await _validateCard(card, refs);
    }
    final resolved = [for (final r in refs.values) await r];
    final turn = boundary;
    final alreadyShown = <bool>[];
    final id = await db.transaction((tx) async {
      final seen = <String>{
        for (final row in await tx.query('ui_presentations',
            columns: ['cards'],
            where: 'thread_id=? AND turn_id=?',
            whereArgs: [turn['threadId'], turn['turnId']]))
          for (final old in (jsonDecode(row['cards'] as String) as List))
            _cardIdentity(old as Map)
      };
      for (final card in cards) {
        alreadyShown.add(!seen.add(_cardIdentity(card)));
      }
      for (final r in resolved) {
        if (r.facts case final facts?) {
          await tx.insert(
              'ui_cache',
              {
                'id': r.key,
                'fingerprint': 'found',
                'payload': jsonEncode(facts)
              },
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      return tx.insert('ui_presentations', {
        'thread_id': turn['threadId'],
        'turn_id': turn['turnId'],
        'cards': jsonEncode(cards),
        'origin': invocation.origin,
        'invocation_id': invocation.id,
        'created_at': DateTime.now().toUtc().toIso8601String()
      });
    });
    _changed();
    return {
      'presentationId': id,
      'threadId': boundary['threadId'],
      'turnId': boundary['turnId'],
      'count': cards.length,
      'conversation': invocation.origin.startsWith('harness_cli:chat:')
          ? 'main'
          : 'subagent',
      'cards': [
        for (var i = 0; i < cards.length; i++)
          {'index': i, 'alreadyShown': alreadyShown[i]}
      ],
      if (resolved.isNotEmpty)
        'refs': [
          for (final r in resolved)
            {
              'ref': r.ref.toJson(),
              'workId': r.workId,
              if (r.facts case final facts?) ...{
                'title': facts['title'],
                'year': facts['year'],
              },
            }
        ],
    };
  }

  // —— Works outside the library ——

  /// A card's `ref`: a work-level provider object, canonical.
  static ExternalRef _workRef(Object? input, String field) {
    final json = input is Map ? Map<String, Object?>.from(input) : null;
    final provider = (json?['provider'] as String?)?.trim().toLowerCase();
    final type = (json?['objectType'] as String?)?.trim();
    final external = (json?['externalId'] as String?)?.trim();
    if (json == null ||
        json.keys.any((k) => !const {
              'provider',
              'objectType',
              'externalId',
              'scope'
            }.contains(k)) ||
        !(Found.kinds[provider]?.contains(type) ?? false) ||
        external == null ||
        external.isEmpty ||
        (json['scope'] ?? '') != '') {
      throw Failure(FailureCode.invalidInput,
          '$field is a work-level provider object {provider, objectType, externalId, scope:""}: tmdb tv or movie, bangumi subject, or dandanplay anime, as media.metadata.search/get return it.');
    }
    return ExternalRef(provider!, type!, external);
  }

  /// One ref of a batch: the library work holding it, or what its provider
  /// says of it. Each ref is read once per batch.
  Future<void> _resolveRef(Map<String, Object?> holder, String field,
      Map<String, Future<_RefWork>> refs) async {
    final ref = _workRef(holder['ref'], field);
    holder['ref'] = ref.toJson();
    final key =
        Found.id(ref.provider, ref.externalId, objectType: ref.objectType);
    await refs.putIfAbsent(key, () async {
      final held = (await media.acceptedWorkIds([ref])).single;
      return held != null
          ? _RefWork(key, ref, workId: held)
          : _RefWork(key, ref, facts: await _fetchFound(ref, field));
    });
  }

  /// What a found work's card shows, read from its provider; its poster
  /// goes to the artwork cache.
  Future<JsonMap> _fetchFound(ExternalRef ref, String field) async {
    final name = '${ref.provider} ${ref.objectType} ${ref.externalId}';
    final MetadataRecord record;
    try {
      record = await media.provider(ref.provider).get(ref);
    } on ProviderRetry catch (e) {
      throw Failure(FailureCode.unavailable,
          '$field: $name cannot be read now (${e.reason}); retry after ${e.at.toUtc().toIso8601String()}.',
          retryable: true);
    } on Failure catch (e) {
      throw e.code == FailureCode.unavailable
          ? Failure(FailureCode.unavailable,
              '$field: $name cannot be read now (${e.message}).',
              retryable: e.retryable)
          : Failure(FailureCode.invalidInput,
              '$field must reference an existing work: ${ref.provider} did not return $name (${e.message}).');
    } catch (_) {
      throw Failure(FailureCode.unavailable,
          '$field: ${ref.provider} returned no usable record for $name.');
    }
    final title = record.title.trim();
    if (title.isEmpty) {
      throw Failure(FailureCode.invalidInput,
          '$field must reference an existing work: $name has no title.');
    }
    ({String path, int tint})? picture;
    if (record.imageUrl case final url?) {
      try {
        picture = await artwork.picture(url);
      } catch (_) {
        // Without a cached copy the card loads the picture itself.
      }
    }
    return {
      'title': title,
      'originalTitle': _display(record.originalTitle),
      'year': record.year,
      'overview': _display(record.overview),
      'episodeCount': Found.episodeCount(record.toJson()),
      'rating': record.rating,
      'imageUrl': record.imageUrl,
      'poster': picture?.path,
      'tint': picture?.tint,
      'fetchedAt': record.fetchedAt.toUtc().toIso8601String(),
    };
  }

  /// A ref card's work as it is now: the library's when the library holds
  /// that identity, otherwise the found work from its cached facts.
  Future<UiWork?> _refWork(Map json) async {
    final ref = ExternalRef.fromJson(Map<String, Object?>.from(json));
    if ((await media.acceptedWorkIds([ref])).single case final id?) {
      if (await work(id) case final held?) return held;
    }
    final key =
        Found.id(ref.provider, ref.externalId, objectType: ref.objectType);
    final rows = await db.query('ui_cache', where: 'id=?', whereArgs: [key]);
    JsonMap facts;
    if (rows.isNotEmpty) {
      facts = decodeMediaJson(rows.single['payload']);
    } else {
      // The disposable cache was cleared: read the provider once more.
      try {
        facts = await _fetchFound(ref, 'ref');
      } on Failure {
        return null;
      }
      await db.insert('ui_cache',
          {'id': key, 'fingerprint': 'found', 'payload': jsonEncode(facts)},
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    final poster = facts['poster'];
    return Found.fromRecord(key, facts,
        artwork: UiArtwork(
            poster: poster is String && await File(poster).exists()
                ? poster
                : facts['imageUrl'] as String?,
            tint: facts['tint'] as int?));
  }

  final Directory mediaRoot;

  Future<void> _requireEntity(String id, String? kind, String field,
      {String hint = ''}) async {
    if (id.startsWith('source-')) {
      final parent = await libraryData!.sourceParent(id);
      if (parent != null &&
          (kind != 'episode' && await work(id) != null ||
              kind != 'work' &&
                  (await episodes(parent)).any((e) => e.episodeId == id))) {
        return;
      }
      throw const Failure(FailureCode.invalidInput,
          'Unknown source work or episode reference.');
    }
    if (meshLibrary != null) {
      final parent = await meshLibrary!.parent(id);
      if (parent != null) {
        if (kind != 'episode' && await work(id) != null) return;
        if (kind != 'work' &&
            (await episodes(parent)).any((e) => e.episodeId == id)) {
          return;
        }
      }
    }
    final rows =
        await db.query('media_entities', where: 'id=?', whereArgs: [id]);
    if (rows.isEmpty || kind != null && rows.single['kind'] != kind) {
      throw Failure(FailureCode.invalidInput,
          '$field must reference an existing ${kind ?? 'work or episode'}. Use state.query library.${kind == 'episode' ? 'episodes' : 'works'} and copy the row id; an external provider ID or episode number is not a local ID.$hint');
    }
    if (kind == null && !{'work', 'episode'}.contains(rows.single['kind'])) {
      throw const Failure(FailureCode.invalidInput,
          'steps[].entityId must reference a work or episode.');
    }
  }

  Future<void> _validateCard(
      JsonMap card, Map<String, Future<_RefWork>> refs) async {
    const outside = ' A work outside the library uses ref instead.';
    void shape(Set<String> allowed, Set<String> required) {
      if (card.keys.any((k) => !allowed.contains(k)) ||
          required.any((k) => !card.containsKey(k))) {
        throw Failure(FailureCode.invalidInput,
            '${card['kind']} card expects only ${allowed.join(', ')}; required: ${required.join(', ')}. States/progress are read from referenced objects.');
      }
    }

    switch (card['kind']) {
      case 'work':
        shape({'kind', 'workId', 'ref'}, {'kind'});
        if (card.containsKey('workId') == card.containsKey('ref')) {
          throw const Failure(FailureCode.invalidInput,
              'work card takes exactly one of workId (a library work) or ref (a provider work).');
        }
        if (card.containsKey('ref')) {
          await _resolveRef(card, 'ref', refs);
        } else {
          await _requireEntity(card['workId'] as String, 'work', 'workId',
              hint: outside);
        }
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
              'candidates requires at least one item with workId or ref.');
        }
        final items = [
          for (final item in card['items'] as List)
            Map<String, Object?>.from(item as Map)
        ];
        card['items'] = items;
        for (final item in items) {
          if (item.keys.any((k) => !{'workId', 'ref', 'reason'}.contains(k)) ||
              item.containsKey('workId') == item.containsKey('ref')) {
            throw const Failure(FailureCode.invalidInput,
                'candidates.items take exactly one of workId (a library work) or ref (a provider work), and optional reason.');
          }
          if (item['reason'] != null) {
            validateViewerText(item['reason'] as String);
          }
        }
        await Future.wait([
          for (final item in items)
            item.containsKey('ref')
                ? _resolveRef(item, 'items[].ref', refs)
                : _requireEntity(
                    item['workId'] as String, 'work', 'items[].workId',
                    hint: outside),
        ]);
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
      case 'choices':
        shape({'kind', 'question', 'options'}, {'kind', 'options'});
        final options = (card['options'] as List).cast<Map>();
        if (options.length < 2 || options.length > 6) {
          throw const Failure(FailureCode.invalidInput,
              'choices offers 2 to 6 options; each has a label, an optional detail and recommended.');
        }
        if (card['question'] != null) {
          validateViewerText(card['question'] as String);
        }
        final labels = <String>{};
        for (final option in options) {
          final label = option['label'] as String;
          validateViewerText(label);
          if (option['detail'] != null) {
            validateViewerText(option['detail'] as String);
          }
          if (!labels.add(label)) {
            throw const Failure(FailureCode.invalidInput,
                'choices options need distinct labels: the chosen label is what the viewer says.');
          }
        }
      default:
        throw const Failure(FailureCode.invalidInput,
            'kind must be work, episode, candidates, preparation, task or choices.');
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

  /// What a card points at: a work by workId or ref, an episode by
  /// episodeId, a task by taskId; any other card by its whole content.
  static String _cardIdentity(Map card) {
    String canonical(Object? v) => jsonEncode(switch (v) {
          Map() => {
              for (final k in (v.keys.cast<String>().toList()..sort()))
                k: jsonDecode(canonical(v[k]))
            },
          List() => [for (final e in v) jsonDecode(canonical(e))],
          _ => v,
        });
    final kind = card['kind'];
    return switch (kind) {
      'work' when card['ref'] is Map => 'work:ref:${canonical(card['ref'])}',
      'work' => 'work:id:${card['workId']}',
      'episode' => 'episode:${card['episodeId']}',
      'task' => 'task:${card['taskId']}',
      _ => '$kind:${canonical(card)}',
    };
  }

  @override
  Future<List<UiCard>> cards({required String threadId, String? turnId}) async {
    final seen = <String>{};
    final rows = await db.query('ui_presentations',
        where: turnId == null ? 'thread_id=?' : 'thread_id=? AND turn_id=?',
        whereArgs: [threadId, if (turnId != null) turnId],
        orderBy: 'id');
    final result = <UiCard>[];
    for (final row in rows)
      for (final card
          in (jsonDecode(row['cards'] as String) as List).cast<Map>()) {
        if (!seen.add('${row['turn_id']}\u0000${_cardIdentity(card)}')) {
          continue;
        }
        switch (card['kind']) {
          case 'work':
            final shown = card['ref'] is Map
                ? await _refWork(card['ref'] as Map)
                : await work(card['workId'] as String);
            if (shown != null) result.add(UiWorkCard(shown));
          case 'episode':
            final episodeId = card['episodeId'] as String;
            final resolvedId = meshLibrary == null
                ? episodeId
                : await meshLibrary!.resolvedId(episodeId);
            final workId = (await _parentWork(episodeId))!;
            result.add(UiEpisodeCard(
                (await work(workId))!,
                (await episodes(workId))
                    .singleWhere((e) => e.episodeId == resolvedId)));
          case 'task':
            result.add(UiTaskCard(
                await _task(await engine.get(card['taskId'] as String))));
          case 'choices':
            result.add(UiChoicesCard([
              for (final option in (card['options'] as List).cast<Map>())
                UiChoice(option['label'] as String,
                    detail: option['detail'] as String?,
                    recommended: option['recommended'] == true)
            ], question: card['question'] as String?));
          case 'candidates':
            final items = <UiCandidate>[];
            for (final item in (card['items'] as List).cast<Map>()) {
              final shown = item['ref'] is Map
                  ? await _refWork(item['ref'] as Map)
                  : await work(item['workId'] as String);
              if (shown != null) {
                items
                    .add(UiCandidate(shown, reason: item['reason'] as String?));
              }
            }
            if (items.isNotEmpty) result.add(UiCandidatesCard(items));
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

  /// Next's interface is closed: nothing here is kept fresh until [start]
  /// again. Its streams stay open for whoever listens then.
  Future<void> pause() async {
    _timer?.cancel();
    _timer = null;
    _midnight?.cancel();
    _midnight = null;
    await _classic?.cancel();
    _classic = null;
    await _jobs?.cancel();
    _jobs = null;
    await _polling;
    await _publishing;
  }

  Future<void> close() async {
    _closed = true;
    _timer?.cancel();
    _midnight?.cancel();
    await _classic?.cancel();
    await _jobs?.cancel();
    await _polling;
    await _publishing;
    await meshLibrary?.close();
    artwork.close();
    await _changes.close();
    await _tasks.close();
  }
}

/// A ref met in one ui.present batch.
final class _RefWork {
  const _RefWork(this.key, this.ref, {this.workId, this.facts});

  /// The found work's ID, also its ui_cache row.
  final String key;
  final ExternalRef ref;

  /// The library work holding this identity.
  final String? workId;

  /// What its provider says of it, when the library has none.
  final JsonMap? facts;
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
      'setting_consent' => '修改设置',
      'download' => '下载',
      'danmaku.fetch' => '准备弹幕',
      'danmaku.align' => '对齐弹幕',
      'media.scan' => '整理片库',
      'media.scan_classic' => '扫描片库',
      'media.metadata.refresh' => '更新作品资料',
      'harness.hook' => '处理后续',
      _ => '准备作品'
    };

/// A download whose work is not known yet goes by its own name, as it came
/// (the torrent's, or the magnet's display name). A source without one (a
/// magnet without dn, a torrent URL named by its hash) is titled by its info
/// hash, which is no name to show.
String _downloadTitle(String title) {
  final name = title
      .trim()
      .replaceFirst(RegExp(r'\.torrent$', caseSensitive: false), '')
      .trim();
  return name.isEmpty || RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(name)
      ? '下载'
      : '下载 $name';
}

/// A film's episode goes without its number.
String? _caption(UiWork work, UiEpisode? e) {
  if (e == null) return null;
  final left = e.runtime != null &&
          e.progress != null &&
          e.progress! > 0 &&
          e.progress! < 1
      ? (e.runtime!.inMilliseconds * (1 - e.progress!) / 60000).ceil()
      : null;
  if (work.film) return left == null ? null : '剩 $left 分钟';
  final caption = [
    if (e.number case final n?) '第 $n 集',
    if (left != null) '剩 $left 分钟',
  ].join(' · ');
  return caption.isEmpty ? null : caption;
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

/// The last `chat.turn_boundary` of [origin] in [journal], by
/// [lastJournalRow] on a background isolate.
Future<JsonMap?> lastTurnBoundary(File journal, String origin) =>
    Isolate.run(() => lastJournalRow(
        journal,
        'chat.turn_boundary',
        (row) =>
            row['event'] == 'chat.turn_boundary' && row['origin'] == origin));

/// The last row of a JSONL [journal] that [match]es, read from the end of the
/// file: only the lines written after it are read, not the whole journal.
/// Only lines containing [marker] are decoded.
Future<JsonMap?> lastJournalRow(
    File journal, String marker, bool Function(JsonMap row) match) async {
  if (!await journal.exists()) return null;
  final file = await journal.open();
  try {
    var end = await file.length();
    var tail = Uint8List(0);
    JsonMap? read(List<int> bytes) {
      if (bytes.isEmpty) return null;
      final line = utf8.decode(bytes);
      if (!line.contains(marker)) return null;
      final row = decodeMediaJson(line.trimRight());
      return match(row) ? row : null;
    }

    while (end > 0) {
      final start = end > 65536 ? end - 65536 : 0;
      await file.setPosition(start);
      final block = BytesBuilder(copy: false)
        ..add(await file.read(end - start))
        ..add(tail);
      final data = block.takeBytes();
      var lineEnd = data.length;
      for (var i = data.length - 1; i >= 0; i--) {
        if (data[i] != 0x0a) continue;
        if (read(Uint8List.sublistView(data, i + 1, lineEnd)) case final row?) {
          return row;
        }
        lineEnd = i;
      }
      tail = Uint8List.sublistView(data, 0, lineEnd);
      end = start;
    }
    return read(tail);
  } finally {
    await file.close();
  }
}

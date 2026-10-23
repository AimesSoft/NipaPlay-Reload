import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// How big the generated profile is. The defaults follow the old, large lab
/// profile (e2e42b) and go past it where it was small: a hundred and more
/// works, thousands of tasks and task events, tens of thousands of danmaku
/// comments, tens of MB of invocation journal, hundreds of MB of lab chat
/// events.
final class BigProfileSpec {
  const BigProfileSpec({
    this.works = 120,
    this.episodesPerWork = 12,
    this.danmakuEpisodes = 40,
    this.danmakuPerEpisode = 1500,
    this.jobs = 1500,
    this.followups = 1200,
    this.waitingFollowups = 8,
    this.hookEvents = 4000,
    this.historyItems = 600,
    this.calendarAnime = 120,
    this.journalBytes = 40 << 20,
    this.chatEventBytes = 300 << 20,
  });
  final int works,
      episodesPerWork,
      danmakuEpisodes,
      danmakuPerEpisode,
      jobs,
      followups,
      waitingFollowups,
      hookEvents,
      historyItems,
      calendarAnime,
      journalBytes,
      chatEventBytes;
}

/// What the generated profile holds, for the scenario that runs over it.
final class BigProfile {
  BigProfile._(this.root, this.media, this.deviceId, this.spec);
  final Directory root, media;
  final String deviceId;
  final BigProfileSpec spec;
  final workIds = <String>[];
  final episodeIds = <String>[];
  final fileIds = <String>[];
  final locators = <String>[];
  final jobIds = <String>[];

  /// Classic's watch history, as `WatchHistoryItem.toJson` gives it.
  final history = <Map<String, Object?>>[];

  /// The calendar as Classic keeps it encoded in its preferences.
  late final String calendarJson;
  File get journal => File('${root.path}/journal.jsonl');
}

const _device = 'device-0123456789abcdef0123456789abcdef';
final _start = DateTime.utc(2026, 9, 1);
String _at(int minutes) =>
    _start.add(Duration(minutes: minutes)).toIso8601String();

/// Generates a large Next profile under [root] (which must be empty):
/// next.db through the app's own migrations, then rows written directly in
/// the shapes the app writes them, media files on disk, danmaku content
/// files, the invocation journal and the lab chat event log.
Future<BigProfile> buildBigProfile(Directory root,
    {BigProfileSpec spec = const BigProfileSpec(), int seed = 7}) async {
  final random = Random(seed);
  await root.create(recursive: true);
  await File('${root.path}/device.json')
      .writeAsString(jsonEncode({'deviceId': _device}));
  final media = await Directory('${root.path}/media').create();
  final profile = BigProfile._(root, media, _device, spec);
  final db = await openNextDatabase(root, factory: databaseFactoryFfi);
  try {
    await _library(db, profile, random);
    await _danmaku(db, profile, random);
    await _tasks(db, profile, random);
    await _followups(db, profile, random);
    await _activity(db, profile, random);
  } finally {
    await db.close();
  }
  _history(profile, random);
  profile.calendarJson = jsonEncode(_calendar(spec.calendarAnime, random));
  await Isolate.run(() => _writeJournal(
      profile.journal.path, spec.journalBytes, profile.workIds.take(20).toList(), seed));
  // The lab build appends every chat event here; nothing reads it back. Its
  // size is there, its content is not needed.
  final events = await File('${root.path}/chat-events.jsonl').open(mode: FileMode.write);
  await events.truncate(spec.chatEventBytes);
  await events.close();
  return profile;
}

String _text(Random random, int length) {
  const words = ['今天', '弹幕', '作品', '这一集', '真好看', '前方高能', '名场面',
    '哈哈哈', '再看一遍', '字幕组辛苦了', 'op', 'ed', '神作', '泪目', '可爱', '打卡'];
  final out = StringBuffer();
  while (out.length < length) {
    out.write(words[random.nextInt(words.length)]);
  }
  return out.toString().substring(0, length);
}

Future<void> _library(Database db, BigProfile profile, Random random) async {
  final spec = profile.spec;
  var batch = db.batch();
  void entity(String id, String kind, String? parent, Map<String, Object?> attrs) =>
      batch.insert('media_entities', {
        'id': id, 'kind': kind, 'parent_id': parent, 'revision': 0,
        'attributes': jsonEncode(attrs)
      });
  void object(String id, String provider, String type, String external, String scope) =>
      batch.insert('media_external_objects', {
        'id': id, 'provider': provider, 'object_type': type,
        'external_id': external, 'scope': scope
      });
  var bindingCount = 0;
  void bind(String entity, String object, String relation, String source, int minutes) =>
      batch.insert('media_bindings', {
        'id': 'binding-perf-${bindingCount++}', 'entity_id': entity, 'object_id': object,
        'relation': relation,
        'scope': jsonEncode({'order': 'provider', 'season': null, 'cour': null,
          'numbers': [], 'startMs': null, 'endMs': null}),
        'status': 'accepted', 'source': source,
        'bound_by': source == 'classic_match' ? null : 'agent', 'revision': 0,
        'invocation_id': source == 'classic_match' ? null : 'inv-perf-bind-$bindingCount',
        'created_at': _at(minutes)
      });
  void snapshot(String id, String object, Map<String, Object?> ref,
          Map<String, Object?> metadata, int minutes) =>
      batch.insert('media_snapshots', {
        'id': id, 'object_id': object, 'language': 'zh-CN', 'fetched_at': _at(minutes),
        'fields': jsonEncode({
          'ref': ref, 'metadata': metadata, 'language': 'zh-CN',
          'fetchedAt': _at(minutes), 'receivedAt': _at(minutes),
          'source': 'provider_snapshot', 'origin': 'application'
        })
      });
  for (var w = 0; w < spec.works; w++) {
    final work = 'work-perf-$w', release = 'release-perf-$w';
    final title = '性能夹具作品 $w ${_text(random, 6)}';
    profile.workIds.add(work);
    final attrs = {'title': title, 'type': 'regular', 'number': null,
      'season': null, 'order': 'provider'};
    entity(work, 'work', null, attrs);
    entity(release, 'release', work, attrs);
    final tv = 'object-perf-tmdb-tv-$w', anime = 'object-perf-ddp-anime-$w';
    object(tv, 'tmdb', 'tv', '${100000 + w}', '');
    object(anime, 'dandanplay', 'anime', '${10000 + w}', '');
    bind(work, tv, 'exact', 'agent', w);
    bind(work, anime, 'contains', 'classic_match', w);
    bind(release, anime, 'contains', 'classic_match', w);
    snapshot('snapshot-perf-tv-$w', tv,
        {'provider': 'tmdb', 'objectType': 'tv', 'externalId': '${100000 + w}', 'scope': ''},
        {
          'title': title, 'originalTitle': 'Perf Fixture $w',
          'overview': _text(random, 300), 'year': 2018 + w % 8,
          'genres': ['动画', '喜剧'], 'studio': 'Studio $w',
          'episodeCount': spec.episodesPerWork, 'runtimeMs': 1440000,
          'rating': {'value': 7 + random.nextDouble() * 2, 'max': 10, 'count': 100 + w},
          'episodes': [
            for (var e = 1; e <= spec.episodesPerWork; e++)
              {'ref': {'provider': 'tmdb', 'objectType': 'episode',
                  'externalId': '${w * 1000 + e}',
                  'scope': 'tv/${100000 + w}/season/1/episode/$e'},
                'title': '第$e话 ${_text(random, 8)}', 'number': '$e'}
          ],
        }, w);
    snapshot('snapshot-perf-anime-$w', anime,
        {'provider': 'dandanplay', 'objectType': 'anime', 'externalId': '${10000 + w}', 'scope': ''},
        {'title': title, 'year': 2018 + w % 8}, w);
    final folder = Directory('${profile.media.path}/work-$w')..createSync();
    for (var e = 1; e <= spec.episodesPerWork; e++) {
      final episode = 'episode-perf-$w-$e', file = 'file-perf-$w-$e';
      final locator = '${folder.path}/[Fixture] Work $w - ${e.toString().padLeft(2, '0')}.mkv';
      File(locator).writeAsBytesSync(utf8.encode('fixture $w $e ${'x' * 200}'));
      profile.episodeIds.add(episode);
      profile.fileIds.add(file);
      profile.locators.add(locator);
      entity(episode, 'episode', release, {'title': '第$e话 ${_text(random, 8)}',
        'type': 'regular', 'number': '$e', 'season': 1, 'order': 'provider'});
      entity(file, 'file', null, {'probe': {'durationMs': 1440000}, 'bindingRevision': 0});
      batch.insert('media_file_episodes', {'file_id': file, 'episode_id': episode,
        'relation': 'exact', 'ordinal': 0, 'start_ms': null, 'end_ms': null});
      batch.insert('media_locations', {'id': 'location-perf-$w-$e', 'file_id': file,
        'source': 'local', 'owner_device_id': profile.deviceId,
        'locator': locator, 'available': 1});
      final ddp = 'object-perf-ddp-ep-$w-$e', tmdb = 'object-perf-tmdb-ep-$w-$e';
      object(ddp, 'dandanplay', 'episode', '${(10000 + w) * 10000 + e}', 'anime/${10000 + w}');
      object(tmdb, 'tmdb', 'episode', '${w * 1000 + e}', 'tv/${100000 + w}/season/1/episode/$e');
      bind(episode, ddp, 'exact', 'classic_match', w);
      bind(episode, tmdb, 'exact', 'agent', w);
      snapshot('snapshot-perf-ep-$w-$e', tmdb,
          {'provider': 'tmdb', 'objectType': 'episode', 'externalId': '${w * 1000 + e}',
            'scope': 'tv/${100000 + w}/season/1/episode/$e'},
          {'title': '第$e话 ${_text(random, 10)}', 'overview': _text(random, 120),
            'runtimeMs': 1440000, 'number': '$e', 'season': 1}, w);
    }
    if (w % 10 == 9) {
      await batch.commit(noResult: true);
      batch = db.batch();
    }
  }
  await batch.commit(noResult: true);
}

Future<void> _danmaku(Database db, BigProfile profile, Random random) async {
  final spec = profile.spec;
  final directory = Directory('${profile.root.path}/danmaku')..createSync();
  final batch = db.batch();
  for (var i = 0; i < spec.danmakuEpisodes; i++) {
    final w = i ~/ 4, e = i % 4 + 1;
    final file = 'file-perf-$w-$e';
    final videoId = '${(10000 + w) * 10000 + e}';
    final entries = [
      for (var n = 0; n < spec.danmakuPerEpisode; n++)
        {
          'sourceId': 'dandanplay', 'videoId': videoId, 'platform': 'dandanplay',
          // Denser in the opening minutes, as real tracks are.
          'sourceTimeMs': n < spec.danmakuPerEpisode ~/ 3
              ? random.nextInt(180000)
              : random.nextInt(1440000),
          'text': _text(random, 2 + random.nextInt(14)),
          'mode': 1, 'colorRgb': 16777215, 'platformId': null,
          'sourceEntryId': '$videoId-$n', 'originSource': null,
          'originVideoId': null, 'sender': 'u$n', 'fontSize': 25, 'sentAt': null
        }
    ]..sort((a, b) => (a['sourceTimeMs'] as int).compareTo(b['sourceTimeMs'] as int));
    final bytes = utf8.encode(jsonEncode(entries));
    final hash = sha256.convert(bytes).toString();
    File('${directory.path}/$hash.json').writeAsBytesSync(bytes);
    final key = 'danmaku-cache-perf-$w-$e';
    batch.insert('danmaku_cache_chunks', {
      'cache_key': key, 'chunk_index': 0, 'start_ms': 0, 'end_ms': 1440000,
      'payload': '[]', 'coverage': 'relatedPool', 'fetched_at': _at(100 + i),
      'file_path': 'danmaku/$hash.json', 'entry_count': entries.length,
      'byte_count': bytes.length, 'storage_kind': 'cache'
    });
    batch.insert('danmaku_bindings', {
      'id': 'danmaku-perf-$w-$e', 'entity_id': file, 'entity_revision': 0,
      'object_id': 'object-perf-ddp-ep-$w-$e',
      'video': jsonEncode({'sourceId': 'dandanplay', 'videoId': videoId,
        'title': '性能夹具作品 $w · 第$e话', 'durationMs': 1440000, 'objectType': 'episode'}),
      'status': 'accepted', 'enabled': 1, 'deduplicate': 1, 'offset_ms': 0,
      'alignment': jsonEncode({'method': 'identity', 'confirmed': false}),
      'evidence': jsonEncode({'reason': 'fixture', 'url': null}),
      'bound_by': 'agent', 'invocation_id': 'inv-perf-danmaku-$i', 'revision': 0,
      'cache_key': key, 'cache_revision': 1, 'cache_job_id': null,
      'created_at': _at(100 + i), 'provenance': null, 'local_file': null
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _tasks(Database db, BigProfile profile, Random random) async {
  final spec = profile.spec;
  var batch = db.batch();
  for (var j = 0; j < spec.jobs; j++) {
    final type = switch (j % 10) {
      0 || 1 || 2 || 3 || 4 || 5 => 'download',
      6 || 7 => 'harness.hook',
      8 => 'danmaku.fetch',
      _ => j % 20 == 9 ? 'program' : 'agent.helper',
    };
    final id = 'job-perf-$j';
    profile.jobIds.add(id);
    final created = _start.add(Duration(minutes: 200 + j));
    final files = type == 'download' ? 1 + random.nextInt(12) : 0;
    final w = j % spec.works;
    final completedFiles = [
      for (var f = 0; f < files; f++)
        {
          'objectId': '$id:$f', 'jobId': id, 'index': f,
          'path': profile.locators[(w * spec.episodesPerWork + f) % profile.locators.length],
          'expectedSize': 300000000, 'actualSize': 300000000,
          'completedBytes': 300000000, 'complete': true, 'verification': 'verified',
          'local': true, 'included': true, 'isVideo': true, 'imported': true,
          'media': {'fileId': 'file-perf-$w-${f % spec.episodesPerWork + 1}',
            'workIds': ['work-perf-$w'], 'identificationPending': false,
            'animeName': '性能夹具作品 $w', 'episodeTitle': '第${f + 1}话'},
          'completedAt': created.add(Duration(minutes: f + 1)).toIso8601String(),
        }
    ];
    final returnTo = j % 3 == 0
        ? {'threadId': 'thread-perf-${j % 7}', 'repository': '/perf/harness',
            'origin': 'harness_cli:chat:perf', 'invocationId': 'inv-perf-job-$j'}
        : null;
    final input = <String, Object?>{
      if (type == 'download') ...{'source': 'magnet:?xt=urn:btih:${j.toRadixString(16).padLeft(40, '0')}',
        'infoHash': j.toRadixString(16).padLeft(40, '0'), 'title': 'Fixture batch $j'},
      if (type == 'harness.hook') ...{'event': 'task.state_changed', 'objectId': 'job-perf-${j - 1}'},
      if (type == 'program') ...{'command': 'echo $j', 'shell': 'sh'},
      if (type == 'agent.helper') ...{'parentThreadId': 'thread-perf-${j % 7}', 'threadId': 'helper-$j'},
      if (returnTo != null) 'returnTo': returnTo,
    };
    final revisions = type == 'download' ? 8 : 3;
    final events = <Map<String, Object?>>[];
    for (var r = 0; r < revisions; r++) {
      final last = r == revisions - 1;
      final job = Job(
        jobId: id, type: type, title: '$type fixture $j', ownerDeviceId: profile.deviceId,
        state: last ? JobState.succeeded : r == 0 ? JobState.queued : JobState.running,
        phase: last ? 'done' : r == 0 ? 'queued' : 'working',
        progress: JobProgress(completed: last ? files : r * files ~/ revisions,
            total: files == 0 ? null : files, unit: 'files'),
        createdAt: created, updatedAt: created.add(Duration(seconds: r * 30)),
        revision: r, input: input,
        checkpoint: {
          if (type == 'download') ...{
            'completedFiles': last ? completedFiles : completedFiles.take(r * files ~/ revisions).toList(),
            'infoHash': input['infoHash'], 'stalls': <Object?>[]},
        },
        details: {
          if (type == 'download') 'backend': {'kind': 'builtin'},
          if (type == 'program') ...{'stdoutTail': _text(random, 400), 'exitCode': 0},
          if (type == 'agent.helper') ...{'threadId': 'helper-$j', 'currentActivity': _text(random, 20)},
        },
        receipt: last
            ? JobReceipt(verification: VerificationLevel.verified, details: {
                if (type == 'download') ...{
                  'infoHash': input['infoHash'], 'downloadComplete': true,
                  'fileIds': [for (final f in completedFiles) (f['media'] as Map)['fileId']],
                  'workIds': ['work-perf-$w']},
                if (type == 'agent.helper') 'summary': _text(random, 200),
                if (type == 'program') ...{'exitCode': 0, 'stdoutTail': _text(random, 300)},
              })
            : null,
        sideEffectCommitted: last,
      );
      events.add({
        'job_id': id, 'revision': r, 'kind': r == 0 ? 'submitted' : last ? 'succeeded' : 'progress',
        'at': job.updatedAt.toIso8601String(), 'snapshot': jsonEncode(job.toJson()),
        'origin': type == 'harness.hook' ? 'hook:task.state_changed' : 'harness_cli:chat:perf',
        'invocation_id': 'inv-perf-job-$j'
      });
      if (last) {
        batch.insert('jobs', {'job_id': id, 'type': type, 'state': job.state.wireName,
          'revision': r, 'created_at': created.toIso8601String(),
          'snapshot': jsonEncode(job.toStorageJson())});
        batch.insert('task_origins', {'job_id': id,
          'origin': type == 'harness.hook' ? 'hook:task.state_changed' : 'harness_cli:chat:perf',
          'invocation_id': 'inv-perf-job-$j'});
      }
    }
    for (final event in events) {
      batch.insert('job_events', event);
    }
    if (returnTo != null && (type == 'download' || type == 'program')) {
      final row = <String, Object?>{
        'id': type == 'download' ? 'followup-download-$id-0' : 'followup-program-$id',
        'automatic': type, 'state': 'completed',
        'title': '${type == 'download' ? '下载事实' : '程序回执'}：$type fixture $j',
        'instruction': 'fixture',
        'condition': type == 'download' ? {'downloadJobId': id} : {'programJobId': id},
        if (type == 'download') 'downloadObjects': [
          for (final f in completedFiles) f['objectId'], 'terminal:$id'],
        'deliverAfter': created.toIso8601String(),
        'waitingFor': null, 'repository': '/perf/harness',
        'threadId': returnTo['threadId'], 'turnId': 'turn-auto-$j',
        'origin': returnTo['origin'], 'invocationId': returnTo['invocationId'],
        'createdAt': created.toIso8601String(), 'updatedAt': created.toIso8601String(),
        'reason': null, 'turnStatus': 'completed',
        'trigger': {'kind': '$type.facts', 'jobId': id, 'title': '$type fixture $j', 'facts': <Object?>[]},
      };
      batch.insert('followups', {'id': row['id'], 'state': 'completed', 'snapshot': jsonEncode(row)});
    }
    if (j % 100 == 99) {
      await batch.commit(noResult: true);
      batch = db.batch();
    }
  }
  await batch.commit(noResult: true);
}

Future<void> _followups(Database db, BigProfile profile, Random random) async {
  final spec = profile.spec;
  final batch = db.batch();
  for (var f = 0; f < spec.followups; f++) {
    final waiting = f >= spec.followups - spec.waitingFollowups;
    final jobId = profile.jobIds[f % profile.jobIds.length];
    final row = {
      'id': 'followup-perf-$f',
      'state': waiting ? 'waiting' : f % 9 == 0 ? 'cancelled' : 'completed',
      'title': '等任务 $jobId',
      'instruction': _text(random, 120),
      'condition': waiting
          ? {'event': 'download.file_completed', 'objectId': 'job-perf-none:$f'}
          : {'jobId': jobId},
      'hookCursor': 0,
      'waitingFor': waiting ? 'download.file_completed for job-perf-none:$f' : null,
      'repository': '/perf/harness',
      'threadId': 'thread-perf-${f % 7}',
      'turnId': waiting ? null : 'turn-perf-$f',
      'origin': 'harness_cli:chat:perf',
      'invocationId': 'inv-perf-followup-$f',
      'createdAt': _at(300 + f),
      'updatedAt': _at(301 + f),
      'trigger': waiting ? null : {'kind': 'task.terminal', 'jobId': jobId, 'facts': {'state': 'succeeded'}},
      'reason': null,
      'turnStatus': waiting ? null : 'completed',
    };
    batch.insert('followups', {'id': row['id'], 'state': row['state'], 'snapshot': jsonEncode(row)});
    for (final type in ['registered', if (!waiting) 'finished']) {
      batch.insert('followup_events', {'followup_id': row['id'], 'at': row['updatedAt'],
        'type': 'followup.$type', 'origin': 'harness_cli:chat:perf',
        'invocation_id': row['invocationId'], 'facts': jsonEncode(row..remove('hookCursor'))});
    }
  }
  for (var h = 0; h < spec.hookEvents; h++) {
    batch.insert('followup_hook_events', {
      'event': h % 4 == 0 ? 'download.file_completed' : 'task.state_changed',
      'object_id': '${profile.jobIds[h % profile.jobIds.length]}:${h % 3}',
      'payload': jsonEncode({'event': 'task.state_changed', 'objectId': profile.jobIds[h % profile.jobIds.length],
        'occurredAt': _at(400 + h), 'data': {'state': 'running', 'title': _text(random, 40)}})
    });
  }
  await batch.commit(noResult: true);
}

Future<void> _activity(Database db, BigProfile profile, Random random) async {
  final batch = db.batch();
  for (var b = 0; b < 400; b++) {
    batch.insert('body_changes', {
      'at': _at(500 + b), 'type': b.isEven ? 'history.watched' : 'ui.shelf_changed',
      'subject_id': profile.fileIds[b % profile.fileIds.length], 'actor': 'user', 'origin': 'gui',
      'invocation_id': null,
      'facts': jsonEncode({'title': '看了 ${_text(random, 10)}', 'fileId': profile.fileIds[b % profile.fileIds.length]}),
    });
  }
  for (var e = 0; e < 600; e++) {
    batch.insert('media_metadata_edits', {
      'entity_id': profile.workIds[e % profile.workIds.length], 'field': 'overview',
      'mode': 'persistent', 'value': jsonEncode(_text(random, 80)),
      'changed_at': _at(600 + e), 'origin': 'harness_cli:chat:perf',
      'invocation_id': 'inv-perf-edit-$e', 'actor': 'agent',
    });
  }
  await batch.commit(noResult: true);
}

void _history(BigProfile profile, Random random) {
  final now = DateTime.now();
  for (var i = 0; i < profile.spec.historyItems && i < profile.locators.length; i++) {
    final w = i ~/ profile.spec.episodesPerWork, e = i % profile.spec.episodesPerWork + 1;
    profile.history.add({
      'filePath': profile.locators[i],
      'animeName': '性能夹具作品 $w',
      'episodeTitle': '第$e话',
      'episodeId': (10000 + w) * 10000 + e,
      'animeId': 10000 + w,
      'watchProgress': random.nextDouble(),
      'lastPosition': random.nextInt(1440000),
      'duration': 1440000,
      'lastWatchTime': now.subtract(Duration(minutes: i * 7)).toIso8601String(),
      'thumbnailPath': null,
      'isFromScan': false,
      'videoHash': sha256.convert(utf8.encode(profile.locators[i])).toString(),
      'mediaKey': null,
    });
  }
}

List<Map<String, Object?>> _calendar(int count, Random random) => [
      for (var a = 0; a < count; a++)
        {
          'id': 20000 + a, 'name': 'Calendar $a', 'name_cn': '日历番 $a ${_text(random, 6)}',
          'imageUrl': 'https://example.invalid/$a.jpg', 'backgroundImageUrl': null,
          'summary': _text(random, 400), 'air_date': '2026-10-0${a % 9 + 1}',
          'airDay': a % 7 + 1, 'rating': 7.5, 'ratingDetails': {'Bangumi评分': 7.5},
          'tags': ['动画', '原创'], 'metadata': ['制作: Studio $a'], 'isNSFW': false,
          'platform': 'TV', 'totalEpisodes': 12, 'typeDescription': 'TV',
          'bangumiUrl': null, 'isOnAir': true, 'isFavorited': false,
          'titles': [{'title': 'Calendar $a', 'language': 'en'}], 'searchKeyword': null,
          'episodeList': [
            for (var e = 1; e <= 12; e++)
              {'episodeId': (20000 + a) * 10000 + e, 'episodeTitle': '第$e话 ${_text(random, 8)}',
                'airDate': '2026-${(9 + e ~/ 4).toString().padLeft(2, '0')}-0${e % 9 + 1}',
                'episodeNumber': '$e'}
          ],
        }
    ];

/// The journal as a long-used profile has it: mostly read calls with their
/// results (state queries, task lists, the catalogue, the hook polling the
/// player), some writes, and chat turn boundaries.
void _writeJournal(String path, int bytes, List<String> works, int seed) {
  final random = Random(seed);
  final sink = File(path).openSync(mode: FileMode.write);
  var written = 0, n = 0;
  String row(int i) => _text(random, 40 + random.nextInt(80));
  while (written < bytes) {
    n++;
    final at = _start.add(Duration(seconds: n * 20)).toIso8601String();
    final kind = n % 50;
    final Map<String, Object?> line;
    if (kind == 0) {
      line = {'event': 'chat.turn_boundary', 'origin': 'harness_cli:chat:perf',
        'threadId': 'thread-perf-${n % 7}', 'turnId': 'turn-$n',
        'phase': n % 100 == 0 ? 'started' : 'completed', 'status': 'completed', 'startedAt': at};
    } else if (kind < 8) {
      line = {'invocationId': 'inv-journal-$n', 'actionId': 'media.metadata.put',
        'origin': 'harness_cli:chat:perf', 'effect': 'write',
        'input': {'entityId': works[n % works.length], 'fields': {'overview': row(n)}},
        'status': 'completed', 'startedAt': at, 'elapsedMs': 12,
        'result': {'entityId': works[n % works.length], 'changed': ['overview']}};
    } else if (kind < 30) {
      line = {'invocationId': 'inv-journal-$n', 'actionId': 'playback.state',
        'origin': 'hook:job-perf-1', 'effect': 'read', 'input': {},
        'status': 'completed', 'startedAt': at, 'elapsedMs': 3,
        'result': {'playing': true, 'positionMs': n * 2000, 'durationMs': 1440000,
          'path': '/perf/media/work-1/episode.mkv', 'title': row(n)}};
    } else if (kind < 45) {
      line = {'invocationId': 'inv-journal-$n', 'actionId': 'state.query',
        'origin': 'harness_cli:chat:perf', 'effect': 'read',
        'input': {'view': 'tasks', 'limit': 50},
        'status': 'completed', 'startedAt': at, 'elapsedMs': 80,
        'result': {'rows': [for (var r = 0; r < 50; r++) {'jobId': 'job-perf-$r', 'title': row(r), 'state': 'succeeded'}]}};
    } else {
      line = {'invocationId': 'inv-journal-$n', 'actionId': 'app.capabilities',
        'origin': 'application:catalog', 'effect': 'read', 'input': {},
        'status': 'completed', 'startedAt': at, 'elapsedMs': 40,
        'result': {'actions': [for (var r = 0; r < 300; r++) {'id': 'action.$r', 'description': row(r)}]}};
    }
    final encoded = utf8.encode('${jsonEncode(line)}\n');
    sink.writeFromSync(encoded);
    written += encoded.length;
  }
  sink.closeSync();
}

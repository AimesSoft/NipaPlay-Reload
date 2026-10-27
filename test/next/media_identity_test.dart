import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:path/path.dart' as ppath;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  late MediaFixture f;
  setUp(() async {
    f = MediaFixture();
    await f.open(sources: ['tmdb', 'bangumi', 'dandanplay']);
  });
  tearDown(() => f.close());

  test(
      'v1 migration preserves existing Task Engine rows and appends identity tables',
      () async {
    final root = await Directory.systemTemp.createTemp('next-v1-');
    final db = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, version) async {
              await db.execute(
                  'CREATE TABLE jobs(job_id TEXT PRIMARY KEY,type TEXT NOT NULL,state TEXT NOT NULL,revision INTEGER NOT NULL,created_at TEXT NOT NULL,snapshot TEXT NOT NULL)');
              await db.execute(
                  'CREATE TABLE job_events(job_id TEXT NOT NULL REFERENCES jobs(job_id),revision INTEGER NOT NULL,kind TEXT NOT NULL,at TEXT NOT NULL,snapshot TEXT NOT NULL,PRIMARY KEY(job_id,revision))');
            }));
    final now = DateTime.utc(2026, 10, 10);
    final job = Job(
        jobId: 'preexisting-download',
        type: 'download',
        title: 'Existing',
        state: JobState.queued,
        phase: 'queued',
        progress: JobProgress(completed: 0, unit: 'bytes'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'device',
        revision: 0);
    await db.insert('jobs', {
      'job_id': job.jobId,
      'type': job.type,
      'state': 'queued',
      'revision': 0,
      'created_at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toStorageJson())
    });
    await db.insert('job_events', {
      'job_id': job.jobId,
      'revision': 0,
      'kind': 'submitted',
      'at': now.toIso8601String(),
      'snapshot': jsonEncode(job.toJson())
    });
    await db.close();
    final upgraded =
        await SqliteJobStore.open(root, factory: databaseFactoryFfi);
    expect(
        (await upgraded.get(job.jobId))!.toStorageJson(), job.toStorageJson());
    expect(await upgraded.events(job.jobId), hasLength(1));
    expect(await upgraded.database.getVersion(), 23);
    expect(await upgraded.database.query('media_entities'), isEmpty);
    await upgraded.close();
    await root.delete(recursive: true);
  });

  test(
      'cleared history IDs remain unknown-provenance evidence without accepted identities',
      () async {
    final path = '${f.media.path}/legacy.mkv';
    f.classic.rows[path] = {
      'filePath': path,
      'animeName': '',
      'episodeTitle': null,
      'animeId': 7001,
      'episodeId': 7101,
      'videoHash': null,
      'watchProgress': 0.7,
      'lastPosition': 7000
    };
    await f.call('media.library.import_history', {});
    await f.call('media.library.import_history', {});
    final files = await f.jobs.database
        .query('media_entities', where: 'kind = ?', whereArgs: ['file']);
    expect(files, hasLength(1));
    final identity = (await f.call(
            'media.identity.get', {'entityId': files.single['id']}))['identity']
        as Map;
    expect(identity['bindings'], isEmpty);
    expect((identity['legacyEvidence'] as List).single['provenance'],
        'legacy_unknown');
    expect((await f.call('media.library.works', {}))['works'], isEmpty);
    expect(f.classic.rows[path]!['lastPosition'], 7000);
    expect(await f.jobs.database.query('media_legacy_history'), hasLength(1));
  });

  test('binding persists agent reasoning, scope and evidence for all levels',
      () async {
    final id = await f.file('E99.2160p arbitrary.mkv');
    final input = {
      'requestId': 'explicit',
      'entries': [tmdbBinding(id)]
    };
    final result = await f.call('media.identity.bind_batch', input);
    final entry = (result['entries'] as List).single as JsonMap;
    final workId = entry['workId'] as String;
    final work =
        (await f.call('media.library.work', {'workId': workId}))['work'] as Map;
    expect((work['releases'] as List).single['episodes'], hasLength(1));
    final identity = (await f
        .call('media.identity.get', {'entityId': id}))['identity'] as Map;
    expect((identity['bindings'] as List).single['boundBy'], 'agent');
    expect((identity['bindings'] as List).single['ref'], mediaEpisodeRef(1));
    expect((identity['evidence'] as List).single['reason'], contains('Agent'));
    expect((identity['evidence'] as List).single['evidence'], isNotEmpty);
    final db = f.jobs.database;
    for (final binding in await db.query('media_bindings')) {
      expect(binding['bound_by'], 'agent');
      expect(binding['source'], 'explicit_binding');
      expect(
          await db.query('media_evidence',
              where: 'binding_id=?', whereArgs: [binding['id']]),
          isNotEmpty);
    }
    final before = await db.query('media_bindings');
    await f.reopen(sources: ['tmdb', 'bangumi', 'dandanplay']);
    expect(await f.call('media.identity.bind_batch', input), result);
    expect(await f.jobs.database.query('media_bindings'), before);
  });

  test('Classic recognition reuses the explicit whole-file hierarchy', () async {
    final fileId = await f.file('adopt.mkv');
    final result = await f.call('media.identity.bind_batch', {
      'requestId': 'tmdb-first', 'entries': [tmdbBinding(fileId)]
    });
    final bound = (result['entries'] as List).single as Map;
    final path = (await f.identities.locations(fileId)).single['locator'] as String;
    f.classic.rows[path] = {'filePath': path, 'animeName': 'Recognized anime',
      'episodeTitle': 'Recognized episode', 'animeId': 7001, 'episodeId': 7101,
      'videoHash': null};
    await f.call('media.library.import_history', {});
    await f.call('media.library.import_history', {});
    final db = f.jobs.database;
    expect(await db.query('media_entities', where: "kind='work'"), hasLength(1));
    expect(await db.query('media_entities', where: "kind='episode'"), hasLength(1));
    final links = await db.query('media_file_episodes', where: 'file_id=?', whereArgs: [fileId]);
    expect(links.single['episode_id'], (bound['episodeIds'] as List).single);
    final owners = await db.rawQuery("SELECT b.entity_id FROM media_bindings b JOIN media_external_objects o ON o.id=b.object_id WHERE b.status='accepted' AND o.provider='dandanplay' AND o.object_type='anime' AND b.entity_id=?", [bound['workId']]);
    expect(owners, hasLength(1));
  });

  test('explicit identity adopts Classic ownership only for identical file segments', () async {
    final fileId = await f.file('classic-first.mkv');
    final path = (await f.identities.locations(fileId)).single['locator'] as String;
    f.classic.rows[path] = {'filePath': path, 'animeName': 'Recognized anime',
      'episodeTitle': 'Recognized episode', 'animeId': 7001, 'episodeId': 7101,
      'videoHash': null};
    await f.call('media.library.import_history', {});
    final result = await f.call('media.identity.bind_batch', {
      'requestId': 'tmdb-second', 'entries': [tmdbBinding(fileId)]
    });
    final bound = (result['entries'] as List).single as Map;
    await f.call('media.identity.bind_batch', {
      'requestId': 'adopt-exact', 'entries': [
        {'kind': 'work', 'entityId': bound['workId'], 'reason': 'Same files',
          'ref': {'provider': 'dandanplay', 'objectType': 'anime', 'externalId': '7001', 'scope': ''}},
        {'kind': 'episode', 'entityId': (bound['episodeIds'] as List).single,
          'reason': 'Same file and timeline',
          'ref': {'provider': 'dandanplay', 'objectType': 'episode', 'externalId': '7101', 'scope': 'anime/7001'}},
      ]
    });
    final links = await f.jobs.database.query('media_file_episodes', where: 'file_id=?', whereArgs: [fileId]);
    expect(links.single['episode_id'], (bound['episodeIds'] as List).single);
    final audit = await f.jobs.database.query('media_evidence', where: "payload LIKE '%\"event\":\"adopt\"%'");
    expect(audit, hasLength(2));
    final other = await f.file('other-content.mkv');
    final second = await f.call('media.identity.bind_batch', {
      'requestId': 'other-work', 'entries': [tmdbBinding(other)]
    });
    // Fixture TMDB reuses the same work; an unrelated local episode must still
    // refuse to steal the accepted external episode.
    await f.jobs.database.insert('media_entities', {'id': 'unrelated-episode', 'kind': 'episode',
      'parent_id': (second['entries'] as List).single['releaseId'], 'attributes': '{}'});
    final failed = await f.harness.invokeJson('media.identity.bind_batch', {
      'requestId': 'must-not-steal', 'entries': [
        {'kind': 'episode', 'entityId': 'unrelated-episode', 'reason': 'No matching file',
          'ref': {'provider': 'dandanplay', 'objectType': 'episode', 'externalId': '7101', 'scope': 'anime/7001'}}]
    }, Invocation(origin: 'mcp'));
    expect(failed, isA<Failed>());
  });

  test('GUI provenance is host derived and cannot be supplied by an Agent',
      () async {
    final id = await f.file('user.mkv');
    await f.call(
        'media.identity.bind_batch',
        {
          'requestId': 'user',
          'entries': [tmdbBinding(id)]
        },
        origin: 'gui');
    expect(
        (await f.jobs.database.query('media_bindings'))
            .every((row) => row['bound_by'] == 'user'),
        isTrue);
    final invalid = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'spoof',
          'entries': [
            {...tmdbBinding(id), 'boundBy': 'user'}
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(invalid.failure.code, FailureCode.invalidInput);
    expect(invalid.failure.violations.first.path, '/entries/0/boundBy');
  });

  test(
      'wrong catalogue member reports its batch index and leaves no accepted bindings',
      () async {
    final first = await f.file('one.mkv'), second = await f.file('two.mkv');
    final bad = {...mediaEpisodeRef(2), 'scope': 'tv/9001/season/2/episode/2'};
    final result = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'bad',
          'entries': [
            tmdbBinding(first),
            {
              ...tmdbBinding(second),
              'episodeRefs': [bad]
            }
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(result.failure.code, FailureCode.invalidInput);
    expect(result.failure.violations.single.path, '/entries/1/episodeRefs/0');
    expect(result.failure.message, contains('not a member'));
    expect(result.failure.message, contains(jsonEncode(mediaEpisodeRef(2))));
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
    expect(await f.jobs.database.query('media_binding_operations'), isEmpty);
  });

  test(
      'conflicting binding rolls back earlier entries and can be corrected explicitly',
      () async {
    final first = await f.file('first.mkv'),
        second = await f.file('second.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'initial',
      'entries': [tmdbBinding(second)]
    });
    final before = await f.jobs.database.query('media_bindings');
    final result = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'conflict',
          'entries': [
            tmdbBinding(first),
            tmdbBinding(second, episodes: [2])
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(result.failure.code, FailureCode.conflict);
    expect(result.failure.violations.single.path, '/entries/1');
    expect(await f.jobs.database.query('media_bindings'), before);
    final unbind = {
      'requestId': 'unbind',
      'entries': [
        {'entityId': second, 'reason': 'Correct previous episode'}
      ]
    };
    final revoked = await f.call('media.identity.unbind_batch', unbind);
    expect(await f.call('media.identity.unbind_batch', unbind), revoked);
    await f.call('media.identity.bind_batch', {
      'requestId': 'corrected',
      'entries': [
        tmdbBinding(first),
        tmdbBinding(second, episodes: [2])
      ]
    });
    final identity = await f.identities.identity(second);
    expect(
        (identity['bindings'] as List)
            .where((b) => b['status'] == 'accepted')
            .single['external_id'],
        '9202');
    expect(
        (identity['evidence'] as List)
            .any((e) => jsonDecode(e['payload'])['event'] == 'unbind'),
        true);
  });

  test('missing file and stale content are explicit indexed errors', () async {
    final id = await f.file('missing.mkv');
    await File('${f.media.path}/missing.mkv').delete();
    final missing = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'missing',
          'entries': [tmdbBinding(id)]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(missing.failure.code, FailureCode.notFound);
    expect(missing.failure.violations.single.path, '/entries/0');
    final staleId = await f.file('stale.mkv');
    await File('${f.media.path}/stale.mkv')
        .writeAsString('changed content with another size');
    final stale = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'stale',
          'entries': [tmdbBinding(staleId)]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(stale.failure.code, FailureCode.conflict);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test(
      'one file can contain multiple episodes and an episode can have multiple files',
      () async {
    final combined = await f.file('combined.mkv'),
        alternate = await f.file('alternate.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'many',
      'entries': [
        {
          ...tmdbBinding(combined, episodes: [1, 2]),
          'startMs': 0,
          'endMs': 1440000
        },
        tmdbBinding(alternate)
      ]
    });
    final links = await f.jobs.database.query('media_file_episodes');
    expect(links, hasLength(3));
    expect(
        links
            .where((l) => l['file_id'] == combined)
            .every((l) => l['relation'] == 'combined'),
        true);
    final partial =
        (await f.identities.identity(combined))['bindings'] as List<JsonMap>;
    await f.call('media.identity.unbind_batch', {
      'requestId': 'partial',
      'entries': [
        {
          'entityId': combined,
          'bindingIds': [partial.first['id']],
          'reason': 'Remove one external association'
        }
      ]
    });
    expect(
        await f.jobs.database.query('media_file_episodes',
            where: 'file_id=?', whereArgs: [combined]),
        hasLength(1));
  });

  test(
      'work season and episode can be bound and unbound in batches without file cascade',
      () async {
    final result = await f.call('media.identity.bind_batch', {
      'requestId': 'levels',
      'entries': [
        {'kind': 'work', 'workRef': mediaWorkRef, 'reason': 'Work chosen'},
        {
          'kind': 'release',
          'workRef': mediaWorkRef,
          'releaseRef': mediaReleaseRef,
          'reason': 'Season chosen'
        },
        {
          'kind': 'episode',
          'workRef': mediaWorkRef,
          'releaseRef': mediaReleaseRef,
          'episodeRefs': [mediaEpisodeRef(2)],
          'reason': 'Episode chosen'
        }
      ]
    });
    final entries = (result['entries'] as List).cast<JsonMap>();
    expect(await f.jobs.database.query('media_file_episodes'), isEmpty);
    expect(
        await f.jobs.database
            .query('media_entities', where: 'kind=?', whereArgs: ['episode']),
        hasLength(1));
    await f.call('media.identity.unbind_batch', {
      'requestId': 'levels-unbind',
      'entries': [
        {
          'entityId': entries[0]['workId'],
          'reason': 'Withdraw work association'
        },
        {
          'entityId': entries[1]['releaseId'],
          'reason': 'Withdraw season association'
        },
        {
          'entityId': (entries[2]['episodeIds'] as List).single,
          'reason': 'Withdraw episode association'
        }
      ]
    });
    expect(
        (await f.jobs.database.query('media_bindings'))
            .every((b) => b['status'] == 'revoked'),
        true);
  });

  test('requestId cannot silently accept different contents', () async {
    final id = await f.file('dedup.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'same',
      'entries': [tmdbBinding(id)]
    });
    final result = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'same',
          'entries': [
            tmdbBinding(id, episodes: [2])
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(result.failure.code, FailureCode.conflict);
    expect(result.failure.message, contains('requestId'));
  });

  test(
      'projection failure remains durable and retries do not duplicate identity',
      () async {
    final id = await f.file('hash.mkv');
    final input = {
      'requestId': 'projection',
      'entries': [dandanplayBinding(id)]
    };
    f.classic.rejectReadback = true;
    final result = await f.harness.invokeJson(
            'media.identity.bind_batch', input, Invocation(origin: 'mcp'))
        as Failed;
    expect(result.failure.code, FailureCode.unavailable);
    expect(await f.identities.pendingProjections(), hasLength(1));
    final bindings = await f.jobs.database.query('media_bindings');
    f.classic.rejectReadback = false;
    await f.call('media.identity.bind_batch', input);
    expect(await f.jobs.database.query('media_bindings'), bindings);
    expect(await f.identities.pendingProjections(), isEmpty);
    final locator =
        (await f.identities.locations(id)).single['locator'] as String;
    expect(f.classic.rows[locator]!['episodeId'], 7101);
    await f.call('media.identity.unbind_batch', {
      'requestId': 'clear',
      'entries': [
        {'entityId': id, 'reason': 'Withdraw hash match'}
      ]
    });
    expect(f.classic.rows[locator]!['animeName'], '');
  });

  test(
      'metadata refresh preserves bindings and host-attributed persistent edits',
      () async {
    final id = await f.file('override.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'override-bind',
      'entries': [tmdbBinding(id)]
    });
    final agent = await f.call('media.metadata.override',
        {'entityId': id, 'field': 'title', 'value': 'Agent title'});
    final agentTitle = (((agent['identity'] as Map)['metadata'] as List)
        .singleWhere((field) => (field as Map)['field'] == 'title')) as Map;
    expect(agentTitle['actor'], 'agent');
    expect(agentTitle['origin'], 'mcp');
    expect(agentTitle['mode'], 'persistent');
    await f.call('media.metadata.override',
        {'entityId': id, 'field': 'title', 'value': 'User title'},
        origin: 'gui');
    final before = await f.jobs.database.query('media_bindings');
    final refresh = await f.call('media.metadata.refresh',
        {'ref': mediaEpisodeRef(1), 'requestId': 'refresh'});
    await waitForJob(
        f.engine, (refresh['job'] as Map)['jobId'], JobState.succeeded);
    expect(await f.jobs.database.query('media_bindings'), before);
    expect(((await f.identities.mergedMetadata(id))['fields'] as Map)['title'],
        'User title');
  });

  test(
      'corrections expire on newer snapshots and clear removes persistent edits',
      () async {
    final id = await f.file('correction.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'correct-bind',
      'entries': [tmdbBinding(id)]
    });
    await f.call('media.metadata.override', {
      'entityId': id,
      'field': 'title',
      'value': 'Correction',
      'mode': 'correction'
    });
    expect(((await f.identities.mergedMetadata(id))['fields'] as Map)['title'],
        'Correction');
    await f.jobs.database.update('media_snapshots', {
      'fetched_at': DateTime.now()
          .toUtc()
          .add(const Duration(seconds: 1))
          .toIso8601String()
    });
    expect(((await f.identities.mergedMetadata(id))['fields'] as Map)['title'],
        isNot('Correction'));
    await f.call('media.metadata.override', {
      'entityId': id,
      'field': 'title',
      'value': 'Pinned',
      'mode': 'persistent'
    });
    expect(((await f.identities.mergedMetadata(id))['fields'] as Map)['title'],
        'Pinned');
    await f.call('media.metadata.override',
        {'entityId': id, 'field': 'title', 'value': null, 'mode': 'clear'});
    expect(((await f.identities.mergedMetadata(id))['fields'] as Map)['title'],
        isNot('Pinned'));
    expect(
        (await f.jobs.database.query('media_metadata_edits'))
            .map((row) => row['mode']),
        ['correction', 'persistent', 'clear']);
    expect(
        (await f.jobs.database.query('media_metadata_edits'))
            .every((row) => row['actor'] == 'agent' && row['origin'] == 'mcp'),
        isTrue);
  });

  test('read primitives never create bindings snapshots or jobs', () async {
    await File('${f.media.path}/arbitrary.mkv')
        .writeAsString('read-only bytes');
    await f.call('media.files.list', {'root': f.media.path});
    await f.call('media.hash.match', {
      'files': [
        {'path': '${f.media.path}/arbitrary.mkv'}
      ]
    });
    await f.call('media.metadata.search_batch', {
      'queries': [
        {'provider': 'tmdb', 'query': '长安', 'kind': 'tv'},
        {'provider': 'bangumi', 'query': 'title'},
        {'provider': 'dandanplay', 'query': 'sample'}
      ]
    });
    await f.call('media.metadata.get_batch', {
      'refs': [mediaWorkRef, mediaReleaseRef, mediaEpisodeRef(1)]
    });
    for (final table in [
      'media_entities',
      'media_snapshots',
      'media_bindings',
      'jobs',
      'media_binding_operations'
    ]) {
      expect(await f.jobs.database.query(table), isEmpty, reason: table);
    }
  });

  test(
      'read batch errors preserve successful neighbours and duplicate refs are fetched once',
      () async {
    final result = await f.call('media.metadata.get_batch', {
      'refs': [
        mediaEpisodeRef(1),
        {...mediaWorkRef, 'provider': 'unknown'},
        mediaEpisodeRef(1)
      ]
    });
    final rows = result['results'] as List;
    expect(rows[0]['record'], rows[2]['record']);
    expect(rows[1]['error']['code'], 'invalid_input');
    expect(f.tmdb.requests, hasLength(1));
    final hashes = await f.call('media.hash.match', {
      'files': [
        {'path': '${f.media.path}/absent.mkv'},
        {'path': '${f.media.path}/also-absent.mkv'}
      ]
    });
    expect((hashes['files'] as List).map((row) => row['error']['code']),
        ['not_found', 'not_found']);
  });

  test('scan only indexes files and never queries metadata or binds', () async {
    await File('${f.media.path}/S99E999.whatever.mp4').writeAsString('video');
    await File('${f.media.path}/notes.txt').writeAsString('not video');
    final input = {'root': f.media.path, 'requestId': 'infrastructure'};
    final scan = await f.call('media.library.scan', input);
    final repeated = await f.call('media.library.scan', input);
    // The task may advance between reads, but the request must not enqueue twice.
    expect((repeated['job'] as Map)['jobId'], (scan['job'] as Map)['jobId']);
    final job = await waitForJob(
        f.engine, (scan['job'] as Map)['jobId'], JobState.succeeded);
    expect(job.receipt!.details['indexed'], 1);
    expect((await f.engine.list()).map((j) => j.type), ['media.scan']);
    expect(f.tmdb.requests, isEmpty);
    expect(f.dandanplay.requests, isEmpty);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test('scan leaves out a directory Windows cannot list and says so', () async {
    // A path beyond 259 characters is made with the extended prefix; without
    // the system's long path setting a plain path to it cannot be listed.
    var deep = f.media.path;
    for (var i = 0; i < 9; i++) {
      deep = ppath.join(deep, 'a-directory-name-of-some-length-$i-${'x' * 20}');
    }
    await Directory(r'\\?\' + deep).create(recursive: true);
    await File(r'\\?\' + ppath.join(deep, 'deep.mkv')).writeAsString('video');
    await File(ppath.join(f.media.path, 'near.mp4')).writeAsString('video');
    final scan = await f.call('media.library.scan',
        {'root': f.media.path, 'requestId': 'unreadable'});
    final job = await waitForJob(
        f.engine, (scan['job'] as Map)['jobId'], JobState.succeeded);
    expect(job.receipt!.details['indexed'], 1);
    final unreadable = job.receipt!.details['unreadableDirectories'] as Map;
    expect(unreadable['count'], greaterThanOrEqualTo(1));
    expect(unreadable['examples'], isNotEmpty);
    expect(unreadable['reason'], contains('os error 3'));
  }, skip: Platform.isWindows ? null : 'A Windows path length limit');

  test(
      'same content with richer duration probe does not revoke existing bindings',
      () async {
    final id = await f.file('enriched.mkv');
    await f.call('media.identity.bind_batch', {
      'requestId': 'enriched',
      'entries': [tmdbBinding(id)]
    });
    final before = await f.jobs.database.query('media_bindings');
    final file = await f.identities.entity(id);
    final probe = (file['attributes'] as JsonMap)['probe'] as JsonMap;
    await f.identities.registerFile(
        '${f.media.path}/enriched.mkv', {...probe, 'durationMs': 1500000});
    expect(await f.jobs.database.query('media_bindings'), before);
    expect((await f.identities.entity(id))['revision'], file['revision']);
  });

  test(
      'explicit local IDs combine metadata sources without dropping links or Classic projection',
      () async {
    final id = await f.file('multiple-sources.mkv');
    final original = await f.call('media.identity.bind_batch', {
      'requestId': 'tmdb-source',
      'entries': [tmdbBinding(id)]
    });
    final local = (original['entries'] as List).single as JsonMap;
    await f.call('media.identity.bind_batch', {
      'requestId': 'dandan-source',
      'entries': [
        {
          ...dandanplayBinding(id),
          'workId': local['workId'],
          'releaseId': local['releaseId'],
          'localEpisodeIds': local['episodeIds']
        }
      ]
    });
    final identity = await f.identities.identity(id);
    expect(
        (identity['bindings'] as List).where((b) => b['status'] == 'accepted'),
        hasLength(2));
    expect(identity['episodes'], hasLength(1));
    expect(await f.identities.pendingProjections(), isEmpty);
    final tmdb = (identity['bindings'] as List)
        .singleWhere((b) => b['provider'] == 'tmdb');
    await f.call('media.identity.unbind_batch', {
      'requestId': 'only-tmdb',
      'entries': [
        {
          'entityId': id,
          'bindingIds': [tmdb['id']],
          'reason': 'Keep Dandanplay identity'
        }
      ]
    });
    expect((await f.identities.identity(id))['episodes'], hasLength(1));
    expect(await f.identities.pendingProjections(), isEmpty);
    final locator =
        (await f.identities.locations(id)).single['locator'] as String;
    expect(f.classic.rows[locator]!['episodeId'], 7101);
  });

  test(
      'new file indexing and all identity writes roll back when a later row conflicts',
      () async {
    final file =
        await File('${f.media.path}/atomic-new.mkv').writeAsString('new bytes');
    final first = {...tmdbBinding('')..remove('entityId'), 'path': file.path};
    final second = {
      ...tmdbBinding('', episodes: [2])..remove('entityId'),
      'path': file.path
    };
    final failed = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'atomic-new',
          'entries': [first, second]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(failed.failure.code, FailureCode.conflict);
    expect(failed.failure.violations.single.path, '/entries/1');
    for (final table in [
      'media_entities',
      'media_locations',
      'media_bindings',
      'media_snapshots',
      'media_evidence',
      'media_projection_outbox',
      'media_binding_operations'
    ]) {
      expect(await f.jobs.database.query(table), isEmpty, reason: table);
    }
  });

  test('a TV work cannot stand in for a season or an episode', () async {
    final id = await f.file('invalid-level.mkv');
    final failed = await f.harness.invokeJson(
        'media.identity.bind_batch',
        {
          'requestId': 'invalid-level',
          'entries': [
            {...tmdbBinding(id), 'releaseRef': mediaWorkRef}
          ]
        },
        Invocation(origin: 'mcp')) as Failed;
    expect(failed.failure.code, FailureCode.invalidInput);
    expect(failed.failure.message, contains('must identify a season'));
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });

  test('hash misses remain empty signals without fallback or decisions',
      () async {
    final id = await f.file('garbage.S99E12345.mkv');
    f.dandanplay.responses['/api/v2/match'] = {
      'isMatched': false,
      'matches': []
    };
    final result = await f.call('media.hash.match', {
      'files': [
        {'entityId': id}
      ]
    });
    expect((result['files'] as List).single['candidates'], isEmpty);
    expect(f.dandanplay.requests.map((row) => row['path']), ['/api/v2/match']);
    expect(await f.engine.list(), isEmpty);
    expect(await f.jobs.database.query('media_bindings'), isEmpty);
  });
}

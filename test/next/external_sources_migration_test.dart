import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/media/external_sources_migration.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media_sources/metadata.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'startup retires all four sources atomically, preserves file services and identities, and resumes cleanup',
      () async {
    const retired = ['jellyfin', 'emby', 'dandanplay_remote', 'nipaplay'];
    SharedPreferences.setMockInitialValues({
      for (final type in retired) 'next.source.$type:fixture.facts': '{}',
      'next.source.smb:fixture.libraries': ['/anime'],
      'server_profiles': 'Classic configuration stays',
      'dandanplay_remote_api_token': 'Classic credential stays',
    });
    sqfliteFfiInit();
    final root = await Directory.systemTemp.createTemp('next-noext-');
    var db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });
    final store = IdentityStore(db, 'fixture-device');
    final local = await store.ensureFile('/local/episode.mkv');
    final smb = await store.ensureRemoteFile('smb://fixture/anime/episode.mkv',
        'smb:fixture', {'type': 'smb', 'itemId': '/anime/episode.mkv'});
    final dav = await store.ensureRemoteFile(
        'webdav://fixture/episode.mkv', 'webdav:fixture', {'type': 'webdav'});
    await db.insert('media_entities',
        {'id': 'user-work', 'kind': 'work', 'attributes': '{"title":"用户的身份"}'});
    await db.insert('media_external_objects', {
      'id': 'user-tmdb',
      'provider': 'tmdb',
      'object_type': 'tv',
      'external_id': '123',
      'scope': ''
    });
    for (final id in ['user-work', local]) {
      await db.insert('media_bindings', {
        'id': 'user-$id',
        'entity_id': id,
        'object_id': 'user-tmdb',
        'relation': 'exact',
        'scope': '{}',
        'status': 'accepted',
        'source': 'explicit_binding',
        'bound_by': 'agent',
        'revision': 0,
        'created_at': '2026-01-01T00:00:00Z'
      });
    }
    var userBindings = await db.query('media_bindings');
    final retainedNative = <String>[];
    final remoteFiles = <String>[];
    for (final type in [...retired, 'smb']) {
      final source = '$type:fixture';
      final scheme = type == 'dandanplay_remote' ? 'dandanplay' : type;
      final locator = type == 'nipaplay'
          ? 'https://fixture.invalid/api/media/local/share/stream/one'
          : '$scheme://fixture/one';
      final file = await store.ensureRemoteFile(locator, source,
          {'type': type, 'serverId': 'server', 'itemId': 'one'});
      if (type != 'smb') remoteFiles.add(file);
      await store.observeSourceCatalog(sourceCatalogRecords(source, {
        'id': 'one',
        'name': type,
        'kind': 'File',
        'serverId': 'server',
        'fileId': file
      }));
      if (type == 'jellyfin') {
        final records = sourceCatalogRecords(source, {
          'id': 'one',
          'name': type,
          'kind': 'File',
          'serverId': 'server',
          'fileId': file
        });
        retainedNative.addAll(records.map((record) => record['id'] as String));
        for (final id in [records.first['id'], records.last['id']]) {
          await db.insert('media_bindings', {
            'id': 'explicit-$id',
            'entity_id': id,
            'object_id': 'user-tmdb',
            'relation': 'exact',
            'scope': '{}',
            'status': 'accepted',
            'source': 'explicit_binding',
            'bound_by': 'agent',
            'revision': 0,
            'created_at': '2026-01-01T00:00:00Z'
          });
        }
        await db.insert('media_file_episodes', {
          'file_id': local,
          'episode_id': records.last['id'],
          'relation': 'explicit_binding',
          'ordinal': 0
        });
        userBindings = await db.query('media_bindings',
            where: "source='explicit_binding'");
      }
      for (final key in [
        'library:layout:$source',
        'library:parent:${base64Url.encode(utf8.encode(jsonEncode([
              source,
              'one'
            ])))}',
        'library:source-cache:${base64Url.encode(utf8.encode(jsonEncode([
              source,
              'server'
            ])))}',
        'library:source-cache:${base64Url.encode(utf8.encode(jsonEncode([
              'library:source-cache:${base64Url.encode(utf8.encode(jsonEncode([
                    source,
                    'server'
                  ])))}',
              'roots'
            ])))}',
      ]) {
        await db.insert(
            'ui_cache', {'id': key, 'fingerprint': 'fixture', 'payload': '{}'});
      }
      if (type != 'smb') {
        await db.insert('media_projection_outbox', {
          'id': source,
          'file_id': file,
          'file_revision': 0,
          'binding_revision': 0,
          'state': 'pending',
          'payload': jsonEncode({
            'remoteTarget': {'sourceId': source}
          })
        });
      }
    }
    // A retired remote file with another local position must survive.
    final mixed = remoteFiles.first;
    await db.insert('media_locations', {
      'id': 'mixed-local',
      'file_id': mixed,
      'source': 'local',
      'owner_device_id': 'fixture-device',
      'locator': '/local/also-here.mkv',
      'available': 1
    });
    await db.insert('media_projection_outbox', {
      'id': 'local-projection',
      'file_id': local,
      'file_revision': 0,
      'binding_revision': 0,
      'state': 'delivered',
      'payload': '{}'
    });
    await db.insert('file_skip_segments', {
      'file_id': remoteFiles.last,
      'kind': 'opening',
      'start_ms': 0,
      'end_ms': 1000,
      'set_at': 'fixture'
    });

    final artwork = await Directory('${root.path}/source-artwork').create();
    final removedCover = File('${artwork.path}/retired-cover');
    final keptCover = File('${artwork.path}/shared-cover');
    await removedCover.writeAsString('removed');
    await keptCover.writeAsString('kept');
    for (final snapshot in await db.query('media_snapshots')) {
      final fields = jsonDecode(snapshot['fields'] as String) as Map;
      final object = (await db.query('media_external_objects',
              where: 'id=?', whereArgs: [snapshot['object_id']]))
          .single;
      if ((object['scope'] as String).contains('jellyfin:')) {
        await db.update(
            'media_snapshots',
            {
              'fields': jsonEncode({
                ...fields,
                'artwork': [removedCover.path, keptCover.path]
              })
            },
            where: 'id=?',
            whereArgs: [snapshot['id']]);
      }
    }
    await db.insert('media_overrides', {
      'entity_id': 'user-work',
      'field': 'poster',
      'value': jsonEncode(keptCover.path),
      'invocation_id': 'user'
    });
    final now = DateTime.now().toUtc();
    for (final (id, type, source) in [
      for (final source in retired)
        (source, 'media.sources.sync', '$source:fixture'),
      ('login', 'media.sources.login', 'emby:fixture'),
      ('connection', 'remote.connection', 'nipaplay:fixture'),
      ('smb-job', 'media.sources.sync', 'smb:fixture'),
      ('unknown', 'retired.plugin', 'unrelated'),
    ]) {
      final job = Job(
          jobId: id,
          type: type,
          title: id,
          state: JobState.queued,
          phase: 'queued',
          progress: JobProgress(completed: 0, unit: 'items'),
          createdAt: now,
          updatedAt: now,
          ownerDeviceId: 'fixture-device',
          revision: 0,
          input: {'sourceId': source});
      await db.insert('jobs', {
        'job_id': id,
        'type': type,
        'state': 'queued',
        'revision': 0,
        'created_at': now.toIso8601String(),
        'snapshot': jsonEncode(job.toStorageJson())
      });
    }
    await db.update('next_external_sources_retirement', {'payload': 'pending'},
        where: 'id=?', whereArgs: ['phase']);
    await store.closeEvents();
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    await finishExternalSourcesPreferences(db);
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await db.query('media_bindings', where: "source='explicit_binding'"),
        userBindings);
    expect(
        (await db.query('media_external_objects', where: "provider='tmdb'"))
            .single['id'],
        'user-tmdb');
    for (final id in [local, smb, dav, mixed]) {
      expect(await db.query('media_entities', where: 'id=?', whereArgs: [id]),
          hasLength(1));
    }
    for (final id in remoteFiles.skip(1)) {
      expect(await db.query('media_entities', where: 'id=?', whereArgs: [id]),
          isEmpty);
    }
    expect(
        (await db.query('media_locations',
                where: 'file_id=?', whereArgs: [mixed]))
            .single['source'],
        'local');
    expect(await db.query('file_skip_segments'), isEmpty);
    expect((await db.query('media_projection_outbox')).single['id'],
        'local-projection');
    expect(await db.query('ui_cache'), hasLength(4),
        reason: 'all four cache key forms retain only SMB data');
    for (final row in await db.query('media_external_objects',
        where: "provider='https://sources.nipaplay.app'")) {
      expect((jsonDecode(row['scope'] as String) as List)[1], 'smb:fixture');
    }
    expect(
        (await db.query('ui_cache')).every((row) =>
            !retired.any((type) => (row['id'] as String).contains(type))),
        isTrue);
    expect(
        (await db.query('media_entities', where: "id LIKE 'source-%'")).every(
            (row) =>
                (row['attributes'] as String).contains('smb:fixture') ||
                retainedNative.contains(row['id'])),
        isTrue);
    for (final id in retainedNative) {
      final entity =
          (await db.query('media_entities', where: 'id=?', whereArgs: [id]))
              .single;
      expect(jsonDecode(entity['attributes'] as String),
          isNot(contains('sourceCatalog')));
    }
    expect(
        (await db.query('media_file_episodes',
                where: 'file_id=?', whereArgs: [local]))
            .single['relation'],
        'explicit_binding');
    expect(await removedCover.exists(), isFalse);
    expect(await keptCover.exists(), isTrue);
    final prefs = await SharedPreferences.getInstance();
    for (final type in retired) {
      expect(prefs.containsKey('next.source.$type:fixture.facts'), isFalse);
    }
    expect(prefs.getString('server_profiles'), 'Classic configuration stays');
    expect(prefs.getString('dandanplay_remote_api_token'),
        'Classic credential stays');
    expect(
        prefs.getStringList('next.source.smb:fixture.libraries'), ['/anime']);
    final jobs = SqliteJobStore.fromDatabase(db);
    for (final id in [...retired, 'login', 'connection']) {
      final job = (await jobs.get(id))!;
      expect(job.state, JobState.failed);
      expect(job.error!.message, contains('Classic'));
      expect(job.receipt!.details['reason'], 'external_media_source_retired');
    }
    final engine = TaskEngine(store: jobs, ownerDeviceId: 'fixture-device');
    await engine.start(); // Unknown executor types must not crash restoration.
    expect((await jobs.get('unknown'))!.state, JobState.queued);
    expect((await jobs.get('smb-job'))!.state, JobState.queued);
    final events = await db.query('job_events');
    await retireExternalSources(db, root.path);
    await finishExternalSourcesPreferences(db);
    expect(await db.query('job_events'), events,
        reason: 'rerunning never duplicates retirement events');
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await engine.close();
  });
}

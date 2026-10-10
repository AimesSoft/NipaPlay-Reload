import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/danmaku/migration.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_migration.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/settings/migration.dart';
import 'package:nipaplay/next/tasks/job_migration.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  test(
      'v4 upgrade preserves accepted identities evidence snapshots file links and outbox, and retires old decisions',
      () async {
    final root = await Directory.systemTemp.createTemp('media-v4-');
    addTearDown(() => root.delete(recursive: true));
    final old = await databaseFactoryFfi.openDatabase('${root.path}/next.db',
        options: OpenDatabaseOptions(
            version: 4,
            onCreate: (db, _) async {
              await migrateJobs(db);
              await migrateMediaIdentity(db);
              await migrateDanmaku(db);
              await migrateSettings(db);
            }));
    for (final entity in [
      {
        'id': 'existing-work',
        'kind': 'work',
        'parent_id': null,
        'attributes': jsonEncode({'title': '既有作品'})
      },
      {
        'id': 'existing-release',
        'kind': 'release',
        'parent_id': 'existing-work',
        'attributes': jsonEncode({'title': '既有季'})
      },
      {
        'id': 'existing-episode',
        'kind': 'episode',
        'parent_id': 'existing-release',
        'attributes':
            jsonEncode({'title': '既有集', 'number': '1', 'type': 'regular'})
      },
      {
        'id': 'existing-file',
        'kind': 'file',
        'parent_id': null,
        'attributes': jsonEncode({
          'bindingRevision': 1,
          'probe': {'size': 4, 'headMd5': 'old'}
        })
      }
    ]) {
      await old.insert('media_entities', {...entity, 'revision': 0});
    }
    await old.insert('media_locations', {
      'id': 'location',
      'file_id': 'existing-file',
      'source': 'local',
      'owner_device_id': 'device',
      'locator': '${root.path}/video.mkv',
      'available': 1
    });
    await old.insert('media_external_objects', {
      'id': 'object',
      'provider': 'tmdb',
      'object_type': 'episode',
      'external_id': '9201',
      'scope': 'tv/9001/season/1/episode/1'
    });
    await old.insert('media_bindings', {
      'id': 'old-binding',
      'entity_id': 'existing-file',
      'object_id': 'object',
      'relation': 'exact',
      'scope': '{}',
      'status': 'accepted',
      'source': 'filename',
      'bound_by': 'user',
      'revision': 1,
      'invocation_id': 'old-invocation',
      'job_id': 'retired-job',
      'created_at': '2026-10-10T00:00:00Z'
    });
    await old.insert('media_file_episodes', {
      'file_id': 'existing-file',
      'episode_id': 'existing-episode',
      'relation': 'exact',
      'ordinal': 0
    });
    await old.insert('media_evidence', {
      'id': 'evidence',
      'binding_id': 'old-binding',
      'job_id': 'retired-job',
      'source': 'filename',
      'payload': '{"reason":"既有理由"}',
      'created_at': '2026-10-10T00:00:00Z'
    });
    await old.insert('media_snapshots', {
      'id': 'snapshot',
      'object_id': 'object',
      'language': 'zh-CN',
      'fetched_at': '2026-10-10T00:00:00Z',
      'fields': '{"title":"既有集"}'
    });
    await old.insert('media_projection_outbox', {
      'id': 'projection',
      'file_id': 'existing-file',
      'file_revision': 0,
      'binding_revision': 1,
      'payload': '{"animeId":7001}',
      'state': 'pending'
    });
    await old.insert('media_candidates', {
      'id': 'candidate',
      'job_id': 'retired-job',
      'file_id': 'existing-file',
      'file_revision': 0,
      'binding_revision': 1,
      'payload': '{}',
      'source': 'filename',
      'state': 'proposed'
    });
    final now = DateTime.utc(2026, 10, 10);
    final pending = Job(
        jobId: 'retired-job',
        type: 'media.identify',
        title: 'Old identification',
        state: JobState.needsDecision,
        phase: 'decision',
        progress: JobProgress(completed: 0, unit: 'files'),
        createdAt: now,
        updatedAt: now,
        ownerDeviceId: 'device',
        revision: 1,
        decision: const Decision(prompt: 'Old workflow', options: [
          DecisionOption(
              label: 'Old choice', call: ActionCall('media.identity.bind', {}))
        ]));
    await old.insert('jobs', {
      'job_id': pending.jobId,
      'type': pending.type,
      'state': pending.state.wireName,
      'revision': pending.revision,
      'created_at': now.toIso8601String(),
      'snapshot': jsonEncode(pending.toStorageJson())
    });
    final preserved = <String, List<Map<String, Object?>>>{};
    for (final table in [
      'media_entities',
      'media_locations',
      'media_external_objects',
      'media_bindings',
      'media_file_episodes',
      'media_evidence',
      'media_snapshots',
      'media_projection_outbox'
    ]) {
      preserved[table] = await old.query(table);
    }
    await old.close();
    final db = await openNextDatabase(root, factory: databaseFactoryFfi);
    addTearDown(db.close);
    for (final table in preserved.keys) {
      expect(await db.query(table), preserved[table], reason: table);
    }
    final identity =
        await IdentityStore(db, 'device').identity('existing-file');
    expect((identity['bindings'] as List).single['status'], 'accepted');
    expect((identity['metadata'] as Map)['fields'], {'title': '既有集'});
    expect((await IdentityStore(db, 'device').library()).single['releases'],
        hasLength(1));
    final retired = Job.fromJson(Map<String, Object?>.from(
        jsonDecode((await db.query('jobs')).single['snapshot'] as String)
            as Map));
    expect(retired.state, JobState.failed);
    expect(retired.decision, isNull);
    expect(retired.error!.code, FailureCode.unavailable);
    expect(retired.receipt!.details['bindingsPreserved'], true);
    expect((await db.query('job_events')).single['kind'], 'workflow_retired');
    final tables =
        await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    expect(tables.map((row) => row['name']),
        isNot(contains('media_identifications')));
    expect(
        tables.map((row) => row['name']), isNot(contains('media_candidates')));
    expect(await db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });
}

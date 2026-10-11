// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/next/media/classic_projection.dart';
import 'package:nipaplay/next/media/identity_store.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/media/media_service.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/tasks/sqlite_job_store.dart';
import 'package:nipaplay/services/scoped_media_server_mapping.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late Database classic;
  late SqliteJobStore jobs;
  late IdentityStore store;
  late Harness harness;

  Future<void> connect({ClassicMetadataPort? port}) async {
    jobs = await SqliteJobStore.open(Directory('${root.path}/next'),
        factory: databaseFactoryFfi);
    store = IdentityStore(jobs.database, 'x17');
    final service = MediaService(
        store: store,
        providers: [
          DandanplayMetadataProvider(FixtureTransport('dandanplay')),
          TmdbMetadataProvider(FixtureTransport('tmdb')),
        ],
        classic: port ?? WatchHistoryMetadataPort(changed: () async {}),
        authorizedRoots: () => [],
        durationProbe: (_) =>
            throw StateError('Remote binding must not probe bytes'));
    harness = Harness([MediaCapability(service)]);
  }

  Future<JsonMap> call(String action, JsonMap input) async {
    final result =
        await harness.invokeJson(action, input, Invocation(origin: 'x17'));
    expect(result, isA<Completed>(), reason: jsonEncode(result.toEnvelope()));
    final value = (result as Completed).value.toJson();
    expect(harness.lookup(action)!.spec.output.validate(value), isEmpty);
    return value;
  }

  Future<Outcome> invoke(String action, JsonMap input) =>
      harness.invokeJson(action, input, Invocation(origin: 'x17'));
  JsonMap bind(String id, String request, {JsonMap? entry}) => {
        'requestId': request,
        'entries': [entry ?? dandanplayBinding(id)]
      };
  JsonMap undo(String id, String request) => {
        'requestId': request,
        'entries': [
          {'entityId': id, 'reason': 'Withdraw experiment identity'}
        ]
      };
  Future<String> remote(String type, String profile, String item) =>
      store.ensureRemoteFile('$type://$item', '$type:$profile', {
        'type': type,
        'itemId': item,
        'seriesId': 'series',
        'seasonId': 'season',
        'number': 1,
        'name': 'remote file'
      });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nipa-x17-data-');
    StorageService.debugAppStorageDirectoryOverride = root;
    classic = await WatchHistoryDatabase.instance.database;
    await connect();
  });
  tearDown(() async {
    await store.closeEvents();
    await jobs.database.close();
    await WatchHistoryDatabase.instance.close();
    StorageService.debugAppStorageDirectoryOverride = null;
    await root.delete(recursive: true);
  });

  test(
      'Remote sources share identity records; scoped mappings undo and replay across restart',
      () async {
    for (final type in ['jellyfin', 'emby', 'smb', 'webdav', 'nipaplay']) {
      final path = type == 'nipaplay'
          ? 'http://127.0.0.1:12345/share/episode'
          : '$type://item';
      final id = await store.ensureRemoteFile(path, '$type:server-a', {
        'type': type,
        'itemId': 'item',
        'seriesId': 'series',
        'seasonId': 'season',
        'number': 1,
        'name': 'remote file'
      });
      final beforeHistory = await classic.query('watch_history');
      final result =
          await call('media.identity.bind_batch', bind(id, '$type-bind'));
      final identity = await store.identity(id);
      final binding = (identity['bindings'] as List).single;
      expect(binding['source'], 'explicit_binding');
      expect(binding['bound_by'], 'agent');
      expect(binding['status'], 'accepted');
      expect(identity['episodes'], hasLength(1));
      if (type == 'jellyfin' || type == 'emby') {
        expect(await scopedEpisodeMapping(classic, type, 'server-a', 'item'),
            containsPair('dandanplay_episode_id', 7101));
        expect(await classic.query('watch_history'), beforeHistory);
      }
      final receipt =
          await call('media.identity.unbind_batch', undo(id, '$type-undo'));
      expect((receipt['entries'] as List).single['classicProjection'],
          everyElement(containsPair('restored', true)));
      if (type == 'jellyfin' || type == 'emby') {
        expect(await classic.query('${type}_episode_mapping'), isEmpty);
        expect(await classic.query('${type}_dandanplay_mapping'), isEmpty);
      }
      expect(await call('media.identity.unbind_batch', undo(id, '$type-undo')),
          receipt);
      expect(result['entries'], hasLength(1));
    }
    await store.closeEvents();
    await jobs.database.close();
    await connect();
    final receipts = await jobs.database.query('media_binding_operations');
    expect(receipts, hasLength(10));
    expect(await classic.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await jobs.database.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    print(
        'X17 sources: Jellyfin/Emby/SMB/WebDAV/shared identity accepted; undo/replay=true; receipts after restart=10; foreign_key_check=[]');
  });

  test(
      'Two servers with identical item IDs remain distinct and path binding is ambiguous',
      () async {
    for (final type in ['jellyfin', 'emby']) {
      final a = await remote(type, 'a', 'same-id');
      final b = await remote(type, 'b', 'same-id');
      expect(a, isNot(b));
      await call('media.identity.bind_batch', bind(a, '$type-a'));
      final other = dandanplayBinding(b);
      (other['episodeRefs'] as List).single['externalId'] = '7102';
      await call('media.identity.bind_batch', bind(b, '$type-b', entry: other));
      expect(
          (await scopedEpisodeMapping(
              classic, type, 'a', 'same-id'))!['dandanplay_episode_id'],
          7101);
      expect(
          (await scopedEpisodeMapping(
              classic, type, 'b', 'same-id'))!['dandanplay_episode_id'],
          7102);
      final pathEntry = {
        ...dandanplayBinding(a)..remove('entityId'),
        'path': '$type://same-id'
      };
      final ambiguous = await invoke('media.identity.bind_batch',
          bind(a, '$type-ambiguous', entry: pathEntry));
      expect((ambiguous as Failed).failure.code, FailureCode.conflict);
      await call('media.identity.unbind_batch', undo(a, '$type-a-undo'));
      expect(await scopedEpisodeMapping(classic, type, 'a', 'same-id'), isNull);
      expect(
          (await scopedEpisodeMapping(
              classic, type, 'b', 'same-id'))!['dandanplay_episode_id'],
          7102);
    }
    print(
        'X17 isolation: identical Jellyfin/Emby IDs -> distinct files and Classic mappings; ambiguous path=conflict; undo A preserves B=true');
  });

  test(
      'Classic edits and repeated projections retain the original undo evidence',
      () async {
    final id = await remote('jellyfin', 'a', 'item');
    await call('media.identity.bind_batch', bind(id, 'bind'));
    await classic.update('jellyfin_dandanplay_mapping',
        {'dandanplay_anime_title': 'Classic edited title'});
    final before = await classic.query('jellyfin_episode_mapping');
    final animeBefore = await classic.query('jellyfin_dandanplay_mapping');
    final localEpisodes = (await store.identity(id))['episodes'] as List;
    final secondary = tmdbBinding(id)
      ..['localEpisodeIds'] = [localEpisodes.single['episode_id']];
    final second = await invoke(
        'media.identity.bind_batch', bind(id, 'secondary', entry: secondary));
    expect((second as Failed).failure.code, FailureCode.conflict);
    final undoResult =
        await invoke('media.identity.unbind_batch', undo(id, 'undo'));
    expect((undoResult as Failed).failure.code, FailureCode.conflict);
    expect(await classic.query('jellyfin_episode_mapping'), before);
    expect(await classic.query('jellyfin_dandanplay_mapping'), animeBefore);
    expect((await store.identity(id))['bindings'],
        everyElement(containsPair('status', 'revoked')));
    expect(
        ((await call('media.identity.get', {'entityId': id}))['identity']
            as Map)['conflicts'],
        isNotEmpty);
    print(
        'X17 Classic edit: secondary projection=conflict; undo=conflict; Next revoked=true; edited Classic rows unchanged=true');
  });

  test('Arbitrary source file refs reuse an explicitly accepted local episode',
      () async {
    final files = [
      for (final type in ['jellyfin', 'emby', 'smb', 'webdav', 'nipaplay'])
        await remote(type, 'a', 'item')
    ];
    final seeded = await call('media.identity.bind_batch',
        bind(files.first, 'seed', entry: tmdbBinding(files.first)));
    final episodeId = ((seeded['entries'] as List).single['episodeIds'] as List)
        .single as String;
    const ref = {
      'provider': 'https://example.org',
      'objectType': 'episode',
      'externalId': 'opaque-episode',
      'scope': 'catalogue/opaque'
    };
    final input = {
      'requestId': 'arbitrary-source',
      'entries': [
        {
          'kind': 'episode',
          'entityId': episodeId,
          'ref': ref,
          'reason': 'Explicit arbitrary-source episode identity'
        },
        for (final id in files)
          {
            'kind': 'file',
            'entityId': id,
            'ref': ref,
            'localEpisodeIds': [episodeId],
            'reason': 'Explicit remote file association'
          }
      ]
    };
    final result = await call('media.identity.bind_batch', input);
    expect(await call('media.identity.bind_batch', input), result);
    for (final id in files) {
      final identity = await store.identity(id);
      expect(
          (identity['bindings'] as List)
              .where((b) => b['provider'] == ref['provider'])
              .single['status'],
          'accepted');
      expect((identity['episodes'] as List).single['episode_id'], episodeId);
    }
    final before = await jobs.database.query('media_bindings');
    final bad = await invoke('media.identity.bind_batch', {
      'requestId': 'wrong-ref',
      'entries': [
        {
          'kind': 'file',
          'entityId': files.last,
          'ref': {...ref, 'externalId': 'different'},
          'localEpisodeIds': [episodeId],
          'reason': 'Rejected because this ref is not accepted on the episode'
        }
      ]
    });
    expect((bad as Failed).failure.code, FailureCode.invalidInput);
    expect(await jobs.database.query('media_bindings'), before);
    print(
        'X17 arbitrary source: HTTPS opaque episode ref accepted on all five remote source types; same local Episode/provenance=true; mismatched ref rejected atomically=true; no provider fetch');
  });

  test('Retargeting a source profile cannot alias another physical server',
      () async {
    Future<String> server(String serverId) =>
        store.ensureRemoteFile('emby://same-id', 'emby:profile', {
          'type': 'emby',
          'serverId': serverId,
          'itemId': 'same-id',
          'seriesId': 'series',
          'seasonId': 'season',
          'number': 1,
          'name': 'remote'
        });
    final a = await server('physical-a');
    final b = await server('physical-b');
    expect(a, isNot(b));
    await call('media.identity.bind_batch', bind(a, 'server-a'));
    expect(
        await scopedEpisodeMapping(classic, 'emby',
            mediaServerScope('profile', 'physical-a'), 'same-id'),
        isNotNull);
    expect(
        await scopedEpisodeMapping(classic, 'emby',
            mediaServerScope('profile', 'physical-b'), 'same-id'),
        isNull);
    await call('media.identity.bind_batch', bind(b, 'server-b'));
    await call('media.identity.unbind_batch', undo(a, 'undo-a'));
    expect(
        await scopedEpisodeMapping(classic, 'emby',
            mediaServerScope('profile', 'physical-b'), 'same-id'),
        isNotNull);
    print(
        'X17 server replacement: same profile + same item ID + different physical server -> distinct files/mappings; undo old server preserves new server=true');
  });

  test('Independent Classic mapping and TMDB leave Classic rows untouched',
      () async {
    final id = await remote('emby', 'a', 'item');
    await ensureMediaServerMappingTables(classic, 'emby');
    final mappingId = await classic.insert('emby_dandanplay_mapping', {
      'emby_series_id': scopedMediaServerId('a', 'series'),
      'emby_season_id': 'season',
      'dandanplay_anime_id': 7001,
      'dandanplay_anime_title': 'Classic original'
    });
    await classic.insert('emby_episode_mapping', {
      'emby_episode_id': scopedMediaServerId('a', 'item'),
      'emby_index_number': 1,
      'dandanplay_episode_id': 7101,
      'mapping_id': mappingId,
      'confirmed': 0
    });
    final before = await classic.query('emby_episode_mapping');
    final animeBefore = await classic.query('emby_dandanplay_mapping');
    await call('media.identity.bind_batch', bind(id, 'bind'));
    final receipt = await call('media.identity.unbind_batch', undo(id, 'undo'));
    expect((receipt['entries'] as List).single['classicProjection'],
        everyElement(containsPair('status', 'unchanged')));
    expect(await classic.query('emby_episode_mapping'), before);
    expect(await classic.query('emby_dandanplay_mapping'), animeBefore);
    final tmdb = await call(
        'media.identity.bind_batch', bind(id, 'tmdb', entry: tmdbBinding(id)));
    expect((tmdb['entries'] as List).single['classicProjectionId'], isNull);
    expect(await classic.query('emby_episode_mapping'), before);
    print(
        'X17 independent Classic: bind/undo preserves complete original rows=true; undo.status=unchanged; TMDB projection=null');
  });

  test(
      'Remote Classic readback interruption recovers bind and undo receipts after restart',
      () async {
    Future<void> reopen({ClassicMetadataPort? port}) async {
      await store.closeEvents();
      await jobs.database.close();
      await connect(port: port);
    }

    await reopen(port: _InterruptRemoteReadback());
    final id = await remote('jellyfin', 'a', 'item');
    final interrupted =
        await invoke('media.identity.bind_batch', bind(id, 'bind'));
    expect((interrupted as Failed).failure.code, FailureCode.unavailable);
    expect(
        (await scopedEpisodeMapping(
            classic, 'jellyfin', 'a', 'item'))!['dandanplay_episode_id'],
        7101);
    final committed = await classic.query('jellyfin_episode_mapping');
    await reopen();
    await call('media.identity.bind_batch', bind(id, 'bind'));
    expect(await classic.query('jellyfin_episode_mapping'), committed);
    await reopen(port: _InterruptRemoteReadback());
    final undoInterrupted =
        await invoke('media.identity.unbind_batch', undo(id, 'undo'));
    expect((undoInterrupted as Failed).failure.code, FailureCode.unavailable);
    expect(await classic.query('jellyfin_episode_mapping'), isEmpty);
    await reopen();
    final receipt = await call('media.identity.unbind_batch', undo(id, 'undo'));
    expect((receipt['entries'] as List).single['classicProjection'],
        everyElement(containsPair('restored', true)));
    expect(
        await call('media.identity.unbind_batch', undo(id, 'undo')), receipt);
    print(
        'X17 remote readback interruption: bind committed once=true; undo already restored before restart=true; pending outbox recovered; persisted receipt.restored=true');
  });

  test(
      'Mapping and journal insert roll back together; same request retries safely',
      () async {
    final id = await remote('jellyfin', 'a', 'item');
    await classic.execute('''CREATE TABLE next_remote_projection_journal (
      projection_id TEXT NOT NULL, locator TEXT NOT NULL, type TEXT NOT NULL,
      episode_key TEXT NOT NULL, before_episode TEXT, after_episode TEXT NOT NULL,
      before_anime TEXT, after_anime TEXT NOT NULL, state TEXT NOT NULL,
      PRIMARY KEY(projection_id, locator))''');
    await classic.execute(
        "CREATE TRIGGER interrupt_remote_journal BEFORE INSERT ON next_remote_projection_journal BEGIN SELECT RAISE(ABORT, 'injected interruption'); END");
    final result = await invoke('media.identity.bind_batch', bind(id, 'bind'));
    expect(result, isA<Failed>());
    final table = await classic.rawQuery(
        "SELECT name FROM sqlite_master WHERE name='jellyfin_episode_mapping'");
    expect(table, isEmpty); // Schema and rows also rolled back.
    expect((await store.identity(id))['bindings'],
        everyElement(containsPair('status', 'accepted')));
    await classic.execute('DROP TRIGGER interrupt_remote_journal');
    await call('media.identity.bind_batch', bind(id, 'bind'));
    await call('media.identity.unbind_batch', undo(id, 'undo'));
    expect(await classic.query('jellyfin_episode_mapping'), isEmpty);
    print(
        'X17 interruption: Classic schema/mapping/journal rolled back=true; Next binding durable=true; same request retry/undo=true');
  });
}

final class _InterruptRemoteReadback implements ReversibleClassicMetadataPort {
  final port = WatchHistoryMetadataPort(changed: () async {});
  bool first = true;
  @override
  Future<List<JsonMap>> history() => port.history();
  @override
  Future<void> apply(String locator, JsonMap fields) =>
      port.apply(locator, fields);
  @override
  Future<JsonMap> projectionOutcome(String locator, JsonMap fields) =>
      port.projectionOutcome(locator, fields);
  @override
  Future<bool> verify(String locator, JsonMap fields) async {
    if (first) {
      first = false;
      return false;
    }
    return port.verify(locator, fields);
  }
}

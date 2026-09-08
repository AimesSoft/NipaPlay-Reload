// Data preservation regressions for the unified database.
// Run ONLY on a disposable GitHub-hosted Linux runner. No real user fixtures.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/anime_episode_relation.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/anime_info/anime_info_service.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:nipaplay/utils/dandanplay_auth.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const ddp = AniEpiRltType.dandanplay;
const bgm = AniEpiRltType.bangumi;
final hash = Uint8List.fromList(List<int>.generate(16, (i) => i));

Future<void> seed(AniEpiRltType type, int anime, List<int> episodes) =>
    DatabaseService.upsertSourceAnimeEpisodeRelation(
      type, AniEpiRlt(animeId: anime, episodeIds: episodes));

void main() {
  final root = Platform.environment['NIPAPLAY_DATA_SAFETY_ROOT'];
  final runnerTemp = Platform.environment['RUNNER_TEMP'];
  if (Platform.environment['GITHUB_ACTIONS'] != 'true' ||
      !Platform.isLinux || root == null || runnerTemp == null ||
      !root.startsWith('$runnerTemp/') ||
      Platform.environment['XDG_DATA_HOME'] != '$root/xdg-data') {
    if (root != null) {
      throw StateError('Data safety tests require isolated runner directories.');
    }
    test('data safety requires a disposable GitHub Actions runner', () {},
        skip: 'Uses real SQLite and storage services with synthetic data only.');
    return;
  }
  TestWidgetsFlutterBinding.ensureInitialized();
  var counter = 0;
  late String dbPath;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'linux_storage_migration_completed': true,
      'linux_storage_migration_version': 1,
      'dandanplay_app_secret': 'synthetic-review-secret',
      'dandanplay_token': 'synthetic-review-token',
      'custom_storage_path': '/synthetic/previous-choice',
      'synthetic_favorites': '[10,20]',
    });
    await Directory(root).create(recursive: true);
    final appDir = await StorageService.getAppStorageDirectory();
    expect(appDir.path, startsWith('$root/'));
    for (final name in ['anime', 'episode']) {
      final directory = Directory('${appDir.path}/$name');
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    dbPath = '$root/new-${counter++}.db';
    await DatabaseService.initialize(dbPath);
  });
  tearDown(() async {
    await DatabaseService.close();
  });

  test('legacy history, JSON files and preferences survive new database writes', () async {
    final appDir = await StorageService.getAppStorageDirectory();
    final legacy = await WatchHistoryDatabase.instance.database;
    await legacy.insert('watch_history', {
      'file_path': '/synthetic/episode.mkv', 'media_key': 'synthetic-key',
      'anime_name': 'Synthetic legacy anime', 'episode_title': 'Episode 1',
      'anime_id': 10, 'episode_id': 101, 'watch_progress': 0.5,
      'last_position': 12345, 'duration': 24690,
      'last_watch_time': '2026-01-01T00:00:00Z', 'is_from_scan': 0,
    });
    await WatchHistoryDatabase.instance.close();
    final legacyFile = File('${appDir.path}/watch_history.db');
    final legacyBytes = await legacyFile.readAsBytes();
    final sentinels = <File, String>{};
    for (final name in ['watch_history.json', 'watch_history.json.bak.migrated',
        'favorites.json', 'media_library.json', 'sync_state.json']) {
      final file = File('${appDir.path}/$name');
      final contents = jsonEncode({'reviewFixture': name, 'position': 12345});
      await file.writeAsString(contents);
      sentinels[file] = contents;
    }
    final prefs = await SharedPreferences.getInstance();
    final preferencesBefore = {for (final key in prefs.getKeys()) key: prefs.get(key)};
    // Exercise onCreate with legacy fixtures already present, not a cached handle.
    await DatabaseService.close();
    dbPath = '$root/coexistence-fresh.db';
    await DatabaseService.initialize(dbPath);
    await seed(ddp, 10, [101, 102]);
    await seed(bgm, 20, [201]);
    await DatabaseService.linkSourceAnimeToCommonAnime(bgm, 20,
        (await DatabaseService.getCommonAnimeId(ddp, 10))!);
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    await DatabaseService.linkVideoAssetToEpisode(hash,
        (await DatabaseService.getCommonEpisodeId(ddp, 101))!);
    expect(await DandanplayAuth.getAppSecret(), 'synthetic-review-secret');
    final expectedSignature = base64Encode(sha256.convert(utf8.encode(
        'nipaplayv11700000000/api/v2/matchsynthetic-review-secret')).bytes);
    expect(DandanplayAuth.generateSignature(timestamp: 1700000000,
        apiPath: '/api/v2/match', appSecret: 'synthetic-review-secret'), expectedSignature);
    expect(await legacyFile.readAsBytes(), orderedEquals(legacyBytes));
    for (final entry in sentinels.entries) {
      expect(await entry.key.readAsString(), entry.value);
    }
    expect({for (final key in prefs.getKeys()) key: prefs.get(key)}, preferencesBefore);
    final reopened = await WatchHistoryDatabase.instance.database;
    expect((await reopened.query('watch_history')).single['last_position'], 12345);
    await WatchHistoryDatabase.instance.close();
  });

  test('incremental refresh retains omitted episodes and asset links', () async {
    await seed(ddp, 10, [101, 102]);
    final original = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    await DatabaseService.linkVideoAssetToEpisode(hash, original);
    await seed(ddp, 10, [102, 103]);
    expect(await DatabaseService.getAllEpisodeIds(ddp, 10), {101, 102, 103});
    expect(await DatabaseService.getCommonEpisodeId(ddp, 101), original);
    expect(await DatabaseService.getDandanplayEpisodeIdByAssetHash(hash), 101);
  });

  test('conflicting link rolls back without deleting either anime', () async {
    await seed(ddp, 10, [101]);
    await seed(ddp, 11, [111]);
    final first = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    final second = (await DatabaseService.getCommonAnimeId(ddp, 11))!;
    await expectLater(DatabaseService.linkSourceAnimeToCommonAnime(ddp, 11, first), throwsA(anything));
    expect(await DatabaseService.getCommonAnimeId(ddp, 10), first);
    expect(await DatabaseService.getCommonAnimeId(ddp, 11), second);
    expect(await DatabaseService.hasEpisode(ddp, 101), isTrue);
    expect(await DatabaseService.hasEpisode(ddp, 111), isTrue);
  });

  test('merging matched episodes preserves playback lookup for previously linked assets', () async {
    await seed(ddp, 10, [101]);
    await seed(bgm, 20, [201]);
    final commonAnime = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    await DatabaseService.linkSourceAnimeToCommonAnime(bgm, 20, commonAnime);
    final ddpEpisode = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    final bgmEpisode = (await DatabaseService.getCommonEpisodeId(bgm, 201))!;
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    await DatabaseService.linkVideoAssetToEpisode(hash, bgmEpisode);
    await DatabaseService.linkSourceEpisodeToCommonEpisode(bgm, 201, ddpEpisode);
    print('MERGE: assetEpisode=${await DatabaseService.getCommonEpisodeIdByAssetHash(hash)}, '
        'mergedEpisode=$ddpEpisode, ddpLookup=${await DatabaseService.getDandanplayEpisodeIdByAssetHash(hash)}');
    expect(await DatabaseService.getDandanplayEpisodeIdByAssetHash(hash), 101,
        reason: 'Existing asset must follow the common episode when the sources are merged.');
  });

  test('episode relink preserves user JSON and does not reuse it for an unrelated episode', () async {
    await seed(ddp, 10, [101]);
    await seed(bgm, 20, [201]);
    final commonAnime = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    await DatabaseService.linkSourceAnimeToCommonAnime(bgm, 20, commonAnime);
    final target = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    final old = (await DatabaseService.getCommonEpisodeId(bgm, 201))!;
    final appDir = await StorageService.getAppStorageDirectory();
    await Directory('${appDir.path}/episode').create(recursive: true);
    await saveJsonToFile(JsonFileType.episode, old,
        {'isMatchedDandanplay': true, 'watchPosition': 76543, 'userNote': 'belongs to 201'});
    await DatabaseService.linkSourceEpisodeToCommonEpisode(bgm, 201, target);
    await seed(ddp, 10, [101, 102]);
    final unrelated = (await DatabaseService.getCommonEpisodeId(ddp, 102))!;
    final inheritedMatch = await getDandanplayEpisodeMatchStatus(unrelated);
    print('JSON: old=$old, merged=$target, newUnrelated=$unrelated, '
        'unrelatedInheritedMatch=$inheritedMatch, '
        'targetJsonExists=${await File('${appDir.path}/episode/$target.json').exists()}');
    expect(inheritedMatch, isFalse,
        reason: 'An unrelated newly inserted episode must not inherit another episode\'s saved user data.');
    expect(await readJsonFromFile(JsonFileType.episode, target), {
      'isMatchedDandanplay': true, 'watchPosition': 76543, 'userNote': 'belongs to 201',
    }, reason: 'Saved JSON must remain reachable after a common ID changes.');
    expect(await File('${appDir.path}/episode/$old.json').exists(), isTrue);
    expect(unrelated, isNot(old));
    await DatabaseService.close();
    await DatabaseService.initialize(dbPath);
    expect(await getDandanplayEpisodeMatchStatus(target), isTrue);
    expect(await getDandanplayEpisodeMatchStatus(old), isTrue);
  });

  test('normal asset refresh preserves previously stored SHA-256', () async {
    final sha = Uint8List.fromList(List<int>.filled(32, 42));
    await DatabaseService.upsertAssetRecord(DbAssetRecord(
        hashPre16MiBMd5: hash, size: 1024, codec: 'mkv', hashSha256: sha));
    await DatabaseService.upsertAssetRecord(DbAssetRecord(
        hashPre16MiBMd5: hash, size: 1024, codec: 'mkv'));
    expect((await DatabaseService.getAssetRecord(hash))!.hashSha256, orderedEquals(sha),
        reason: 'A refresh without a newly computed SHA-256 must retain the saved value.');
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    final unchanged = (await DatabaseService.getAssetRecord(hash))!;
    expect(unchanged.size, 1024);
    expect(unchanged.codec, 'mkv');
    expect(unchanged.hashSha256, orderedEquals(sha));
  });

  test('anime merge preserves both JSON documents and resolves old IDs after restart', () async {
    await seed(ddp, 10, [101]);
    await seed(bgm, 20, [201]);
    final target = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    final old = (await DatabaseService.getCommonAnimeId(bgm, 20))!;
    await saveJsonToFile(JsonFileType.anime, target,
        {'title': 'target title', 'settings': {'cover': 'target.png'}});
    await saveJsonToFile(JsonFileType.anime, old,
        {'title': 'source title', 'settings': {'description': 'user description'}});
    final appDir = await StorageService.getAppStorageDirectory();
    final sourceFile = File('${appDir.path}/anime/$old.json');
    final sourceBytes = await sourceFile.readAsBytes();
    await DatabaseService.linkSourceAnimeToCommonAnime(bgm, 20, target);
    await seed(ddp, 30, [301]);
    expect(await DatabaseService.getCommonAnimeId(ddp, 30), isNot(old));
    await DatabaseService.close();
    await DatabaseService.initialize(dbPath);
    expect(await readJsonFromFile(JsonFileType.anime, old), {
      'title': 'target title',
      'settings': {'cover': 'target.png', 'description': 'user description'},
    });
    expect(await sourceFile.readAsBytes(), orderedEquals(sourceBytes));
    expect(await DatabaseService.getCommonAnimeId(AniEpiRltType.common, old), target);
    expect(await DatabaseService.getSourceAnimeId(ddp, old), 10);
    expect(await DatabaseService.getAllAnimeIds(AniEpiRltType.common), isNot(contains(old)));
  });

  test('repeated merges and writes through old IDs retain the most recent user changes', () async {
    await seed(ddp, 10, [101]);
    final original = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await saveJsonToFile(JsonFileType.episode, original,
        {'nested': {'position': 100, 'note': 'keep'}, 'isMatchedDandanplay': true});
    await DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, 9000);
    await saveJsonToFile(JsonFileType.episode, original, {'nested': {'position': 200}});
    await DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, 8000);
    await DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, original);
    await DatabaseService.close();
    await DatabaseService.initialize(dbPath);
    expect(await readJsonFromFile(JsonFileType.episode, original), {
      'nested': {'position': 200, 'note': 'keep'}, 'isMatchedDandanplay': true,
    });
    expect(await DatabaseService.getCommonEpisodeId(ddp, 101), 8000);
    expect(await DatabaseService.getSourceEpisodeId(ddp, original), 101);
    final anime = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    expect(await DatabaseService.getAllEpisodeIds(AniEpiRltType.common, anime), {8000});
  });

  test('a conflict in the second source rolls back the first source and all metadata', () async {
    await seed(ddp, 10, [101, 102]);
    await seed(bgm, 20, [201, 202]);
    final anime = (await DatabaseService.getCommonAnimeId(ddp, 10))!;
    await DatabaseService.linkSourceAnimeToCommonAnime(bgm, 20, anime);
    final old = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await DatabaseService.linkSourceEpisodeToCommonEpisode(bgm, 201, old);
    final target = (await DatabaseService.getCommonEpisodeId(bgm, 202))!;
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    await DatabaseService.linkVideoAssetToEpisode(hash, old);
    await saveJsonToFile(JsonFileType.episode, old, {'note': 'original user data'});
    await expectLater(DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, target),
        throwsA(anything));
    expect(await DatabaseService.getCommonEpisodeId(ddp, 101), old);
    expect(await DatabaseService.getCommonEpisodeId(bgm, 201), old);
    expect(await DatabaseService.getCommonEpisodeId(bgm, 202), target);
    expect(await DatabaseService.getCommonEpisodeIdByAssetHash(hash), old);
    expect(await readJsonFromFile(JsonFileType.episode, old), {'note': 'original user data'});
    expect(await readJsonFromFile(JsonFileType.episode, target), isNull);
  });

  test('upgrading an existing v2 unified database preserves every relation and JSON file', () async {
    await DatabaseService.close();
    dbPath = '$root/unified-v2.db';
    final schema = await File('test/database/fixtures/schema_v2.sql').readAsString();
    final v2 = await databaseFactoryFfi.openDatabase(dbPath, options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) async {
        for (final sql in schema.split(';')) {
          if (sql.trim().isNotEmpty) await db.execute(sql);
        }
      },
    ));
    await v2.insert('anime', {'anime_id': 11});
    await v2.insert('episode', {'episode_id': 21, 'anime_id': 11});
    await v2.insert('dandanplay_anime', {'dandanplay_anime_id': 10, 'anime_id': 11});
    await v2.insert('dandanplay_episode', {
      'dandanplay_episode_id': 101, 'dandanplay_anime_id': 10, 'episode_id': 21,
    });
    await v2.insert('bangumi_anime', {'bangumi_anime_id': 20, 'anime_id': 11});
    await v2.insert('bangumi_episode', {
      'bangumi_episode_id': 201, 'bangumi_anime_id': 20, 'episode_id': 21,
    });
    await v2.insert('asset', {'asset_pre16mib_md5': hash, 'asset_size': 123});
    await v2.insert('asset_episode', {'asset_pre16mib_md5': hash, 'episode_id': 21});
    await v2.insert('net_asset', {'net_url': 'https://synthetic.invalid/video', 'asset_pre16mib_md5': hash});
    await v2.insert('path_asset', {'asset_name_no_ext': 'fixture',
      'updated_at': '2026-01-01T00:00:00Z', 'asset_pre16mib_md5': hash});
    final tables = ['dandanplay_anime', 'dandanplay_episode', 'bangumi_anime',
      'bangumi_episode', 'asset', 'asset_episode', 'net_asset', 'path_asset'];
    final before = {for (final table in tables) table: await v2.query(table)};
    await v2.close();
    final appDir = await StorageService.getAppStorageDirectory();
    final jsonFile = File('${appDir.path}/episode/21.json');
    await jsonFile.parent.create(recursive: true);
    await jsonFile.writeAsString('{"watchPosition":12345}');
    await DatabaseService.initialize(dbPath);
    final upgraded = await databaseFactoryFfi.openDatabase(dbPath);
    expect(await upgraded.getVersion(), 3);
    for (final table in tables) {
      expect(await upgraded.query(table), before[table], reason: table);
    }
    expect(await upgraded.query('anime', columns: ['anime_id']), [{'anime_id': 11}]);
    expect(await upgraded.query('episode', columns: ['episode_id', 'anime_id']),
        [{'episode_id': 21, 'anime_id': 11}]);
    expect(await upgraded.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(await jsonFile.readAsString(), '{"watchPosition":12345}');
    expect(await readJsonFromFile(JsonFileType.episode, 21), {'watchPosition': 12345});
    expect(await DatabaseService.getDandanplayEpisodeIdByAssetHash(hash), 101);
  });

  test('a legacy database passed by mistake is rejected without changing its version or data', () async {
    final wrongPath = '$root/wrong-legacy.db';
    final legacy = await databaseFactoryFfi.openDatabase(wrongPath, options: OpenDatabaseOptions(
      version: 2,
      onCreate: (db, _) => db.execute('CREATE TABLE watch_history (position INTEGER)'),
    ));
    await legacy.insert('watch_history', {'position': 12345});
    await legacy.close();
    final before = await File(wrongPath).readAsBytes();
    await expectLater(DatabaseService.initialize(wrongPath), throwsA(anything));
    expect(await File(wrongPath).readAsBytes(), orderedEquals(before));
    final reopened = await databaseFactoryFfi.openDatabase(wrongPath);
    expect(await reopened.getVersion(), 2);
    expect(await reopened.query('watch_history'), [{'position': 12345}]);
    await reopened.close();
    // The failed initialization must also leave the previous unified handle usable.
    await seed(ddp, 10, [101]);
    expect(await DatabaseService.hasEpisode(ddp, 101), isTrue);
  });

  test('invalid JSON updates do not truncate saved user files', () async {
    await seed(ddp, 10, [101]);
    final id = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await saveJsonToFile(JsonFileType.episode, id, {'position': 12345});
    final appDir = await StorageService.getAppStorageDirectory();
    final file = File('${appDir.path}/episode/$id.json');
    final before = await file.readAsBytes();
    await expectLater(saveJsonToFile(JsonFileType.episode, id, {'invalid': double.nan}),
        throwsA(anything));
    expect(await file.readAsBytes(), orderedEquals(before));
    expect(await readJsonFromFile(JsonFileType.episode, id), {'position': 12345});
  });

  test('concurrent user updates and an ID merge preserve every field', () async {
    await seed(ddp, 10, [101]);
    final old = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await Future.wait([
      saveJsonToFile(JsonFileType.episode, old, {'first': 1}),
      DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, 9000),
      saveJsonToFile(JsonFileType.episode, old, {'second': 2}),
    ]);
    expect(await readJsonFromFile(JsonFileType.episode, 9000), {'first': 1, 'second': 2});
  });

  test('corrupt source JSON aborts an update without overwriting the canonical file', () async {
    await seed(ddp, 10, [101]);
    final old = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    await saveJsonToFile(JsonFileType.episode, old, {'original': 'keep'});
    await DatabaseService.linkSourceEpisodeToCommonEpisode(ddp, 101, 9000);
    await saveJsonToFile(JsonFileType.episode, 9000, {'updated': 'keep too'});
    final appDir = await StorageService.getAppStorageDirectory();
    final target = File('${appDir.path}/episode/9000.json');
    final before = await target.readAsBytes();
    final source = File('${appDir.path}/episode/$old.json');
    await source.writeAsString('{incomplete');
    await expectLater(saveJsonToFile(JsonFileType.episode, 9000, {'updated': 'overwrite'}),
        throwsA(isA<FormatException>()));
    expect(await target.readAsBytes(), orderedEquals(before));
    expect(await source.readAsString(), '{incomplete');
  });

  test('an unmatched shared episode stays intact until its last asset is relinked', () async {
    await seed(ddp, 10, [101]);
    final target = (await DatabaseService.getCommonEpisodeId(ddp, 101))!;
    final secondHash = Uint8List.fromList(List<int>.filled(16, 42));
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: hash));
    final old = (await DatabaseService.getCommonEpisodeIdByAssetHash(hash))!;
    await DatabaseService.upsertAssetRecord(DbAssetRecord(hashPre16MiBMd5: secondHash));
    await DatabaseService.linkVideoAssetToEpisode(secondHash, old);
    await saveJsonToFile(JsonFileType.episode, old, {'note': 'unmatched user setting'});
    await DatabaseService.linkVideoAssetToEpisode(hash, target);
    expect(await DatabaseService.getCommonEpisodeIdByAssetHash(secondHash), old);
    expect(await DatabaseService.getCommonEpisodeId(AniEpiRltType.common, old), old);
    await DatabaseService.linkVideoAssetToEpisode(secondHash, target);
    expect(await DatabaseService.getDandanplayEpisodeIdByAssetHash(secondHash), 101);
    expect(await readJsonFromFile(JsonFileType.episode, target), {'note': 'unmatched user setting'});
  });
}

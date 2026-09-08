// Review-only regression tests for PR #869 at d4b44e60.
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
  final root = Platform.environment['NIPAPLAY_REVIEW_ROOT'];
  final runnerTemp = Platform.environment['RUNNER_TEMP'];
  if (Platform.environment['GITHUB_ACTIONS'] != 'true' ||
      !Platform.isLinux || root == null || runnerTemp == null ||
      !root.startsWith('$runnerTemp/') ||
      Platform.environment['XDG_DATA_HOME'] != '$root/xdg-data') {
    throw StateError('This review suite must only run in isolated GitHub Actions.');
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
    dbPath = '$root/new-${counter++}.db';
    await DatabaseService.initialize(dbPath);
  });
  tearDown(() async {
    await (await databaseFactoryFfi.openDatabase(dbPath)).close();
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
    expect(await File('${appDir.path}/episode/$target.json').exists(), isTrue,
        reason: 'Saved JSON must remain reachable after a common ID changes.');
  });

  test('normal asset refresh preserves previously stored SHA-256', () async {
    final sha = Uint8List.fromList(List<int>.filled(32, 42));
    await DatabaseService.upsertAssetRecord(DbAssetRecord(
        hashPre16MiBMd5: hash, size: 1024, codec: 'mkv', hashSha256: sha));
    await DatabaseService.upsertAssetRecord(DbAssetRecord(
        hashPre16MiBMd5: hash, size: 1024, codec: 'mkv'));
    expect((await DatabaseService.getAssetRecord(hash))!.hashSha256, orderedEquals(sha),
        reason: 'A refresh without a newly computed SHA-256 must retain the saved value.');
  });
}

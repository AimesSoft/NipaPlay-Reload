
// test/database/database_test.dart
// 数据库相关测试

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/database/anime_episode_relation.dart';
import 'package:nipaplay/models/database/asset_record.dart';
import 'package:nipaplay/services/database/database_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upsert 与 link 方法建立统一 Anime, Episode 和视频资产关联', () async {

    void session(String message) => debugPrint('\n=== $message ===');
    void log(String message) => debugPrint('[Database upsert/link] $message');
    Future<void> endSession(String message) async {
      debugPrint('--- $message 结束: Anime/Episode 表完整状态 ---');
      await DatabaseService.printAnimeEpisodeTables();
    }


    session('初始化内存数据库');
    await DatabaseService.initialize(inMemoryDatabasePath);
    log(await DatabaseService.getTableNames());
    await endSession('初始化内存数据库');


    session('首次写入');
    log('写入 Dandanplay Anime=10, Episodes=[101, 102]');
    await DatabaseService.upsertAnimeEpisodeRelation(
      DbAnimeEpisodeRelation(
        animeId: 10,
        episodeIds: const <int>[101, 102],
      ),
      DbAnimeEpisodeRelationType.dandanplay,
    );
    log('写入 Bangumi Anime=20, Episodes=[201, 202]');
    await DatabaseService.upsertAnimeEpisodeRelation(
      DbAnimeEpisodeRelation(
        animeId: 20,
        episodeIds: const <int>[201, 202],
      ),
      DbAnimeEpisodeRelationType.bangumi,
    );

    final hasDandanplayAnime = await DatabaseService.hasAnime(
      DbAnimeEpisodeRelationType.dandanplay,
      10,
    );
    final hasBangumiAnime = await DatabaseService.hasAnime(
      DbAnimeEpisodeRelationType.bangumi,
      20,
    );
    final hasDandanplayEpisode = await DatabaseService.hasEpisode(
      DbAnimeEpisodeRelationType.dandanplay,
      101,
    );
    log(
      '首次 upsert: Dandanplay Anime=$hasDandanplayAnime, '
      'Bangumi Anime=$hasBangumiAnime, '
      'Dandanplay Episode 101=$hasDandanplayEpisode',
    );
    expect(hasDandanplayAnime, isTrue);
    expect(hasBangumiAnime, isTrue);
    expect(hasDandanplayEpisode, isTrue);
    await endSession('首次写入');


    session('增量写入');
    log('增量写入 Dandanplay Anime=10, Episodes=[101, 102, 103]');
    await DatabaseService.upsertAnimeEpisodeRelation(
      DbAnimeEpisodeRelation(
        animeId: 10,
        episodeIds: const <int>[101, 102, 103],
      ),
      DbAnimeEpisodeRelationType.dandanplay,
    );
    final hasAddedEpisode = await DatabaseService.hasEpisode(
      DbAnimeEpisodeRelationType.dandanplay,
      103,
    );
    log('增量 upsert: Dandanplay Episode 103=$hasAddedEpisode');
    expect(hasAddedEpisode, isTrue);
    await endSession('增量写入');


    session('建立 Anime 关联');
    const targetAnimeId = 9000;
    log('关联 Dandanplay Anime 10 -> 通用 Anime $targetAnimeId');
    await DatabaseService.linkToAnime(
      DbAnimeEpisodeRelationType.dandanplay,
      10,
      targetAnimeId,
    );
    log('关联 Bangumi Anime 20 -> 通用 Anime $targetAnimeId');
    await DatabaseService.linkToAnime(
      DbAnimeEpisodeRelationType.bangumi,
      20,
      targetAnimeId,
    );
    final linkedCommonAnimeId = await DatabaseService.getCommonAnimeId(
      DbAnimeEpisodeRelationType.dandanplay,
      10,
    );
    final linkedBangumiAnimeId = linkedCommonAnimeId == null
        ? null
        : await DatabaseService.getSourceAnimeId(
            DbAnimeEpisodeRelationType.bangumi,
            linkedCommonAnimeId,
          );
    log(
      'Anime 关联查询: Dandanplay Episode 101 -> '
      'Bangumi Anime $linkedBangumiAnimeId',
    );
    expect(linkedBangumiAnimeId, 20);
    await endSession('建立 Anime 关联');


    session('建立 Episode 关联');
    const targetEpisodeId = 9101;
    log('关联 Dandanplay Episode 101 -> 通用 Episode $targetEpisodeId');
    await DatabaseService.linkToEpisode(
      DbAnimeEpisodeRelationType.dandanplay,
      101,
      targetEpisodeId,
    );
    log('关联 Bangumi Episode 201 -> 通用 Episode $targetEpisodeId');
    await DatabaseService.linkToEpisode(
      DbAnimeEpisodeRelationType.bangumi,
      201,
      targetEpisodeId,
    );
    final linkedCommonEpisodeId = await DatabaseService.getCommonEpisodeId(
      DbAnimeEpisodeRelationType.dandanplay,
      101,
    );
    final linkedBangumiEpisodeId = linkedCommonEpisodeId == null
        ? null
        : await DatabaseService.getSourceEpisodeId(
            DbAnimeEpisodeRelationType.bangumi,
            linkedCommonEpisodeId,
          );
    log(
      'Episode 关联查询: Dandanplay Episode 101 -> '
      'Bangumi Episode $linkedBangumiEpisodeId',
    );
    expect(linkedBangumiEpisodeId, 201);
    await endSession('建立 Episode 关联');


    session('建立视频资产关联');
    final assetHash = Uint8List.fromList(
      List<int>.generate(16, (index) => index),
    );
    log('写入资产: hash=${_toHex(assetHash)}, size=1024, codec=mkv');
    await DatabaseService.upsertAssetRecord(
      DbAssetRecord(
        hashPre16MiBMd5: assetHash,
        size: 1024,
        codec: 'mkv',
      ),
    );
    log('关联资产 -> 通用 Episode $targetEpisodeId');
    await DatabaseService.linkVideoAssetToEpisode(
      assetHash,
      targetEpisodeId,
    );
    final assetCommonEpisodeId =
        await DatabaseService.getCommonEpisodeIdByAssetHash(assetHash);
    final linkedDandanplayEpisodeId = assetCommonEpisodeId == null
        ? null
        : await DatabaseService.getSourceEpisodeId(
            DbAnimeEpisodeRelationType.dandanplay,
            assetCommonEpisodeId,
          );
    log(
      '资产关联查询: hash=${_toHex(assetHash)} -> '
      'Dandanplay Episode $linkedDandanplayEpisodeId',
    );
    expect(linkedDandanplayEpisodeId, 101);

    log('写入资产设置: linkOptions=1, offsets=1.5/2.0');
    await DatabaseService.setAssetLinkOptions(
      assetHash,
      DatabaseService.linkDandanplay,
    );
    await DatabaseService.setAssetDanmakuOffsets(
      assetHash,
      dandanplay: 1.5,
      user: 2.0,
    );
    final assetEpisodeInfo =
        await DatabaseService.getAssetEpisodeInfo(assetHash);
    log(
      '资产设置查询: linkOptions=${assetEpisodeInfo?.linkOptions}, '
      'DandanplayOffset=${assetEpisodeInfo?.dandanplayDanmakuOffset}, '
      'UserOffset=${assetEpisodeInfo?.userDanmakuOffset}',
    );
    expect(assetEpisodeInfo, isNotNull);
    expect(assetEpisodeInfo!.linkOptions, DatabaseService.linkDandanplay);
    expect(assetEpisodeInfo.dandanplayDanmakuOffset, 1.5);
    expect(assetEpisodeInfo.userDanmakuOffset, 2.0);
    await endSession('建立视频资产关联');
    log('全部 upsert/link 断言通过');
  });
}

String _toHex(Uint8List bytes) => bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

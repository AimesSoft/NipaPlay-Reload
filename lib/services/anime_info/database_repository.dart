
// lib/services/anime_info/database_repository.dart
// 主要用于 AnimeInfoService 的数据库操作

part of 'anime_info_service.dart';


class _DatabaseRepository {

  /// 1. 查看缓存文件是否存在, 如果不存在, 则打印提示信息并返回
  /// 2. 读取缓存文件, 解析 JSON, 提取 Anime ID 和 Episode ID 的对应关系
  /// 3. 将对应关系插入更新数据库
  static Future<void> refreshDandanplayAnimeRelationByCache(int ddpAniId) async {
    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/dandanplay/$ddpAniId.json');
    if (!await cacheFile.exists()) {
      _printLine(
        color(
          '未找到 Dandanplay Anime ${_val(ddpAniId)} 缓存: '
          '${_val(cacheFile.path)}',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final packageJson = _decodeAnimePackageCache(
      await cacheFile.readAsString(),
      'Dandanplay',
    );
    final relation = _parseAnimeEpisodeRelationDandanplay(packageJson);
    if (relation.animeId != ddpAniId) {
      throw FormatException(
        'Dandanplay Anime 缓存 ID 不一致: '
        '文件名=$ddpAniId, 内容=${relation.animeId}',
      );
    }

    await DatabaseService.upsertSourceAnimeEpisodeRelation(
      DbAnimeEpisodeRelationType.dandanplay,
      relation,
    );
    _printLine(
      '已从缓存更新 Dandanplay Anime ${_val(ddpAniId)} 关系, '
      'Episode 数量: ${_val(relation.episodeIds.length)}',
    );
  }

  /// 1. 查看缓存文件是否存在, 如果不存在, 则打印提示信息并返回
  /// 2. 读取缓存文件, 解析 JSON, 提取 Anime ID 和 Episode ID 的对应关系
  /// 3. 将对应关系插入更新数据库
  static Future<void> refreshBangumiAnimeRelationByCache(int bangumiAnimeId) async {

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/bangumi/$bangumiAnimeId.json');
    if (!await cacheFile.exists()) {
      _printLine(color('未找到 Bangumi Anime ${_val(bangumiAnimeId)} 缓存: ${_val(cacheFile.path)}', ColorCode.yellow));
      return;
    }

    final packageJson = _decodeAnimePackageCache(
      await cacheFile.readAsString(),
      'Bangumi',
    );
    final relation = _parseAnimeEpisodeRelationBangumi(packageJson);
    if (relation.animeId != bangumiAnimeId) {
      throw FormatException(
        'Bangumi Anime 缓存 ID 不一致: '
        '文件名=$bangumiAnimeId, 内容=${relation.animeId}',
      );
    }

    await DatabaseService.upsertSourceAnimeEpisodeRelation(
      DbAnimeEpisodeRelationType.bangumi,
      relation,
    );
    _printLine(
      '已从缓存更新 Bangumi Anime ${_val(bangumiAnimeId)} 关系, '
      'Episode 数量: ${_val(relation.episodeIds.length)}',
    );
  }
}

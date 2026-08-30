
part of 'anime_info_service.dart';


/// 获取动画信息的服务类
class _AnimeInfoRepository {

  static Future<String> debugAnimeEpisodeRelations({String? cacheRootPath}) async {
    final resolvedCacheRootPath = cacheRootPath ?? (await StorageService.getCacheDirectory()).path;
    final titles = await _loadAnimeEpisodeDebugTitles(resolvedCacheRootPath);
    return DatabaseService.buildAnimeEpisodeRelationReport(
      dandanplayAnimeTitles: titles.dandanplayAnime,
      bangumiAnimeTitles: titles.bangumiAnime,
      dandanplayEpisodeTitles: titles.dandanplayEpisode,
      bangumiEpisodeTitles: titles.bangumiEpisode,
    );
  }


  /// 通过文件信息保证数据库中存在该文件 hash <-> Dandanplay Episode 的关联关系,
  /// 期间如有必要会访问 API 获取必要数据.
  ///
  /// - 将资产记录插入或更新到 asset 表
  ///
  /// - 尝试用 hash 查找 Dandanplay Episode ID:
  /// - 如果没有找到 dandanplay epi id, 则继续尝试用文件信息访问 /api/v2/match API
  /// - 特别的, 如果 forceMatch 为 true, 则无论如何都访问 /api/v2/match API
  ///
  /// - 如果 API 匹配失败, 则打印提示信息并直接返回
  /// - 如果 API 匹配成功, 根据匹配到的 Dandanplay Episode ID 查询 dandanplay episode 表
  /// - 如果没有找到对应的记录, 则刷新 Dandanplay Anime 缓存和数据库关系
  /// - 确保数据库内有对应的 dandanplay_episode 记录后, 关联资产与剧集
  /// - 最后保存弹幕偏移量
  ///
  /// [fileInfo] 由调用方负责根据本地文件路径或 http(s) 远程文件地址 (例如 WebDAV 文件地址)
  /// 计算得到, 本方法不再关心文件地址的具体形式, 只消费已经算好的哈希/大小/文件名等信息.
  ///
  /// **整个过程随时打印详细执行信息, 方便调试和查看执行结果**
  static Future<void> identifyFileUseDandanplayMatch(FileInfo fileInfo, {bool forceMatch = false}) async {

    final fileName        = '${fileInfo.fileNameNoExtension}.${fileInfo.fileExtension}';
    final fileDisplayPath = '${fileInfo.fileDirectory}/$fileName';
    final fileHash        = fileInfo.filePre16MiBMd5Hash;
    final fileHashEncode  = encodeHex(fileHash);

    _printLine("");
    _printLine(color('===== 开始刷新文件的 Dandanplay 弹幕关联 =====', ColorCode.boldCyan));
    _printLine('文件地址: ${_val(fileDisplayPath)}');
    _printLine('文件名  : ${_val(fileName)}');
    _printLine('大小    : ${_val(_formatFileSize(fileInfo.fileSize))}');
    _printLine('哈希    : ${_val(fileHashEncode)}');
    _printLine('强制匹配: ${_val(forceMatch)}');

    // 将文件哈希等信息写入 asset 表
    await DatabaseService.upsertAssetRecord(fileInfo.toDbAssetRecord());

    _printLine(
      '[1/5] 资产记录已写入数据库: '
      '文件名 ${_val(fileName)}, '
      '哈希 ${_val(fileHashEncode)}, '
      '后缀 ${_val(fileInfo.fileExtension)}'
    );


    // ------------------------------ Dandanplay ---------------------------- //

    if (forceMatch) {
      const msg = '[2/5] 强制匹配模式已启用, 将跳过数据库检查并访问 Dandanplay API';
      _printLine(color(msg, ColorCode.yellow));
    }
    else {
      final id = await DatabaseService.getDandanplayEpisodeIdByAssetHash(fileHash);
      if (id != null) {
        final msg =
        '[2/5] 资产已匹配 Dandanplay 剧集: ${_val(id)}, '
        '跳过重复匹配: ${_val(fileHashEncode)}';
        _printLine(color(msg, ColorCode.green));
        return;
      }
      _printLine('[2/5] 资产尚未匹配 Dandanplay 剧集, 继续访问匹配 API');
    }

    // 根据文件信息访问 /api/v2/match API, 获取匹配结果
    final arg = fileInfo.toDandanplayFileMatchArgument();
    final res = await _APIRepository.requestDandanplayFileMatch(arg);
    if (res == null) {
      final msg =
      '[3/5] 文件未匹配到 Dandanplay 剧集: ${_val(fileHashEncode)}';
      _printLine(color(msg, ColorCode.red));
      return;
    }
    final ddpAniId = res.dandanplayAnimeId;
    final ddpEpiId = res.dandanplayEpisodeId;
    final danmakuOffset = res.danmakuOffset;
    _printLine(
      '[3/5] 匹配到 Dandanplay Anime: ${_val(ddpAniId)}, '
      'Episode: ${_val(ddpEpiId)}, '
      '弹幕偏移量: ${_val(danmakuOffset)}'
    );

    // 确保数据库中存在对应的 Dandanplay Episode 记录
    int? commonEpiId = await DatabaseService.getCommonEpisodeId(AniEpiRltType.dandanplay, ddpEpiId);
    if (commonEpiId == null) {

      _printLine(
        '[4/5] 数据库中未找到 Dandanplay Episode: ${_val(ddpEpiId)}, '
        '开始刷新 Dandanplay Anime 缓存和数据库关系'
      );

      await _APIRepository.refreshDandanplayAnimeCacheJson(ddpAniId);            // 访问 API 刷新缓存
      await _DatabaseRepository.refreshDandanplayAnimeRelationByCache(ddpAniId); // 利用缓存刷新数据库
      commonEpiId = await DatabaseService.getCommonEpisodeId(AniEpiRltType.dandanplay, ddpEpiId);
      if (commonEpiId == null) {
        _printLine(color('[4/5] 刷新后仍未找到 Dandanplay Episode: ${_val(ddpEpiId)}', ColorCode.red));
        return;
      }
      _printLine(
        '[4/5] Dandanplay Anime 缓存和数据库关系刷新完成, '
        'Common Episode ID: ${_val(commonEpiId)}'
      );
    } else {
      _printLine(
        '[4/5] 数据库中已存在 Dandanplay Episode: ${_val(ddpEpiId)}, '
        'Common Episode ID: ${_val(commonEpiId)}'
      );
    }

    // 将文件关联到 Dandanplay Episode
    await DatabaseService.linkVideoAssetToEpisode(fileHash, commonEpiId);
    _printLine(
      '[5/5] 文件已关联 Dandanplay Episode: ${_val(ddpEpiId)}, '
      'Common Episode ID: ${_val(commonEpiId)}, '
      '弹幕偏移量: ${_val(danmakuOffset)}'
    );

    // 设置参数
    await storeDandanplayEpisodeDanmakuOffset(fileHash, danmakuOffset);

    _printLine(color(
      '===== 刷新文件的 Dandanplay 弹幕关联完成: ${_val(fileDisplayPath)} =====',
      ColorCode.boldGreen
    ));
  }

  /// 关联 Dandanplay 和 Bangumi 番剧
  /// 1. 根据共通 Anime ID 查询 Dandanplay 与 Bangumi Anime ID
  /// 2. 任意一方不存在时打印提示并返回
  /// 3. 确保两侧缓存存在, 抽取 Episode 排序信息并建立对应关系
  /// 4. 匹配剧集使用两方较小的共通 Episode ID
  static Future<void> linkDandanplayBangumiAnime(int generalAnimeId) async {

    final ddpAniId = await DatabaseService.getSourceAnimeId(DbAnimeEpisodeRelationType.dandanplay, generalAnimeId);
    final bgmAniId = await DatabaseService.getSourceAnimeId(DbAnimeEpisodeRelationType.bangumi, generalAnimeId);
    if (ddpAniId == null || bgmAniId == null) {
      final missingSources = <String>[
        if (ddpAniId == null) 'Dandanplay',
        if (bgmAniId == null) 'Bangumi',
      ];
      _printLine(
        color(
          '共通 Anime ${_val(generalAnimeId)} 缺少 '
          '${missingSources.join(' / ')} 记录, 终止关联',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final cacheRoot = await StorageService.getCacheDirectory();
    final dandanplayCacheFile = File('${cacheRoot.path}/dandanplay/$ddpAniId.json');
    final bangumiCacheFile = File('${cacheRoot.path}/bangumi/$bgmAniId.json');

    final missingCacheFiles = <File>[
      if (!await dandanplayCacheFile.exists()) dandanplayCacheFile,
      if (!await bangumiCacheFile.exists()) bangumiCacheFile,
    ];
    if (missingCacheFiles.isNotEmpty) {
      _printLine(
        color(
          '缺少 Anime Package 缓存, 终止关联: '
          '${missingCacheFiles.map((file) => file.path).join(', ')}',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final dandanplayPackageJson = _decodeAnimePackageCache(
      await dandanplayCacheFile.readAsString(),
      'Dandanplay',
    );
    final bangumiPackageJson = _decodeAnimePackageCache(
      await bangumiCacheFile.readAsString(),
      'Bangumi',
    );
    final dandanplayPackage =_parseAnimeEpisodeRelationDandanplay(dandanplayPackageJson);
    final bangumiPackage = _parseAnimeEpisodeRelationBangumi(bangumiPackageJson);
    final episodeMatches = _getDandanplayBangumiEpisodeMatch(dandanplayPackageJson, bangumiPackageJson);

    await DatabaseService.upsertSourceAnimeEpisodeRelation(
      DbAnimeEpisodeRelationType.dandanplay,
      dandanplayPackage,
    );
    await DatabaseService.upsertSourceAnimeEpisodeRelation(
      DbAnimeEpisodeRelationType.bangumi,
      bangumiPackage,
    );

    var linkedCount = 0;
    for (final (dandanplayEpisodeId, bangumiEpisodeId) in episodeMatches) {
      if (dandanplayEpisodeId == null || bangumiEpisodeId == null) continue;

      final dandanplayCommonEpisodeId =
          await DatabaseService.getCommonEpisodeId(
        DbAnimeEpisodeRelationType.dandanplay,
        dandanplayEpisodeId,
      );
      final bangumiCommonEpisodeId =
          await DatabaseService.getCommonEpisodeId(
        DbAnimeEpisodeRelationType.bangumi,
        bangumiEpisodeId,
      );
      if (dandanplayCommonEpisodeId == null ||
          bangumiCommonEpisodeId == null) {
        throw StateError(
          '数据库中缺少待关联的 Episode 记录: '
          'Dandanplay=$dandanplayEpisodeId, Bangumi=$bangumiEpisodeId',
        );
      }
      final commonEpisodeId =
          dandanplayCommonEpisodeId < bangumiCommonEpisodeId
              ? dandanplayCommonEpisodeId
              : bangumiCommonEpisodeId;

      await DatabaseService.linkSourceEpisodeToCommonEpisode(
        DbAnimeEpisodeRelationType.dandanplay,
        dandanplayEpisodeId,
        commonEpisodeId,
      );
      await DatabaseService.linkSourceEpisodeToCommonEpisode(
        DbAnimeEpisodeRelationType.bangumi,
        bangumiEpisodeId,
        commonEpisodeId,
      );
      linkedCount++;
    }

    _printLine(
      '已关联 Dandanplay Anime ${_val(ddpAniId)} 与 Bangumi Anime ${_val(bgmAniId)}, '
      '共通 Anime ID: ${_val(generalAnimeId)}, 匹配剧集数: ${_val(linkedCount)}',
    );
  }

  /// 1. 查找 asset 表, 获取对应通用 Episode ID, 如果没有, 则打印提示信息并返回 null
  /// 2. 查找 dandanplay_episode 表, 获取对应的 Dandanplay Episode ID 和弹幕相关配置, 如果没有, 则打印提示信息并返回 null
  /// 3. 根据 Dandanplay Episode ID 查找 cache/danmaku/{ddpEpiId}.json, 如果没有, 则打印提示信息并返回 null
  /// 4. 返回含弹幕 JSON 类型数据
  static Future<Map<String, dynamic>?> getDandanplayDanmakuByAssetHash(Uint8List assetHash) async {

    final commonEpisodeId = await DatabaseService.getCommonEpisodeIdByAssetHash(assetHash);
    if (commonEpisodeId == null) {
      _printLine(color('视频资产没有关联共通 Episode', ColorCode.yellow));
      return null;
    }

    final ddpEpiId = await DatabaseService.getSourceEpisodeId(DbAnimeEpisodeRelationType.dandanplay, commonEpisodeId);
    if (ddpEpiId == null) {
      _printLine(color('共通 Episode ${_val(commonEpisodeId)} 没有 Dandanplay 记录', ColorCode.yellow));
      return null;
    }

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheFile = File('${cacheRoot.path}/danmaku/$ddpEpiId.json');
    if (!await cacheFile.exists()) {
      _printLine(color('未找到 Dandanplay Episode ${_val(ddpEpiId)} 弹幕缓存', ColorCode.yellow));
      return null;
    }

    // 解析 JSON 确保格式正确
    Map<String, dynamic>? parsedJson;
    try {
      parsedJson = jsonDecode(await cacheFile.readAsString());
      if (parsedJson is! Map) {
        throw const FormatException('Dandanplay 弹幕 JSON 格式无效');
      }
    } catch (error) {
      _printLine(color('Dandanplay Episode ${_val(ddpEpiId)} 弹幕 JSON 解析失败: $error', ColorCode.red));
      return null;
    }

    return parsedJson;
  }


  // ======================================================================== //

  /// 根据 DanDanPlay AnimeID 获取 BangumiTv ID
  static Future<int?> requestBangumiIdByDandanplayId(int ddpId) async {
    final details = await DandanplayService.getBangumiDetails(ddpId, useCache: false);
    final bangumi = details['bangumi'] is Map ? Map<String, dynamic>.from(details['bangumi'] as Map) : <String, dynamic>{};

    return AnimeInfoParse.getBangumiTvId(bangumi);
  }

  /// 根据 Bangumi TV 条目 ID 获取弹弹play 动画 ID
  static Future<int?> requestDandanplayIdByBangumiId(int bgmId) async {
    final details =
        await DandanplayService.getBangumiByBgmId(bgmId);
    if (details == null) return null;

    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    return AnimeInfoParse.toPositiveInt(bangumi['animeId'] ?? details['animeId']);
  }


  // ======================================================================== //
  // ======================================================================== //
  // ======================================================================== //


  static Future<_AnimeEpisodeDebugTitles> _loadAnimeEpisodeDebugTitles(
    String cacheRootPath,
  ) async {
    final titles = (
      dandanplayAnime: <int, String>{},
      bangumiAnime: <int, String>{},
      dandanplayEpisode: <int, String>{},
      bangumiEpisode: <int, String>{},
    );
    final dandanplayAnimeIds = await DatabaseService.getAllAnimeIds(
      DbAnimeEpisodeRelationType.dandanplay,
    );
    for (final animeId in dandanplayAnimeIds) {
      final file = File('$cacheRootPath/dandanplay/$animeId.json');
      if (!await file.exists()) continue;
      final package = _decodeAnimePackageCache(
        await file.readAsString(),
        file.path,
      );
      final anime = package['anime'];
      if (anime is Map) {
        final title = _dandanplayAnimeTitle(anime);
        if (title != null) titles.dandanplayAnime[animeId] = title;
      }
      _collectDebugEpisodeTitles(
        package,
        idKey: 'episodeId',
        titleKeys: const <String>['episodeTitle'],
        target: titles.dandanplayEpisode,
      );
    }

    final bangumiAnimeIds = await DatabaseService.getAllAnimeIds(
      DbAnimeEpisodeRelationType.bangumi,
    );
    for (final animeId in bangumiAnimeIds) {
      final file = File('$cacheRootPath/bangumi/$animeId.json');
      if (!await file.exists()) continue;
      final package = _decodeAnimePackageCache(
        await file.readAsString(),
        file.path,
      );
      final anime = package['anime'];
      if (anime is Map) {
        final title = _firstNonEmptyString(
          anime,
          const <String>['name_cn', 'name'],
        );
        if (title != null) titles.bangumiAnime[animeId] = title;
      }
      _collectDebugEpisodeTitles(
        package,
        idKey: 'id',
        titleKeys: const <String>['name_cn', 'name'],
        target: titles.bangumiEpisode,
      );
    }
    return titles;
  }

  static String? _dandanplayAnimeTitle(Map<dynamic, dynamic> anime) {
    final direct = _firstNonEmptyString(
      anime,
      const <String>['animeTitle', 'title'],
    );
    if (direct != null) return direct;

    final rawTitles = anime['titles'];
    if (rawTitles is! List) return null;
    for (final rawTitle in rawTitles) {
      if (rawTitle is! Map) continue;
      final title = rawTitle['title'];
      if (title is String && title.trim().isNotEmpty) return title;
    }
    return null;
  }

  static void _collectDebugEpisodeTitles(
    Map<String, dynamic> package, {
    required String idKey,
    required List<String> titleKeys,
    required Map<int, String> target,
  }) {
    final episodes = package['episodes'];
    if (episodes is! List) return;
    for (final episode in episodes) {
      if (episode is! Map || episode[idKey] is! num) continue;
      final title = _firstNonEmptyString(episode, titleKeys);
      if (title != null) {
        target[(episode[idKey] as num).toInt()] = title;
      }
    }
  }

  static String? _firstNonEmptyString(
    Map<dynamic, dynamic> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = source[key];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }



  /// 抽取两个 JSON 文件的 episode 排序信息, 相互匹配, 确立对应关系
  /// 返回 Set<(int?, int?)>, 其中第一个元素为 Dandanplay Episode ID, 第二个元素为对应的 Bangumi Episode ID
  static Set<(int?, int?)> _getDandanplayBangumiEpisodeMatch(Map<String, dynamic> ddpJson, Map<String, dynamic> bgmJson) {

    final dandanplayEpisodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
      ddpJson,
      episodeIdKey: 'episodeId',
      sortOrderKey: 'episodeNumber',
      sourceName: 'Dandanplay',
    );
    final bangumiEpisodeIdsBySortOrder = _parseEpisodeIdsBySortOrder(
      bgmJson,
      episodeIdKey: 'id',
      sortOrderKey: 'sort',
      sourceName: 'Bangumi',
    );

    final matches = <(int?, int?)>{};
    for (final entry in dandanplayEpisodeIdsBySortOrder.entries) {
      matches.add((
        entry.value,
        bangumiEpisodeIdsBySortOrder[entry.key],
      ));
    }
    for (final entry in bangumiEpisodeIdsBySortOrder.entries) {
      if (!dandanplayEpisodeIdsBySortOrder.containsKey(entry.key)) {
        matches.add((null, entry.value));
      }
    }
    return matches;
  }
}

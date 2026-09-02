
part of 'anime_info_service.dart';

class _APIRepository {

  /// 访问 Dandanplay API: /api/v2/match
  /// 获取文件匹配的 Episode ID 和对应 Anime ID
  static Future<DandanplayFileMatchResult?> requestDandanplayFileMatch(DandanplayFileMatchArgument arg) async {

    final stopwatch = Stopwatch()..start();

    DandanplayFileMatchResult? end(DandanplayFileMatchResult? result, String message) {
      final elapsed = _val('${stopwatch.elapsedMilliseconds}ms');
      stopwatch.stop();
      if (result != null)
      { _printLine(color('Dandanplay 文件匹配成功: $message, 总耗时: $elapsed', ColorCode.cyan));} 
      else
      { _printLine(color('Dandanplay 文件匹配失败: $message, 总耗时: $elapsed', ColorCode.red ));}
      return result;
    }

    _printLine(
      '${color('Dandanplay API 开始匹配文件', ColorCode.cyan)}: ${_val(arg.fileName)}, '
      '哈希: ${_val(arg.fileHash)}, '
      '大小: ${_val(_formatFileSize(arg.fileSize))}'
    );

    const apiPath = '/api/v2/match';
    final appSecret = await DandanplayService.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final response = await http.post(
      Uri.parse('${await DandanplayService.getApiBaseUrl()}$apiPath'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': DandanplayService.userAgent,
        'X-AppId': DandanplayService.appId,
        'X-Signature': DandanplayService.generateSignature(
          DandanplayService.appId,
          timestamp,
          apiPath,
          appSecret,
        ),
        'X-Timestamp': '$timestamp',
      },
      body: jsonEncode(<String, dynamic>{
        'fileName': arg.fileName,
        'fileHash': arg.fileHash,
        'fileSize': arg.fileSize,
        'matchMode': 'hashAndFileName',
      }),
    );
    if (response.statusCode != 200) {
      final error = response.headers['x-error-message'] ?? response.body;
      // throw Exception('弹弹play 文件匹配失败 (${response.statusCode}): $error');
      return end(null, 'HTTP ${response.statusCode}, 错误信息: $error');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('弹弹play 文件匹配响应格式无效');
    }
    final matches = decoded['matches'];
    if (matches is! List) return end(null, '响应格式无效');

    for (final rawMatch in matches) {
      if (rawMatch is! Map) continue;
      final match = Map<String, dynamic>.from(rawMatch);
      final animeId = AnimeInfoParse.toPositiveInt(match['animeId']);
      final episodeId = AnimeInfoParse.toPositiveInt(match['episodeId']);
      if (animeId != null && episodeId != null) {

        _printLine(
          'Dandanplay 文件匹配成功: '
          '总耗时: ${_val('${stopwatch.elapsedMilliseconds}ms')}',
        );

        final result = DandanplayFileMatchResult(
          dandanplayAnimeId: animeId,
          dandanplayEpisodeId: episodeId,
          danmakuOffset: match['shift'].toDouble(),
        );
        return end(result, '匹配成功');
      }
    }

    return end(null, '未找到匹配项');
  }

  /// 1. 根据 Dandanplay Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息
  /// 2. 将动画及其所有剧集整理成一个 JSON 对象
  /// 3. 将该 JSON 对象覆盖写入 `<应用数据根目录>/cache/dandanplay/{ddpAniId}.json`
  static Future<void> refreshDandanplayAnimeCacheJson(int ddpAniId) async {

    final stopwatch = Stopwatch()..start();

    final idStr = _val(ddpAniId);
    _printLine('开始刷新 $_ddpLabel Anime Package: $idStr');

    // 获取原始请求
    final packageJson = await _getDandanplayAnimePackageById(ddpAniId);
    if (packageJson == null) {
      final message = color(
        '未获取到对应 ID 的 Dandanplay Anime Package: $idStr'
        '耗时: ${_val('${stopwatch.elapsedMilliseconds}ms')}', ColorCode.red);
      _printLine(message);
      return;
    } else {
      _printLine(
        '已获取 Dandanplay Anime Package: $idStr, '
        '耗时: ${_val('${stopwatch.elapsedMilliseconds}ms')}',
      );
    }

    // 将 JSON 缓存到本地
    final cacheDirectory = Directory('${(await StorageService.getCacheDirectory()).path}/dandanplay');
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$ddpAniId.json');
    await cacheFile.writeAsString(const JsonEncoder.withIndent('  ').convert(packageJson));
    _printLine(
      '已缓存 $_ddpLabel Anime Package: ${_val(cacheFile.path)}, '
      '耗时: ${_val('${stopwatch.elapsedMilliseconds}ms')}'
    );
  }


  /// 1. 根据 Dandanplay Episode ID 访问 Dandanplay API 获取对应的弹幕 JSON 字符串, 如果失败, 则打印提示信息并返回
  /// 2. 将弹幕 JSON 字符串写入 cache/danmaku/{ddpEpiId}.json
  static Future<void> refreshDandanplayDanmakuCacheByEpisodeId(int ddpEpiId) async {

    String danmakuJson;
    try {
      danmakuJson = await _requestDandanplayDanmakuJson(ddpEpiId);
    } catch (error) {
      _printLine(color('获取 Dandanplay Episode ${_val(ddpEpiId)} 弹幕失败: $error', ColorCode.red));
      return;
    }

    final cacheRoot = await StorageService.getCacheDirectory();
    final cacheDirectory = Directory('${cacheRoot.path}/danmaku/dandanplay');
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$ddpEpiId.json');
    await cacheFile.writeAsString(danmakuJson);
    _printLine(
      '已缓存 Dandanplay Episode ${_val(ddpEpiId)} 弹幕: '
      '${_val(cacheFile.path)}',
    );
  }

  static Future<void> refreshDandanplayAnimeCacheByBangumiId(
    int bgmAniId,
  ) async {
    final details = await DandanplayService.getBangumiByBgmId(bgmAniId);
    if (details == null) {
      _printLine(
        color(
          '未找到 Bangumi Anime ${_val(bgmAniId)} 对应的 Dandanplay Anime',
          ColorCode.yellow,
        ),
      );
      return;
    }

    final bangumi = details['bangumi'];
    if (bangumi is! Map) {
      throw const FormatException('Dandanplay Bangumi 响应缺少 bangumi 对象');
    }
    final ddpAniId = AnimeInfoParse.toPositiveInt(
      bangumi['animeId'] ?? details['animeId'],
    );
    if (ddpAniId == null) {
      throw const FormatException(
        'Dandanplay Bangumi 响应缺少有效的 animeId',
      );
    }

    final anime = Map<String, dynamic>.from(bangumi)
      ..remove('episodes')
      ..['animeId'] = ddpAniId;
    final episodes = bangumi['episodes'] is List
        ? (bangumi['episodes'] as List)
            .whereType<Map>()
            .map((episode) => Map<String, dynamic>.from(episode))
            .toList()
        : const <Map<String, dynamic>>[];
    final packageJson = <String, dynamic>{
      'anime': anime,
      'episodes': episodes,
    };

    final cacheDirectory = Directory(
      '${(await StorageService.getCacheDirectory()).path}/dandanplay',
    );
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$ddpAniId.json');
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packageJson),
    );
    _printLine('已缓存 $_ddpLabel Anime Package: ${_val(cacheFile.path)}');
  }

  /// 1. 根据 Bangumi Anime ID 访问 API 获取对应的 Anime 及其所有 Episode 信息
  /// 2. 将动画及其所有剧集整理成一个 JSON 对象
  /// 3. 将该 JSON 对象覆盖写入 `<应用数据根目录>/cache/bangumi/{bangumiAnimeId}.json`
  static Future<void> refreshBangumiAnimeCacheJson(int bangumiAnimeId) async {

    final idStr = _val(bangumiAnimeId);
    _printLine('开始刷新 $_bgmLabel Anime Package: $idStr');

    final packageJson = await _getBangumiAnimePackageById(bangumiAnimeId);

    final cacheDirectory = Directory(
      '${(await StorageService.getCacheDirectory()).path}/bangumi',
    );
    await cacheDirectory.create(recursive: true);
    final cacheFile = File('${cacheDirectory.path}/$bangumiAnimeId.json');
    await cacheFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packageJson),
    );
    _printLine('已缓存 $_bgmLabel Anime Package: ${_val(cacheFile.path)}');
  }

  static Future<String> _requestDandanplayDanmakuJson(int ddpEpiId) async {
    final apiPath = '/api/v2/comment/$ddpEpiId';
    final baseUrl = await NetworkSettings.getDandanplayServer();
    final appSecret = await DandanplayAuth.getAppSecret();
    final timestamp =
        (DateTime.now().toUtc().millisecondsSinceEpoch / 1000).round();
    final uri = Uri.parse('$baseUrl$apiPath').replace(
      queryParameters: const <String, String>{
        'withRelated': 'true',
      },
    );
    final response = await http.get(
      uri,
      headers: <String, String>{
        'Accept': 'application/json',
        'User-Agent': DandanplayAuth.userAgent,
        'X-AppId': DandanplayAuth.appId,
        'X-AppSecret': appSecret,
        'X-Signature': DandanplayAuth.generateSignature(
          timestamp: timestamp,
          apiPath: apiPath,
          appSecret: appSecret,
        ),
        'X-Timestamp': '$timestamp',
      },
    );
    if (response.statusCode != 200) {
      final error = response.headers['x-error-message'] ?? response.body;
      throw Exception(
        '弹弹play弹幕请求失败 (${response.statusCode}): $error',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['comments'] is! List) {
      throw const FormatException('弹弹play弹幕响应格式无效');
    }
    return response.body;
  }

  static Future<Map<String, dynamic>> _getBangumiAnimePackageById(
    int bangumiAnimeId,
  ) async {
    final anime = await BangumiApiService.getPublicSubject(bangumiAnimeId);
    final returnedAnimeId = AnimeInfoParse.toPositiveInt(anime['id']);
    if (returnedAnimeId == null) {
      throw const FormatException('Bangumi Anime Package 缺少有效的 id');
    }
    final episodes =
        await BangumiApiService.getPublicSubjectEpisodes(bangumiAnimeId);
    return <String, dynamic>{
      'anime': anime,
      'episodes': episodes,
    };
  }

  static Future<Map<String, dynamic>?> _getDandanplayAnimePackageById(
    int dandanplayAnimeId,
  ) async {
    final details = await DandanplayService.getBangumiDetails(
      dandanplayAnimeId,
      useCache: false,
    );
    final bangumi = details['bangumi'] is Map
        ? Map<String, dynamic>.from(details['bangumi'] as Map)
        : <String, dynamic>{};
    final returnedAnimeId = AnimeInfoParse.toPositiveInt(
      bangumi['animeId'] ?? details['animeId'],
    );
    if (returnedAnimeId == null) return null;

    final rawEpisodes = bangumi['episodes'] is List
        ? bangumi['episodes'] as List
        : (details['episodes'] is List
            ? details['episodes'] as List
            : const <dynamic>[]);
    final episodes = rawEpisodes
        .whereType<Map>()
        .map((episode) => Map<String, dynamic>.from(episode))
        .toList();
    final anime = Map<String, dynamic>.from(
      bangumi.isNotEmpty ? bangumi : details,
    )
      ..remove('episodes')
      ..['animeId'] = returnedAnimeId;
    return <String, dynamic>{
      'anime': anime,
      'episodes': episodes,
    };
  }

}
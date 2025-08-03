import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';

/// Emby剧集映射服务
/// 
/// 负责管理Emby剧集到DandanPlay剧集的智能映射
/// 包括：动画级映射、剧集级映射、自动推算和持久化存储
class EmbyEpisodeMappingService {
  static final EmbyEpisodeMappingService _instance = EmbyEpisodeMappingService._internal();
  factory EmbyEpisodeMappingService() => _instance;
  EmbyEpisodeMappingService._internal();

  static EmbyEpisodeMappingService get instance => _instance;

  Database? _database;
  
  // 缓存机制
  final Map<String, Map<String, dynamic>?> _animeMappingCache = {};
  final Map<String, int?> _episodePredictionCache = {};
  DateTime? _lastCacheClean;

  /// 初始化数据库
  Future<void> initialize() async {
    if (_database != null) return;
    
    final mainDb = await WatchHistoryDatabase.instance.database;
    _database = mainDb;

    // 创建映射表（简化版本，移除复杂的偏移量字段）
    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS emby_dandanplay_mapping (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emby_series_id TEXT NOT NULL,
        emby_series_name TEXT,
        emby_season_id TEXT,
        dandanplay_anime_id INTEGER NOT NULL,
        dandanplay_anime_title TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(emby_series_id, emby_season_id, dandanplay_anime_id)
      )
    ''');

    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS emby_episode_mapping (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        emby_episode_id TEXT NOT NULL UNIQUE,
        emby_index_number INTEGER,
        dandanplay_episode_id INTEGER NOT NULL,
        mapping_id INTEGER NOT NULL,
        confirmed BOOLEAN DEFAULT FALSE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (mapping_id) REFERENCES emby_dandanplay_mapping (id)
      )
    ''');

    debugPrint('[Emby映射服务] 数据库初始化完成');
    
    // 清理过期缓存
    _cleanExpiredCache();
  }

  /// 清理过期缓存
  void _cleanExpiredCache() {
    final now = DateTime.now();
    if (_lastCacheClean != null && now.difference(_lastCacheClean!).inMinutes < 30) {
      return; // 30分钟内不重复清理
    }
    
    _animeMappingCache.clear();
    _episodePredictionCache.clear();
    _lastCacheClean = now;
    debugPrint('[Emby映射服务] 缓存已清理');
  }

  /// 建立或更新动画级映射（简化版本）
  Future<int> createOrUpdateAnimeMapping({
    required String embySeriesId,
    required String embySeriesName,
    String? embySeasonId,
    required int dandanplayAnimeId,
    required String dandanplayAnimeTitle,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] 创建动画映射: $embySeriesName -> $dandanplayAnimeTitle');

    // 检查是否已存在映射
    final existing = await _database!.query(
      'emby_dandanplay_mapping',
      where: 'emby_series_id = ? AND emby_season_id = ? AND dandanplay_anime_id = ?',
      whereArgs: [embySeriesId, embySeasonId, dandanplayAnimeId],
    );

    if (existing.isNotEmpty) {
      // 更新现有映射
      final mappingId = existing.first['id'] as int;
      await _database!.update(
        'emby_dandanplay_mapping',
        {
          'emby_series_name': embySeriesName,
          'dandanplay_anime_title': dandanplayAnimeTitle,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [mappingId],
      );
      debugPrint('[Emby映射服务] 更新现有动画映射: ID=$mappingId');
      return mappingId;
    } else {
      // 创建新映射
      final mappingId = await _database!.insert(
        'emby_dandanplay_mapping',
        {
          'emby_series_id': embySeriesId,
          'emby_series_name': embySeriesName,
          'emby_season_id': embySeasonId,
          'dandanplay_anime_id': dandanplayAnimeId,
          'dandanplay_anime_title': dandanplayAnimeTitle,
        },
      );
      debugPrint('[Emby映射服务] 创建新动画映射: ID=$mappingId');
      return mappingId;
    }
  }

  /// 记录剧集级映射（增强版本，会自动优化基础偏移量）
  Future<void> recordEpisodeMapping({
    required String embyEpisodeId,
    required int embyIndexNumber,
    required int dandanplayEpisodeId,
    required int mappingId,
    bool confirmed = true,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] 记录剧集映射: Emby集$embyIndexNumber -> DandanPlay集$dandanplayEpisodeId');

    // 保存剧集映射
    await _database!.insert(
      'emby_episode_mapping',
      {
        'emby_episode_id': embyEpisodeId,
        'emby_index_number': embyIndexNumber,
        'dandanplay_episode_id': dandanplayEpisodeId,
        'mapping_id': mappingId,
        'confirmed': confirmed ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 清理相关缓存
    final cacheKeyToRemove = _episodePredictionCache.keys
        .where((key) => key.startsWith(embyEpisodeId))
        .toList();
    for (final key in cacheKeyToRemove) {
      _episodePredictionCache.remove(key);
    }

    // 如果是确认的映射，更新相关统计信息
    if (confirmed) {
      debugPrint('[Emby映射服务] 已确认剧集映射，更新统计信息');
    }
  }

  /// 获取动画映射（带缓存）
  Future<Map<String, dynamic>?> getAnimeMapping({
    required String embySeriesId,
    String? embySeasonId,
  }) async {
    await initialize();

    // 生成缓存键
    final cacheKey = '${embySeriesId}_${embySeasonId ?? 'null'}';
    
    // 检查缓存
    if (_animeMappingCache.containsKey(cacheKey)) {
      debugPrint('[Emby映射服务] 从缓存获取动画映射: $cacheKey');
      return _animeMappingCache[cacheKey];
    }

    final results = await _database!.query(
      'emby_dandanplay_mapping',
      where: 'emby_series_id = ? AND (emby_season_id = ? OR emby_season_id IS NULL)',
      whereArgs: [embySeriesId, embySeasonId],
      orderBy: 'emby_season_id IS NULL, updated_at DESC', // 优先匹配指定季节
    );

    final result = results.isNotEmpty ? results.first : null;
    
    // 缓存结果
    _animeMappingCache[cacheKey] = result;
    
    debugPrint('[Emby映射服务] 动画映射已缓存: $cacheKey');
    return result;
  }

  /// 获取剧集映射
  Future<Map<String, dynamic>?> getEpisodeMapping(String embyEpisodeId) async {
    await initialize();

    final results = await _database!.query(
      'emby_episode_mapping',
      where: 'emby_episode_id = ?',
      whereArgs: [embyEpisodeId],
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// 智能预测剧集映射（基于已有映射规律推算）
  Future<int?> predictEpisodeMapping({
    required EmbyEpisodeInfo embyEpisode,
  }) async {
    await initialize();

    // 如果没有集号信息，无法预测
    if (embyEpisode.indexNumber == null) {
      debugPrint('[Emby映射服务] Emby剧集缺少集号信息，无法预测映射');
      return null;
    }

    // 生成缓存键
    final cacheKey = '${embyEpisode.id}_${embyEpisode.indexNumber}';
    
    // 检查缓存
    if (_episodePredictionCache.containsKey(cacheKey)) {
      debugPrint('[Emby映射服务] 从缓存获取剧集预测: $cacheKey');
      return _episodePredictionCache[cacheKey];
    }

    debugPrint('[Emby映射服务] 预测剧集映射: ${embyEpisode.seriesName} 第${embyEpisode.indexNumber}集');

    // 1. 查找动画级映射
    final animeMapping = await getAnimeMapping(
      embySeriesId: embyEpisode.seriesId!,
      embySeasonId: embyEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[Emby映射服务] 未找到动画级映射');
      _episodePredictionCache[cacheKey] = null;
      return null;
    }

    final mappingId = animeMapping['id'] as int;

    // 2. 检查是否有直接的剧集映射
    final directMapping = await _database!.query(
      'emby_episode_mapping',
      where: 'emby_episode_id = ?',
      whereArgs: [embyEpisode.id],
    );

    if (directMapping.isNotEmpty) {
      final dandanplayEpisodeId = directMapping.first['dandanplay_episode_id'] as int;
      debugPrint('[Emby映射服务] 找到直接剧集映射: $dandanplayEpisodeId');
      _episodePredictionCache[cacheKey] = dandanplayEpisodeId;
      return dandanplayEpisodeId;
    }

    // 3. 基于已有映射推算剧集ID（核心逻辑）
    final targetEmbyIndex = embyEpisode.indexNumber!;
    
    // 查找同一个映射中已有的剧集映射记录，用于推算规律
    final existingMappings = await _database!.query(
      'emby_episode_mapping',
      where: 'mapping_id = ?',
      whereArgs: [mappingId],
      orderBy: 'emby_index_number ASC',
    );
    
    if (existingMappings.isNotEmpty) {
      // 使用已有的映射推算新的剧集ID
      final referenceMapping = existingMappings.first;
      final referenceEmbyIndex = referenceMapping['emby_index_number'] as int;
      final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
      
      // 计算偏移量并推算目标剧集ID
      final offset = targetEmbyIndex - referenceEmbyIndex;
      final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
      
      debugPrint('[Emby映射服务] 基于已有映射推算: 参考第$referenceEmbyIndex集(ID=$referenceDandanplayEpisodeId) -> 预测第$targetEmbyIndex集(ID=$predictedEpisodeId)');
      
      // 自动记录这个预测的映射
      await recordEpisodeMapping(
        embyEpisodeId: embyEpisode.id,
        embyIndexNumber: targetEmbyIndex,
        dandanplayEpisodeId: predictedEpisodeId,
        mappingId: mappingId,
        confirmed: false, // 标记为未确认的预测映射
      );
      
      // 缓存结果
      _episodePredictionCache[cacheKey] = predictedEpisodeId;
      return predictedEpisodeId;
    } else {
      debugPrint('[Emby映射服务] 没有已有映射记录，无法推算');
    }

    _episodePredictionCache[cacheKey] = null;
    return null;
  }

  /// 根据当前剧集获取下一集的映射
  Future<Map<String, dynamic>?> getNextEpisodeMapping({
    required EmbyEpisodeInfo currentEpisode,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] 查找下一集: ${currentEpisode.seriesName} 当前第${currentEpisode.indexNumber}集');

    // 查找同一系列的所有剧集映射
    final animeMapping = await getAnimeMapping(
      embySeriesId: currentEpisode.seriesId!,
      embySeasonId: currentEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[Emby映射服务] 未找到动画映射，无法预测下一集');
      return null;
    }

    // 查询数据库中该系列的所有剧集映射
    final episodeMappings = await _database!.rawQuery('''
      SELECT eem.*, edm.dandanplay_anime_id, edm.dandanplay_anime_title
      FROM emby_episode_mapping eem
      INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
      WHERE eem.mapping_id = ? AND eem.emby_index_number > ?
      ORDER BY eem.emby_index_number ASC
      LIMIT 1
    ''', [animeMapping['id'], currentEpisode.indexNumber ?? 0]);

    if (episodeMappings.isNotEmpty) {
      final nextMapping = episodeMappings.first;
      debugPrint('[Emby映射服务] 找到下一集映射: 第${nextMapping['emby_index_number']}集');
      return Map<String, dynamic>.from(nextMapping);
    }

    debugPrint('[Emby映射服务] 未找到下一集的现有映射');
    return null;
  }

  /// 根据当前剧集获取上一集的映射
  Future<Map<String, dynamic>?> getPreviousEpisodeMapping({
    required EmbyEpisodeInfo currentEpisode,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] 查找上一集: ${currentEpisode.seriesName} 当前第${currentEpisode.indexNumber}集');

    final animeMapping = await getAnimeMapping(
      embySeriesId: currentEpisode.seriesId!,
      embySeasonId: currentEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[Emby映射服务] 未找到动画映射，无法预测上一集');
      return null;
    }

    final episodeMappings = await _database!.rawQuery('''
      SELECT eem.*, edm.dandanplay_anime_id, edm.dandanplay_anime_title
      FROM emby_episode_mapping eem
      INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
      WHERE eem.mapping_id = ? AND eem.emby_index_number < ?
      ORDER BY eem.emby_index_number DESC
      LIMIT 1
    ''', [animeMapping['id'], currentEpisode.indexNumber ?? 0]);

    if (episodeMappings.isNotEmpty) {
      final prevMapping = episodeMappings.first;
      debugPrint('[Emby映射服务] 找到上一集映射: 第${prevMapping['emby_index_number']}集');
      return Map<String, dynamic>.from(prevMapping);
    }

    debugPrint('[Emby映射服务] 未找到上一集的现有映射');
    return null;
  }

  /// 根据弹幕ID获取下一集的映射
  Future<Map<String, dynamic>?> getNextEpisodeMappingByDanmakuIds({
    required int currentAnimeId,
    required int currentEpisodeId,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] ========== 开始查找下一集映射 ==========');
    debugPrint('[Emby映射服务] 输入参数: animeId=$currentAnimeId, episodeId=$currentEpisodeId');

    try {
      // 1. 首先根据当前弹幕ID找到对应的Emby剧集映射
      debugPrint('[Emby映射服务] 第1步: 查找当前剧集的映射记录');
      final currentMappingResults = await _database!.rawQuery('''
        SELECT eem.*, edm.emby_series_id, edm.emby_season_id, edm.dandanplay_anime_id
        FROM emby_episode_mapping eem
        INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
        WHERE eem.dandanplay_episode_id = ? AND edm.dandanplay_anime_id = ?
      ''', [currentEpisodeId, currentAnimeId]);

      debugPrint('[Emby映射服务] 查询结果数量: ${currentMappingResults.length}');
      if (currentMappingResults.isNotEmpty) {
        debugPrint('[Emby映射服务] 当前映射记录: ${currentMappingResults.first}');
      }

      if (currentMappingResults.isEmpty) {
        debugPrint('[Emby映射服务] ❌ 未找到当前剧集的映射记录');
        return null;
      }

      final currentMapping = currentMappingResults.first;
      final currentEmbyIndexNumber = currentMapping['emby_index_number'] as int?;
      final seriesId = currentMapping['emby_series_id'] as String?;
      final seasonId = currentMapping['emby_season_id'] as String?;
      final mappingId = currentMapping['mapping_id'] as int;

      debugPrint('[Emby映射服务] 第2步: 解析当前映射信息');
      debugPrint('[Emby映射服务] - 当前集号: $currentEmbyIndexNumber');
      debugPrint('[Emby映射服务] - 系列ID: $seriesId');
      debugPrint('[Emby映射服务] - 季节ID: $seasonId'); 
      debugPrint('[Emby映射服务] - 映射ID: $mappingId');

      if (currentEmbyIndexNumber == null || seriesId == null) {
        debugPrint('[Emby映射服务] ❌ 当前剧集映射缺少必要信息');
        return null;
      }

      // 2. 查找下一集的Emby索引号
      final nextEmbyIndexNumber = currentEmbyIndexNumber + 1;
      debugPrint('[Emby映射服务] 第3步: 计算下一集号 = $nextEmbyIndexNumber');
      
      // 3. 检查是否已有下一集的映射
      debugPrint('[Emby映射服务] 第4步: 查找下一集的现有映射');
      final nextMappingResults = await _database!.rawQuery('''
        SELECT eem.*, edm.dandanplay_anime_id, edm.dandanplay_anime_title, edm.emby_series_id, edm.emby_season_id
        FROM emby_episode_mapping eem
        INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
        WHERE eem.mapping_id = ? AND eem.emby_index_number = ?
      ''', [mappingId, nextEmbyIndexNumber]);

      debugPrint('[Emby映射服务] 下一集现有映射查询结果数量: ${nextMappingResults.length}');

      if (nextMappingResults.isNotEmpty) {
        final nextMapping = nextMappingResults.first;
        debugPrint('[Emby映射服务] ✅ 找到下一集的现有映射: $nextMapping');
        debugPrint('[Emby映射服务] - 下一集集号: ${nextMapping['emby_index_number']}');
        debugPrint('[Emby映射服务] - 下一集弹幕ID: ${nextMapping['dandanplay_episode_id']}');
        return Map<String, dynamic>.from(nextMapping);
      }

      // 4. 如果没有现有映射，尝试基于已有映射推算下一集
      debugPrint('[Emby映射服务] 第5步: 没有现有映射，开始基于已有映射推算下一集');
      debugPrint('[Emby映射服务] - 目标集号: $nextEmbyIndexNumber');
      
      // 查找同一个映射中已有的剧集映射记录，用于推算规律
      final existingMappings = await _database!.query(
        'emby_episode_mapping',
        where: 'mapping_id = ?',
        whereArgs: [mappingId],
        orderBy: 'emby_index_number ASC',
      );
      
      debugPrint('[Emby映射服务] 找到 ${existingMappings.length} 个已有映射记录');
      
      if (existingMappings.isNotEmpty) {
        // 使用已有的映射推算下一集ID
        final referenceMapping = existingMappings.first;
        final referenceEmbyIndex = referenceMapping['emby_index_number'] as int;
        final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
        
        // 计算偏移量并推算目标剧集ID
        final offset = nextEmbyIndexNumber - referenceEmbyIndex;
        final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
        
        debugPrint('[Emby映射服务] 基于已有映射推算下一集:');
        debugPrint('[Emby映射服务] - 参考: 第$referenceEmbyIndex集 -> DandanPlay ID: $referenceDandanplayEpisodeId');
        debugPrint('[Emby映射服务] - 偏移量: $offset');
        debugPrint('[Emby映射服务] - 预测: 第$nextEmbyIndexNumber集 -> DandanPlay ID: $predictedEpisodeId');
        
        // 返回预测的映射信息
        final predictedMapping = {
          'emby_index_number': nextEmbyIndexNumber,
          'dandanplay_episode_id': predictedEpisodeId,
          'dandanplay_anime_id': currentAnimeId,
          'emby_series_id': seriesId,
          'emby_season_id': seasonId,
          'mapping_id': mappingId,
          'confirmed': 0, // 标记为预测映射
        };
        debugPrint('[Emby映射服务] ✅ 返回推算的映射: $predictedMapping');
        return predictedMapping;
      } else {
        debugPrint('[Emby映射服务] ❌ 没有已有映射记录，无法推算');
      }

      debugPrint('[Emby映射服务] ❌ 未找到下一集的有效映射');
      debugPrint('[Emby映射服务] ========== 查找下一集映射结束 ==========');
      return null;
    } catch (e) {
      debugPrint('[Emby映射服务] 查找下一集映射时出错：$e');
      return null;
    }
  }

  /// 根据弹幕ID获取上一集的映射
  Future<Map<String, dynamic>?> getPreviousEpisodeMappingByDanmakuIds({
    required int currentAnimeId,
    required int currentEpisodeId,
  }) async {
    await initialize();

    debugPrint('[Emby映射服务] 查找上一集: animeId=$currentAnimeId, episodeId=$currentEpisodeId');

    try {
      // 1. 首先根据当前弹幕ID找到对应的Emby剧集映射
      final currentMappingResults = await _database!.rawQuery('''
        SELECT eem.*, edm.emby_series_id, edm.emby_season_id, edm.dandanplay_anime_id
        FROM emby_episode_mapping eem
        INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
        WHERE eem.dandanplay_episode_id = ? AND edm.dandanplay_anime_id = ?
      ''', [currentEpisodeId, currentAnimeId]);

      if (currentMappingResults.isEmpty) {
        debugPrint('[Emby映射服务] 未找到当前剧集的映射记录');
        return null;
      }

      final currentMapping = currentMappingResults.first;
      final currentEmbyIndexNumber = currentMapping['emby_index_number'] as int?;
      final seriesId = currentMapping['emby_series_id'] as String?;
      final seasonId = currentMapping['emby_season_id'] as String?;
      final mappingId = currentMapping['mapping_id'] as int;

      if (currentEmbyIndexNumber == null || currentEmbyIndexNumber <= 1 || seriesId == null) {
        debugPrint('[Emby映射服务] 当前剧集映射缺少必要信息或已是第一集');
        return null;
      }

      // 2. 查找上一集的Emby索引号
      final previousEmbyIndexNumber = currentEmbyIndexNumber - 1;
      
      // 3. 检查是否已有上一集的映射
      final previousMappingResults = await _database!.rawQuery('''
        SELECT eem.*, edm.dandanplay_anime_id, edm.dandanplay_anime_title, edm.emby_series_id, edm.emby_season_id
        FROM emby_episode_mapping eem
        INNER JOIN emby_dandanplay_mapping edm ON eem.mapping_id = edm.id
        WHERE eem.mapping_id = ? AND eem.emby_index_number = ?
      ''', [mappingId, previousEmbyIndexNumber]);

      if (previousMappingResults.isNotEmpty) {
        final previousMapping = previousMappingResults.first;
        debugPrint('[Emby映射服务] 找到上一集的现有映射: 第${previousMapping['emby_index_number']}集');
        return Map<String, dynamic>.from(previousMapping);
      }

      // 4. 如果没有现有映射，尝试基于已有映射推算上一集
      debugPrint('[Emby映射服务] 尝试基于已有映射推算上一集: 第$previousEmbyIndexNumber集');
      
      // 查找同一个映射中已有的剧集映射记录，用于推算规律
      final existingMappings = await _database!.query(
        'emby_episode_mapping',
        where: 'mapping_id = ?',
        whereArgs: [mappingId],
        orderBy: 'emby_index_number ASC',
      );
      
      if (existingMappings.isNotEmpty) {
        // 使用已有的映射推算上一集ID
        final referenceMapping = existingMappings.first;
        final referenceEmbyIndex = referenceMapping['emby_index_number'] as int;
        final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
        
        // 计算偏移量并推算目标剧集ID
        final offset = previousEmbyIndexNumber - referenceEmbyIndex;
        final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
        
        debugPrint('[Emby映射服务] 基于已有映射推算上一集: 参考第$referenceEmbyIndex集(ID=$referenceDandanplayEpisodeId) -> 预测第$previousEmbyIndexNumber集(ID=$predictedEpisodeId)');
        
        // 返回预测的映射信息
        final predictedMapping = {
          'emby_index_number': previousEmbyIndexNumber,
          'dandanplay_episode_id': predictedEpisodeId,
          'dandanplay_anime_id': currentAnimeId,
          'emby_series_id': seriesId,
          'emby_season_id': seasonId,
          'mapping_id': mappingId,
          'confirmed': 0, // 标记为预测映射
        };
        return predictedMapping;
      } else {
        debugPrint('[Emby映射服务] 没有已有映射记录，无法推算');
      }

      debugPrint('[Emby映射服务] 未找到上一集的有效映射');
      return null;
    } catch (e) {
      debugPrint('[Emby映射服务] 查找上一集映射时出错：$e');
      return null;
    }
  }

  /// 清理缓存
  void clearCache() {
    _animeMappingCache.clear();
    _episodePredictionCache.clear();
    _lastCacheClean = DateTime.now();
    debugPrint('[Emby映射服务] 缓存已清理');
  }

  /// 智能推算未知剧集的弹幕ID
  Future<int?> predictEpisodeId({
    required String embyEpisodeId,
    required int embyIndexNumber,
    required String embySeriesId,
    String? embySeasonId,
  }) async {
    await initialize();

    // 生成缓存键
    final cacheKey = '${embyEpisodeId}_${embyIndexNumber}_${embySeriesId}_${embySeasonId ?? 'null'}';
    
    // 检查缓存
    if (_episodePredictionCache.containsKey(cacheKey)) {
      debugPrint('[Emby映射服务] 从缓存获取推算结果: $cacheKey');
      return _episodePredictionCache[cacheKey];
    }

    // 获取动画映射
    final animeMapping = await getAnimeMapping(
      embySeriesId: embySeriesId,
      embySeasonId: embySeasonId,
    );

    if (animeMapping == null) {
      debugPrint('[Emby映射服务] 未找到动画映射，无法推算');
      return null;
    }

    final mappingId = animeMapping['id'] as int;

    // 查找同一动画下的其他已确认映射
    final confirmedMappings = await _database!.query(
      'emby_episode_mapping',
      where: 'mapping_id = ? AND confirmed = 1',
      whereArgs: [mappingId],
      orderBy: 'emby_index_number ASC',
    );

    if (confirmedMappings.length < 2) {
      debugPrint('[Emby映射服务] 确认映射数量不足，无法推算');
      return null;
    }

    // 计算基础偏移量
    double totalOffset = 0;
    int mappingCount = 0;

    for (int i = 0; i < confirmedMappings.length - 1; i++) {
      final current = confirmedMappings[i];
      final next = confirmedMappings[i + 1];

      final currentIndex = current['emby_index_number'] as int;
      final nextIndex = next['emby_index_number'] as int;
      final currentEpisodeId = current['dandanplay_episode_id'] as int;
      final nextEpisodeId = next['dandanplay_episode_id'] as int;

      // 计算两个映射之间的偏移量
      final embyDiff = nextIndex - currentIndex;
      final dandanplayDiff = nextEpisodeId - currentEpisodeId;

      if (embyDiff > 0 && dandanplayDiff > 0) {
        final offset = dandanplayDiff / embyDiff;
        totalOffset += offset;
        mappingCount++;
      }
    }

    if (mappingCount == 0) {
      debugPrint('[Emby映射服务] 无法计算有效偏移量');
      return null;
    }

    final averageOffset = totalOffset / mappingCount;

    // 找到最接近的基准映射
    int? baseEpisodeId;
    int? baseIndexNumber;
    double minDistance = double.infinity;

    for (final mapping in confirmedMappings) {
      final index = mapping['emby_index_number'] as int;
      final distance = (index - embyIndexNumber).abs();
      if (distance < minDistance) {
        minDistance = distance.toDouble();
        baseEpisodeId = mapping['dandanplay_episode_id'] as int;
        baseIndexNumber = index;
      }
    }

    if (baseEpisodeId == null || baseIndexNumber == null) {
      debugPrint('[Emby映射服务] 未找到基准映射');
      return null;
    }

    // 推算目标剧集ID
    final indexDiff = embyIndexNumber - baseIndexNumber;
    final predictedEpisodeId = baseEpisodeId + (indexDiff * averageOffset).round();

    debugPrint('[Emby映射服务] 推算结果: Emby集$embyIndexNumber -> DandanPlay集$predictedEpisodeId (偏移量: $averageOffset)');

    // 缓存结果
    _episodePredictionCache[cacheKey] = predictedEpisodeId;

    return predictedEpisodeId;
  }

  /// 获取动画的所有剧集映射
  Future<List<Map<String, dynamic>>> getAnimeEpisodeMappings({
    required String embySeriesId,
    String? embySeasonId,
  }) async {
    await initialize();

    final animeMapping = await getAnimeMapping(
      embySeriesId: embySeriesId,
      embySeasonId: embySeasonId,
    );

    if (animeMapping == null) {
      return [];
    }

    final mappingId = animeMapping['id'] as int;

    return await _database!.query(
      'emby_episode_mapping',
      where: 'mapping_id = ?',
      whereArgs: [mappingId],
      orderBy: 'emby_index_number ASC',
    );
  }

  /// 删除动画映射及其所有剧集映射
  Future<void> deleteAnimeMapping({
    required String embySeriesId,
    String? embySeasonId,
  }) async {
    await initialize();

    final animeMapping = await getAnimeMapping(
      embySeriesId: embySeriesId,
      embySeasonId: embySeasonId,
    );

    if (animeMapping == null) {
      debugPrint('[Emby映射服务] 未找到要删除的动画映射');
      return;
    }

    final mappingId = animeMapping['id'] as int;

    // 删除所有相关的剧集映射
    await _database!.delete(
      'emby_episode_mapping',
      where: 'mapping_id = ?',
      whereArgs: [mappingId],
    );

    // 删除动画映射
    await _database!.delete(
      'emby_dandanplay_mapping',
      where: 'id = ?',
      whereArgs: [mappingId],
    );

    // 清理相关缓存
    final cacheKeyToRemove = _animeMappingCache.keys
        .where((key) => key.startsWith('${embySeriesId}_'))
        .toList();
    for (final key in cacheKeyToRemove) {
      _animeMappingCache.remove(key);
    }

    debugPrint('[Emby映射服务] 已删除动画映射: $embySeriesId');
  }

  /// 获取所有动画映射
  Future<List<Map<String, dynamic>>> getAllAnimeMappings() async {
    await initialize();

    return await _database!.query(
      'emby_dandanplay_mapping',
      orderBy: 'updated_at DESC',
    );
  }

  /// 搜索动画映射
  Future<List<Map<String, dynamic>>> searchAnimeMappings(String keyword) async {
    await initialize();

    return await _database!.query(
      'emby_dandanplay_mapping',
      where: 'emby_series_name LIKE ? OR dandanplay_anime_title LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%'],
      orderBy: 'updated_at DESC',
    );
  }

  /// 获取映射统计信息
  Future<Map<String, dynamic>> getMappingStatistics() async {
    await initialize();

    final animeCount = Sqflite.firstIntValue(await _database!.rawQuery(
      'SELECT COUNT(*) FROM emby_dandanplay_mapping'
    )) ?? 0;

    final episodeCount = Sqflite.firstIntValue(await _database!.rawQuery(
      'SELECT COUNT(*) FROM emby_episode_mapping'
    )) ?? 0;

    final confirmedCount = Sqflite.firstIntValue(await _database!.rawQuery(
      'SELECT COUNT(*) FROM emby_episode_mapping WHERE confirmed = 1'
    )) ?? 0;

    return {
      'anime_mappings': animeCount,
      'episode_mappings': episodeCount,
      'confirmed_mappings': confirmedCount,
      'predicted_mappings': episodeCount - confirmedCount,
    };
  }

  /// 清理过期的未确认映射
  Future<void> cleanupUnconfirmedMappings({int daysOld = 7}) async {
    await initialize();

    final cutoffDate = DateTime.now().subtract(Duration(days: daysOld));
    
    final deletedCount = await _database!.delete(
      'emby_episode_mapping',
      where: 'confirmed = 0 AND created_at < ?',
      whereArgs: [cutoffDate.toIso8601String()],
    );

    debugPrint('[Emby映射服务] 清理了 $deletedCount 个过期未确认映射');
  }

  /// 导出映射数据
  Future<Map<String, dynamic>> exportMappings() async {
    await initialize();

    final animeMappings = await getAllAnimeMappings();
    final episodeMappings = await _database!.query('emby_episode_mapping');

    return {
      'anime_mappings': animeMappings,
      'episode_mappings': episodeMappings,
      'export_time': DateTime.now().toIso8601String(),
    };
  }

  /// 导入映射数据
  Future<void> importMappings(Map<String, dynamic> data) async {
    await initialize();

    final animeMappings = data['anime_mappings'] as List<dynamic>;
    final episodeMappings = data['episode_mappings'] as List<dynamic>;

    await _database!.transaction((txn) async {
      // 导入动画映射
      for (final mapping in animeMappings) {
        await txn.insert(
          'emby_dandanplay_mapping',
          Map<String, dynamic>.from(mapping),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // 导入剧集映射
      for (final mapping in episodeMappings) {
        await txn.insert(
          'emby_episode_mapping',
          Map<String, dynamic>.from(mapping),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });

    // 清理缓存
    _animeMappingCache.clear();
    _episodePredictionCache.clear();

    debugPrint('[Emby映射服务] 导入完成: ${animeMappings.length}个动画映射, ${episodeMappings.length}个剧集映射');
  }
} 
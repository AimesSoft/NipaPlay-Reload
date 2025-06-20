import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../models/jellyfin_model.dart';
import '../models/watch_history_database.dart';

/// Jellyfin剧集映射服务
/// 
/// 负责管理Jellyfin剧集到DandanPlay剧集的智能映射
/// 包括：动画级映射、剧集级映射、自动推算和持久化存储
class JellyfinEpisodeMappingService {
  static final JellyfinEpisodeMappingService _instance = JellyfinEpisodeMappingService._internal();
  factory JellyfinEpisodeMappingService() => _instance;
  JellyfinEpisodeMappingService._internal();

  static JellyfinEpisodeMappingService get instance => _instance;

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
      CREATE TABLE IF NOT EXISTS jellyfin_dandanplay_mapping (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        jellyfin_series_id TEXT NOT NULL,
        jellyfin_series_name TEXT,
        jellyfin_season_id TEXT,
        dandanplay_anime_id INTEGER NOT NULL,
        dandanplay_anime_title TEXT,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(jellyfin_series_id, jellyfin_season_id, dandanplay_anime_id)
      )
    ''');

    await _database!.execute('''
      CREATE TABLE IF NOT EXISTS jellyfin_episode_mapping (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        jellyfin_episode_id TEXT NOT NULL UNIQUE,
        jellyfin_index_number INTEGER,
        dandanplay_episode_id INTEGER NOT NULL,
        mapping_id INTEGER NOT NULL,
        confirmed BOOLEAN DEFAULT FALSE,
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (mapping_id) REFERENCES jellyfin_dandanplay_mapping (id)
      )
    ''');

    debugPrint('[映射服务] 数据库初始化完成');
    
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
    debugPrint('[映射服务] 缓存已清理');
  }

  /// 建立或更新动画级映射（简化版本）
  Future<int> createOrUpdateAnimeMapping({
    required String jellyfinSeriesId,
    required String jellyfinSeriesName,
    String? jellyfinSeasonId,
    required int dandanplayAnimeId,
    required String dandanplayAnimeTitle,
  }) async {
    await initialize();

    debugPrint('[映射服务] 创建动画映射: $jellyfinSeriesName -> $dandanplayAnimeTitle');

    // 检查是否已存在映射
    final existing = await _database!.query(
      'jellyfin_dandanplay_mapping',
      where: 'jellyfin_series_id = ? AND jellyfin_season_id = ? AND dandanplay_anime_id = ?',
      whereArgs: [jellyfinSeriesId, jellyfinSeasonId, dandanplayAnimeId],
    );

    if (existing.isNotEmpty) {
      // 更新现有映射
      final mappingId = existing.first['id'] as int;
      await _database!.update(
        'jellyfin_dandanplay_mapping',
        {
          'jellyfin_series_name': jellyfinSeriesName,
          'dandanplay_anime_title': dandanplayAnimeTitle,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [mappingId],
      );
      debugPrint('[映射服务] 更新现有动画映射: ID=$mappingId');
      return mappingId;
    } else {
      // 创建新映射
      final mappingId = await _database!.insert(
        'jellyfin_dandanplay_mapping',
        {
          'jellyfin_series_id': jellyfinSeriesId,
          'jellyfin_series_name': jellyfinSeriesName,
          'jellyfin_season_id': jellyfinSeasonId,
          'dandanplay_anime_id': dandanplayAnimeId,
          'dandanplay_anime_title': dandanplayAnimeTitle,
        },
      );
      debugPrint('[映射服务] 创建新动画映射: ID=$mappingId');
      return mappingId;
    }
  }

  /// 记录剧集级映射（增强版本，会自动优化基础偏移量）
  Future<void> recordEpisodeMapping({
    required String jellyfinEpisodeId,
    required int jellyfinIndexNumber,
    required int dandanplayEpisodeId,
    required int mappingId,
    bool confirmed = true,
  }) async {
    await initialize();

    debugPrint('[映射服务] 记录剧集映射: Jellyfin集$jellyfinIndexNumber -> DandanPlay集$dandanplayEpisodeId');

    // 保存剧集映射
    await _database!.insert(
      'jellyfin_episode_mapping',
      {
        'jellyfin_episode_id': jellyfinEpisodeId,
        'jellyfin_index_number': jellyfinIndexNumber,
        'dandanplay_episode_id': dandanplayEpisodeId,
        'mapping_id': mappingId,
        'confirmed': confirmed ? 1 : 0,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // 清理相关缓存
    final cacheKeyToRemove = _episodePredictionCache.keys
        .where((key) => key.startsWith(jellyfinEpisodeId))
        .toList();
    for (final key in cacheKeyToRemove) {
      _episodePredictionCache.remove(key);
    }

    // 如果是确认的映射，更新相关统计信息
    if (confirmed) {
      debugPrint('[映射服务] 已确认剧集映射，更新统计信息');
    }
  }

  /// 获取动画映射（带缓存）
  Future<Map<String, dynamic>?> getAnimeMapping({
    required String jellyfinSeriesId,
    String? jellyfinSeasonId,
  }) async {
    await initialize();

    // 生成缓存键
    final cacheKey = '${jellyfinSeriesId}_${jellyfinSeasonId ?? 'null'}';
    
    // 检查缓存
    if (_animeMappingCache.containsKey(cacheKey)) {
      debugPrint('[映射服务] 从缓存获取动画映射: $cacheKey');
      return _animeMappingCache[cacheKey];
    }

    final results = await _database!.query(
      'jellyfin_dandanplay_mapping',
      where: 'jellyfin_series_id = ? AND (jellyfin_season_id = ? OR jellyfin_season_id IS NULL)',
      whereArgs: [jellyfinSeriesId, jellyfinSeasonId],
      orderBy: 'jellyfin_season_id IS NULL, updated_at DESC', // 优先匹配指定季节
    );

    final result = results.isNotEmpty ? results.first : null;
    
    // 缓存结果
    _animeMappingCache[cacheKey] = result;
    
    debugPrint('[映射服务] 动画映射已缓存: $cacheKey');
    return result;
  }

  /// 智能预测剧集映射（基于已有映射规律推算）
  Future<int?> predictEpisodeMapping({
    required JellyfinEpisodeInfo jellyfinEpisode,
  }) async {
    await initialize();

    // 如果没有集号信息，无法预测
    if (jellyfinEpisode.indexNumber == null) {
      debugPrint('[映射服务] Jellyfin剧集缺少集号信息，无法预测映射');
      return null;
    }

    // 生成缓存键
    final cacheKey = '${jellyfinEpisode.id}_${jellyfinEpisode.indexNumber}';
    
    // 检查缓存
    if (_episodePredictionCache.containsKey(cacheKey)) {
      debugPrint('[映射服务] 从缓存获取剧集预测: $cacheKey');
      return _episodePredictionCache[cacheKey];
    }

    debugPrint('[映射服务] 预测剧集映射: ${jellyfinEpisode.seriesName} 第${jellyfinEpisode.indexNumber}集');

    // 1. 查找动画级映射
    final animeMapping = await getAnimeMapping(
      jellyfinSeriesId: jellyfinEpisode.seriesId!,
      jellyfinSeasonId: jellyfinEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[映射服务] 未找到动画级映射');
      _episodePredictionCache[cacheKey] = null;
      return null;
    }

    final mappingId = animeMapping['id'] as int;

    // 2. 检查是否有直接的剧集映射
    final directMapping = await _database!.query(
      'jellyfin_episode_mapping',
      where: 'jellyfin_episode_id = ?',
      whereArgs: [jellyfinEpisode.id],
    );

    if (directMapping.isNotEmpty) {
      final dandanplayEpisodeId = directMapping.first['dandanplay_episode_id'] as int;
      debugPrint('[映射服务] 找到直接剧集映射: $dandanplayEpisodeId');
      _episodePredictionCache[cacheKey] = dandanplayEpisodeId;
      return dandanplayEpisodeId;
    }

    // 3. 基于已有映射推算剧集ID（核心逻辑）
    final targetJellyfinIndex = jellyfinEpisode.indexNumber!;
    
    // 查找同一个映射中已有的剧集映射记录，用于推算规律
    final existingMappings = await _database!.query(
      'jellyfin_episode_mapping',
      where: 'mapping_id = ?',
      whereArgs: [mappingId],
      orderBy: 'jellyfin_index_number ASC',
    );
    
    if (existingMappings.isNotEmpty) {
      // 使用已有的映射推算新的剧集ID
      final referenceMapping = existingMappings.first;
      final referenceJellyfinIndex = referenceMapping['jellyfin_index_number'] as int;
      final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
      
      // 计算偏移量并推算目标剧集ID
      final offset = targetJellyfinIndex - referenceJellyfinIndex;
      final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
      
      debugPrint('[映射服务] 基于已有映射推算: 参考第${referenceJellyfinIndex}集(ID=${referenceDandanplayEpisodeId}) -> 预测第${targetJellyfinIndex}集(ID=${predictedEpisodeId})');
      
      // 自动记录这个预测的映射
      await recordEpisodeMapping(
        jellyfinEpisodeId: jellyfinEpisode.id,
        jellyfinIndexNumber: targetJellyfinIndex,
        dandanplayEpisodeId: predictedEpisodeId,
        mappingId: mappingId,
        confirmed: false, // 标记为未确认的预测映射
      );
      
      // 缓存结果
      _episodePredictionCache[cacheKey] = predictedEpisodeId;
      return predictedEpisodeId;
    } else {
      debugPrint('[映射服务] 没有已有映射记录，无法推算');
    }

    _episodePredictionCache[cacheKey] = null;
    return null;
  }

  /// 根据当前剧集获取下一集的映射
  Future<Map<String, dynamic>?> getNextEpisodeMapping({
    required JellyfinEpisodeInfo currentEpisode,
  }) async {
    await initialize();

    debugPrint('[映射服务] 查找下一集: ${currentEpisode.seriesName} 当前第${currentEpisode.indexNumber}集');

    // 查找同一系列的所有剧集映射
    final animeMapping = await getAnimeMapping(
      jellyfinSeriesId: currentEpisode.seriesId!,
      jellyfinSeasonId: currentEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[映射服务] 未找到动画映射，无法预测下一集');
      return null;
    }

    // 查询数据库中该系列的所有剧集映射
    final episodeMappings = await _database!.rawQuery('''
      SELECT jem.*, jdm.dandanplay_anime_id, jdm.dandanplay_anime_title
      FROM jellyfin_episode_mapping jem
      INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
      WHERE jem.mapping_id = ? AND jem.jellyfin_index_number > ?
      ORDER BY jem.jellyfin_index_number ASC
      LIMIT 1
    ''', [animeMapping['id'], currentEpisode.indexNumber ?? 0]);

    if (episodeMappings.isNotEmpty) {
      final nextMapping = episodeMappings.first;
      debugPrint('[映射服务] 找到下一集映射: 第${nextMapping['jellyfin_index_number']}集');
      return Map<String, dynamic>.from(nextMapping);
    }

    debugPrint('[映射服务] 未找到下一集的现有映射');
    return null;
  }

  /// 根据当前剧集获取上一集的映射
  Future<Map<String, dynamic>?> getPreviousEpisodeMapping({
    required JellyfinEpisodeInfo currentEpisode,
  }) async {
    await initialize();

    debugPrint('[映射服务] 查找上一集: ${currentEpisode.seriesName} 当前第${currentEpisode.indexNumber}集');

    final animeMapping = await getAnimeMapping(
      jellyfinSeriesId: currentEpisode.seriesId!,
      jellyfinSeasonId: currentEpisode.seasonId,
    );

    if (animeMapping == null) {
      debugPrint('[映射服务] 未找到动画映射，无法预测上一集');
      return null;
    }

    final episodeMappings = await _database!.rawQuery('''
      SELECT jem.*, jdm.dandanplay_anime_id, jdm.dandanplay_anime_title
      FROM jellyfin_episode_mapping jem
      INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
      WHERE jem.mapping_id = ? AND jem.jellyfin_index_number < ?
      ORDER BY jem.jellyfin_index_number DESC
      LIMIT 1
    ''', [animeMapping['id'], currentEpisode.indexNumber ?? 0]);

    if (episodeMappings.isNotEmpty) {
      final prevMapping = episodeMappings.first;
      debugPrint('[映射服务] 找到上一集映射: 第${prevMapping['jellyfin_index_number']}集');
      return Map<String, dynamic>.from(prevMapping);
    }

    debugPrint('[映射服务] 未找到上一集的现有映射');
    return null;
  }

  /// 根据弹幕ID获取下一集的映射
  Future<Map<String, dynamic>?> getNextEpisodeMappingByDanmakuIds({
    required int currentAnimeId,
    required int currentEpisodeId,
  }) async {
    await initialize();

    debugPrint('[映射服务] ========== 开始查找下一集映射 ==========');
    debugPrint('[映射服务] 输入参数: animeId=$currentAnimeId, episodeId=$currentEpisodeId');

    try {
      // 1. 首先根据当前弹幕ID找到对应的Jellyfin剧集映射
      debugPrint('[映射服务] 第1步: 查找当前剧集的映射记录');
      final currentMappingResults = await _database!.rawQuery('''
        SELECT jem.*, jdm.jellyfin_series_id, jdm.jellyfin_season_id, jdm.dandanplay_anime_id
        FROM jellyfin_episode_mapping jem
        INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
        WHERE jem.dandanplay_episode_id = ? AND jdm.dandanplay_anime_id = ?
      ''', [currentEpisodeId, currentAnimeId]);

      debugPrint('[映射服务] 查询结果数量: ${currentMappingResults.length}');
      if (currentMappingResults.isNotEmpty) {
        debugPrint('[映射服务] 当前映射记录: ${currentMappingResults.first}');
      }

      if (currentMappingResults.isEmpty) {
        debugPrint('[映射服务] ❌ 未找到当前剧集的映射记录');
        return null;
      }

      final currentMapping = currentMappingResults.first;
      final currentJellyfinIndexNumber = currentMapping['jellyfin_index_number'] as int?;
      final seriesId = currentMapping['jellyfin_series_id'] as String?;
      final seasonId = currentMapping['jellyfin_season_id'] as String?;
      final mappingId = currentMapping['mapping_id'] as int;

      debugPrint('[映射服务] 第2步: 解析当前映射信息');
      debugPrint('[映射服务] - 当前集号: $currentJellyfinIndexNumber');
      debugPrint('[映射服务] - 系列ID: $seriesId');
      debugPrint('[映射服务] - 季节ID: $seasonId'); 
      debugPrint('[映射服务] - 映射ID: $mappingId');

      if (currentJellyfinIndexNumber == null || seriesId == null) {
        debugPrint('[映射服务] ❌ 当前剧集映射缺少必要信息');
        return null;
      }

      // 2. 查找下一集的Jellyfin索引号
      final nextJellyfinIndexNumber = currentJellyfinIndexNumber + 1;
      debugPrint('[映射服务] 第3步: 计算下一集号 = $nextJellyfinIndexNumber');
      
      // 3. 检查是否已有下一集的映射
      debugPrint('[映射服务] 第4步: 查找下一集的现有映射');
      final nextMappingResults = await _database!.rawQuery('''
        SELECT jem.*, jdm.dandanplay_anime_id, jdm.dandanplay_anime_title, jdm.jellyfin_series_id, jdm.jellyfin_season_id
        FROM jellyfin_episode_mapping jem
        INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
        WHERE jem.mapping_id = ? AND jem.jellyfin_index_number = ?
      ''', [mappingId, nextJellyfinIndexNumber]);

      debugPrint('[映射服务] 下一集现有映射查询结果数量: ${nextMappingResults.length}');

      if (nextMappingResults.isNotEmpty) {
        final nextMapping = nextMappingResults.first;
        debugPrint('[映射服务] ✅ 找到下一集的现有映射: ${nextMapping}');
        debugPrint('[映射服务] - 下一集集号: ${nextMapping['jellyfin_index_number']}');
        debugPrint('[映射服务] - 下一集弹幕ID: ${nextMapping['dandanplay_episode_id']}');
        return Map<String, dynamic>.from(nextMapping);
      }

      // 4. 如果没有现有映射，尝试基于已有映射推算下一集
      debugPrint('[映射服务] 第5步: 没有现有映射，开始基于已有映射推算下一集');
      debugPrint('[映射服务] - 目标集号: $nextJellyfinIndexNumber');
      
      // 查找同一个映射中已有的剧集映射记录，用于推算规律
      final existingMappings = await _database!.query(
        'jellyfin_episode_mapping',
        where: 'mapping_id = ?',
        whereArgs: [mappingId],
        orderBy: 'jellyfin_index_number ASC',
      );
      
      debugPrint('[映射服务] 找到 ${existingMappings.length} 个已有映射记录');
      
      if (existingMappings.isNotEmpty) {
        // 使用已有的映射推算下一集ID
        final referenceMapping = existingMappings.first;
        final referenceJellyfinIndex = referenceMapping['jellyfin_index_number'] as int;
        final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
        
        // 计算偏移量并推算目标剧集ID
        final offset = nextJellyfinIndexNumber - referenceJellyfinIndex;
        final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
        
        debugPrint('[映射服务] 基于已有映射推算下一集:');
        debugPrint('[映射服务] - 参考: 第${referenceJellyfinIndex}集 -> DandanPlay ID: ${referenceDandanplayEpisodeId}');
        debugPrint('[映射服务] - 偏移量: $offset');
        debugPrint('[映射服务] - 预测: 第${nextJellyfinIndexNumber}集 -> DandanPlay ID: ${predictedEpisodeId}');
        
        // 返回预测的映射信息
        final predictedMapping = {
          'jellyfin_index_number': nextJellyfinIndexNumber,
          'dandanplay_episode_id': predictedEpisodeId,
          'dandanplay_anime_id': currentAnimeId,
          'jellyfin_series_id': seriesId,
          'jellyfin_season_id': seasonId,
          'mapping_id': mappingId,
          'confirmed': 0, // 标记为预测映射
        };
        debugPrint('[映射服务] ✅ 返回推算的映射: $predictedMapping');
        return predictedMapping;
      } else {
        debugPrint('[映射服务] ❌ 没有已有映射记录，无法推算');
      }

      debugPrint('[映射服务] ❌ 未找到下一集的有效映射');
      debugPrint('[映射服务] ========== 查找下一集映射结束 ==========');
      return null;
    } catch (e) {
      debugPrint('[映射服务] 查找下一集映射时出错：$e');
      return null;
    }
  }

  /// 根据弹幕ID获取上一集的映射
  Future<Map<String, dynamic>?> getPreviousEpisodeMappingByDanmakuIds({
    required int currentAnimeId,
    required int currentEpisodeId,
  }) async {
    await initialize();

    debugPrint('[映射服务] 查找上一集: animeId=$currentAnimeId, episodeId=$currentEpisodeId');

    try {
      // 1. 首先根据当前弹幕ID找到对应的Jellyfin剧集映射
      final currentMappingResults = await _database!.rawQuery('''
        SELECT jem.*, jdm.jellyfin_series_id, jdm.jellyfin_season_id, jdm.dandanplay_anime_id
        FROM jellyfin_episode_mapping jem
        INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
        WHERE jem.dandanplay_episode_id = ? AND jdm.dandanplay_anime_id = ?
      ''', [currentEpisodeId, currentAnimeId]);

      if (currentMappingResults.isEmpty) {
        debugPrint('[映射服务] 未找到当前剧集的映射记录');
        return null;
      }

      final currentMapping = currentMappingResults.first;
      final currentJellyfinIndexNumber = currentMapping['jellyfin_index_number'] as int?;
      final seriesId = currentMapping['jellyfin_series_id'] as String?;
      final seasonId = currentMapping['jellyfin_season_id'] as String?;
      final mappingId = currentMapping['mapping_id'] as int;

      if (currentJellyfinIndexNumber == null || currentJellyfinIndexNumber <= 1 || seriesId == null) {
        debugPrint('[映射服务] 当前剧集映射缺少必要信息或已是第一集');
        return null;
      }

      // 2. 查找上一集的Jellyfin索引号
      final previousJellyfinIndexNumber = currentJellyfinIndexNumber - 1;
      
      // 3. 检查是否已有上一集的映射
      final previousMappingResults = await _database!.rawQuery('''
        SELECT jem.*, jdm.dandanplay_anime_id, jdm.dandanplay_anime_title, jdm.jellyfin_series_id, jdm.jellyfin_season_id
        FROM jellyfin_episode_mapping jem
        INNER JOIN jellyfin_dandanplay_mapping jdm ON jem.mapping_id = jdm.id
        WHERE jem.mapping_id = ? AND jem.jellyfin_index_number = ?
      ''', [mappingId, previousJellyfinIndexNumber]);

      if (previousMappingResults.isNotEmpty) {
        final previousMapping = previousMappingResults.first;
        debugPrint('[映射服务] 找到上一集的现有映射: 第${previousMapping['jellyfin_index_number']}集');
        return Map<String, dynamic>.from(previousMapping);
      }

      // 4. 如果没有现有映射，尝试基于已有映射推算上一集
      debugPrint('[映射服务] 尝试基于已有映射推算上一集: 第$previousJellyfinIndexNumber集');
      
      // 查找同一个映射中已有的剧集映射记录，用于推算规律
      final existingMappings = await _database!.query(
        'jellyfin_episode_mapping',
        where: 'mapping_id = ?',
        whereArgs: [mappingId],
        orderBy: 'jellyfin_index_number ASC',
      );
      
      if (existingMappings.isNotEmpty) {
        // 使用已有的映射推算上一集ID
        final referenceMapping = existingMappings.first;
        final referenceJellyfinIndex = referenceMapping['jellyfin_index_number'] as int;
        final referenceDandanplayEpisodeId = referenceMapping['dandanplay_episode_id'] as int;
        
        // 计算偏移量并推算目标剧集ID
        final offset = previousJellyfinIndexNumber - referenceJellyfinIndex;
        final predictedEpisodeId = referenceDandanplayEpisodeId + offset;
        
        debugPrint('[映射服务] 基于已有映射推算上一集: 参考第${referenceJellyfinIndex}集(ID=${referenceDandanplayEpisodeId}) -> 预测第${previousJellyfinIndexNumber}集(ID=${predictedEpisodeId})');
        
        // 返回预测的映射信息
        return {
          'jellyfin_index_number': previousJellyfinIndexNumber,
          'dandanplay_episode_id': predictedEpisodeId,
          'dandanplay_anime_id': currentAnimeId,
          'jellyfin_series_id': seriesId,
          'jellyfin_season_id': seasonId,
          'mapping_id': mappingId,
          'confirmed': 0, // 标记为预测映射
        };
      }

      debugPrint('[映射服务] 未找到上一集的有效映射');
      return null;
    } catch (e) {
      debugPrint('[映射服务] 查找上一集映射时出错：$e');
      return null;
    }
  }

  /// 清除所有映射数据
  Future<void> clearAllMappings() async {
    await initialize();

    debugPrint('[映射服务] 清除所有映射数据');

    try {
      // 先删除所有剧集映射
      await _database!.delete('jellyfin_episode_mapping');
      
      // 再删除所有动画映射
      await _database!.delete('jellyfin_dandanplay_mapping');
      
      // 清理缓存
      _animeMappingCache.clear();
      _episodePredictionCache.clear();
      
      debugPrint('[映射服务] 所有映射数据清除完成');
    } catch (e) {
      debugPrint('[映射服务] 清除映射数据失败: $e');
      rethrow;
    }
  }

  /// 批量记录剧集映射
  Future<void> batchRecordEpisodeMappings(List<Map<String, dynamic>> mappings) async {
    await initialize();

    debugPrint('[映射服务] 批量记录${mappings.length}个剧集映射');

    final batch = _database!.batch();
    
    for (final mapping in mappings) {
      batch.insert(
        'jellyfin_episode_mapping',
        {
          'jellyfin_episode_id': mapping['jellyfinEpisodeId'],
          'jellyfin_index_number': mapping['jellyfinIndexNumber'],
          'dandanplay_episode_id': mapping['dandanplayEpisodeId'],
          'mapping_id': mapping['mappingId'],
          'confirmed': mapping['confirmed'] == true ? 1 : 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    await batch.commit(noResult: true);
    
    // 清理相关缓存
    _episodePredictionCache.clear();
    
    debugPrint('[映射服务] 批量记录完成');
  }

  /// 清理指定系列的缓存
  void _clearSeriesCache(String jellyfinSeriesId, String? seasonId) {
    final cacheKey = '${jellyfinSeriesId}_${seasonId ?? 'null'}';
    _animeMappingCache.remove(cacheKey);
    
    // 清理相关的剧集预测缓存
    final keysToRemove = _episodePredictionCache.keys
        .where((key) => key.startsWith(jellyfinSeriesId))
        .toList();
    
    for (final key in keysToRemove) {
      _episodePredictionCache.remove(key);
    }
  }

  /// 清除指定系列的映射（用于重新配置）
  Future<void> clearSeriesMapping(String jellyfinSeriesId, {String? seasonId}) async {
    await initialize();

    debugPrint('[映射服务] 清除系列映射: $jellyfinSeriesId');

    // 先删除剧集映射
    await _database!.rawDelete('''
      DELETE FROM jellyfin_episode_mapping 
      WHERE mapping_id IN (
        SELECT id FROM jellyfin_dandanplay_mapping 
        WHERE jellyfin_series_id = ? AND (jellyfin_season_id = ? OR ? IS NULL)
      )
    ''', [jellyfinSeriesId, seasonId, seasonId]);

    // 再删除动画映射
    await _database!.delete(
      'jellyfin_dandanplay_mapping',
      where: 'jellyfin_series_id = ? AND (jellyfin_season_id = ? OR ? IS NULL)',
      whereArgs: [jellyfinSeriesId, seasonId, seasonId],
    );

    // 清理相关缓存
    _clearSeriesCache(jellyfinSeriesId, seasonId);

    debugPrint('[映射服务] 映射清除完成');
  }

  /// 获取映射统计信息（增强版本）
  Future<Map<String, dynamic>> getMappingStats() async {
    await initialize();

    // 基础统计
    final animeMappingCount = await _database!.rawQuery('SELECT COUNT(*) as count FROM jellyfin_dandanplay_mapping');
    final episodeMappingCount = await _database!.rawQuery('SELECT COUNT(*) as count FROM jellyfin_episode_mapping');
    final confirmedMappingCount = await _database!.rawQuery('SELECT COUNT(*) as count FROM jellyfin_episode_mapping WHERE confirmed = 1');
    final predictedMappingCount = await _database!.rawQuery('SELECT COUNT(*) as count FROM jellyfin_episode_mapping WHERE confirmed = 0');

    // 最近映射活动
    final recentMappings = await _database!.rawQuery('''
      SELECT jdm.jellyfin_series_name, jdm.dandanplay_anime_title, jdm.updated_at
      FROM jellyfin_dandanplay_mapping jdm
      ORDER BY jdm.updated_at DESC
      LIMIT 5
    ''');

    // 映射准确性统计（简化版本，去掉偏移量字段）
    final accuracyStats = await _database!.rawQuery('''
      SELECT 
        jdm.jellyfin_series_name,
        COUNT(jem.id) as total_episodes,
        SUM(CASE WHEN jem.confirmed = 1 THEN 1 ELSE 0 END) as confirmed_episodes
      FROM jellyfin_dandanplay_mapping jdm
      LEFT JOIN jellyfin_episode_mapping jem ON jdm.id = jem.mapping_id
      GROUP BY jdm.id
      HAVING total_episodes > 0
    ''');

    return {
      'animeCount': (animeMappingCount.first['count'] as int?) ?? 0,
      'episodeCount': (episodeMappingCount.first['count'] as int?) ?? 0,
      'confirmedCount': (confirmedMappingCount.first['count'] as int?) ?? 0,
      'predictedCount': (predictedMappingCount.first['count'] as int?) ?? 0,
      'recentMappings': recentMappings,
      'accuracyStats': accuracyStats,
    };
  }

  /// 获取单个剧集的映射信息
  Future<Map<String, dynamic>?> getEpisodeMapping(String jellyfinEpisodeId) async {
    await initialize();

    final results = await _database!.query(
      'jellyfin_episode_mapping',
      where: 'jellyfin_episode_id = ?',
      whereArgs: [jellyfinEpisodeId],
    );

    if (results.isNotEmpty) {
      return results.first;
    }
    return null;
  }
}

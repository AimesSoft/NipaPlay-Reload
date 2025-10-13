import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/services/bangumi_api_service.dart';

/// Bangumi同步服务
/// 
/// 提供本地观看历史与Bangumi收藏状态的同步功能
/// 包括：
/// - 手动同步本地观看历史到Bangumi
/// - 数据映射逻辑（观看进度转收藏状态）
/// - 增量同步（只同步更新的记录）
/// - 进度跟踪和错误处理
/// 
/// 遵循项目的单例模式和错误处理标准
class BangumiSyncService {
  static final BangumiSyncService instance = BangumiSyncService._();
  static const String _lastSyncTimeKey = 'bangumi_last_sync_time';
  static const String _syncStatusKey = 'bangumi_sync_status';
  static const String _syncedItemsKey = 'bangumi_synced_items';

  BangumiSyncService._();

  /// 初始化服务
  static Future<void> initialize() async {
    await BangumiApiService.initialize();
    debugPrint('[Bangumi同步] 同步服务初始化完成');
  }

  /// 获取上次同步时间
  static Future<DateTime?> getLastSyncTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final timeStr = prefs.getString(_lastSyncTimeKey);
      if (timeStr != null) {
        return DateTime.parse(timeStr);
      }
    } catch (e) {
      debugPrint('[Bangumi同步] 获取上次同步时间失败: $e');
    }
    return null;
  }

  /// 保存同步时间
  static Future<void> _saveLastSyncTime(DateTime time) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_lastSyncTimeKey, time.toIso8601String());
    } catch (e) {
      debugPrint('[Bangumi同步] 保存同步时间失败: $e');
    }
  }

  /// 获取同步状态
  static Future<Map<String, dynamic>?> getSyncStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statusStr = prefs.getString(_syncStatusKey);
      if (statusStr != null) {
        return json.decode(statusStr);
      }
    } catch (e) {
      debugPrint('[Bangumi同步] 获取同步状态失败: $e');
    }
    return null;
  }

  /// 保存同步状态
  static Future<void> _saveSyncStatus(Map<String, dynamic> status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncStatusKey, json.encode(status));
    } catch (e) {
      debugPrint('[Bangumi同步] 保存同步状态失败: $e');
    }
  }

  /// 获取已同步的项目ID列表
  static Future<Set<String>> _getSyncedItems() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final itemsStr = prefs.getString(_syncedItemsKey);
      if (itemsStr != null) {
        final List<dynamic> items = json.decode(itemsStr);
        return items.cast<String>().toSet();
      }
    } catch (e) {
      debugPrint('[Bangumi同步] 获取已同步项目失败: $e');
    }
    return <String>{};
  }

  /// 保存已同步的项目ID列表
  static Future<void> _saveSyncedItems(Set<String> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncedItemsKey, json.encode(items.toList()));
    } catch (e) {
      debugPrint('[Bangumi同步] 保存已同步项目失败: $e');
    }
  }

  /// 根据观看历史计算Bangumi收藏类型
  /// 
  /// 逻辑：
  /// 1. 观看任意一集 → Doing（在看）
  /// 2. 观看完全部集数 → Done（看过）
  /// 3. 完全未观看 → Wish（想看）
  /// 
  /// [episodes] 该动画的所有剧集观看记录
  /// 返回Bangumi收藏类型：1=Wish, 2=Done, 3=Doing
  static int _calculateCollectionType(List<WatchHistoryItem> episodes) {
    // 过滤有效的剧集（有观看进度的）
    final validEpisodes = episodes.where((episode) => episode.watchProgress >= 0.0).toList();
    
    if (validEpisodes.isEmpty) {
      return 1; // Wish - 完全未观看
    }
    
    // 检查是否观看任意一集
    final hasWatchedAnyEpisode = validEpisodes.any((episode) => episode.watchProgress > 0.1);
    
    if (!hasWatchedAnyEpisode) {
      return 1; // Wish - 观看进度太低，视为未观看
    }
    
    // 检查是否所有有效集数都观看完成
    final completedEpisodes = validEpisodes.where((episode) => episode.watchProgress >= 0.95).toList();
    
    // 如果所有有效集数都完成了，则标记为"看过"
    if (completedEpisodes.length == validEpisodes.length && validEpisodes.isNotEmpty) {
      return 2; // Done - 所有集数都已观看完成
    }
    
    // 否则标记为"在看"
    return 3; // Doing - 至少观看了一集但未完成全部
  }

  /// 将观看进度转换为剧集收藏类型
  /// 
  /// [watchProgress] 观看进度 (0.0-1.0)
  /// 返回剧集收藏类型：0=Uncollected, 1=Wish, 2=Done
  static int _mapWatchProgressToEpisodeType(double watchProgress) {
    if (watchProgress <= 0.1) {
      return 1; // Wish - 想看
    } else if (watchProgress >= 0.8) {
      return 2; // Done - 看过
    } else {
      return 0; // Uncollected - 未收藏（观看中但进度不足）
    }
  }

  /// 根据弹弹play的anime_id查找对应的Bangumi subject_id
  /// 
  /// [animeId] 弹弹play的动画ID
  /// [animeName] 动画名称（用于搜索）
  /// 返回Bangumi的subject_id，如果找不到返回null
  static Future<int?> _findBangumiSubjectId(int animeId, String animeName) async {
    try {
      debugPrint('[Bangumi同步] 查找Bangumi条目: animeId=$animeId, name=$animeName');

      // 尝试通过名称搜索Bangumi条目
      final searchResult = await BangumiApiService.searchSubjects(
        animeName,
        type: 2, // 动画类型
        limit: 10,
      );

      if (searchResult['success'] && searchResult['data'] != null) {
        final searchData = searchResult['data'];
        final List<dynamic> items = searchData['data'] ?? [];

        if (items.isNotEmpty) {
          // 取第一个匹配结果
          final firstItem = items.first;
          final subjectId = firstItem['id'] as int?;
          
          if (subjectId != null) {
            debugPrint('[Bangumi同步] 找到Bangumi条目: $subjectId');
            return subjectId;
          }
        }
      }

      debugPrint('[Bangumi同步] 未找到对应的Bangumi条目: $animeName');
      return null;
    } catch (e) {
      debugPrint('[Bangumi同步] 查找Bangumi条目失败: $e');
      return null;
    }
  }

  /// 同步单个动画的观看历史到Bangumi
  /// 
  /// [animeId] 弹弹play动画ID
  /// [episodes] 该动画的所有剧集观看记录
  /// [progressCallback] 进度回调函数
  /// 返回同步结果
  static Future<Map<String, dynamic>> _syncAnimeToBangumi({
    required int animeId,
    required List<WatchHistoryItem> episodes,
    Function(String)? progressCallback,
  }) async {
    try {
      if (episodes.isEmpty) {
        return {
          'success': false,
          'message': '没有需要同步的剧集',
        };
      }

      // 获取动画信息
      final firstEpisode = episodes.first;
      final animeName = firstEpisode.animeName;

      progressCallback?.call('正在查找 $animeName 的Bangumi条目...');

      // 查找对应的Bangumi subject_id
      final subjectId = await _findBangumiSubjectId(animeId, animeName);
      if (subjectId == null) {
        return {
          'success': false,
          'message': '未找到对应的Bangumi条目: $animeName',
        };
      }

      progressCallback?.call('正在同步 $animeName 的观看状态...');

      // 计算正确的收藏类型
      final collectionType = _calculateCollectionType(episodes);
      debugPrint('[Bangumi同步] 计算得到的收藏类型: $collectionType (动画: $animeName)');

      // 检查是否已收藏该条目
      final existingCollection = await BangumiApiService.getUserCollection(subjectId);
      
      int targetCollectionType = collectionType;
      
      if (existingCollection['success'] && existingCollection['data'] != null) {
        // 已收藏，获取当前收藏类型
        final currentType = existingCollection['data']['type'] as int?;
        debugPrint('[Bangumi同步] 条目已收藏，当前类型: $currentType');
        
        // 根据优先级决定是否需要更新
        // Done(2) > Doing(3) > Wish(1)
        if (currentType != null) {
          bool shouldUpdate = false;
          
          if (targetCollectionType == 2) { // Done - 最高优先级
            shouldUpdate = currentType != 2; // 只有当前不是Done才更新
          } else if (targetCollectionType == 3) { // Doing - 中等优先级
            shouldUpdate = currentType == 1; // 只有当前是Wish才更新
          } else { // Wish - 最低优先级，不更新已有的收藏
            shouldUpdate = false;
          }
          
          if (shouldUpdate) {
            debugPrint('[Bangumi同步] 需要更新收藏状态: $currentType → $targetCollectionType');
          } else {
            debugPrint('[Bangumi同步] 无需更新收藏状态: 当前状态优先级更高或相等');
            targetCollectionType = currentType; // 保持原有状态
          }
        }
      } else {
        // 未收藏，添加新收藏
        debugPrint('[Bangumi同步] 条目未收藏，将添加新收藏，类型: $targetCollectionType');
        final addResult = await BangumiApiService.addUserCollection(
          subjectId,
          targetCollectionType,
          comment: '通过NipaPlay同步新增收藏',
        );
        
        if (!addResult['success']) {
          debugPrint('[Bangumi同步] 添加收藏失败: ${addResult['message']}');
          // 继续执行，尝试更新
        }
      }

      // 预先计算有效观看记录数量（用于更准确的收藏comment）
      final watchedEpisodesCount = episodes.where((e) => 
        e.watchProgress > 0.1
      ).length;

      // 更新动画收藏状态（使用PATCH确保更新而非替换）
      final collectionResult = await BangumiApiService.updateUserCollection(
        subjectId,
        targetCollectionType,
        comment: '通过NipaPlay同步 (观看${watchedEpisodesCount}/${episodes.length}集)',
      );

      if (!collectionResult['success']) {
        debugPrint('[Bangumi同步] 更新动画收藏状态失败: ${collectionResult['message']}');
        // 收藏状态更新失败，直接返回错误，不再继续处理该剧集
        return {
          'success': false,
          'message': '更新收藏状态失败: ${collectionResult['message']}',
          'animeId': animeId,
          'animeName': animeName,
          'detail': '无法更新Bangumi收藏状态，已跳过剧集状态同步',
        };
      }
      
      debugPrint('[Bangumi同步] 动画收藏状态更新成功，类型: $targetCollectionType');

      // 获取Bangumi的剧集信息（用于剧集状态同步）
      // 使用分页处理集数过多的动画
      List<Map<String, dynamic>> bangumiEpisodes = [];
      int offset = 0;
      const int pageSize = 100; // 每次获取100集
      bool hasMoreEpisodes = true;
      
      while (hasMoreEpisodes) {
        final episodesResult = await BangumiApiService.getSubjectEpisodes(
          subjectId,
          type: 0, // 正片
          limit: pageSize,
          offset: offset,
        );

        if (episodesResult['success'] && episodesResult['data'] != null) {
          final episodeData = episodesResult['data'];
          final currentBatch = List<Map<String, dynamic>>.from(episodeData['data'] ?? []);
          
          if (currentBatch.isEmpty) {
            hasMoreEpisodes = false;
          } else {
            bangumiEpisodes.addAll(currentBatch);
            offset += currentBatch.length;
            debugPrint('[Bangumi同步] 已获取 ${bangumiEpisodes.length} 个剧集信息');
            
            // 检查是否还有更多剧集
            final total = episodeData['total'] as int?;
            if (total != null && bangumiEpisodes.length >= total) {
              hasMoreEpisodes = false;
            } else if (currentBatch.length < pageSize) {
              // 返回的数量少于请求的数量，说明没有更多了
              hasMoreEpisodes = false;
            }
            
            // 添加短暂延迟，避免请求过快
            if (hasMoreEpisodes) {
              await Future.delayed(const Duration(milliseconds: 200));
            }
          }
        } else {
          debugPrint('[Bangumi同步] 获取剧集信息失败: ${episodesResult['message'] ?? '未知错误'}');
          hasMoreEpisodes = false;
        }
      }
      
      debugPrint('[Bangumi同步] 总共获取 ${bangumiEpisodes.length} 个剧集信息');

      // 同步剧集观看状态
      int syncedEpisodeCount = 0;
      final List<Map<String, dynamic>> episodeUpdates = [];

      for (var watchHistoryItem in episodes) {
        // 尝试通过集数匹配Bangumi剧集
        Map<String, dynamic>? matchedBangumiEpisode;
        
        if (watchHistoryItem.episodeId != null) {
          // 尝试通过序号匹配
          for (var bangumiEp in bangumiEpisodes) {
            // sort 可能是 int 或 double，统一处理为 int
            final sortValue = bangumiEp['sort'];
            int? sort;
            if (sortValue is int) {
              sort = sortValue;
            } else if (sortValue is double) {
              sort = sortValue.toInt();
            }
            
            if (sort != null && sort == watchHistoryItem.episodeId) {
              matchedBangumiEpisode = bangumiEp;
              break;
            }
          }
        }

        if (matchedBangumiEpisode != null) {
          final bangumiEpisodeId = matchedBangumiEpisode['id'] as int?;
          if (bangumiEpisodeId != null) {
            final episodeType = _mapWatchProgressToEpisodeType(watchHistoryItem.watchProgress);
            
            // 只同步有明确观看状态的剧集（想看或看过）
            if (episodeType == 1 || episodeType == 2) {
              episodeUpdates.add({
                'id': bangumiEpisodeId,
                'type': episodeType,
              });
              syncedEpisodeCount++;
              debugPrint('[Bangumi同步] 准备更新剧集状态: ID=$bangumiEpisodeId, 类型=$episodeType');
            } else {
              debugPrint('[Bangumi同步] 跳过剧集更新: ID=$bangumiEpisodeId, 进度=${watchHistoryItem.watchProgress}（未达到收藏阈值）');
            }
          }
        }
      }

      // 批量更新剧集状态
      if (episodeUpdates.isNotEmpty) {
        progressCallback?.call('正在更新 $syncedEpisodeCount 集的观看状态...');
        debugPrint('[Bangumi同步] 开始批量更新 ${episodeUpdates.length} 个剧集状态');
        
        final episodeResult = await BangumiApiService.batchUpdateEpisodeCollections(
          subjectId,
          episodeUpdates,
        );

        if (!episodeResult['success']) {
          debugPrint('[Bangumi同步] 更新剧集状态失败: ${episodeResult['message']}');
          // 不作为致命错误，继续处理其他项目
        } else {
          debugPrint('[Bangumi同步] 成功更新 $syncedEpisodeCount 个剧集状态');
        }
      } else {
        debugPrint('[Bangumi同步] 没有需要更新的剧集状态');
      }

      return {
        'success': true,
        'message': '同步成功: $animeName',
        'animeId': animeId,
        'subjectId': subjectId,
        'syncedEpisodes': syncedEpisodeCount,
        'totalEpisodes': episodes.length,
      };

    } catch (e, stackTrace) {
      debugPrint('[Bangumi同步] 同步单个动画时发生异常: $e');
      debugPrint('[Bangumi同步] 异常堆栈: $stackTrace');
      
      return {
        'success': false,
        'message': '同步失败: $e',
        'detail': '可能是网络问题、API限制或数据格式错误',
      };
    }
  }

  /// 同步本地观看历史到Bangumi
  /// 
  /// [forceFullSync] 是否强制全量同步，否则只同步增量数据
  /// [progressCallback] 进度回调函数，参数为当前操作描述
  /// 返回同步结果
  static Future<Map<String, dynamic>> syncWatchHistoryToBangumi({
    bool forceFullSync = false,
    Function(String)? progressCallback,
    Function(int, int)? countCallback, // 新增：传递当前进度和总数
  }) async {
    try {
      // 检查是否已授权
      if (!BangumiApiService.isLoggedIn) {
        return {
          'success': false,
          'message': '请先设置Bangumi访问令牌',
        };
      }

      progressCallback?.call('正在获取本地观看历史...');

      // 获取所有观看历史
      List<WatchHistoryItem> allHistory;
      
      // 检查是否已迁移到数据库
      if (WatchHistoryManager.isMigratedToDatabase()) {
        final db = WatchHistoryDatabase.instance;
        allHistory = await db.getAllWatchHistory();
      } else {
        allHistory = await WatchHistoryManager.getAllHistory();
      }

      if (allHistory.isEmpty) {
        return {
          'success': true,
          'message': '没有观看历史需要同步',
          'syncedCount': 0,
        };
      }

      // 过滤有animeId的记录
      final validHistory = allHistory.where((item) => 
        item.animeId != null && item.animeId! > 0
      ).toList();

      if (validHistory.isEmpty) {
        return {
          'success': false,
          'message': '没有匹配到弹弹play动画ID的观看记录',
        };
      }

      // 按animeId分组
      final Map<int, List<WatchHistoryItem>> groupedHistory = {};
      for (var item in validHistory) {
        final animeId = item.animeId!;
        groupedHistory.putIfAbsent(animeId, () => []);
        groupedHistory[animeId]!.add(item);
      }

      debugPrint('[Bangumi同步] 找到 ${groupedHistory.length} 个动画，共 ${validHistory.length} 集');

      // 增量同步逻辑
      Set<String> syncedItems = {};
      if (!forceFullSync) {
        syncedItems = await _getSyncedItems();
        progressCallback?.call('增量同步模式：已同步 ${syncedItems.length} 个项目');
      } else {
        progressCallback?.call('全量同步模式：将同步所有观看历史');
      }

      // 开始同步
      final List<Map<String, dynamic>> syncResults = [];
      int successCount = 0;
      int skipCount = 0;
      int errorCount = 0;
      int currentIndex = 0;
      final totalAnimes = groupedHistory.length;

      for (var entry in groupedHistory.entries) {
        final animeId = entry.key;
        final episodes = entry.value;
        final animeName = episodes.first.animeName;
        
        currentIndex++;
        countCallback?.call(currentIndex, totalAnimes);

        // 生成同步项目的唯一标识
        final syncItemId = 'anime_$animeId';

        // 检查是否需要跳过（增量同步）
        if (!forceFullSync && syncedItems.contains(syncItemId)) {
          skipCount++;
          progressCallback?.call('跳过已同步: $animeName ($currentIndex/$totalAnimes)');
          continue;
        }

        progressCallback?.call('同步中: $animeName ($currentIndex/$totalAnimes)');

        // 同步单个动画
        final result = await _syncAnimeToBangumi(
          animeId: animeId,
          episodes: episodes,
          progressCallback: progressCallback,
        );

        syncResults.add({
          'animeId': animeId,
          'animeName': animeName,
          'result': result,
        });

        if (result['success']) {
          successCount++;
          syncedItems.add(syncItemId);
          debugPrint('[Bangumi同步] 成功同步: $animeName (${result['syncedEpisodes']}/${result['totalEpisodes']}集)');
        } else {
          errorCount++;
          debugPrint('[Bangumi同步] 同步失败: $animeName - ${result['message']}');
        }

        // 避免频繁请求，添加延迟
        if (currentIndex < totalAnimes) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 保存同步状态
      final now = DateTime.now();
      await _saveLastSyncTime(now);
      await _saveSyncedItems(syncedItems);

      final status = {
        'lastSyncTime': now.toIso8601String(),
        'totalAnimes': totalAnimes,
        'successCount': successCount,
        'skipCount': skipCount,
        'errorCount': errorCount,
        'syncMode': forceFullSync ? 'full' : 'incremental',
      };
      await _saveSyncStatus(status);

      progressCallback?.call('同步完成！');

      return {
        'success': true,
        'message': '同步完成：成功 $successCount 个，跳过 $skipCount 个，失败 $errorCount 个',
        'totalAnimes': totalAnimes,
        'successCount': successCount,
        'skipCount': skipCount,
        'errorCount': errorCount,
        'syncResults': syncResults,
        'syncedCount': successCount,
      };

    } catch (e, stackTrace) {
      debugPrint('[Bangumi同步] 同步过程发生异常: $e');
      debugPrint('[Bangumi同步] 异常堆栈: $stackTrace');
      
      return {
        'success': false,
        'message': '同步失败: $e',
      };
    }
  }

  /// 清除同步缓存
  /// 
  /// 清除已同步项目的记录，下次同步时将重新同步所有项目
  static Future<Map<String, dynamic>> clearSyncCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_syncedItemsKey);
      await prefs.remove(_syncStatusKey);
      
      debugPrint('[Bangumi同步] 同步缓存已清除');
      
      return {
        'success': true,
        'message': '同步缓存已清除，下次将重新同步所有项目',
      };
    } catch (e) {
      return {
        'success': false,
        'message': '清除缓存失败: $e',
      };
    }
  }

  /// 获取同步统计信息
  /// 
  /// 返回上次同步的详细统计信息
  static Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final lastSyncTime = await getLastSyncTime();
      final syncStatus = await getSyncStatus();
      final syncedItems = await _getSyncedItems();

      return {
        'success': true,
        'lastSyncTime': lastSyncTime?.toIso8601String(),
        'syncedItemsCount': syncedItems.length,
        'lastSyncStatus': syncStatus,
        'isLoggedIn': BangumiApiService.isLoggedIn,
        'userInfo': BangumiApiService.userInfo,
      };
    } catch (e) {
      return {
        'success': false,
        'message': '获取统计信息失败: $e',
      };
    }
  }

  /// 测试Bangumi API连接
  /// 
  /// 验证当前Token是否有效，并获取用户信息
  static Future<Map<String, dynamic>> testBangumiConnection() async {
    try {
      if (!BangumiApiService.isLoggedIn) {
        return {
          'success': false,
          'message': '未设置访问令牌',
        };
      }

      // 尝试获取用户信息
      final result = await BangumiApiService.testConnection();
      
      if (result['success']) {
        final userData = result['data'];
        return {
          'success': true,
          'message': '连接成功',
          'userInfo': userData,
        };
      } else {
        return {
          'success': false,
          'message': '连接失败: ${result['message']}',
        };
      }
    } catch (e, stackTrace) {
      debugPrint('[Bangumi同步] 测试连接时发生异常: $e');
      debugPrint('[Bangumi同步] 异常堆栈: $stackTrace');
      return {
        'success': false,
        'message': '连接测试失败: $e',
      };
    }
  }
}
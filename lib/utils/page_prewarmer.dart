import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/bangumi_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

/// 页面预热类
/// 
/// 用于应用启动后预加载常用数据，提升用户体验
class PagePrewarmer {
  static final PagePrewarmer _instance = PagePrewarmer._internal();
  static const String _detailsCacheKeyPrefix = 'bangumi_detail_';
  
  factory PagePrewarmer() {
    return _instance;
  }
  
  PagePrewarmer._internal();
  
  bool _isInitialized = false;
  bool _isPrewarmingActive = false;
  
  /// 初始化预热服务
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    debugPrint('[页面预热] 初始化预热服务');
    
    // 初始化弹弹play服务（确保token、API密钥等已就绪）
    await DandanplayService.initialize();
    
    // 初始化番剧服务
    await BangumiService.instance.initialize();
    
    // 检查并修复旧格式的番剧缓存
    await _checkAndFixAnimeCache();
    
    _isInitialized = true;
    debugPrint('[页面预热] 预热服务初始化完成');
  }
  
  /// 检查并修复旧格式的番剧缓存
  Future<void> _checkAndFixAnimeCache() async {
    try {
      debugPrint('[页面预热] 开始检查并修复番剧缓存');
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final detailsKeys = keys.where((key) => key.startsWith(_detailsCacheKeyPrefix)).toList();
      int fixedCount = 0;
      List<int> needRefreshAnimeIds = [];
      
      // 检查每个缓存的格式
      for (var key in detailsKeys) {
        try {
          final String? cachedString = prefs.getString(key);
          if (cachedString != null) {
            final data = json.decode(cachedString);
            
            // 提取animeId
            final animeId = int.parse(key.substring(_detailsCacheKeyPrefix.length));
            
            // 检查是否需要修复
            bool needsFix = false;
            
            if (data.containsKey('animeDetail')) {
              final Map<String, dynamic> animeData = data['animeDetail'];
              
              // 检查剧集列表格式
              if (animeData.containsKey('episodeList') && animeData['episodeList'] is List) {
                final episodeList = animeData['episodeList'] as List;
                if (episodeList.isNotEmpty) {
                  // 检查第一个剧集的格式
                  final firstEpisode = episodeList.first;
                  if (firstEpisode is Map && 
                      (firstEpisode.containsKey('id') && !firstEpisode.containsKey('episodeId'))) {
                    needsFix = true;
                  }
                }
              }
              
              // 检查是否包含episodes字段，如果没有则需要修复
              if (!animeData.containsKey('episodes')) {
                needsFix = true;
              }
            }
            
            if (needsFix) {
              debugPrint('[页面预热] 发现需要修复的番剧缓存: $animeId');
              // 添加到需要刷新的ID列表
              needRefreshAnimeIds.add(animeId);
              
              // 删除当前缓存
              await prefs.remove(key);
              fixedCount++;
            }
          }
        } catch (e) {
          debugPrint('[页面预热] 检查单个番剧缓存时出错: $e');
          continue;
        }
      }
      
      debugPrint('[页面预热] 共有 $fixedCount 条番剧缓存需要刷新');
      
      // 异步刷新需要更新的番剧数据
      if (needRefreshAnimeIds.isNotEmpty) {
        // 限制同时刷新的数量，避免过多请求
        const refreshLimit = 5;
        final animeIdsToRefresh = needRefreshAnimeIds.take(refreshLimit).toList();
        
        debugPrint('[页面预热] 开始刷新 ${animeIdsToRefresh.length} 条番剧数据');
        
        for (var animeId in animeIdsToRefresh) {
          try {
            // 异步获取，不等待完成
            BangumiService.instance.getAnimeDetails(animeId).then((_) {
              debugPrint('[页面预热] 成功刷新番剧 $animeId 的详情');
            }).catchError((e) {
              debugPrint('[页面预热] 刷新番剧 $animeId 详情失败: $e');
            });
            
            // 短暂延迟，避免过多并发请求
            await Future.delayed(const Duration(milliseconds: 500));
          } catch (e) {
            debugPrint('[页面预热] 刷新番剧 $animeId 时出错: $e');
          }
        }
      }
      
      debugPrint('[页面预热] 番剧缓存检查和修复完成');
    } catch (e) {
      debugPrint('[页面预热] 检查和修复番剧缓存时出错: $e');
    }
  }
  
  /// 开始预热过程
  Future<void> startPrewarm(BuildContext context) async {
    if (!_isInitialized) {
      debugPrint('[页面预热] 预热服务尚未初始化，无法开始预热');
      return;
    }
    
    if (_isPrewarmingActive) {
      debugPrint('[页面预热] 预热过程已在进行中');
      return;
    }
    
    _isPrewarmingActive = true;
    debugPrint('[页面预热] 开始页面预热过程');
    
    try {
      // 等待一小段时间，避免与启动初始化冲突
      await Future.delayed(const Duration(seconds: 2));
      
      // 开始预热过程
      await _prewarmBangumiData();
      await _prewarmWatchHistory(context);
      
      debugPrint('[页面预热] 页面预热完成');
    } catch (e) {
      debugPrint('[页面预热] 预热过程发生错误: $e');
    } finally {
      _isPrewarmingActive = false;
    }
  }
  
  /// 预热番剧数据
  Future<void> _prewarmBangumiData() async {
    try {
      debugPrint('[页面预热] 开始预热番剧数据');
      
      // 预加载最近更新的番剧
      await DandanplayService.preloadRecentAnimes();
      
      // 预加载常用的番剧数据
      await BangumiService.instance.preloadCommonData();
      
      debugPrint('[页面预热] 番剧数据预热完成');
    } catch (e) {
      debugPrint('[页面预热] 番剧数据预热失败: $e');
    }
  }
  
  /// 预热观看历史数据（包括检查缺失的animeid和episodeid）
  Future<void> _prewarmWatchHistory(BuildContext context) async {
    try {
      debugPrint('[页面预热] 开始预热观看历史数据');
      
      // 获取观看历史提供者
      final historyProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      
      // 确保历史已加载
      if (!historyProvider.isLoaded) {
        await historyProvider.loadHistory();
      }
      
      // 获取最近观看的历史项
      final recentHistory = historyProvider.history
          .where((item) => item.lastWatchTime != null)
          .toList()
          ..sort((a, b) => (b.lastWatchTime).compareTo(a.lastWatchTime));
      
      // 仅处理最近的10个历史项
      final historyToProcess = recentHistory.take(10).toList();
      debugPrint('[页面预热] 准备处理 ${historyToProcess.length} 条最近观看历史');
      
      // 检查并修复每一条历史
      for (final historyItem in historyToProcess) {
        await _checkAndFixHistoryItem(historyItem, historyProvider);
      }
      
      debugPrint('[页面预热] 观看历史数据预热完成');
    } catch (e) {
      debugPrint('[页面预热] 观看历史数据预热失败: $e');
    }
  }
  
  /// 检查并修复单个历史项
  Future<void> _checkAndFixHistoryItem(WatchHistoryItem historyItem, WatchHistoryProvider historyProvider) async {
    // 检查是否缺少关键信息
    final needsFixing = historyItem.animeId == null || 
                        historyItem.episodeId == null || 
                        historyItem.animeId == 0 || 
                        historyItem.episodeId == 0;
    
    if (needsFixing) {
      final fileName = path.basename(historyItem.filePath);
      debugPrint('[页面预热] 发现需要修复的历史项: $fileName');
      debugPrint('[页面预热] 当前信息: animeId=${historyItem.animeId}, episodeId=${historyItem.episodeId}');
      
      try {
        // 使用文件名和路径重新获取匹配信息
        final filePath = historyItem.filePath;
        
        if (filePath.isNotEmpty && File(filePath).existsSync()) {
          // 重新匹配视频信息
          final videoMatchInfo = await DandanplayService.getVideoInfo(filePath);
          
          if (videoMatchInfo['success'] == true && videoMatchInfo['matches'] != null) {
            final matches = videoMatchInfo['matches'] as List;
            if (matches.isNotEmpty) {
              // 获取第一个匹配结果
              final matchInfo = matches.first as Map<String, dynamic>;
              final animeId = matchInfo['animeId'] as int?;
              final episodeId = matchInfo['episodeId'] as int?;
              
              if (animeId != null && episodeId != null && animeId > 0 && episodeId > 0) {
                // 更新历史项
                historyItem.animeId = animeId;
                historyItem.episodeId = episodeId;
                
                // 保存更新后的历史
                await historyProvider.addOrUpdateHistory(historyItem);
                
                debugPrint('[页面预热] 成功修复历史项: animeId=$animeId, episodeId=$episodeId');
                
                // 尝试预加载番剧详情
                if (animeId > 0) {
                  BangumiService.instance.getAnimeDetails(animeId).catchError((e) {
                    debugPrint('[页面预热] 预加载番剧 $animeId 详情失败: $e');
                  });
                }
              } else {
                debugPrint('[页面预热] 匹配到信息但animeId或episodeId无效');
              }
            } else {
              debugPrint('[页面预热] 未找到匹配结果');
            }
          } else {
            debugPrint('[页面预热] 匹配视频信息失败: ${videoMatchInfo['errorMessage'] ?? '未知错误'}');
          }
        } else {
          debugPrint('[页面预热] 无法修复历史项：文件不存在或路径为空');
        }
      } catch (e) {
        debugPrint('[页面预热] 修复历史项时出错: $e');
      }
    } else if (historyItem.animeId != null && historyItem.animeId! > 0) {
      // 对于不需要修复的项，预加载番剧详情
      debugPrint('[页面预热] 预加载已有历史项的番剧详情: animeId=${historyItem.animeId}');
      
      // 检查是否需要刷新番剧详情缓存
      final hasCache = await BangumiService.instance.hasCachedAnimeDetails(historyItem.animeId!);
      
      if (!hasCache) {
        // 没有缓存，加载详情
        BangumiService.instance.getAnimeDetails(historyItem.animeId!).catchError((e) {
          debugPrint('[页面预热] 预加载番剧 ${historyItem.animeId} 详情失败: $e');
        });
      } else {
        debugPrint('[页面预热] 番剧 ${historyItem.animeId} 详情已缓存，无需重新加载');
      }
    }
  }
} 
import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/services/web_remote_access_service.dart';

/// 用户活动记录的业务逻辑控制器
/// 包含所有共享的功能和状态管理
mixin UserActivityController<T extends StatefulWidget> on State<T>, TickerProvider {
  late TabController tabController;
  bool isLoading = true;
  
  // 数据
  List<Map<String, dynamic>> recentWatched = [];
  List<Map<String, dynamic>> favorites = [];
  List<Map<String, dynamic>> rated = [];
  
  // 错误状态
  String? error;
  
  // 分页控制
  static const int maxDisplayItems = 100; // 最大显示数量

  @override
  void initState() {
    super.initState();
    tabController = TabController(length: 3, vsync: this);
    loadUserActivity();
  }

  @override
  void dispose() {
    tabController.dispose();
    super.dispose();
  }

  /// 加载用户活动数据
  Future<void> loadUserActivity() async {
    final logService = DebugLogService();
    if (!DandanplayService.isLoggedIn) {
      if (mounted) {
        setState(() {
          isLoading = false;
          error = context.l10n.userActivityNotLoggedIn;
        });
      }
      logService.addWarning('用户活动加载失败: 未登录弹弹play账号', tag: 'UserActivity');
      return;
    }

    if (mounted) {
      setState(() {
        isLoading = true;
        error = null;
      });
    }
    logService.addLog('开始加载用户活动记录', level: 'INFO', tag: 'UserActivity');

    try {
      // 并行获取所有数据
      final results = await Future.wait([
        DandanplayService.getUserPlayHistory(),
        DandanplayService.getUserFavorites(),
      ]);

      final playHistory = results[0];
      final favoritesData = results[1];

      // 处理观看历史
      final List<Map<String, dynamic>> recentWatchedList = [];

      
      if (playHistory['success'] == true && playHistory['playHistoryAnimes'] != null) {
        final animes = playHistory['playHistoryAnimes'] as List;
        
        // 取最近观看的动画（最多显示设定数量）
        final animesToProcess = animes.take(maxDisplayItems);
        
        for (final anime in animesToProcess) {
          final animeId = anime['animeId'];
          final animeTitle = anime['animeTitle'];
          
          // 确保animeId是有效的整数且animeTitle不为空
          if (animeId != null && animeId is int && animeTitle != null && animeTitle.toString().isNotEmpty) {
            // 获取最后观看的剧集信息
            String? lastEpisodeTitle;
            String? lastWatchedTime;
            
            if (anime['episodes'] != null && (anime['episodes'] as List).isNotEmpty) {
              final episodes = anime['episodes'] as List;
              DateTime? latestWatchTime;
              // 找到最后观看的剧集，通过比较 lastWatched 时间
              for (final episode in episodes) {
                if (episode['lastWatched'] != null) {
                  final currentWatchTime = DateTime.tryParse(episode['lastWatched'] as String);
                  if (currentWatchTime != null) {
                    if (latestWatchTime == null || currentWatchTime.isAfter(latestWatchTime)) {
                      latestWatchTime = currentWatchTime;
                      lastEpisodeTitle = episode['episodeTitle'] as String?;
                      lastWatchedTime = episode['lastWatched'] as String?;
                    }
                  }
                }
              }
            }
            
            recentWatchedList.add({
              'animeId': animeId,
              'animeTitle': animeTitle.toString(),
              'imageUrl': anime['imageUrl'] as String?,
              'lastEpisodeTitle': lastEpisodeTitle,
              'lastWatchedTime': lastWatchedTime,
            });
          }
        }
      }

      // 处理收藏和评分
      final List<Map<String, dynamic>> favoriteList = [];
      final List<Map<String, dynamic>> ratedList = [];
      
      if (favoritesData['success'] == true && favoritesData['favorites'] != null) {
        final favs = favoritesData['favorites'] as List;
        
        for (final fav in favs) {
          final animeId = fav['animeId'];
          final animeTitle = fav['animeTitle'];
          final userRating = fav['userRating'];
          
          // 确保animeId是有效的整数且animeTitle不为空
          if (animeId != null && animeId is int && animeTitle != null && animeTitle.toString().isNotEmpty) {
            final ratingValue = (userRating is int) ? userRating : 0;
            
            favoriteList.add({
              'animeId': animeId,
              'animeTitle': animeTitle.toString(),
              'imageUrl': fav['imageUrl'] as String?,
              'favoriteStatus': fav['favoriteStatus'] as String?,
              'rating': ratingValue,
            });
            
            // 如果有评分，也添加到评分列表
            if (ratingValue > 0) {
              ratedList.add({
                'animeId': animeId,
                'animeTitle': animeTitle.toString(),
                'imageUrl': fav['imageUrl'] as String?,
                'rating': ratingValue,
              });
            }
          }
        }
      }

      if (mounted) {
        setState(() {
          recentWatched = recentWatchedList;
          favorites = favoriteList;
          rated = ratedList;
          isLoading = false;
        });
      }
      logService.addLog(
        '用户活动加载完成: 观看${recentWatchedList.length}，收藏${favoriteList.length}，评分${ratedList.length}',
        level: 'INFO',
        tag: 'UserActivity',
      );
    } catch (e, stackTrace) {
      logService.addError('用户活动加载失败: $e', tag: 'UserActivity');
      logService.addError('用户活动异常堆栈: $stackTrace', tag: 'UserActivity');
      if (mounted) {
        setState(() {
          error = context.l10n.loadFailedWithError(e.toString());
          isLoading = false;
        });
      }
    }
  }

  /// 打开动画详情页面
  void openAnimeDetail(int animeId) {
    ThemedAnimeDetail.show(context, animeId);
  }

  /// 格式化时间显示
  String formatTime(String? timeString) {
    if (timeString == null) return '';
    
    try {
      final dateTime = DateTime.tryParse(timeString);
      if (dateTime == null) return '';
      
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 0) {
        return context.l10n.daysAgo(difference.inDays);
      } else if (difference.inHours > 0) {
        return context.l10n.hoursAgo(difference.inHours);
      } else if (difference.inMinutes > 0) {
        return context.l10n.minutesAgo(difference.inMinutes);
      } else {
        return context.l10n.justNow;
      }
    } catch (e) {
      return '';
    }
  }

  /// 获取评分文本
  String getRatingText(int rating) {
    if (rating >= 9) return context.l10n.ratingLevelMasterpiece;
    if (rating >= 8) return context.l10n.ratingLevelGreat;
    if (rating >= 7) return context.l10n.ratingLevelGood;
    if (rating >= 6) return context.l10n.ratingLevelAverage;
    if (rating >= 5) return context.l10n.ratingLevelOkay;
    if (rating >= 4) return context.l10n.ratingLevelPoor;
    if (rating >= 3) return context.l10n.ratingLevelVeryPoor;
    return context.l10n.ratingLevelTerrible;
  }

  /// 处理图片URL（Web代理）
  String? processImageUrl(String? imageUrl) {
    if (kIsWeb && imageUrl != null && imageUrl.isNotEmpty) {
      return WebRemoteAccessService.imageProxyUrl(imageUrl) ?? imageUrl;
    }
    return imageUrl;
  }

  /// 获取收藏状态文本
  String getFavoriteStatusText(String? status) {
    switch (status) {
      case 'favorited':
        return context.l10n.favoriteStatusFollowing;
      case 'finished':
        return context.l10n.favoriteStatusFinished;
      case 'abandoned':
        return context.l10n.favoriteStatusAbandoned;
      default:
        return context.l10n.favoriteStatusFavorited;
    }
  }
}

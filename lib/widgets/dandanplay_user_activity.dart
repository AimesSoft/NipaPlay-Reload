import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import '../services/dandanplay_service.dart';
import '../pages/anime_detail_page.dart';

class DandanplayUserActivity extends StatefulWidget {
  const DandanplayUserActivity({super.key});

  @override
  State<DandanplayUserActivity> createState() => _DandanplayUserActivityState();
}

class _DandanplayUserActivityState extends State<DandanplayUserActivity> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  
  // 数据
  List<Map<String, dynamic>> _recentWatched = [];
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _rated = [];
  
  // 错误状态
  String? _error;
  
  // 分页控制
  static const int _maxDisplayItems = 100; // 最大显示数量

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadUserActivity();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUserActivity() async {
    if (!DandanplayService.isLoggedIn) {
      setState(() {
        _isLoading = false;
        _error = '未登录弹弹play账号';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 并行获取所有数据
      final results = await Future.wait([
        DandanplayService.getUserPlayHistory(),
        DandanplayService.getUserFavorites(),
      ]);

      final playHistory = results[0];
      final favorites = results[1];

      debugPrint('[用户活动] 播放历史响应: ${playHistory['success']}');
      debugPrint('[用户活动] 收藏列表响应: ${favorites['success']}');
      
      // 处理观看历史
      final List<Map<String, dynamic>> recentWatched = [];
      int filteredCount = 0;
      
      if (playHistory['success'] == true && playHistory['playHistoryAnimes'] != null) {
        final animes = playHistory['playHistoryAnimes'] as List;
        debugPrint('[用户活动] 观看历史动画数量: ${animes.length}');
        
        // 取最近观看的动画（最多显示设定数量）
        final animesToProcess = animes.take(_maxDisplayItems);
        
        for (final anime in animesToProcess) {
          final animeId = anime['animeId'];
          final animeTitle = anime['animeTitle'];
          
          debugPrint('[用户活动] 处理动画: animeId=$animeId (${animeId.runtimeType}), title=$animeTitle');
          
          // 确保animeId是有效的整数且animeTitle不为空
          if (animeId != null && animeId is int && animeTitle != null && animeTitle.toString().isNotEmpty) {
            // 获取最后观看的剧集信息
            String? lastEpisodeTitle;
            String? lastWatchedTime;
            
            if (anime['episodes'] != null && (anime['episodes'] as List).isNotEmpty) {
              final episodes = anime['episodes'] as List;
              // 找到最后观看的剧集
              for (final episode in episodes) {
                if (episode['lastWatched'] != null) {
                  lastEpisodeTitle = episode['episodeTitle'] as String?;
                  lastWatchedTime = episode['lastWatched'] as String?;
                  break;
                }
              }
            }
            
            recentWatched.add({
              'animeId': animeId,
              'animeTitle': animeTitle.toString(),
              'imageUrl': anime['imageUrl'] as String?,
              'lastEpisodeTitle': lastEpisodeTitle,
              'lastWatchedTime': lastWatchedTime,
            });
          } else {
            filteredCount++;
            debugPrint('[用户活动] 过滤无效动画: animeId=$animeId, title=$animeTitle');
          }
        }
        
        if (filteredCount > 0) {
          debugPrint('[用户活动] 共过滤了 $filteredCount 个无效的观看记录');
        }
      }

      // 处理收藏和评分
      final List<Map<String, dynamic>> favoriteList = [];
      final List<Map<String, dynamic>> ratedList = [];
      
      if (favorites['success'] == true && favorites['favorites'] != null) {
        final favs = favorites['favorites'] as List;
        debugPrint('[用户活动] 收藏列表数量: ${favs.length}');
        
        for (final fav in favs) {
          final animeId = fav['animeId'];
          final animeTitle = fav['animeTitle'];
          final userRating = fav['userRating'];
          
          debugPrint('[用户活动] 处理收藏: animeId=$animeId (${animeId.runtimeType}), title=$animeTitle, userRating=$userRating (${userRating.runtimeType})');
          debugPrint('[用户活动] 完整收藏对象: $fav');
          
          // 确保animeId是有效的整数且animeTitle不为空
          if (animeId != null && animeId is int && animeTitle != null && animeTitle.toString().isNotEmpty) {
            final ratingValue = (userRating is int) ? userRating : 0;
            debugPrint('[用户活动] 最终评分值: $ratingValue');
            
            final item = {
              'animeId': animeId,
              'animeTitle': animeTitle.toString(),
              'imageUrl': fav['imageUrl'] as String?,
              'favoriteStatus': fav['favoriteStatus'] as String?,
              'rating': ratingValue,
              'comment': fav['comment'] as String?,
            };
            
            favoriteList.add(item);
            
            // 如果有评分，也加入评分列表
            if (ratingValue > 0) {
              debugPrint('[用户活动] 添加到评分列表: $animeTitle, 评分: $ratingValue');
              ratedList.add(item);
            }
          }
        }
      }

      if (mounted) {
        // 打印处理结果统计
        debugPrint('[用户活动] 数据处理完成:');
        debugPrint('[用户活动] - 观看历史: ${recentWatched.length} 个动画');
        debugPrint('[用户活动] - 收藏列表: ${favoriteList.length} 个动画');
        debugPrint('[用户活动] - 评分列表: ${ratedList.length} 个动画');
        
        setState(() {
          _recentWatched = recentWatched;
          _favorites = favoriteList;
          _rated = ratedList;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '加载失败: ${e.toString()}';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        
        // 标题和刷新按钮
        Row(
          children: [
            const Text(
              '我的活动记录',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: _isLoading ? null : _loadUserActivity,
              icon: Icon(
                Ionicons.refresh_outline,
                color: _isLoading ? Colors.white30 : Colors.white70,
                size: 20,
              ),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // 标签栏
        TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.blue,
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.play_circle_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('观看(${_recentWatched.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.heart_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('收藏(${_favorites.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.star_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('评分(${_rated.length})'),
                ],
              ),
            ),
          ],
        ),
        
        // 内容区域
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Ionicons.warning_outline,
                            color: Colors.white60,
                            size: 48,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.white60),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadUserActivity,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.2),
                            ),
                            child: const Text(
                              '重试',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildRecentWatchedList(),
                        _buildFavoritesList(),
                        _buildRatedList(),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildRecentWatchedList() {
    if (_recentWatched.isEmpty) {
      return _buildEmptyState('暂无观看记录', Ionicons.play_circle_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _recentWatched.length,
      itemBuilder: (context, index) {
        final item = _recentWatched[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: item['lastEpisodeTitle'] != null 
              ? '看到: ${item['lastEpisodeTitle']}'
              : '已观看',
          trailing: item['lastWatchedTime'] != null
              ? Text(
                  _formatTime(item['lastWatchedTime']),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    if (_favorites.isEmpty) {
      return _buildEmptyState('暂无收藏', Ionicons.heart_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _favorites.length,
      itemBuilder: (context, index) {
        final item = _favorites[index];
        String statusText = '';
        switch (item['favoriteStatus']) {
          case 'favorited':
            statusText = '关注中';
            break;
          case 'finished':
            statusText = '已完成';
            break;
          case 'abandoned':
            statusText = '已弃坑';
            break;
          default:
            statusText = '已收藏';
        }

        return _buildAnimeListItem(
          item: item,
          subtitle: statusText,
          trailing: item['rating'] > 0
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Ionicons.star,
                      color: Colors.yellow,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${item['rating']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }

  Widget _buildRatedList() {
    if (_rated.isEmpty) {
      return _buildEmptyState('暂无评分记录', Ionicons.star_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _rated.length,
      itemBuilder: (context, index) {
        final item = _rated[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: _getRatingText(item['rating']),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Ionicons.star,
                color: Colors.yellow,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${item['rating']}',
                style: const TextStyle(
                  color: Colors.yellow,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAnimeListItem({
    required Map<String, dynamic> item,
    required String subtitle,
    Widget? trailing,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openAnimeDetail(item['animeId']),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面图片
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: item['imageUrl'] != null
                          ? Image.network(
                              item['imageUrl'],
                              width: 40,
                              height: 60,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  width: 40,
                                  height: 60,
                                  color: Colors.white.withOpacity(0.1),
                                  child: const Icon(
                                    Ionicons.image_outline,
                                    color: Colors.white60,
                                    size: 20,
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 40,
                              height: 60,
                              color: Colors.white.withOpacity(0.1),
                              child: const Icon(
                                Ionicons.image_outline,
                                color: Colors.white60,
                                size: 20,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),
                    
                    // 标题和副标题
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['animeTitle'] ?? '未知标题',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // 右侧内容
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      trailing,
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: Colors.white30,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? timeString) {
    if (timeString == null) return '';
    
    try {
      final dateTime = DateTime.parse(timeString);
      final now = DateTime.now();
      final difference = now.difference(dateTime);
      
      if (difference.inDays > 0) {
        return '${difference.inDays}天前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}小时前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分钟前';
      } else {
        return '刚刚';
      }
    } catch (e) {
      return timeString;
    }
  }

  String _getRatingText(int rating) {
    const Map<int, String> ratingMap = {
      1: '不忍直视',
      2: '很差',
      3: '差',
      4: '较差',
      5: '不过不失',
      6: '还行',
      7: '推荐',
      8: '力荐',
      9: '神作',
      10: '超神作',
    };
    return ratingMap[rating] ?? '$rating分';
  }

  void _openAnimeDetail(int animeId) {
    // 确保animeId是有效的正整数
    if (animeId > 0) {
      AnimeDetailPage.show(context, animeId);
    } else {
      debugPrint('[用户活动] 无效的animeId: $animeId');
    }
  }
} 
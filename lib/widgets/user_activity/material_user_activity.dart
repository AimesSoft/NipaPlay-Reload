import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/controllers/user_activity_controller.dart';

/// Material Design版本的用户活动记录组件
class MaterialUserActivity extends StatefulWidget {
  const MaterialUserActivity({super.key});

  @override
  State<MaterialUserActivity> createState() => _MaterialUserActivityState();
}

class _MaterialUserActivityState extends State<MaterialUserActivity> 
    with SingleTickerProviderStateMixin, UserActivityController {

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
              locale:Locale("zh-Hans","zh"),
style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const Spacer(),
            IconButton(
              onPressed: isLoading ? null : loadUserActivity,
              icon: Icon(
                Ionicons.refresh_outline,
                color: isLoading ? Colors.white30 : Colors.white70,
                size: 20,
              ),
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        
        // Material Design标签栏
        TabBar(
          controller: tabController,
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
                  Text('观看(${recentWatched.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.heart_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('收藏(${favorites.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Ionicons.star_outline, size: 16),
                  const SizedBox(width: 4),
                  Text('评分(${rated.length})'),
                ],
              ),
            ),
          ],
        ),
        
        // 内容区域
        Expanded(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : error != null
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
                            error!,
                            style: const TextStyle(color: Colors.white60),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: loadUserActivity,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.2),
                            ),
                            child: const Text(
                              '重试',
                              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: tabController,
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
    if (recentWatched.isEmpty) {
      return _buildEmptyState('暂无观看记录', Ionicons.play_circle_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: recentWatched.length,
      itemBuilder: (context, index) {
        final item = recentWatched[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: item['lastEpisodeTitle'] != null 
              ? '看到: ${item['lastEpisodeTitle']}'
              : '已观看',
          trailing: item['lastWatchedTime'] != null
              ? Text(
                  formatTime(item['lastWatchedTime']),
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
    if (favorites.isEmpty) {
      return _buildEmptyState('暂无收藏', Ionicons.heart_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: favorites.length,
      itemBuilder: (context, index) {
        final item = favorites[index];
        final statusText = getFavoriteStatusText(item['favoriteStatus']);

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
    if (rated.isEmpty) {
      return _buildEmptyState('暂无评分记录', Ionicons.star_outline);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rated.length,
      itemBuilder: (context, index) {
        final item = rated[index];
        return _buildAnimeListItem(
          item: item,
          subtitle: getRatingText(item['rating']),
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
    final imageUrl = processImageUrl(item['imageUrl']);

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
              onTap: () => openAnimeDetail(item['animeId']),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    // 封面图片
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: imageUrl != null
                          ? Image.network(
                              imageUrl,
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
}
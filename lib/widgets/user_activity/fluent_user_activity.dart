import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/controllers/user_activity_controller.dart';

/// Fluent UI版本的用户活动记录组件
class FluentUserActivity extends StatefulWidget {
  const FluentUserActivity({super.key});

  @override
  State<FluentUserActivity> createState() => _FluentUserActivityState();
}

class _FluentUserActivityState extends State<FluentUserActivity> 
    with SingleTickerProviderStateMixin, UserActivityController {
  
  int _currentTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        
        // 标题和刷新按钮
        Row(
          children: [
            Text(
              '我的活动记录',
              style: FluentTheme.of(context).typography.subtitle,
            ),
            const Spacer(),
            IconButton(
              onPressed: isLoading ? null : loadUserActivity,
              icon: Icon(
                FluentIcons.refresh,
                size: 16,
                color: isLoading 
                    ? FluentTheme.of(context).inactiveColor 
                    : FluentTheme.of(context).accentColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Fluent UI标签栏
        Expanded(
          child: TabView(
            currentIndex: _currentTabIndex,
            onChanged: (index) {
              setState(() {
                _currentTabIndex = index;
              });
              tabController.animateTo(index);
            },
            tabs: [
              Tab(
                text: Text('观看 (${recentWatched.length})'),
                icon: const Icon(FluentIcons.play_solid, size: 16),
                body: isLoading
                    ? const Center(child: ProgressRing())
                    : error != null
                        ? _buildErrorState()
                        : _buildRecentWatchedList(),
              ),
              Tab(
                text: Text('收藏 (${favorites.length})'),
                icon: const Icon(FluentIcons.heart, size: 16),
                body: isLoading
                    ? const Center(child: ProgressRing())
                    : error != null
                        ? _buildErrorState()
                        : _buildFavoritesList(),
              ),
              Tab(
                text: Text('评分 (${rated.length})'),
                icon: const Icon(FluentIcons.favorite_star, size: 16),
                body: isLoading
                    ? const Center(child: ProgressRing())
                    : error != null
                        ? _buildErrorState()
                        : _buildRatedList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            FluentIcons.warning,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            error!,
            style: FluentTheme.of(context).typography.body,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: loadUserActivity,
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWatchedList() {
    if (recentWatched.isEmpty) {
      return _buildEmptyState('暂无观看记录', FluentIcons.play_solid);
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
                  style: FluentTheme.of(context).typography.caption,
                )
              : null,
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    if (favorites.isEmpty) {
      return _buildEmptyState('暂无收藏', FluentIcons.heart);
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
                      FluentIcons.favorite_star_fill,
                      color: material.Colors.amber,
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${item['rating']}',
                      style: FluentTheme.of(context).typography.caption?.copyWith(
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
      return _buildEmptyState('暂无评分记录', FluentIcons.favorite_star);
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
                FluentIcons.favorite_star_fill,
                color: material.Colors.amber,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${item['rating']}',
                style: FluentTheme.of(context).typography.body?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: material.Colors.amber,
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          onPressed: () => openAnimeDetail(item['animeId']),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: imageUrl != null
                ? material.Image.network(
                    imageUrl,
                    width: 40,
                    height: 60,
                    fit: material.BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: 40,
                        height: 60,
                        color: FluentTheme.of(context).cardColor,
                        child: Icon(
                          FluentIcons.photo2,
                          color: FluentTheme.of(context).inactiveColor,
                          size: 20,
                        ),
                      );
                    },
                  )
                : Container(
                    width: 40,
                    height: 60,
                    color: FluentTheme.of(context).cardColor,
                    child: Icon(
                      FluentIcons.photo2,
                      color: FluentTheme.of(context).inactiveColor,
                      size: 20,
                    ),
                  ),
          ),
          title: Text(
            item['animeTitle'] ?? '未知标题',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: trailing,
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
            color: FluentTheme.of(context).inactiveColor,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: FluentTheme.of(context).typography.body,
          ),
        ],
      ),
    );
  }
}
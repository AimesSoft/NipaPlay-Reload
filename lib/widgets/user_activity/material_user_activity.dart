import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/controllers/user_activity_controller.dart';
import 'package:nipaplay/pages/tab_labels.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/switchable_view.dart';

/// Fluent UI版本的用户活动记录组件
class MaterialUserActivity extends StatefulWidget {
  const MaterialUserActivity({super.key});

  @override
  State<MaterialUserActivity> createState() => _MaterialUserActivityState();
}

class _MaterialUserActivityState extends State<MaterialUserActivity> 
    with SingleTickerProviderStateMixin, UserActivityController {
  @override
  Widget build(BuildContext context) {
    final theme = fluent.FluentTheme.of(context);
    final textPrimary = theme.resources.textFillColorPrimary;
    final textSecondary = theme.resources.textFillColorSecondary;
    final accent = theme.accentColor.defaultBrushFor(theme.brightness);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final unselectedLabelColor =
        isDarkMode ? Colors.white60 : Colors.black54;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        
        // 标题和刷新按钮
        Row(
          children: [
            Text(
              '我的活动记录',
              locale:Locale("zh-Hans","zh"),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: textPrimary,
              ),
            ),
            const Spacer(),
            BlurButton(
              icon: Ionicons.refresh_outline,
              text: '刷新',
              onTap: () {
                if (isLoading) return;
                loadUserActivity();
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        TabBar(
          controller: tabController,
          isScrollable: true,
          tabs: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: '观看(${recentWatched.length})',
                fontSize: 18,
                icon: const Icon(
                  Ionicons.play_circle_outline,
                  size: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: '收藏(${favorites.length})',
                fontSize: 18,
                icon: const Icon(
                  Ionicons.heart_outline,
                  size: 18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: HoverZoomTab(
                text: '评分(${rated.length})',
                fontSize: 18,
                icon: const Icon(
                  Ionicons.star_outline,
                  size: 18,
                ),
              ),
            ),
          ],
          labelColor: accent,
          unselectedLabelColor: unselectedLabelColor,
          labelPadding: const EdgeInsets.only(bottom: 12.0),
          indicatorPadding: EdgeInsets.zero,
          indicator: _CustomTabIndicator(
            indicatorHeight: 3.0,
            indicatorColor: accent,
            radius: 30.0,
          ),
          tabAlignment: TabAlignment.start,
          splashFactory: NoSplash.splashFactory,
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          dividerColor: Colors.transparent,
          dividerHeight: 3.0,
          indicatorSize: TabBarIndicatorSize.label,
        ),
        const SizedBox(height: 8),
        // 内容区域
        Expanded(
          child: SwitchableView(
            enableAnimation: false,
            keepAlive: true,
            currentIndex: tabController.index,
            controller: tabController,
            children: [
              _buildTabBody(0, accent, textSecondary),
              _buildTabBody(1, accent, textSecondary),
              _buildTabBody(2, accent, textSecondary),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTabBody(
    int index,
    Color accent,
    Color textSecondary,
  ) {
    if (isLoading) {
      return Center(
        child: fluent.ProgressRing(
          activeColor: accent,
          strokeWidth: 2,
        ),
      );
    }

    if (error != null) {
      return _buildErrorState(textSecondary);
    }

    switch (index) {
      case 0:
        return _buildRecentWatchedList();
      case 1:
        return _buildFavoritesList();
      default:
        return _buildRatedList();
    }
  }

  Widget _buildErrorState(Color textSecondary) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          fluent.Icon(
            Ionicons.warning_outline,
            color: textSecondary,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            error!,
            style: TextStyle(color: textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          BlurButton(
            icon: Ionicons.refresh_outline,
            text: '重试',
            onTap: loadUserActivity,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentWatchedList() {
    final theme = fluent.FluentTheme.of(context);
    final textSecondary = theme.resources.textFillColorSecondary;

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
                  style: TextStyle(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildFavoritesList() {
    final theme = fluent.FluentTheme.of(context);
    final textPrimary = theme.resources.textFillColorPrimary;

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
                    const fluent.Icon(
                      Ionicons.star,
                      color: Colors.yellow,
                      size: 14,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${item['rating']}',
                      style: TextStyle(
                        color: textPrimary,
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
              const fluent.Icon(
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
    final theme = fluent.FluentTheme.of(context);
    final textPrimary = theme.resources.textFillColorPrimary;
    final textSecondary = theme.resources.textFillColorSecondary;
    final imageUrl = processImageUrl(item['imageUrl']);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.resources.cardBackgroundFillColorDefault,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.resources.cardStrokeColorDefault,
              width: 0.5,
            ),
          ),
          child: fluent.ListTile(
            contentPadding: const EdgeInsets.all(12),
            margin: EdgeInsets.zero,
            onPressed: () => openAnimeDetail(item['animeId']),
            leading: ClipRRect(
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
                          color: theme.resources.cardBackgroundFillColorSecondary,
                          child: fluent.Icon(
                            Ionicons.image_outline,
                            color: textSecondary,
                            size: 20,
                          ),
                        );
                      },
                    )
                  : Container(
                      width: 40,
                      height: 60,
                      color: theme.resources.cardBackgroundFillColorSecondary,
                      child: fluent.Icon(
                        Ionicons.image_outline,
                        color: textSecondary,
                        size: 20,
                      ),
                    ),
            ),
            title: Text(
              item['animeTitle'] ?? '未知标题',
              style: TextStyle(
                color: textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              subtitle,
              style: TextStyle(
                color: textSecondary,
                fontSize: 12,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: trailing,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    final theme = fluent.FluentTheme.of(context);
    final textSecondary = theme.resources.textFillColorSecondary;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          fluent.Icon(
            icon,
            color: textSecondary,
            size: 48,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              color: textSecondary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

// 自定义Tab指示器
class _CustomTabIndicator extends Decoration {
  final double indicatorHeight;
  final Color indicatorColor;
  final double radius;

  const _CustomTabIndicator({
    required this.indicatorHeight,
    required this.indicatorColor,
    required this.radius,
  });

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) {
    return _CustomPainter(this, onChanged);
  }
}

class _CustomPainter extends BoxPainter {
  final _CustomTabIndicator decoration;

  _CustomPainter(this.decoration, VoidCallback? onChanged) : super(onChanged);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    assert(configuration.size != null);
    // 将指示器绘制在TabBar的底部
    final Rect rect = Offset(
          offset.dx,
          (configuration.size!.height - decoration.indicatorHeight),
        ) &
        Size(configuration.size!.width, decoration.indicatorHeight);
    final Paint paint = Paint();
    paint.color = decoration.indicatorColor;
    paint.style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(decoration.radius)),
      paint,
    );
  }
}

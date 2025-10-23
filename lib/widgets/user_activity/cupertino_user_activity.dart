import 'dart:math' as math;

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Icons;

import 'package:nipaplay/controllers/user_activity_controller.dart';

class CupertinoUserActivity extends StatefulWidget {
  const CupertinoUserActivity({super.key});

  @override
  State<CupertinoUserActivity> createState() => _CupertinoUserActivityState();
}

class _CupertinoUserActivityState extends State<CupertinoUserActivity>
    with SingleTickerProviderStateMixin, UserActivityController {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    tabController.addListener(_handleTabChange);
  }

  @override
  void dispose() {
    tabController.removeListener(_handleTabChange);
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted) return;
    if (_selectedIndex != tabController.index) {
      setState(() {
        _selectedIndex = tabController.index;
      });
    }
  }

  void _onSegmentChanged(int index) {
    if (_selectedIndex == index) return;
    setState(() {
      _selectedIndex = index;
    });
    tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '我的活动记录',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            AdaptiveButton.icon(
              onPressed: isLoading ? null : loadUserActivity,
              icon: PlatformInfo.isIOS ? CupertinoIcons.refresh : Icons.refresh,
              size: AdaptiveButtonSize.small,
              style: AdaptiveButtonStyle.bordered,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AdaptiveSegmentedControl(
          labels: const ['观看', '收藏', '评分'],
          selectedIndex: _selectedIndex,
          onValueChanged: _onSegmentChanged,
        ),
        const SizedBox(height: 16),
        _buildContent(),
      ],
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Center(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: const CupertinoActivityIndicator(radius: 12),
        ),
      );
    }

    if (error != null) {
      return AdaptiveCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error!,
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(
                    color: CupertinoColors.destructiveRed,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            AdaptiveButton(
              onPressed: loadUserActivity,
              style: AdaptiveButtonStyle.tinted,
              label: '重试',
            ),
          ],
        ),
      );
    }

    final items = _selectedIndex == 0
        ? recentWatched
        : (_selectedIndex == 1 ? favorites : rated);

    if (items.isEmpty) {
      final String emptyText = _selectedIndex == 0
          ? '暂无观看记录'
          : (_selectedIndex == 1 ? '暂无收藏内容' : '尚未对作品评分');

      return AdaptiveCard(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            emptyText,
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(color: CupertinoColors.systemGrey),
          ),
        ),
      );
    }

    final displayCount = math.min(items.length, 5);

    return AdaptiveCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          for (int i = 0; i < displayCount; i++)
            _buildActivityTile(items[i], isLast: i == displayCount - 1),
        ],
      ),
    );
  }

  Widget _buildActivityTile(Map<String, dynamic> item, {required bool isLast}) {
    final int? animeId = item['animeId'] as int?;
    final String title = (item['animeTitle'] ?? '未知作品').toString();

    final String subtitle;
    if (_selectedIndex == 0) {
      final String? episodeTitle = item['lastEpisodeTitle'] as String?;
      final String watched = formatTime(item['lastWatchedTime'] as String?);
      subtitle = [
        if (episodeTitle != null && episodeTitle.isNotEmpty)
          '看到：$episodeTitle',
        if (watched.isNotEmpty) '更新时间：$watched',
      ].join(' · ');
    } else if (_selectedIndex == 1) {
      final String? status = item['favoriteStatus'] as String?;
      final int rating = item['rating'] as int? ?? 0;
      subtitle = [
        if (status != null && status.isNotEmpty) '状态：$status',
        if (rating > 0) '评分：$rating',
      ].join(' · ');
    } else {
      final int rating = item['rating'] as int? ?? 0;
      subtitle = '评分：$rating';
    }

    return Column(
      children: [
        AdaptiveListTile(
          leading: _buildThumbnail(item['imageUrl'] as String?),
          title: Text(title),
          subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
          trailing: const Icon(
            CupertinoIcons.chevron_forward,
            size: 16,
            color: CupertinoColors.systemGrey2,
          ),
          onTap: animeId == null ? null : () => openAnimeDetail(animeId),
        ),
        if (!isLast)
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            color: CupertinoColors.systemGrey5,
          ),
      ],
    );
  }

  Widget _buildThumbnail(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey5,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          CupertinoIcons.film,
          color: CupertinoColors.systemGrey2,
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: CupertinoColors.systemGrey5,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              CupertinoIcons.photo,
              color: CupertinoColors.systemGrey2,
            ),
          );
        },
      ),
    );
  }
}

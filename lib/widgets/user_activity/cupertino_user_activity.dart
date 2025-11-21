import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/controllers/user_activity_controller.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_shared_anime_detail_page.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoUserActivity extends StatefulWidget {
  const CupertinoUserActivity({super.key});

  @override
  State<CupertinoUserActivity> createState() => _CupertinoUserActivityState();
}

class _CupertinoUserActivityState extends State<CupertinoUserActivity>
    with SingleTickerProviderStateMixin, UserActivityController {
  static const double _thumbnailWidth = 60;
  static const double _thumbnailHeight = 84;
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
            CupertinoButton(
              padding: EdgeInsets.zero,
              minSize: 0,
              onPressed: isLoading ? null : loadUserActivity,
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey5,
                    context,
                  ),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  CupertinoIcons.refresh,
                  size: 16,
                  color: isLoading
                      ? CupertinoDynamicColor.resolve(
                          CupertinoColors.systemGrey2,
                          context,
                        )
                      : resolveSettingsIconColor(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSegmentedControl(context),
        const SizedBox(height: 16),
        _buildContent(),
      ],
    );
  }

  Widget _buildSegmentedControl(BuildContext context) {
    final Color textColor =
        CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.black,
        darkColor: CupertinoColors.white,
      ),
      context,
    );
    final Color segmentColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.inactiveGray,
      ),
      context,
    );

    final baseTheme = CupertinoTheme.of(context);
    final segmentedTheme = baseTheme.copyWith(
      primaryColor: textColor,
      textTheme: baseTheme.textTheme.copyWith(
        textStyle: baseTheme.textTheme.textStyle.copyWith(color: textColor),
      ),
    );

    return CupertinoTheme(
      data: segmentedTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        child: AdaptiveSegmentedControl(
          labels: const ['观看', '收藏', '评分'],
          selectedIndex: _selectedIndex,
          color: segmentColor,
          onValueChanged: _onSegmentChanged,
        ),
      ),
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
      return Container(
        decoration: BoxDecoration(
          color: resolveSettingsCardBackground(context),
          borderRadius: BorderRadius.circular(24),
        ),
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
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.systemRed,
                      context,
                    ),
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

      return Container(
        decoration: BoxDecoration(
          color: resolveSettingsCardBackground(context),
          borderRadius: BorderRadius.circular(24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            emptyText,
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(
                  color: resolveSettingsSecondaryTextColor(context),
                ),
          ),
        ),
      );
    }

    final BorderRadius radius = BorderRadius.circular(24);

    return Container(
      decoration: BoxDecoration(
        color: resolveSettingsCardBackground(context),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: items.length,
        itemBuilder: (context, index) => _buildActivityTile(items[index]),
        separatorBuilder: (context, index) => Container(
          height: 0.5,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color: resolveSettingsSeparatorColor(context),
        ),
      ),
        ),
      ),
    );
  }

  Widget _buildActivityTile(Map<String, dynamic> item) {
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
      ].join('\n');
    } else if (_selectedIndex == 1) {
      final String? status = item['favoriteStatus'] as String?;
      final int rating = item['rating'] as int? ?? 0;
      subtitle = [
        if (status != null && status.isNotEmpty) '状态：$status',
        if (rating > 0) '评分：$rating',
      ].join('\n');
    } else {
      final int rating = item['rating'] as int? ?? 0;
      subtitle = '评分：$rating';
    }

    final tileColor = resolveSettingsTileBackground(context);

    return AdaptiveListTile(
      leading: _buildThumbnail(item['imageUrl'] as String?),
      title: Text(
        title,
        style: TextStyle(color: resolveSettingsPrimaryTextColor(context)),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(
                height: 1.35,
                color: resolveSettingsSecondaryTextColor(context),
              ),
            )
          : null,
      trailing: Icon(
        CupertinoIcons.chevron_forward,
        size: 16,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey2,
          context,
        ),
      ),
      backgroundColor: tileColor,
      onTap: animeId == null ? null : () => _openDetailBottomSheet(item),
    );
  }

  Future<void> _openDetailBottomSheet(Map<String, dynamic> item) async {
    final int? animeId = item['animeId'] as int?;
    if (animeId == null) return;

    SharedRemoteLibraryProvider? sharedProvider;
    try {
      sharedProvider = context.read<SharedRemoteLibraryProvider>();
    } catch (_) {
      sharedProvider = null;
    }

    final detailMode = context.read<ThemeNotifier>().animeDetailDisplayMode;

    if (sharedProvider == null) {
      openAnimeDetail(animeId);
      return;
    }

    final summary = _buildSharedSummary(sharedProvider, item, animeId);

    await CupertinoBottomSheet.show(
      context: context,
      title: null,
      showCloseButton: false,
      child: ChangeNotifierProvider<SharedRemoteLibraryProvider>.value(
        value: sharedProvider,
        child: CupertinoSharedAnimeDetailPage(
          anime: summary,
          hideBackButton: true,
          displayModeOverride: detailMode,
          showCloseButton: true,
        ),
      ),
    );
  }

  SharedRemoteAnimeSummary _buildSharedSummary(
    SharedRemoteLibraryProvider provider,
    Map<String, dynamic> item,
    int animeId,
  ) {
    for (final candidate in provider.animeSummaries) {
      if (candidate.animeId == animeId) {
        return candidate;
      }
    }

    final title = (item['animeTitle'] ?? '未知作品').toString();
    final imageUrl = item['imageUrl'] as String?;
    final rawTime = item['lastWatchedTime'] as String?;
    final parsed = rawTime != null
        ? DateTime.tryParse(rawTime)?.toLocal()
        : null;

    return SharedRemoteAnimeSummary(
      animeId: animeId,
      name: title,
      nameCn: title,
      summary: null,
      imageUrl: imageUrl,
      lastWatchTime: parsed ?? DateTime.now(),
      episodeCount: 0,
      hasMissingFiles: true,
    );
  }

  Widget _buildThumbnail(String? url) {
    if (url == null || url.isEmpty) {
      return Container(
        width: _thumbnailWidth,
        height: _thumbnailHeight,
        decoration: BoxDecoration(
          color: resolveSettingsTileBackground(context),
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(
          CupertinoIcons.film,
          size: 24,
          color: resolveSettingsSecondaryTextColor(context),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        width: _thumbnailWidth,
        height: _thumbnailHeight,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) {
          return Container(
            width: _thumbnailWidth,
            height: _thumbnailHeight,
            decoration: BoxDecoration(
              color: resolveSettingsTileBackground(context),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              CupertinoIcons.photo,
              size: 24,
              color: resolveSettingsSecondaryTextColor(context),
            ),
          );
        },
      ),
    );
  }
}

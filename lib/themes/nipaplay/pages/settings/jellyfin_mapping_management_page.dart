import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';

class JellyfinMappingManagementPage extends StatefulWidget {
  const JellyfinMappingManagementPage({super.key});

  @override
  State<JellyfinMappingManagementPage> createState() =>
      _JellyfinMappingManagementPageState();
}

class _JellyfinMappingManagementPageState
    extends State<JellyfinMappingManagementPage> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMappingStats();
  }

  Future<void> _loadMappingStats() async {
    try {
      final stats =
          await JellyfinEpisodeMappingService.instance.getMappingStats();
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      BlurSnackBar.show(context, '加载映射统计失败: $e');
    }
  }

  Future<void> _reloadMappingStats() async {
    setState(() {
      _isLoading = true;
    });
    await _loadMappingStats();
  }

  Future<void> _clearAllMappings() async {
    final colorScheme = Theme.of(context).colorScheme;
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '清除所有映射',
      content: '确定要清除所有Jellyfin剧集映射吗？这将删除所有已建立的智能映射关系，无法恢复。',
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            '取消',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
        HoverScaleTextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            '确定清除',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(color: colorScheme.error),
          ),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await JellyfinEpisodeMappingService.instance.clearAllMappings();
        BlurSnackBar.show(context, '所有映射已清除');
        await _loadMappingStats();
      } catch (e) {
        BlurSnackBar.show(context, '清除映射失败: $e');
      }
    }
  }

  Future<void> _showMappingAnalysis() async {
    if (_stats.isEmpty || _stats['accuracyStats'] == null) {
      BlurSnackBar.show(context, '请先加载统计数据');
      return;
    }

    final accuracyStats = _stats['accuracyStats'] as List;
    final colorScheme = Theme.of(context).colorScheme;

    if (accuracyStats.isEmpty) {
      await BlurDialog.show(
        context: context,
        title: '映射分析',
        content: '暂无映射数据可供分析。\n\n请先使用Jellyfin播放器观看动画并手动匹配弹幕，系统将自动建立映射关系。',
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              '知道了',
              locale: const Locale('zh-Hans', 'zh'),
              style: TextStyle(color: colorScheme.onSurface),
            ),
          ),
        ],
      );
      return;
    }

    final content = StringBuffer()..writeln('映射准确性分析：\n');
    for (final stat in accuracyStats.take(10)) {
      final seriesName = stat['jellyfin_series_name'] as String? ?? '未知系列';
      final totalEpisodes = stat['total_episodes'] as int? ?? 0;
      final confirmedEpisodes = stat['confirmed_episodes'] as int? ?? 0;
      final baseOffset = stat['base_episode_offset'] as int? ?? 0;
      final accuracy = totalEpisodes > 0
          ? (confirmedEpisodes / totalEpisodes * 100).toStringAsFixed(1)
          : '0.0';

      content.writeln(seriesName);
      content.writeln('   剧集总数: $totalEpisodes');
      content.writeln('   已确认: $confirmedEpisodes');
      content.writeln('   准确率: $accuracy%');
      content.writeln('   基础偏移: $baseOffset');
      content.writeln('');
    }

    if (accuracyStats.length > 10) {
      content.writeln('... 还有 ${accuracyStats.length - 10} 个映射');
    }

    await BlurDialog.show(
      context: context,
      title: '映射分析报告',
      content: content.toString(),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            '关闭',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(color: colorScheme.onSurface),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      children: [
        _buildStatisticsCard(),
        const SizedBox(height: 16),
        _buildManagementCard(),
        const SizedBox(height: 16),
        _buildHelpCard(),
      ],
    );
  }

  Widget _buildStatisticsCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Ionicons.stats_chart_outline,
            title: '映射统计',
          ),
          const SizedBox(height: 18),
          if (_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
            )
          else ...[
            _buildStatItem('动画映射', _countFor('animeCount'), Icons.tv),
            _buildStatItem(
              '剧集映射',
              _countFor('episodeCount'),
              Icons.video_library,
            ),
            _buildStatItem(
              '已确认映射',
              _countFor('confirmedCount'),
              Icons.verified,
            ),
            _buildStatItem(
              '预测映射',
              _countFor('predictedCount'),
              Icons.auto_awesome,
            ),
            _buildRecentMappings(),
          ],
        ],
      ),
    );
  }

  Widget _buildManagementCard() {
    return SettingsCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
            child: _buildSectionHeader(
              icon: Ionicons.settings_outline,
              title: '映射管理',
            ),
          ),
          SettingsItem.button(
            title: '重新加载统计',
            subtitle: '刷新映射统计信息',
            icon: Ionicons.refresh_outline,
            onTap: _reloadMappingStats,
          ),
          Divider(height: 1, color: _dividerColor),
          SettingsItem.button(
            title: '映射分析',
            subtitle: '查看映射准确性和使用情况',
            icon: Ionicons.analytics_outline,
            onTap: _showMappingAnalysis,
          ),
          Divider(height: 1, color: _dividerColor),
          SettingsItem.button(
            title: '清除所有映射',
            subtitle: '删除所有已建立的映射关系',
            icon: Ionicons.trash_outline,
            isDestructive: true,
            onTap: _clearAllMappings,
          ),
        ],
      ),
    );
  }

  Widget _buildHelpCard() {
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            icon: Ionicons.help_circle_outline,
            title: '关于智能映射',
          ),
          const SizedBox(height: 16),
          Text(
            '智能映射系统会记录 Jellyfin 剧集与 DandanPlay 弹幕的对应关系。',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildHelpItem(
            Icons.track_changes_rounded,
            '自动匹配',
            '为新剧集自动匹配弹幕，无需重复选择',
          ),
          _buildHelpItem(
            Icons.skip_next_rounded,
            '集数导航',
            '支持 Jellyfin 剧集的上一话/下一话导航',
          ),
          _buildHelpItem(
            Icons.auto_awesome_rounded,
            '智能预测',
            '基于已有映射预测新剧集的弹幕 ID',
          ),
          _buildHelpItem(
            Icons.save_rounded,
            '持久化存储',
            '映射关系会保存，重启应用后仍然有效',
          ),
          const SizedBox(height: 12),
          Text(
            '映射会在手动匹配弹幕时自动创建。',
            locale: const Locale('zh-Hans', 'zh'),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.62),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: colorScheme.onSurface, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          locale: const Locale('zh-Hans', 'zh'),
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon,
              color: colorScheme.onSurface.withValues(alpha: 0.70), size: 17),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              locale: const Locale('zh-Hans', 'zh'),
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.72),
                fontSize: 14,
              ),
            ),
          ),
          Text(
            count.toString(),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentMappings() {
    final recentMappings = _stats['recentMappings'];
    if (recentMappings is! List || recentMappings.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Divider(color: _dividerColor),
        const SizedBox(height: 8),
        Text(
          '最近活动',
          locale: const Locale('zh-Hans', 'zh'),
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...recentMappings.take(3).map(
              (mapping) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  '${mapping['jellyfin_series_name']} ↔ ${mapping['dandanplay_anime_title']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.66),
                    fontSize: 12,
                  ),
                ),
              ),
            ),
      ],
    );
  }

  Widget _buildHelpItem(IconData icon, String title, String description) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              color: colorScheme.onSurface.withValues(alpha: 0.72), size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  locale: const Locale('zh-Hans', 'zh'),
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  locale: const Locale('zh-Hans', 'zh'),
                  style: TextStyle(
                    color: colorScheme.onSurface.withValues(alpha: 0.64),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _countFor(String key) {
    final value = _stats[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  Color get _dividerColor =>
      Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10);
}

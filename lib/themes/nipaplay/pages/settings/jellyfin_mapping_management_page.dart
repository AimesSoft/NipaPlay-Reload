import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/services/jellyfin_episode_mapping_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';

class JellyfinMappingManagementPage extends StatefulWidget {
  const JellyfinMappingManagementPage({super.key});

  @override
  State<JellyfinMappingManagementPage> createState() => _JellyfinMappingManagementPageState();
}

class _JellyfinMappingManagementPageState extends State<JellyfinMappingManagementPage> {
  Map<String, dynamic> _stats = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMappingStats();
  }

  Future<void> _loadMappingStats() async {
    try {
      final stats = await JellyfinEpisodeMappingService.instance.getMappingStats();
      if (mounted) {
        setState(() {
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        BlurSnackBar.show(context, '加载映射统计失败: $e');
      }
    }
  }

  Future<void> _clearAllMappings() async {
    final confirm = await BlurDialog.show<bool>(
      context: context,
      title: '清除所有映射',
      content: '确定要清除所有Jellyfin剧集映射吗？这将删除所有已建立的智能映射关系，无法恢复。',
      actions: [
        HoverScaleTextButton(
          child: const Text('取消', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70)),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        HoverScaleTextButton(
          child: const Text('确定清除', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red)),
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    );

    if (confirm == true) {
      try {
        await JellyfinEpisodeMappingService.instance.clearAllMappings();
        BlurSnackBar.show(context, '所有映射已清除');
        await _loadMappingStats(); // 重新加载统计信息
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

    final List<dynamic> accuracyStats = _stats['accuracyStats'] as List;
    
    if (accuracyStats.isEmpty) {
      BlurDialog.show(
        context: context,
        title: '映射分析',
        content: '暂无映射数据可供分析。\n\n请先使用Jellyfin播放器观看动画并手动匹配弹幕，系统将自动建立映射关系。',
        actions: [
          HoverScaleTextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white)),
          ),
        ],
      );
      return;
    }

    final StringBuffer content = StringBuffer();
    content.writeln('映射准确性分析：\n');

    for (final stat in accuracyStats.take(10)) { // 显示前10个
      final seriesName = stat['jellyfin_series_name'] as String? ?? '未知系列';
      final totalEpisodes = stat['total_episodes'] as int? ?? 0;
      final confirmedEpisodes = stat['confirmed_episodes'] as int? ?? 0;
      final baseOffset = stat['base_episode_offset'] as int? ?? 0;
      
      final accuracy = totalEpisodes > 0 
          ? (confirmedEpisodes / totalEpisodes * 100).toStringAsFixed(1)
          : '0.0';
      
      content.writeln('📺 $seriesName');
      content.writeln('   剧集总数: $totalEpisodes');
      content.writeln('   已确认: $confirmedEpisodes');
      content.writeln('   准确率: $accuracy%');
      content.writeln('   基础偏移: $baseOffset');
      content.writeln('');
    }

    if (accuracyStats.length > 10) {
      content.writeln('... 还有 ${accuracyStats.length - 10} 个映射');
    }

    BlurDialog.show(
      context: context,
      title: '映射分析报告',
      content: content.toString(),
      actions: [
        HoverScaleTextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭', locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final disableBlur = SettingsVisualScope.isBlurDisabled(context);
    return ListView(
      children: [
        // 映射统计信息
        _buildStatisticsCard(disableBlur),
        
        const SizedBox(height: 16),
        
        // 管理操作
        _buildManagementCard(disableBlur),
        
        const SizedBox(height: 16),
        
        // 说明信息
        _buildHelpCard(disableBlur),
      ],
    );
  }

  Widget _buildStatisticsCard(bool disableBlur) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Ionicons.stats_chart_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '映射统计',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else ...[
            _buildStatItem('动画映射', _stats['animeCount'] ?? 0, Icons.tv),
            const SizedBox(height: 8),
            _buildStatItem('剧集映射', _stats['episodeCount'] ?? 0, Icons.video_library),
            const SizedBox(height: 8),
            _buildStatItem('已确认映射', _stats['confirmedCount'] ?? 0, Icons.verified),
            const SizedBox(height: 8),
            _buildStatItem('预测映射', _stats['predictedCount'] ?? 0, Icons.auto_awesome),
            
            // 显示最近映射活动
            if (_stats['recentMappings'] != null && (_stats['recentMappings'] as List).isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(color: Colors.white12),
              const SizedBox(height: 8),
              const Text(
                '最近活动',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              ...(_stats['recentMappings'] as List).take(3).map((mapping) => 
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${mapping['jellyfin_series_name']} ↔ ${mapping['dandanplay_anime_title']}',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: disableBlur
          ? card
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: card,
            ),
    );
  }

  Widget _buildStatItem(String label, int count, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.white70, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Text(
          count.toString(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildManagementCard(bool disableBlur) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Ionicons.settings_outline, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  '映射管理',
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          
          ListTile(
            leading: const Icon(Ionicons.refresh_outline, color: Colors.white),
            title: const Text(
              '重新加载统计',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '刷新映射统计信息',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
            ),
            onTap: () {
              setState(() {
                _isLoading = true;
              });
              _loadMappingStats();
            },
          ),
          
          const Divider(color: Colors.white12, height: 1),
          
          ListTile(
            leading: const Icon(Ionicons.analytics_outline, color: Colors.white),
            title: const Text(
              '映射分析',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '查看映射准确性和使用情况',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
            ),
            onTap: _showMappingAnalysis,
          ),
          
          const Divider(color: Colors.white12, height: 1),
          
          ListTile(
            leading: const Icon(Ionicons.trash_outline, color: Colors.red),
            title: const Text(
              '清除所有映射',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.red, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              '删除所有已建立的映射关系',
              locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70),
            ),
            onTap: _clearAllMappings,
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: disableBlur
          ? card
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: card,
            ),
    );
  }

  Widget _buildHelpCard(bool disableBlur) {
    final card = Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Ionicons.help_circle_outline, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                '关于智能映射',
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          const Text(
            '智能映射系统自动记录Jellyfin剧集与DandanPlay弹幕的对应关系，实现以下功能：',
            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          const SizedBox(height: 12),
          
          _buildHelpItem('🎯', '自动匹配', '为新剧集自动匹配弹幕，无需重复选择'),
          _buildHelpItem('⏭️', '集数导航', '支持Jellyfin剧集的上一话/下一话导航'),
          _buildHelpItem('🧠', '智能预测', '基于已有映射预测新剧集的弹幕ID'),
          _buildHelpItem('💾', '持久化存储', '映射关系永久保存，重启应用后仍然有效'),
          
          const SizedBox(height: 12),
          
          const Text(
            '映射会在手动匹配弹幕时自动创建，无需手动配置。',
            locale:Locale("zh-Hans","zh"),
style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: disableBlur
          ? card
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
              child: card,
            ),
    );
  }

  Widget _buildHelpItem(String emoji, String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  description,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

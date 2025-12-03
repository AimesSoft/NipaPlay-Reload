import 'package:flutter/cupertino.dart';

import 'package:nipaplay/models/dandanplay_remote_model.dart';

class CupertinoDandanplayRemoteCard extends StatelessWidget {
  const CupertinoDandanplayRemoteCard({
    super.key,
    required this.isConnected,
    required this.isLoading,
    required this.animeGroupCount,
    required this.episodeCount,
    required this.previewGroups,
    required this.onManage,
    this.errorMessage,
    this.serverUrl,
    this.lastSyncedAt,
    this.onRefresh,
    this.onDisconnect,
  });

  final bool isConnected;
  final bool isLoading;
  final int animeGroupCount;
  final int episodeCount;
  final List<DandanplayRemoteAnimeGroup> previewGroups;
  final VoidCallback onManage;
  final VoidCallback? onRefresh;
  final VoidCallback? onDisconnect;
  final String? errorMessage;
  final String? serverUrl;
  final DateTime? lastSyncedAt;

  static const Color _accentColor = Color(0xFFFFC857);

  @override
  Widget build(BuildContext context) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );

    final bool showError = (errorMessage?.isNotEmpty ?? false) && !isLoading;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          if (showError) ...[
            _buildErrorBanner(context),
            const SizedBox(height: 12),
          ],
          if (isConnected)
            ..._buildConnectedContent(context)
          else
            _buildDisconnectedContent(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final Color titleColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _accentColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            CupertinoIcons.chat_bubble_2_fill,
            size: 18,
            color: _accentColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            '弹弹play 远程访问',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: titleColor,
            ),
          ),
        ),
        _buildStatusPill(context),
      ],
    );
  }

  Widget _buildStatusPill(BuildContext context) {
    if (isLoading) {
      return const CupertinoActivityIndicator(radius: 10);
    }

    final bool hasConfig = serverUrl?.isNotEmpty ?? false;
    late final Color pillColor;
    late final String label;

    if (isConnected) {
      pillColor = CupertinoDynamicColor.resolve(
        CupertinoColors.systemGreen,
        context,
      );
      label = '已同步';
    } else if (hasConfig) {
      pillColor = CupertinoDynamicColor.resolve(
        CupertinoColors.systemOrange,
        context,
      );
      label = '连接失败';
    } else {
      pillColor = CupertinoDynamicColor.resolve(
        CupertinoColors.systemGrey,
        context,
      );
      label = '未配置';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: pillColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: pillColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final Color borderColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemRed,
      context,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: borderColor.withOpacity(0.11),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: borderColor,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              errorMessage ?? '出现未知错误',
              style: TextStyle(
                color: borderColor,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildConnectedContent(BuildContext context) {
    final List<Widget> children = [];
    children.addAll([
      _buildInfoRow(
        context,
        label: '服务器地址',
        value: serverUrl?.isNotEmpty == true ? serverUrl! : '未知',
      ),
      const SizedBox(height: 8),
      _buildInfoRow(
        context,
        label: '最近同步',
        value: _formatRelativeTime(lastSyncedAt),
      ),
      const SizedBox(height: 12),
      _buildStatsRow(context),
      const SizedBox(height: 16),
      _buildPreviewSection(context),
      const SizedBox(height: 18),
      _buildActionButtons(context),
    ]);
    return children;
  }

  Widget _buildStatsRow(BuildContext context) {
    final stats = [
      {'label': '番剧条目', 'value': '$animeGroupCount'},
      {'label': '视频文件', 'value': '$episodeCount'},
      {'label': '最近同步', 'value': _formatRelativeTime(lastSyncedAt)},
    ];

    return Row(
      children: List.generate(stats.length, (index) {
        final stat = stats[index];
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: index == stats.length - 1 ? 0 : 12),
            child: _buildStatTile(
              context,
              label: stat['label']! as String,
              value: stat['value']! as String,
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatTile(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final Color foreground = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final Color secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color tileColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tileColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: foreground,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: secondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewSection(BuildContext context) {
    if (previewGroups.isEmpty) {
      final Color textColor = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel,
        context,
      );
      final Color tileColor = CupertinoDynamicColor.resolve(
        CupertinoColors.systemGrey5,
        context,
      );
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tileColor.withOpacity(0.4),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          '暂无远程媒体记录，可尝试刷新或确认远程访问设置。',
          style: TextStyle(fontSize: 13, color: textColor, height: 1.35),
        ),
      );
    }

    final Color headingColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '最近更新',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: headingColor,
          ),
        ),
        const SizedBox(height: 10),
        ...previewGroups.map((group) => _buildPreviewTile(context, group)),
      ],
    );
  }

  Widget _buildPreviewTile(
    BuildContext context,
    DandanplayRemoteAnimeGroup group,
  ) {
    final DandanplayRemoteEpisode latest = group.latestEpisode;
    final Color secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color tileColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );

    final String subtitle =
        '${latest.episodeTitle} · ${_formatRelativeTime(latest.lastPlay ?? latest.created)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tileColor.withOpacity(0.45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _accentColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              CupertinoIcons.play_fill,
              color: _accentColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.title,
                  style: TextStyle(
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.label,
                      context,
                    ),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: secondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: CupertinoDynamicColor.resolve(
                CupertinoColors.systemGrey3,
                context,
              ).withOpacity(0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '共 ${group.episodeCount} 集',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final List<Widget> buttons = [];
    buttons.add(
      _buildActionButton(
        context,
        label: '管理连接',
        icon: CupertinoIcons.slider_horizontal_3,
        onPressed: isLoading ? null : onManage,
      ),
    );

    if (onRefresh != null) {
      buttons.add(
        _buildActionButton(
          context,
          label: isLoading ? '同步中...' : '刷新媒体库',
          icon: CupertinoIcons.refresh,
          onPressed: isLoading ? null : onRefresh,
        ),
      );
    }

    if (onDisconnect != null) {
      buttons.add(
        _buildActionButton(
          context,
          label: '断开连接',
          icon: CupertinoIcons.clear,
          onPressed: isLoading ? null : onDisconnect,
          destructive: true,
        ),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      children: buttons,
    );
  }

  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    final Color activeBackground = destructive
        ? CupertinoDynamicColor.resolve(
            CupertinoColors.systemRed,
            context,
          )
        : CupertinoDynamicColor.resolve(
            CupertinoColors.systemGrey5,
            context,
          );
    final Color disabledBackground = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    ).withOpacity(0.5);

    final Color activeForeground =
        destructive ? CupertinoColors.white : CupertinoColors.label;
    final bool isDisabled = onPressed == null;

    return CupertinoButton(
      onPressed: onPressed,
      padding: EdgeInsets.zero,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: isDisabled ? disabledBackground : activeBackground,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color:
                  isDisabled ? CupertinoColors.inactiveGray : activeForeground,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDisabled
                    ? CupertinoDynamicColor.resolve(
                        CupertinoColors.systemGrey2,
                        context,
                      )
                    : activeForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDisconnectedContent(BuildContext context) {
    final Color secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '通过弹弹play 桌面端开启远程访问后，可在此同步家中电脑或 NAS 上的番剧记录并直接播放。',
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: secondary,
          ),
        ),
        const SizedBox(height: 16),
        CupertinoButton.filled(
          onPressed: isLoading ? null : onManage,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(CupertinoIcons.link),
              const SizedBox(width: 6),
              Text(isLoading ? '请稍候...' : '连接弹弹play 远程服务'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required String label,
    required String value,
  }) {
    final Color labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final Color valueColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: labelColor, fontSize: 13),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  String _formatRelativeTime(DateTime? timestamp) {
    if (timestamp == null) {
      return '暂无记录';
    }
    final now = DateTime.now();
    final diff = now.difference(timestamp);
    if (diff.inMinutes < 1) {
      return '刚刚';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes} 分钟前';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours} 小时前';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays} 天前';
    }

    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${timestamp.year}-${twoDigits(timestamp.month)}-${twoDigits(timestamp.day)} '
        '${twoDigits(timestamp.hour)}:${twoDigits(timestamp.minute)}';
  }
}

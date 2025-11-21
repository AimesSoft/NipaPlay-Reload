import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:intl/intl.dart';

class CupertinoBangumiSection extends StatelessWidget {
  final bool isAuthorized;
  final Map<String, dynamic>? userInfo;
  final bool isLoading;
  final bool isSyncing;
  final String syncStatus;
  final DateTime? lastSyncTime;
  final TextEditingController tokenController;
  final VoidCallback onSaveToken;
  final VoidCallback onClearToken;
  final VoidCallback onSync;
  final VoidCallback onFullSync;
  final VoidCallback onTestConnection;
  final VoidCallback onClearCache;
  final VoidCallback onOpenHelp;

  const CupertinoBangumiSection({
    super.key,
    required this.isAuthorized,
    required this.userInfo,
    required this.isLoading,
    required this.isSyncing,
    required this.syncStatus,
    required this.lastSyncTime,
    required this.tokenController,
    required this.onSaveToken,
    required this.onClearToken,
    required this.onSync,
    required this.onFullSync,
    required this.onTestConnection,
    required this.onClearCache,
    required this.onOpenHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(context),
        const SizedBox(height: 16),
        _buildTokenCard(context),
        const SizedBox(height: 16),
        _buildActionsCard(context),
      ],
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final String title = isAuthorized ? '已连接 Bangumi' : '尚未连接 Bangumi';
    final Color iconColor = isAuthorized
        ? CupertinoColors.activeGreen
        : CupertinoColors.systemGrey;
    final Color textColor = CupertinoDynamicColor.resolve(
      isAuthorized ? CupertinoColors.activeGreen : CupertinoColors.systemGrey,
      context,
    );

    final String subtitle;
    if (isAuthorized) {
      final nickname = userInfo?['nickname'] ?? userInfo?['username'] ?? '已授权';
      subtitle = '当前账号：$nickname';
    } else {
      subtitle = '保存 Bangumi 访问令牌以启用观看历史同步。';
    }

    final String? syncInfo;
    if (lastSyncTime != null) {
      syncInfo = '上次同步：${_formatTime(lastSyncTime!)}';
    } else {
      syncInfo = null;
    }

    return _buildRoundedCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.cloud_upload,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(color: CupertinoColors.systemGrey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (syncInfo != null) ...[
            const SizedBox(height: 12),
            Text(
              syncInfo,
              style: CupertinoTheme.of(context)
                  .textTheme
                  .textStyle
                  .copyWith(fontSize: 13, color: CupertinoColors.systemGrey),
            ),
          ],
          if (isSyncing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const CupertinoActivityIndicator(radius: 9),
                const SizedBox(width: 8),
                Text(
                  syncStatus.isEmpty ? '同步中...' : syncStatus,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(color: CupertinoColors.activeBlue),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTokenCard(BuildContext context) {
    return _buildRoundedCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '访问令牌',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          Text(
            '在 Bangumi 网站生成访问令牌后粘贴到此处。',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 12),
          AdaptiveTextField(
            controller: tokenController,
            placeholder: '请输入 Bangumi 访问令牌',
            obscureText: true,
            enabled: !isLoading,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AdaptiveButton(
                  onPressed: isLoading ? null : onSaveToken,
                  style: AdaptiveButtonStyle.filled,
                  label: '保存令牌',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdaptiveButton(
                  onPressed: isLoading ? null : onClearToken,
                  style: AdaptiveButtonStyle.bordered,
                  label: '删除令牌',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AdaptiveButton.child(
            onPressed: onOpenHelp,
            style: AdaptiveButtonStyle.plain,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(CupertinoIcons.link, size: 16, color: CupertinoColors.activeBlue),
                SizedBox(width: 6),
                Text(
                  '如何获取 Bangumi 访问令牌',
                  style: TextStyle(color: CupertinoColors.activeBlue, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    return _buildRoundedCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '同步操作',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          AdaptiveButton(
            onPressed: isSyncing ? null : onSync,
            style: AdaptiveButtonStyle.filled,
            label: '增量同步',
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: isSyncing ? null : onFullSync,
            style: AdaptiveButtonStyle.tinted,
            label: '全量同步',
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: isSyncing ? null : onTestConnection,
            style: AdaptiveButtonStyle.bordered,
            label: '测试连接',
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: isSyncing ? null : onClearCache,
            style: AdaptiveButtonStyle.gray,
            label: '清除同步缓存',
          ),
        ],
      ),
    );
  }

  Widget _buildRoundedCard(
    BuildContext context, {
    required EdgeInsets padding,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBackgroundColor(context),
        borderRadius: BorderRadius.circular(24),
      ),
      padding: padding,
      child: child,
    );
  }

  String _formatTime(DateTime time) {
    final formatter = DateFormat('yyyy-MM-dd HH:mm');
    return formatter.format(time);
  }

  Color _cardBackgroundColor(BuildContext context) {
    return CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );
  }
}

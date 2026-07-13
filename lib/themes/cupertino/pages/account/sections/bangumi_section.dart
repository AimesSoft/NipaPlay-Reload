import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/pages/account/account_page_view_model.dart';
import 'package:intl/intl.dart';

class CupertinoBangumiSection extends StatelessWidget {
  final BangumiAccountViewModel data;

  const CupertinoBangumiSection({
    super.key,
    required this.data,
  });

  Widget _buildBangumiSyncHelpButton(
    BuildContext context,
    VoidCallback onPressed,
  ) {
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(28, 28),
      onPressed: onPressed,
      child: Icon(
        CupertinoIcons.question_circle,
        size: 18,
        color: CupertinoTheme.of(context).primaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildStatusCard(context),
        const SizedBox(height: 16),
        _buildDandanLinkedCard(context),
        const SizedBox(height: 16),
        _buildTokenCard(context),
        const SizedBox(height: 16),
        _buildActionsCard(context),
      ],
    );
  }

  Widget _buildDandanLinkedCard(BuildContext context) {
    final expiresAt = data.dandanLinkedExpireTime;
    final isExpired = data.isDandanAuthorizationExpired;

    return _buildRoundedCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  BangumiAccountViewModel.dandanTitle,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              _buildBangumiSyncHelpButton(
                context,
                data.onOpenDandanHelp,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            data.dandanStatusText,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  color: isExpired
                      ? CupertinoColors.systemOrange
                      : CupertinoColors.systemGrey,
                ),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 8),
            Text(
              '授权过期时间：${_formatTime(expiresAt)}',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: isExpired
                        ? CupertinoColors.systemOrange
                        : CupertinoColors.systemGrey,
                  ),
            ),
          ],
          if (isExpired) ...[
            const SizedBox(height: 6),
            Text(
              '授权已过期或续期失败，请重新授权。',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: CupertinoColors.systemOrange,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          AdaptiveButton(
            onPressed: data.requestDandanAuthAction.onPressed,
            style: AdaptiveButtonStyle.filled,
            color: CupertinoTheme.of(context).primaryColor,
            label: data.requestDandanAuthAction.label,
          ),
          const SizedBox(height: 10),
          AdaptiveButton(
            onPressed: data.manageDandanAction.onPressed,
            style: AdaptiveButtonStyle.bordered,
            color: CupertinoTheme.of(context).primaryColor,
            label: data.manageDandanAction.label,
          ),
          const SizedBox(height: 10),
          AdaptiveButton(
            onPressed: data.refreshDandanAction.onPressed,
            style: AdaptiveButtonStyle.bordered,
            color: CupertinoTheme.of(context).primaryColor,
            label: data.refreshDandanAction.label,
          ),
          const SizedBox(height: 8),
          Text(
            BangumiAccountViewModel.dandanDescription,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 13,
                  color: CupertinoColors.systemGrey,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final String title = data.connectionTitle;
    final Color iconColor = data.isAuthorized
        ? CupertinoColors.activeGreen
        : CupertinoColors.systemGrey;
    final Color textColor = CupertinoDynamicColor.resolve(
      data.isAuthorized
          ? CupertinoColors.activeGreen
          : CupertinoColors.systemGrey,
      context,
    );

    final String? syncInfo;
    if (data.lastSyncTime != null) {
      syncInfo = '上次同步：${_formatTime(data.lastSyncTime!)}';
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
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(CupertinoIcons.cloud_upload, color: iconColor),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
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
                        ),
                        _buildBangumiSyncHelpButton(
                          context,
                          data.onOpenNipaplayHelp,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.connectionSubtitle,
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
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: CupertinoColors.systemGrey,
                  ),
            ),
          ],
          if (data.isSyncing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const CupertinoActivityIndicator(radius: 9),
                const SizedBox(width: 8),
                Text(
                  data.syncStatus.isEmpty ? '同步中...' : data.syncStatus,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(color: CupertinoTheme.of(context).primaryColor),
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
            BangumiAccountViewModel.tokenTitle,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            BangumiAccountViewModel.tokenDescription,
            style: CupertinoTheme.of(
              context,
            ).textTheme.textStyle.copyWith(color: CupertinoColors.systemGrey),
          ),
          const SizedBox(height: 12),
          AdaptiveTextField(
            controller: data.tokenController,
            placeholder: BangumiAccountViewModel.tokenPlaceholder,
            obscureText: true,
            enabled: !data.isLoading,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AdaptiveButton(
                  onPressed: data.tokenActions[0].onPressed,
                  style: AdaptiveButtonStyle.filled,
                  color: CupertinoTheme.of(context).primaryColor,
                  label: data.tokenActions[0].label,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AdaptiveButton(
                  onPressed: data.tokenActions[1].onPressed,
                  style: AdaptiveButtonStyle.bordered,
                  color: CupertinoTheme.of(context).primaryColor,
                  label: data.tokenActions[1].label,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AdaptiveButton.child(
            onPressed: data.onOpenNipaplayHelp,
            style: AdaptiveButtonStyle.plain,
            color: CupertinoTheme.of(context).primaryColor,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.link,
                  size: 16,
                  color: CupertinoTheme.of(context).primaryColor,
                ),
                const SizedBox(width: 6),
                Text(
                  BangumiAccountViewModel.tokenHelpLabel,
                  style: TextStyle(
                    color: CupertinoTheme.of(context).primaryColor,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionsCard(BuildContext context) {
    final actions = data.syncActions;
    return _buildRoundedCard(
      context,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            BangumiAccountViewModel.actionsTitle,
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 16),
          AdaptiveButton(
            onPressed: actions[0].onPressed,
            style: AdaptiveButtonStyle.filled,
            color: CupertinoTheme.of(context).primaryColor,
            label: actions[0].label,
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: actions[1].onPressed,
            style: AdaptiveButtonStyle.tinted,
            color: CupertinoTheme.of(context).primaryColor,
            label: actions[1].label,
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: actions[2].onPressed,
            style: AdaptiveButtonStyle.bordered,
            color: CupertinoTheme.of(context).primaryColor,
            label: actions[2].label,
          ),
          const SizedBox(height: 12),
          AdaptiveButton(
            onPressed: actions[3].onPressed,
            style: AdaptiveButtonStyle.gray,
            color: CupertinoTheme.of(context).primaryColor,
            label: actions[3].label,
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

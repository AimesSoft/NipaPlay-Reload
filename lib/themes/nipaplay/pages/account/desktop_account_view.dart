import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nipaplay/pages/account/account_page_view_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';

class DesktopAccountView extends StatelessWidget {
  const DesktopAccountView({
    super.key,
    required this.data,
    required this.userActivity,
  });

  final AccountPageViewModel data;
  final Widget userActivity;

  @override
  Widget build(BuildContext context) {
    final dividerColor =
        fluent.FluentTheme.of(context).resources.dividerStrokeColorDefault;
    return fluent.ScaffoldPage(
      padding: EdgeInsets.zero,
      content: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _DesktopDandanplayAccountSection(
                data: data.dandanplay,
                userActivity: userActivity,
              ),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: dividerColor,
            ),
            Expanded(
              child: _DesktopBangumiAccountSection(data: data.bangumi),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDandanplayAccountSection extends StatelessWidget {
  const _DesktopDandanplayAccountSection({
    required this.data,
    required this.userActivity,
  });

  final DandanplayAccountViewModel data;
  final Widget userActivity;

  @override
  Widget build(BuildContext context) {
    if (!data.isLoggedIn) {
      final actions = data.actions;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _DesktopAccountCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _DesktopSectionTitle(
                    text: DandanplayAccountViewModel.signedOutTitle,
                  ),
                  SizedBox(height: 8),
                  _DesktopSecondaryText(
                    DandanplayAccountViewModel.signedOutDescription,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _DesktopAccountCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DesktopActionButton(action: actions[0]),
                  const SizedBox(height: 12),
                  _DesktopActionButton(action: actions[1]),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final actions = data.actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DesktopAccountCard(
          child: Row(
            children: [
              _DesktopAvatar(
                username: data.username,
                avatarUrl: data.avatarUrl,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DesktopSectionTitle(text: data.username),
                    const SizedBox(height: 4),
                    const _DesktopSecondaryText('弹弹play账号'),
                  ],
                ),
              ),
              _DesktopActionButton(action: actions[0], compact: true),
              const SizedBox(width: 8),
              _DesktopActionButton(action: actions[1], compact: true),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: userActivity,
          ),
        ),
      ],
    );
  }
}

class _DesktopBangumiAccountSection extends StatelessWidget {
  const _DesktopBangumiAccountSection({required this.data});

  final BangumiAccountViewModel data;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStatusCard(context),
          const SizedBox(height: 16),
          _buildDandanCard(context),
          const SizedBox(height: 16),
          _buildTokenCard(context),
          const SizedBox(height: 16),
          _buildSyncCard(),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final accent = data.isAuthorized
        ? fluent.Colors.successPrimaryColor
        : fluent.FluentTheme.of(context).resources.textFillColorSecondary;
    return _DesktopAccountCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          fluent.Icon(fluent.FluentIcons.cloud_upload, color: accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _DesktopSectionTitle(
                        text: data.connectionTitle,
                        color: accent,
                      ),
                    ),
                    _DesktopHelpButton(onPressed: data.onOpenNipaplayHelp),
                  ],
                ),
                const SizedBox(height: 4),
                _DesktopSecondaryText(data.connectionSubtitle),
                if (data.lastSyncTime != null) ...[
                  const SizedBox(height: 8),
                  _DesktopSecondaryText(
                    '上次同步：${_formatTime(data.lastSyncTime!)}',
                    fontSize: 12,
                  ),
                ],
                if (data.isSyncing) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: fluent.ProgressRing(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          data.syncStatus.isEmpty ? '同步中...' : data.syncStatus,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDandanCard(BuildContext context) {
    final expiresAt = data.dandanLinkedExpireTime;
    const warningColor = fluent.Colors.warningPrimaryColor;
    return _DesktopAccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: _DesktopSectionTitle(
                  text: BangumiAccountViewModel.dandanTitle,
                ),
              ),
              _DesktopHelpButton(onPressed: data.onOpenDandanHelp),
            ],
          ),
          const SizedBox(height: 12),
          _DesktopSecondaryText(
            data.dandanStatusText,
            color: data.isDandanAuthorizationExpired ? warningColor : null,
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 8),
            _DesktopSecondaryText(
              '授权过期时间：${_formatTime(expiresAt)}',
              fontSize: 12,
              color: data.isDandanAuthorizationExpired ? warningColor : null,
            ),
          ],
          if (data.isDandanAuthorizationExpired) ...[
            const SizedBox(height: 6),
            const _DesktopSecondaryText(
              '授权已过期或续期失败，请重新授权。',
              fontSize: 12,
              color: warningColor,
            ),
          ],
          const SizedBox(height: 14),
          _DesktopActionButton(action: data.requestDandanAuthAction),
          const SizedBox(height: 10),
          _DesktopActionButton(action: data.manageDandanAction),
          const SizedBox(height: 10),
          _DesktopActionButton(action: data.refreshDandanAction),
          const SizedBox(height: 8),
          const _DesktopSecondaryText(
            BangumiAccountViewModel.dandanDescription,
            fontSize: 12,
          ),
        ],
      ),
    );
  }

  Widget _buildTokenCard(BuildContext context) {
    final actions = data.tokenActions;
    return _DesktopAccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DesktopSectionTitle(text: BangumiAccountViewModel.tokenTitle),
          const SizedBox(height: 12),
          const _DesktopSecondaryText(
            BangumiAccountViewModel.tokenDescription,
          ),
          const SizedBox(height: 12),
          fluent.PasswordBox(
            controller: data.tokenController,
            placeholder: BangumiAccountViewModel.tokenPlaceholder,
            enabled: !data.isLoading,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _DesktopActionButton(action: actions[0])),
              const SizedBox(width: 12),
              Expanded(child: _DesktopActionButton(action: actions[1])),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _DesktopActionButton(
              action: AccountActionViewModel(
                id: 'token-help',
                label: BangumiAccountViewModel.tokenHelpLabel,
                onPressed: data.onOpenNipaplayHelp,
                role: AccountActionRole.plain,
              ),
              compact: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncCard() {
    final actions = data.syncActions;
    return _DesktopAccountCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _DesktopSectionTitle(
              text: BangumiAccountViewModel.actionsTitle),
          const SizedBox(height: 16),
          for (var index = 0; index < actions.length; index++) ...[
            _DesktopActionButton(action: actions[index]),
            if (index != actions.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) =>
      DateFormat('yyyy-MM-dd HH:mm').format(time);
}

class _DesktopAccountCard extends StatelessWidget {
  const _DesktopAccountCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final resources = fluent.FluentTheme.of(context).resources;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: resources.cardBackgroundFillColorDefault,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: resources.cardStrokeColorDefault),
      ),
      child: child,
    );
  }
}

class _DesktopSectionTitle extends StatelessWidget {
  const _DesktopSectionTitle({required this.text, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ??
            fluent.FluentTheme.of(context).resources.textFillColorPrimary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _DesktopSecondaryText extends StatelessWidget {
  const _DesktopSecondaryText(
    this.text, {
    this.fontSize = 14,
    this.color,
  });

  final String text;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color ??
            fluent.FluentTheme.of(context).resources.textFillColorSecondary,
        fontSize: fontSize,
      ),
    );
  }
}

class _DesktopActionButton extends StatelessWidget {
  const _DesktopActionButton({
    required this.action,
    this.compact = false,
  });

  final AccountActionViewModel action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final disabled = action.onPressed == null;
    final button = BlurButton(
      icon: _iconFor(action.id),
      text: action.label,
      flatStyle: true,
      hoverScale: 1.06,
      onTap: action.onPressed ?? () {},
    );
    return IgnorePointer(
      ignoring: disabled,
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child:
            compact ? button : SizedBox(width: double.infinity, child: button),
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'login':
        return fluent.FluentIcons.signin;
      case 'register':
        return fluent.FluentIcons.add_friend;
      case 'logout':
        return fluent.FluentIcons.sign_out;
      case 'delete-account':
      case 'clear-token':
        return fluent.FluentIcons.delete;
      case 'save-token':
        return fluent.FluentIcons.save;
      case 'dandan-authorize':
      case 'dandan-manage':
      case 'token-help':
        return fluent.FluentIcons.link;
      case 'dandan-refresh':
      case 'incremental-sync':
      case 'full-sync':
        return fluent.FluentIcons.sync;
      case 'test-connection':
        return fluent.FluentIcons.wifi;
      case 'clear-sync-cache':
        return fluent.FluentIcons.clear;
      default:
        return fluent.FluentIcons.account_management;
    }
  }
}

class _DesktopHelpButton extends StatelessWidget {
  const _DesktopHelpButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return fluent.Tooltip(
      message: '查看说明',
      child: fluent.IconButton(
        icon: const fluent.Icon(fluent.FluentIcons.help, size: 16),
        onPressed: onPressed,
      ),
    );
  }
}

class _DesktopAvatar extends StatelessWidget {
  const _DesktopAvatar({required this.username, required this.avatarUrl});

  final String username;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      color: fluent.FluentTheme.of(context)
          .resources
          .cardBackgroundFillColorSecondary,
      child: Text(
        username.isEmpty ? '?' : username.characters.first.toUpperCase(),
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
    );
    return ClipOval(
      child: avatarUrl == null
          ? fallback
          : Image.network(
              avatarUrl!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            ),
    );
  }
}

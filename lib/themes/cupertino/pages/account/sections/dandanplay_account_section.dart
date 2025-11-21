import 'package:flutter/cupertino.dart';

import '../widgets/account_action_button.dart';
import '../widgets/account_profile_card.dart';

class CupertinoDandanplayAccountSection extends StatelessWidget {
  final bool isLoggedIn;
  final String username;
  final String? avatarUrl;
  final bool isLoading;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;
  final Widget userActivity;

  const CupertinoDandanplayAccountSection({
    super.key,
    required this.isLoggedIn,
    required this.username,
    required this.avatarUrl,
    required this.isLoading,
    required this.onLogin,
    required this.onRegister,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.userActivity,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );

    Widget buildCard({
      required EdgeInsets padding,
      required Widget child,
    }) {
      return Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(24),
        ),
        padding: padding,
        child: child,
      );
    }

    if (isLoggedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoAccountProfileCard(
            username: username,
            avatarUrl: avatarUrl,
          ),
          const SizedBox(height: 16),
          buildCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoAccountActionButton(
                    label: '退出登录',
                    iosIcon: CupertinoIcons.square_arrow_left,
                    onPressed: onLogout,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoAccountActionButton(
                    label: isLoading ? '处理中...' : '注销账号',
                    iosIcon: CupertinoIcons.delete,
                    destructive: true,
                    isLoading: isLoading,
                    onPressed: isLoading ? null : onDeleteAccount,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          userActivity,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '登录弹弹play账号',
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '登录后可同步观看记录、收藏和应用设置。',
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(color: CupertinoColors.systemGrey),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        buildCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CupertinoAccountActionButton(
                label: '立即登录',
                iosIcon: CupertinoIcons.person_crop_circle,
                onPressed: onLogin,
              ),
              const SizedBox(height: 12),
              CupertinoAccountActionButton(
                label: '注册新账号',
                iosIcon: CupertinoIcons.person_badge_plus,
                onPressed: onRegister,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

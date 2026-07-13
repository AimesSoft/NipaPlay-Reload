import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/pages/account/account_page_view_model.dart';

import '../widgets/account_action_button.dart';
import '../widgets/account_profile_card.dart';

class CupertinoDandanplayAccountSection extends StatelessWidget {
  final DandanplayAccountViewModel data;
  final Widget userActivity;

  const CupertinoDandanplayAccountSection({
    super.key,
    required this.data,
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

    if (data.isLoggedIn) {
      final actions = data.actions;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CupertinoAccountProfileCard(
            username: data.username,
            avatarUrl: data.avatarUrl,
          ),
          const SizedBox(height: 16),
          buildCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: CupertinoAccountActionButton(
                    label: actions[0].label,
                    iosIcon: CupertinoIcons.square_arrow_left,
                    onPressed: actions[0].onPressed,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoAccountActionButton(
                    label: actions[1].label,
                    iosIcon: CupertinoIcons.delete,
                    destructive: true,
                    isLoading: actions[1].isLoading,
                    onPressed: actions[1].onPressed,
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

    final actions = data.actions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DandanplayAccountViewModel.signedOutTitle,
                style: CupertinoTheme.of(context)
                    .textTheme
                    .textStyle
                    .copyWith(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                DandanplayAccountViewModel.signedOutDescription,
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
                label: actions[0].label,
                iosIcon: CupertinoIcons.person_crop_circle,
                onPressed: actions[0].onPressed,
              ),
              const SizedBox(height: 12),
              CupertinoAccountActionButton(
                label: actions[1].label,
                iosIcon: CupertinoIcons.person_badge_plus,
                onPressed: actions[1].onPressed,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

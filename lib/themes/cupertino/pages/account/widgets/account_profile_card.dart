import 'package:flutter/cupertino.dart';

class CupertinoAccountProfileCard extends StatelessWidget {
  final String username;
  final String? avatarUrl;

  const CupertinoAccountProfileCard({
    super.key,
    required this.username,
    this.avatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final Color badgeColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGreen.withOpacity(0.2),
      context,
    );
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.darkBackgroundGray,
      ),
      context,
    );

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          _buildAvatar(context),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  username,
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 14,
                        color: CupertinoColors.systemGreen,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '已登录',
                        style: TextStyle(
                          fontSize: 12,
                          color: CupertinoColors.systemGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final double size = 60;
    final BorderRadius radius = BorderRadius.circular(size / 2);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) {
            return _buildFallbackAvatar(size);
          },
        ),
      );
    }

    return _buildFallbackAvatar(size);
  }

  Widget _buildFallbackAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CupertinoColors.systemGrey5,
        borderRadius: BorderRadius.circular(size / 2),
      ),
      child: const Icon(
        CupertinoIcons.person_crop_circle,
        size: 38,
        color: CupertinoColors.systemGrey2,
      ),
    );
  }
}

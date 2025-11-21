import 'package:flutter/cupertino.dart';

/// 液态玻璃风格的网络媒体服务器卡片。
class CupertinoGlassMediaServerCard extends StatelessWidget {
  const CupertinoGlassMediaServerCard({
    super.key,
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.onTap,
    required this.onManage,
    this.subtitle,
    this.libraryNames = const <String>[],
    this.isLoading = false,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color accentColor;
  final List<String> libraryNames;
  final VoidCallback onTap;
  final VoidCallback onManage;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = CupertinoTheme.of(context).brightness ??
        MediaQuery.maybeOf(context)?.platformBrightness ??
        Brightness.light;

    final List<Color> gradientColors = brightness == Brightness.dark
        ? [
            CupertinoColors.white.withValues(alpha: 0.12),
            CupertinoColors.white.withValues(alpha: 0.04),
          ]
        : [
            CupertinoColors.white.withValues(alpha: 0.78),
            CupertinoColors.white.withValues(alpha: 0.45),
          ];

    final Color borderColor = brightness == Brightness.dark
        ? CupertinoColors.white.withValues(alpha: 0.16)
        : CupertinoColors.white.withValues(alpha: 0.35);

    final Color tertiaryLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.tertiaryLabel,
      context,
    );

    final Color secondaryLabelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );

    final String summary = _buildLibrarySummary();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Container(
          constraints: const BoxConstraints(minHeight: 136),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: borderColor, width: 0.6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildIconContainer(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null && subtitle!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                fontSize: 13,
                                color: secondaryLabelColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: CupertinoActivityIndicator(radius: 9),
                    ),
                  CupertinoButton(
                    onPressed: onManage,
                    padding: const EdgeInsets.all(6),
                    minimumSize: const Size(30, 30),
                    child: Icon(
                      CupertinoIcons.slider_horizontal_3,
                      color: accentColor,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                summary,
                style: TextStyle(
                  fontSize: 13,
                  color: libraryNames.isNotEmpty
                      ? secondaryLabelColor
                      : tertiaryLabelColor,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    '浏览媒体库',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label,
                        context,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: secondaryLabelColor,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIconContainer() {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: accentColor, size: 22),
    );
  }

  String _buildLibrarySummary() {
    if (libraryNames.isEmpty) {
      return '未选择任何媒体库，点击右上角进行管理';
    }
    final List<String> displayNames =
        libraryNames.length > 2 ? libraryNames.take(2).toList() : libraryNames;
    final int remaining = libraryNames.length - displayNames.length;
    final buffer = StringBuffer('媒体库：${displayNames.join("、")}');
    if (remaining > 0) {
      buffer.write(' 等 $remaining 个');
    }
    return buffer.toString();
  }
}

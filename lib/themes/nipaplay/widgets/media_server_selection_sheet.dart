import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/media_library/media_source_option.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';

class MediaServerSelectionSheet extends StatelessWidget {
  const MediaServerSelectionSheet({
    super.key,
    this.options = mediaSourceOptions,
  });

  final List<MediaSourceOption> options;

  static Future<String?> show(
    BuildContext context, {
    List<MediaSourceOption> options = mediaSourceOptions,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    return BlurDialog.show<String>(
      context: context,
      title: '添加媒体',
      backgroundColor: backgroundColor,
      contentWidget: MediaServerSelectionSheet(options: options),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subTextColor = isDarkMode ? Colors.white70 : Colors.black54;
    final borderColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.12);
    final cardColor =
        isDarkMode ? const Color(0xFF242424) : const Color(0xFFEDEDED);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final maxWidth = constraints.maxWidth;
        final columnCount = maxWidth >= 420 ? 2 : 1;
        final itemWidth =
            (maxWidth - (columnCount - 1) * spacing) / columnCount;

        Widget buildGrid(List<Widget> items) {
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: items
                .map((item) => SizedBox(width: itemWidth, child: item))
                .toList(),
          );
        }

        return SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final category in MediaSourceCategory.values)
                if (options.any((option) => option.category == category)) ...[
                  _buildSectionTitle(category.label, textColor),
                  const SizedBox(height: 12),
                  buildGrid([
                    for (final option in options.where(
                      (option) => option.category == category,
                    ))
                      _buildServerOptionCard(
                        icon: _buildSourceIcon(option.iconKind),
                        title: option.title,
                        subtitle: option.subtitle,
                        accentColor: _accentColor(option.iconKind),
                        textColor: textColor,
                        subTextColor: subTextColor,
                        borderColor: borderColor,
                        cardColor: cardColor,
                        onTap: () => Navigator.of(context).pop(option.id),
                      ),
                  ]),
                  if (category != MediaSourceCategory.values.last)
                    const SizedBox(height: 20),
                ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title, Color textColor) {
    return Text(
      title,
      locale: const Locale("zh-Hans", "zh"),
      style: TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  Widget _buildServerOptionCard({
    required Widget icon,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color textColor,
    required Color subTextColor,
    required Color borderColor,
    required Color cardColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        focusColor: accentColor.withValues(alpha: 0.12),
        hoverColor: accentColor.withValues(alpha: 0.08),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: Center(child: icon),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      locale: const Locale("zh-Hans", "zh"),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: subTextColor,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Ionicons.chevron_forward,
                size: 16,
                color: subTextColor,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSvgIcon(String asset, Color color) {
    return SvgPicture.asset(
      asset,
      width: 30,
      height: 30,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _buildImageIcon(String asset, Color color) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        asset,
        width: 30,
        height: 30,
      ),
    );
  }

  Widget _buildSourceIcon(MediaSourceIconKind kind) {
    final color = _accentColor(kind);
    return switch (kind) {
      MediaSourceIconKind.localFolder =>
        Icon(Icons.folder_open_outlined, size: 30, color: color),
      MediaSourceIconKind.nipaplay =>
        _buildImageIcon('assets/nipaplay.png', color),
      MediaSourceIconKind.jellyfin =>
        _buildSvgIcon('assets/jellyfin.svg', color),
      MediaSourceIconKind.dandanplay =>
        _buildImageIcon('assets/dandanplay.png', color),
      MediaSourceIconKind.emby => _buildSvgIcon('assets/emby.svg', color),
      MediaSourceIconKind.webdav =>
        Icon(Icons.cloud_outlined, size: 30, color: color),
      MediaSourceIconKind.smb =>
        Icon(Icons.lan_outlined, size: 30, color: color),
    };
  }

  Color _accentColor(MediaSourceIconKind kind) => switch (kind) {
        MediaSourceIconKind.localFolder => const Color(0xFFFFB74D),
        MediaSourceIconKind.nipaplay => const Color(0xFFB39DDB),
        MediaSourceIconKind.jellyfin => Colors.lightBlueAccent,
        MediaSourceIconKind.dandanplay => const Color(0xFF4DA3FF),
        MediaSourceIconKind.emby => const Color(0xFF52B54B),
        MediaSourceIconKind.webdav => const Color(0xFF6AB7FF),
        MediaSourceIconKind.smb => const Color(0xFF5CBF73),
      };
}

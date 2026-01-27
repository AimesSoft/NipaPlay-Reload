import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';

class MediaServerSelectionSheet extends StatelessWidget {
  const MediaServerSelectionSheet({super.key});

  static Future<String?> show(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor =
        isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);
    return BlurDialog.show<String>(
      context: context,
      title: '添加媒体库',
      backgroundColor: backgroundColor,
      contentWidget: const MediaServerSelectionSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subTextColor = isDarkMode ? Colors.white70 : Colors.black54;
    final borderColor =
        isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.12);
    final cardColor = isDarkMode ? const Color(0xFF242424) : const Color(0xFFEDEDED);
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final maxWidth = constraints.maxWidth;
        final columnCount = maxWidth >= 520 ? 2 : 1;
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
              _buildSectionTitle('网络媒体服务器', textColor),
              const SizedBox(height: 12),
              buildGrid([
                _buildServerOptionCard(
                  icon: _buildImageIcon('assets/nipaplay.png',
                      const Color(0xFFB39DDB)),
                  title: 'NipaPlay',
                  subtitle: '局域网媒体共享',
                  accentColor: const Color(0xFFB39DDB),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('nipaplay'),
                ),
                _buildServerOptionCard(
                  icon: _buildSvgIcon('assets/jellyfin.svg',
                      Colors.lightBlueAccent),
                  title: 'Jellyfin',
                  subtitle: '开源媒体服务器',
                  accentColor: Colors.lightBlueAccent,
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('jellyfin'),
                ),
                _buildServerOptionCard(
                  icon: _buildImageIcon(
                      'assets/dandanplay.png', const Color(0xFF4DA3FF)),
                  title: '弹弹play',
                  subtitle: '弹幕番剧远程服务',
                  accentColor: const Color(0xFF4DA3FF),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('dandanplay'),
                ),
                _buildServerOptionCard(
                  icon: _buildSvgIcon(
                      'assets/emby.svg', const Color(0xFF52B54B)),
                  title: 'Emby',
                  subtitle: '功能丰富的媒体服务器',
                  accentColor: const Color(0xFF52B54B),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('emby'),
                ),
              ]),
              const SizedBox(height: 20),
              _buildSectionTitle('网络文件共享', textColor),
              const SizedBox(height: 12),
              buildGrid([
                _buildServerOptionCard(
                  icon: const Icon(Icons.cloud_outlined,
                      size: 22, color: Color(0xFF6AB7FF)),
                  title: 'WebDAV',
                  subtitle: '添加WebDAV服务器',
                  accentColor: const Color(0xFF6AB7FF),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('webdav'),
                ),
                _buildServerOptionCard(
                  icon: const Icon(Icons.lan_outlined,
                      size: 22, color: Color(0xFF5CBF73)),
                  title: 'SMB',
                  subtitle: '添加SMB共享',
                  accentColor: const Color(0xFF5CBF73),
                  textColor: textColor,
                  subTextColor: subTextColor,
                  borderColor: borderColor,
                  cardColor: cardColor,
                  onTap: () => Navigator.of(context).pop('smb'),
                ),
              ]),
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
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
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
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accentColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
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
      width: 24,
      height: 24,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  Widget _buildImageIcon(String asset, Color color) {
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(
        asset,
        width: 24,
        height: 24,
      ),
    );
  }
}

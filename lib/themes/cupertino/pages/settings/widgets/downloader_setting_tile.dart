import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_downloader_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoDownloaderSettingTile extends StatelessWidget {
  const CupertinoDownloaderSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);
    final isZh = Localizations.localeOf(context).languageCode == 'zh';

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.arrow_down_circle, color: iconColor),
      title: Text(isZh ? '下载器' : 'Downloader'),
      subtitle: Text(isZh ? '下载任务、设置' : 'Download tasks & settings'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoDownloaderSettingsPage(),
          ),
        );
      },
    );
  }
}

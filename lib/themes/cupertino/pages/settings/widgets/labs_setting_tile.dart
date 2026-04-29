import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_labs_settings_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoLabsSettingTile extends StatelessWidget {
  const CupertinoLabsSettingTile({super.key});

  @override
  Widget build(BuildContext context) {
    final Color iconColor = resolveSettingsIconColor(context);
    final Color tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(CupertinoIcons.lab_flask, color: iconColor),
      title: const Text('实验室'),
      subtitle: const Text('实验性功能与开关'),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoLabsSettingsPage(),
          ),
        );
      },
    );
  }
}

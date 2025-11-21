import 'package:flutter/cupertino.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/cupertino_about_page.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:package_info_plus/package_info_plus.dart';

class CupertinoAboutSettingTile extends StatefulWidget {
  const CupertinoAboutSettingTile({super.key});

  @override
  State<CupertinoAboutSettingTile> createState() =>
      _CupertinoAboutSettingTileState();
}

class _CupertinoAboutSettingTileState
    extends State<CupertinoAboutSettingTile> {
  String _versionLabel = '加载中…';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _versionLabel = '当前版本：${info.version}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _versionLabel = '版本信息获取失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.info_circle,
        color: resolveSettingsIconColor(context),
      ),
      title: const Text('关于'),
      subtitle: Text(_versionLabel),
      backgroundColor: tileColor,
      showChevron: true,
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => const CupertinoAboutPage(),
          ),
        );
      },
    );
  }
}

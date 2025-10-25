import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../pages/cupertino_about_page.dart';

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
    return AdaptiveListTile(
      leading: const Icon(CupertinoIcons.info_circle),
      title: const Text('关于'),
      subtitle: Text(_versionLabel),
      trailing: Icon(
        PlatformInfo.isIOS
            ? CupertinoIcons.chevron_forward
            : CupertinoIcons.forward,
        color: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey2,
          context,
        ),
      ),
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

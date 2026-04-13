import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
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
  String? _version;
  bool _loadFailed = false;

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
        _version = info.version;
        _loadFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadFailed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = resolveSettingsTileBackground(context);
    final subtitle = _loadFailed
        ? context.l10n.versionLoadFailed
        : (_version == null
            ? context.l10n.loading
            : context.l10n.currentVersion(_version!));

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.info_circle,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(context.l10n.about),
      subtitle: Text(subtitle),
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

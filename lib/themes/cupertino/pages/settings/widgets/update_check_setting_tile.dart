import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';

class CupertinoUpdateCheckSettingTile extends StatefulWidget {
  const CupertinoUpdateCheckSettingTile({super.key});

  @override
  State<CupertinoUpdateCheckSettingTile> createState() =>
      _CupertinoUpdateCheckSettingTileState();
}

class _CupertinoUpdateCheckSettingTileState
    extends State<CupertinoUpdateCheckSettingTile> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final enabled = await UpdateService.isAutoCheckEnabled();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool enabled) async {
    if (_enabled == enabled) return;
    setState(() {
      _enabled = enabled;
    });
    await UpdateService.setAutoCheckEnabled(enabled);
  }

  @override
  Widget build(BuildContext context) {
    final tileColor = resolveSettingsTileBackground(context);

    return CupertinoSettingsTile(
      leading: Icon(
        CupertinoIcons.arrow_clockwise_circle,
        color: resolveSettingsIconColor(context),
      ),
      title: Text(context.l10n.aboutAutoCheckUpdates),
      subtitle: Text(context.l10n.aboutManualOnlyWhenDisabled),
      trailing: AdaptiveSwitch(
        value: _enabled,
        onChanged: _loading ? null : _setEnabled,
      ),
      onTap: _loading ? null : () => _setEnabled(!_enabled),
      backgroundColor: tileColor,
    );
  }
}

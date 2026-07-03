import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';

class AutoUpdateSettingTile extends StatefulWidget {
  const AutoUpdateSettingTile({super.key});

  @override
  State<AutoUpdateSettingTile> createState() => _AutoUpdateSettingTileState();
}

class _AutoUpdateSettingTileState extends State<AutoUpdateSettingTile> {
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
    return AdaptiveSettingsTile.toggle(
      title: context.l10n.aboutAutoCheckUpdates,
      subtitle: context.l10n.aboutManualOnlyWhenDisabled,
      icon: Ionicons.cloud_outline,
      cupertinoIcon: cupertino.CupertinoIcons.arrow_clockwise_circle,
      enabled: !_loading,
      value: _enabled,
      onChanged: _setEnabled,
    );
  }
}

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';

class LabsSettingsContent extends StatelessWidget {
  const LabsSettingsContent({
    super.key,
    required this.onOpenWebDavQuickSettings,
  });

  final VoidCallback onOpenWebDavQuickSettings;

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          dividerIndent: 56,
          children: [
            AdaptiveSettingsTile.button(
              title: _text(
                context,
                'WebDAV 快捷设置',
                'WebDAV 快捷設定',
                'WebDAV Quick Settings',
              ),
              subtitle: _text(
                context,
                '配置底部 WebDAV 快捷 Tab，快速访问 WebDAV 服务器',
                '配置底部 WebDAV 快捷 Tab，快速訪問 WebDAV 伺服器',
                'Configure the bottom WebDAV shortcut tab.',
              ),
              icon: Ionicons.cloud_outline,
              phoneIcon: cupertino.CupertinoIcons.cloud,
              trailingIcon: Ionicons.chevron_forward,
              onTap: onOpenWebDavQuickSettings,
            ),
          ],
        ),
      ],
    );
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final localeName = context.l10n.localeName;
    if (localeName.startsWith('zh_Hant')) {
      return traditional;
    }
    if (localeName.startsWith('en')) {
      return english;
    }
    return simplified;
  }
}

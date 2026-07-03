import 'package:flutter/material.dart';
import 'package:nipaplay/settings/pages/labs_settings_content.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/webdav_quick_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';

class LabsPage extends StatelessWidget {
  const LabsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return LabsSettingsContent(
      onOpenWebDavQuickSettings: () {
        NipaplayWindow.show(
          context: context,
          child: const NipaplayWindowScaffold(
            maxWidth: 600,
            maxHeightFactor: 0.9,
            child: WebDAVQuickSettingsPage(),
          ),
        );
      },
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/labs_settings_content.dart';
import 'package:nipaplay/themes/cupertino/pages/settings/pages/webdav_quick_settings_page.dart';

class CupertinoLabsSettingsPage extends StatelessWidget {
  const CupertinoLabsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: LabsSettingsContent(
        onOpenWebDavQuickSettings: () {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (_) => const CupertinoWebDAVQuickSettingsPage(),
            ),
          );
        },
      ),
    );
  }
}

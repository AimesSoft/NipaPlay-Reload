import 'package:flutter/cupertino.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/webdav_quick_settings_content.dart';

class CupertinoWebDAVQuickSettingsPage extends StatelessWidget {
  const CupertinoWebDAVQuickSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.cupertino,
      child: WebDAVQuickSettingsContent(),
    );
  }
}

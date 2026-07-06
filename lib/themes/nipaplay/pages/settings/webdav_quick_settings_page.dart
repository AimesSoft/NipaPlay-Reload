import 'package:flutter/material.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/pages/webdav_quick_settings_content.dart';

/// WebDAV 快捷访问设置页面
class WebDAVQuickSettingsPage extends StatelessWidget {
  const WebDAVQuickSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.nipaplay,
      child: WebDAVQuickSettingsContent(),
    );
  }
}

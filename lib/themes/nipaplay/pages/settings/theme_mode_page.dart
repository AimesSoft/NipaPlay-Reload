import 'package:flutter/material.dart';
import 'package:nipaplay/settings/pages/appearance_settings_content.dart';
import 'package:nipaplay/utils/theme_notifier.dart';

class ThemeModePage extends StatelessWidget {
  const ThemeModePage({
    super.key,
    required this.themeNotifier,
  });

  final ThemeNotifier themeNotifier;

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: AppearanceSettingsContent(),
    );
  }
}

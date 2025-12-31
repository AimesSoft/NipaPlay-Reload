import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

class MaterialSettingsHomePage extends StatelessWidget {
  const MaterialSettingsHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _sectionTitle(context, '外观'),
        _themeModeTile(
          context,
          title: '跟随系统',
          mode: ThemeMode.system,
          groupValue: themeNotifier.themeMode,
          onChanged: (mode) => themeNotifier.themeMode = mode,
        ),
        _themeModeTile(
          context,
          title: '浅色',
          mode: ThemeMode.light,
          groupValue: themeNotifier.themeMode,
          onChanged: (mode) => themeNotifier.themeMode = mode,
        ),
        _themeModeTile(
          context,
          title: '深色',
          mode: ThemeMode.dark,
          groupValue: themeNotifier.themeMode,
          onChanged: (mode) => themeNotifier.themeMode = mode,
        ),
        const Divider(height: 24),
        _sectionTitle(context, '控件主题'),
        _themeSelectorCard(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _themeModeTile(
    BuildContext context, {
    required String title,
    required ThemeMode mode,
    required ThemeMode groupValue,
    required ValueChanged<ThemeMode> onChanged,
  }) {
    return RadioListTile<ThemeMode>(
      value: mode,
      groupValue: groupValue,
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
      title: Text(title),
    );
  }

  Widget _themeSelectorCard(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, _) {
        final themes = uiThemeProvider.availableThemes;
        final currentId = uiThemeProvider.currentThemeDescriptor.id;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Card(
            child: Column(
              children: [
                for (final theme in themes)
                  RadioListTile<String>(
                    value: theme.id,
                    groupValue: currentId,
                    onChanged: (value) {
                      if (value == null) return;
                      if (value == currentId) return;
                      _confirmAndApplyTheme(context, uiThemeProvider, theme);
                    },
                    title: Text(theme.displayName),
                    subtitle: Text(theme.preview.title),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndApplyTheme(
    BuildContext context,
    UIThemeProvider provider,
    ThemeDescriptor theme,
  ) async {
    final bool? shouldRestart = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换主题'),
        content: Text('切换到 ${theme.displayName} 主题需要重启应用才能完全生效。是否立即重启？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('重启'),
          ),
        ],
      ),
    );

    if (shouldRestart != true) return;

    await provider.setTheme(theme);
    if (!context.mounted) return;
    _exitApplication(context);
  }

  void _exitApplication(BuildContext context) {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请手动刷新页面以应用新主题')),
      );
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      exit(0);
    }

    windowManager.close();
  }
}


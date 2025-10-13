import 'package:flutter/material.dart' as material;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';

class FluentAppearancePage extends StatelessWidget {
  const FluentAppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UIThemeProvider>(
      builder: (context, uiThemeProvider, child) {
        final material.ThemeMode mode = uiThemeProvider.fluentThemeMode;

        return ScaffoldPage(
          header: const PageHeader(
            title: Text('外观模式'),
          ),
          content: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '界面外观',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '选择 Fluent 界面使用浅色、深色，或跟随系统切换。',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ComboBox<material.ThemeMode>(
                            value: mode,
                            items: const [
                              ComboBoxItem<material.ThemeMode>(
                                value: material.ThemeMode.light,
                                child: Text('浅色'),
                              ),
                              ComboBoxItem<material.ThemeMode>(
                                value: material.ThemeMode.dark,
                                child: Text('深色'),
                              ),
                              ComboBoxItem<material.ThemeMode>(
                                value: material.ThemeMode.system,
                                child: Text('跟随系统'),
                              ),
                            ],
                            onChanged: (targetMode) {
                              if (targetMode != null) {
                                uiThemeProvider.setFluentThemeMode(targetMode);
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _appearanceDescription(mode),
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        const SizedBox(height: 16),
                        _buildPreview(mode, context),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                InfoBar(
                  title: const Text('提示'),
                  content: const Text('外观模式仅对 Fluent 主题生效，切换后会即时应用。'),
                  severity: InfoBarSeverity.info,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _appearanceDescription(material.ThemeMode mode) {
    switch (mode) {
      case material.ThemeMode.light:
        return '界面保持明亮色彩，适合光线充足的环境。';
      case material.ThemeMode.dark:
        return '界面使用深色配色，适合夜间或低亮度环境。';
      case material.ThemeMode.system:
        return '界面根据系统设置自动切换浅色或深色模式。';
    }
  }

  Widget _buildPreview(material.ThemeMode mode, BuildContext context) {
    final bool isDark = mode == material.ThemeMode.dark;
    final bool useSystem = mode == material.ThemeMode.system;
    final theme = FluentTheme.of(context);
    final bool effectiveDark = useSystem
        ? theme.brightness == material.Brightness.dark
        : isDark;

    final Color backgroundColor = effectiveDark
        ? const Color(0xFF202020)
        : const Color(0xFFF3F3F3);
    final Color foregroundColor = effectiveDark
        ? theme.accentColor
        : const Color(0xFF106EBE);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluentTheme.of(context).inactiveColor.withOpacity(0.2),
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                FluentIcons.brightness,
                color: foregroundColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                mode == material.ThemeMode.system ? '跟随系统' : (isDark ? '深色模式' : '浅色模式'),
                style: FluentTheme.of(context).typography.subtitle,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '示例窗口标题',
            style: FluentTheme.of(context).typography.bodyStrong?.copyWith(
                  color: foregroundColor,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            '内容区域将根据外观模式切换配色。',
            style: theme.typography.body?.copyWith(
                  color: effectiveDark
                      ? material.Colors.white70
                      : theme.resources.textFillColorPrimary,
                ),
          ),
        ],
      ),
    );
  }
}

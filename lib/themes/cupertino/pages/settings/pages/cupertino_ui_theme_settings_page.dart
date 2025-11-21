import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/theme_descriptor.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoUIThemeSettingsPage extends StatefulWidget {
  const CupertinoUIThemeSettingsPage({super.key});

  @override
  State<CupertinoUIThemeSettingsPage> createState() =>
      _CupertinoUIThemeSettingsPageState();
}

class _CupertinoUIThemeSettingsPageState
    extends State<CupertinoUIThemeSettingsPage> {
  late ThemeDescriptor _selectedTheme;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<UIThemeProvider>(context, listen: false);
    _selectedTheme = provider.currentThemeDescriptor;
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);
    final provider = context.watch<UIThemeProvider>();

    final double topPadding = MediaQuery.of(context).padding.top + 64;

    final List<ThemeDescriptor> availableThemes =
        provider.availableThemes.where((theme) {
      if (globals.isPhone) {
        return true;
      }
      return theme.supportsDesktop;
    }).toList();

    if (availableThemes.isNotEmpty &&
        !availableThemes.any((theme) => theme.id == _selectedTheme.id)) {
      _selectedTheme = availableThemes.first;
    }

    return AdaptiveScaffold(
      appBar: const AdaptiveAppBar(
        title: '主题（实验性）',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
            children: [
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                addDividers: true,
                dividerIndent: 16,
                children: availableThemes.map((theme) {
                  final tileColor = resolveSettingsTileBackground(context);
                  return CupertinoSettingsTile(
                    leading: Icon(
                      theme.preview.icon,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(theme.preview.title),
                    subtitle: Text(_themeSubtitle(theme)),
                    backgroundColor: tileColor,
                    selected: _selectedTheme.id == theme.id,
                    onTap: () => _handleThemeSelection(theme, provider),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '提示：切换主题后需要重新启动应用才能完全生效。',
                  style:
                      CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                            fontSize: 13,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey,
                              context,
                            ),
                            letterSpacing: 0.2,
                          ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _themeSubtitle(ThemeDescriptor descriptor) {
    return descriptor.preview.highlights.join('、');
  }

  Future<void> _handleThemeSelection(
    ThemeDescriptor theme,
    UIThemeProvider provider,
  ) async {
    if (_selectedTheme.id == theme.id) return;
    setState(() {
      _selectedTheme = theme;
    });

    bool confirmed = false;
    await AdaptiveAlertDialog.show(
      context: context,
      title: '主题切换提示',
      message: '切换到 ${theme.displayName} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？',
      actions: [
        AlertAction(
          title: '取消',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: '重启应用',
          style: AlertActionStyle.primary,
          onPressed: () {
            confirmed = true;
          },
        ),
      ],
    );

    if (confirmed) {
      await provider.setTheme(theme);
      if (!mounted) return;
      _exitApplication();
    } else {
      if (!mounted) return;
      setState(() {
        _selectedTheme = provider.currentThemeDescriptor;
      });
    }
  }

  void _exitApplication() {
    if (kIsWeb) {
      AdaptiveSnackBar.show(
        context,
        message: '请手动刷新页面以应用新主题',
        type: AdaptiveSnackBarType.info,
      );
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      exit(0);
    } else {
      windowManager.close();
    }
  }
}

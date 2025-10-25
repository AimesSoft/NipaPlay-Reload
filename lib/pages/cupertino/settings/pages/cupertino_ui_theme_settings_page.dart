import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class CupertinoUIThemeSettingsPage extends StatefulWidget {
  const CupertinoUIThemeSettingsPage({super.key});

  @override
  State<CupertinoUIThemeSettingsPage> createState() =>
      _CupertinoUIThemeSettingsPageState();
}

class _CupertinoUIThemeSettingsPageState
    extends State<CupertinoUIThemeSettingsPage> {
  late UIThemeType _selectedTheme;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<UIThemeProvider>(context, listen: false);
    _selectedTheme = provider.currentTheme;
    if (PlatformInfo.isIOS && _selectedTheme == UIThemeType.fluentUI) {
      _selectedTheme = globals.isPhone ? UIThemeType.cupertino : UIThemeType.nipaplay;
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final provider = context.watch<UIThemeProvider>();

    final double topPadding = MediaQuery.of(context).padding.top + 48;

    final List<UIThemeType> availableThemes = UIThemeType.values.where((theme) {
      if (theme == UIThemeType.cupertino) {
        return globals.isPhone;
      }
      if (PlatformInfo.isIOS && theme == UIThemeType.fluentUI) {
        return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    if (!availableThemes.contains(_selectedTheme) && availableThemes.isNotEmpty) {
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
              AdaptiveFormSection.insetGrouped(
                children: availableThemes.map((theme) {
                  return AdaptiveListTile(
                    leading: Icon(_leadingIcon(theme)),
                    title: Text(_themeTitle(theme)),
                    subtitle: Text(_themeSubtitle(theme)),
                    trailing: AdaptiveRadio<UIThemeType>(
                      value: theme,
                      groupValue: _selectedTheme,
                      onChanged: (value) {
                        if (value != null) {
                          _handleThemeSelection(value, provider);
                        }
                      },
                    ),
                    onTap: () => _handleThemeSelection(theme, provider),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '提示：切换主题后需要重新启动应用才能完全生效。',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .textStyle
                      .copyWith(
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

  IconData _leadingIcon(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return CupertinoIcons.sparkles;
      case UIThemeType.fluentUI:
        return CupertinoIcons.rectangle_on_rectangle_angled;
      case UIThemeType.cupertino:
        return CupertinoIcons.device_phone_portrait;
    }
  }

  String _themeTitle(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return 'NipaPlay 主题';
      case UIThemeType.fluentUI:
        return 'Fluent UI 主题';
      case UIThemeType.cupertino:
        return 'Cupertino 主题';
    }
  }

  String _themeSubtitle(UIThemeType theme) {
    switch (theme) {
      case UIThemeType.nipaplay:
        return '磨砂玻璃风格，适用于桌面端。';
      case UIThemeType.fluentUI:
        return '微软 Fluent 设计语言，桌面体验最佳。';
      case UIThemeType.cupertino:
        return '贴近 iOS 的原生体验，适合移动端。';
    }
  }

  Future<void> _handleThemeSelection(
    UIThemeType theme,
    UIThemeProvider provider,
  ) async {
    if (_selectedTheme == theme) return;
    setState(() {
      _selectedTheme = theme;
    });

    bool confirmed = false;
    await AdaptiveAlertDialog.show(
      context: context,
      title: '主题切换提示',
      message:
          '切换到 ${provider.getThemeName(theme)} 主题需要重启应用才能完全生效。\n\n是否要立即重启应用？',
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
        _selectedTheme = provider.currentTheme;
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

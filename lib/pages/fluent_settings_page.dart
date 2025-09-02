import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_account_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_ui_theme_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_general_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_player_settings_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_about_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_developer_options_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_remote_access_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_remote_media_library_page.dart';
import 'package:nipaplay/pages/fluent_settings/fluent_shortcuts_page.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/pages/fluent_settings/fluent_watch_history_page.dart';

class FluentSettingsPage extends StatefulWidget {
  const FluentSettingsPage({super.key});

  @override
  State<FluentSettingsPage> createState() => _FluentSettingsPageState();
}

class _FluentSettingsPageState extends State<FluentSettingsPage> {
  int _selectedIndex = 0;

  final List<Widget> _settingsPages = [
    const FluentAccountPage(),
    const FluentUIThemePage(),
    const FluentGeneralPage(),
    const FluentWatchHistoryPage(),
    const FluentPlayerSettingsPage(),
    if (globals.isDesktop) const FluentShortcutsPage(),
    const FluentRemoteAccessPage(),
    const FluentRemoteMediaLibraryPage(),
    const FluentDeveloperOptionsPage(),
    const FluentAboutPage(),
  ];

  final List<String> _settingsTitles = [
    '账号',
    '主题（实验性）',
    '通用',
    '观看记录',
    '播放器',
    if (globals.isDesktop) '快捷键',
    '远程访问',
    '远程媒体库',
    '开发者选项',
    '关于',
  ];

  final List<IconData> _settingsIcons = [
    FluentIcons.contact,
    FluentIcons.color,
    FluentIcons.settings,
    FluentIcons.history,
    FluentIcons.play,
    if (globals.isDesktop) FluentIcons.key_phrase_extraction,
    FluentIcons.remote,
    FluentIcons.folder_open,
    FluentIcons.developer_tools,
    FluentIcons.info,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 左侧导航列表
        SizedBox(
          width: 250,
          child: Container(
            decoration: BoxDecoration(
              color: FluentTheme.of(context).navigationPaneTheme.backgroundColor,
              border: Border(
                right: BorderSide(
                  color: FluentTheme.of(context).inactiveColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _settingsPages.length,
              itemBuilder: (context, index) {
                final isSelected = index == _selectedIndex;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: isSelected 
                        ? FluentTheme.of(context).accentColor.withOpacity(0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ListTile(
                    onPressed: () {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    leading: Icon(
                      _settingsIcons[index],
                      color: isSelected 
                          ? FluentTheme.of(context).accentColor
                          : FluentTheme.of(context).inactiveColor,
                    ),
                    title: Text(
                      _settingsTitles[index],
                      locale:Locale("zh","CN"),
style: TextStyle(
                        color: isSelected 
                            ? FluentTheme.of(context).accentColor
                            : null,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        // 右侧内容区域
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: FluentTheme.of(context).scaffoldBackgroundColor,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题栏
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: FluentTheme.of(context).inactiveColor.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                  ),
                  child: Text(
                    _settingsTitles[_selectedIndex],
                    style: FluentTheme.of(context).typography.title,
                  ),
                ),
                // 内容区域
                Expanded(
                  child: _selectedIndex < _settingsPages.length
                      ? _settingsPages[_selectedIndex]
                      : Container(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
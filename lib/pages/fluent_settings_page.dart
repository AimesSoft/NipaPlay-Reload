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

  final List<NavigationPaneItem> _settingsItems = [
    PaneItem(
      key: const ValueKey('account'),
      icon: const Icon(FluentIcons.contact),
      title: const Text('账号'),
      body: const FluentAccountPage(),
    ),
    PaneItem(
      key: const ValueKey('ui_theme'),
      icon: const Icon(FluentIcons.color),
      title: const Text('主题（实验性）'),
      body: const FluentUIThemePage(),
    ),
    PaneItem(
      key: const ValueKey('general'),
      icon: const Icon(FluentIcons.settings),
      title: const Text('通用'),
      body: const FluentGeneralPage(),
    ),
    PaneItem(
      key: const ValueKey('watch_history'),
      icon: const Icon(FluentIcons.history),
      title: const Text('观看记录'),
      body: const FluentWatchHistoryPage(),
    ),
    PaneItem(
      key: const ValueKey('player'),
      icon: const Icon(FluentIcons.play),
      title: const Text('播放器'),
      body: const FluentPlayerSettingsPage(),
    ),
    if (globals.isDesktop) PaneItem(
      key: const ValueKey('shortcuts'),
      icon: const Icon(FluentIcons.key_phrase_extraction),
      title: const Text('快捷键'),
      body: const FluentShortcutsPage(),
    ),
    PaneItem(
      key: const ValueKey('remote_access'),
      icon: const Icon(FluentIcons.remote),
      title: const Text('远程访问'),
      body: const FluentRemoteAccessPage(),
    ),
    PaneItem(
      key: const ValueKey('remote_media'),
      icon: const Icon(FluentIcons.folder_open),
      title: const Text('远程媒体库'),
      body: const FluentRemoteMediaLibraryPage(),
    ),
    PaneItem(
      key: const ValueKey('developer'),
      icon: const Icon(FluentIcons.developer_tools),
      title: const Text('开发者选项'),
      body: const FluentDeveloperOptionsPage(),
    ),
    PaneItem(
      key: const ValueKey('about'),
      icon: const Icon(FluentIcons.info),
      title: const Text('关于'),
      body: const FluentAboutPage(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationView(
      appBar: const NavigationAppBar(
        title: Text('设置'),
        automaticallyImplyLeading: false,
      ),
      pane: NavigationPane(
        selected: _selectedIndex,
        onChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        displayMode: PaneDisplayMode.open,
        items: _settingsItems,
      ),
    );
  }
}
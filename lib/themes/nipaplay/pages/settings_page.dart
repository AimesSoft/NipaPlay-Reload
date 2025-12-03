// settings_page.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/theme_mode_page.dart'; // 导入 ThemeModePage
import 'package:nipaplay/themes/nipaplay/pages/settings/general_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/developer_options_page.dart'; // 导入开发者选项页面
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/responsive_container.dart'; // 导入响应式容器
import 'package:nipaplay/themes/nipaplay/pages/settings/about_page.dart'; // 导入 AboutPage
import 'package:nipaplay/utils/globals.dart'
    as globals; // 导入包含 isDesktop 的全局变量文件
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/account_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/player_settings_page.dart'; // 导入播放器设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_media_library_page.dart'; // 导入远程媒体库设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_access_page.dart'; // 导入远程访问设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/ui_theme_page.dart'; // 导入UI主题设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/watch_history_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/storage_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/backup_restore_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/network_settings_page.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  // currentPage 状态现在用于桌面端的右侧面板
  // 也可以考虑给它一个初始值，这样桌面端一进来右侧不是空的
  Widget? currentPage; // 初始可以为 null
  late TabController _tabController;
  static const Locale _titleLocale = Locale("zh-Hans", "zh");
  static const TextStyle _titleTextStyle =
      TextStyle(color: Colors.white, fontWeight: FontWeight.bold);

  @override
  void initState() {
    super.initState();
    // 初始化TabController
    _tabController = TabController(length: 1, vsync: this);

    // 可以在这里为桌面端和平板设备设置一个默认显示的页面
    if (globals.isDesktop || globals.isTablet) {
      currentPage = const AboutPage(); // 例如默认显示 AboutPage
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // 封装导航或更新状态的逻辑
  void _handleItemTap(Widget pageToShow, String title) {
    List<Widget> settingsTabLabels() {
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(title,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ),
      ];
    }

    final List<Widget> pages = [pageToShow];
    if (globals.isDesktop || globals.isTablet) {
      // 桌面端和平板设备：更新状态，改变右侧面板内容
      setState(() {
        currentPage = pageToShow;
      });
    } else {
      // 移动端：导航到新页面
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => CustomScaffold(
                  pages: pages,
                  tabPage: settingsTabLabels(),
                  pageIsHome: false,
                  tabController: _tabController,
                )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildSettingEntries(context);
    // ResponsiveContainer 会根据 isDesktop 决定是否显示 currentPage
    return ResponsiveContainer(
      currentPage: currentPage ?? Container(), // 将当前页面状态传递给 ResponsiveContainer
      // child 是 ListView，始终显示
      child: ListView.separated(
        itemCount: entries.length,
        itemBuilder: (context, index) => _buildSettingTile(entries[index]),
        separatorBuilder: (context, index) => Divider(
          height: 1,
          color: Colors.white.withOpacity(0.08),
        ),
      ),
    );
  }

  List<_SettingEntry> _buildSettingEntries(BuildContext context) {
    final themeNotifier = context.read<ThemeNotifier>();
    final entries = <_SettingEntry>[
      _SettingEntry(
        title: "账号",
        icon: Ionicons.person_outline,
        onTap: () => _handleItemTap(const AccountPage(), "账号设置"),
      ),
      _SettingEntry(
        title: "外观",
        icon: Ionicons.color_palette_outline,
        onTap: () => _handleItemTap(
            ThemeModePage(themeNotifier: themeNotifier), "外观设置"),
      ),
    ];

    if (!Platform.isAndroid) {
      entries.add(
        _SettingEntry(
          title: "主题（实验性）",
          icon: Ionicons.color_wand_outline,
          onTap: () => _handleItemTap(const UIThemePage(), "主题设置"),
        ),
      );
    }

    entries.addAll([
      _SettingEntry(
        title: "通用",
        icon: Ionicons.settings_outline,
        onTap: () => _handleItemTap(const GeneralPage(), "通用设置"),
      ),
      _SettingEntry(
        title: "存储",
        icon: Ionicons.folder_open_outline,
        onTap: () => _handleItemTap(const StoragePage(), "存储设置"),
      ),
      _SettingEntry(
        title: "网络",
        icon: Ionicons.wifi_outline,
        onTap: () => _handleItemTap(const NetworkSettingsPage(), "网络设置"),
      ),
      _SettingEntry(
        title: "观看记录",
        icon: Ionicons.time_outline,
        onTap: () => _handleItemTap(const WatchHistoryPage(), "观看记录"),
      ),
    ]);

    if (!globals.isPhone) {
      entries.add(
        _SettingEntry(
          title: "备份与恢复",
          icon: Ionicons.cloud_upload_outline,
          onTap: () => _handleItemTap(const BackupRestorePage(), "备份与恢复"),
        ),
      );
    }

    entries.add(
      _SettingEntry(
        title: "播放器",
        icon: Ionicons.play_circle_outline,
        onTap: () => _handleItemTap(const PlayerSettingsPage(), "播放器设置"),
      ),
    );

    if (!globals.isPhone) {
      entries.addAll([
        _SettingEntry(
          title: "快捷键",
          icon: Ionicons.key_outline,
          onTap: () => _handleItemTap(const ShortcutsSettingsPage(), "快捷键设置"),
        ),
        _SettingEntry(
          title: "远程访问（实验性）",
          icon: Ionicons.link_outline,
          onTap: () => _handleItemTap(const RemoteAccessPage(), "远程访问"),
        ),
      ]);
    }

    entries.addAll([
      _SettingEntry(
        title: "远程媒体库",
        icon: Ionicons.library_outline,
        onTap: () =>
            _handleItemTap(const RemoteMediaLibraryPage(), "远程媒体库"),
      ),
      _SettingEntry(
        title: "开发者选项",
        icon: Ionicons.code_slash_outline,
        onTap: () => _handleItemTap(const DeveloperOptionsPage(), "开发者选项"),
      ),
      _SettingEntry(
        title: "关于",
        icon: Ionicons.information_circle_outline,
        onTap: () => _handleItemTap(const AboutPage(), "关于"),
      ),
    ]);

    return entries;
  }

  Widget _buildSettingTile(_SettingEntry entry) {
    return ListTile(
      leading: Icon(entry.icon, color: Colors.white),
      title: Text(entry.title, locale: _titleLocale, style: _titleTextStyle),
      trailing:
          const Icon(Ionicons.chevron_forward_outline, color: Colors.white),
      onTap: entry.onTap,
    );
  }
}

class _SettingEntry {
  const _SettingEntry({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final VoidCallback onTap;
}

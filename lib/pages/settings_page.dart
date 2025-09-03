// settings_page.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/pages/settings/theme_mode_page.dart'; // 导入 ThemeModePage
import 'package:nipaplay/pages/settings/general_page.dart';
import 'package:nipaplay/pages/settings/developer_options_page.dart'; // 导入开发者选项页面
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/widgets/nipaplay_theme/custom_scaffold.dart';
import 'package:nipaplay/widgets/nipaplay_theme/responsive_container.dart'; // 导入响应式容器
import 'package:nipaplay/pages/settings/about_page.dart'; // 导入 AboutPage
import 'package:nipaplay/utils/globals.dart'
    as globals; // 导入包含 isDesktop 的全局变量文件
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/pages/settings/account_page.dart';
import 'package:nipaplay/pages/settings/player_settings_page.dart'; // 导入播放器设置页面
import 'package:nipaplay/pages/settings/remote_media_library_page.dart'; // 导入远程媒体库设置页面
import 'package:nipaplay/pages/settings/remote_access_page.dart'; // 导入远程访问设置页面
import 'package:nipaplay/pages/settings/ui_theme_page.dart'; // 导入UI主题设置页面
import 'package:nipaplay/pages/settings/watch_history_page.dart';
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
    // ResponsiveContainer 会根据 isDesktop 决定是否显示 currentPage
    return ResponsiveContainer(
      currentPage: currentPage ?? Container(), // 将当前页面状态传递给 ResponsiveContainer
      // child 是 ListView，始终显示
      child: ListView(
        children: [
          ListTile(
            title: const Text("账号",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const AccountPage(), "账号设置");
            },
          ),
          ListTile(
            title: const Text("外观",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              final themeNotifier =
                  context.read<ThemeNotifier>(); // 获取 Notifier
              // 调用通用处理函数
              _handleItemTap(
                  ThemeModePage(themeNotifier: themeNotifier), // 目标页面
                  "外观设置" // 移动端 AppBar 标题
                  );
            },
          ),
          if (!globals.isPhone)
            ListTile(
              title: const Text("主题（实验性）",
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: const Icon(Ionicons.chevron_forward_outline,
                  color: Colors.white),
              onTap: () {
                _handleItemTap(const UIThemePage(), "主题设置");
              },
            ),
          ListTile(
            title: const Text("通用",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const GeneralPage(), "通用设置");
            },
          ),
          ListTile(
            title: const Text("观看记录",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const WatchHistoryPage(), "观看记录");
            },
          ),
          ListTile(
            title: const Text("播放器",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const PlayerSettingsPage(), "播放器设置");
            },
          ),
          if (!globals.isPhone)
            ListTile(
              title: const Text("快捷键",
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: const Icon(Ionicons.chevron_forward_outline,
                  color: Colors.white),
              onTap: () {
                _handleItemTap(const ShortcutsSettingsPage(), "快捷键设置");
              },
            ),
          if (!globals.isPhone)
            ListTile(
              title: const Text("远程访问（实验性）",
                  locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
              trailing: const Icon(Ionicons.chevron_forward_outline,
                  color: Colors.white),
              onTap: () {
                _handleItemTap(const RemoteAccessPage(), "远程访问");
              },
            ),
          ListTile(
            title: const Text("远程媒体库",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const RemoteMediaLibraryPage(), "远程媒体库");
            },
          ),
          // 开发者选项
          ListTile(
            title: const Text("开发者选项",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              _handleItemTap(const DeveloperOptionsPage(), "开发者选项");
            },
          ),
          ListTile(
            title: const Text("关于",
                locale:Locale("zh-Hans","zh"),
style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
            trailing: const Icon(Ionicons.chevron_forward_outline,
                color: Colors.white),
            onTap: () {
              // 调用通用处理函数
              _handleItemTap(
                  const AboutPage(), // 目标页面
                  "关于" // 移动端 AppBar 标题
                  );
            },
          ),
        ],
      ),
    );
  }
}

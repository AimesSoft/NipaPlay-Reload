// settings_page.dart
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/theme_mode_page.dart'; // 导入 ThemeModePage
import 'package:nipaplay/themes/nipaplay/pages/settings/general_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/developer_options_page.dart'; // 导入开发者选项页面
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/responsive_container.dart'; // 导入响应式容器
import 'package:nipaplay/themes/nipaplay/pages/settings/about_page.dart'; // 导入 AboutPage
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/utils/globals.dart'
    as globals; // 导入包含 isDesktop 的全局变量文件
import 'package:nipaplay/pages/shortcuts_settings_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/player_settings_page.dart'; // 导入播放器设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_media_library_page.dart'; // 导入远程媒体库设置页面
import 'package:nipaplay/themes/nipaplay/pages/settings/remote_access_page.dart'; // 导入远程访问设置页面
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/storage_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/backup_restore_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/network_settings_page.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  static const String entryRemoteAccess = 'remote_access';
  final String? initialEntryId;

  const SettingsPage({super.key, this.initialEntryId});

  static Future<void> showWindow(
    BuildContext context, {
    String? initialEntryId,
  }) {
    final appearanceSettings =
        Provider.of<AppearanceSettingsProvider>(context, listen: false);
    final enableAnimation = appearanceSettings.enablePageAnimation;
    final screenSize = MediaQuery.of(context).size;
    final isCompactLayout = screenSize.width < 900;
    final maxWidth = isCompactLayout ? screenSize.width * 0.95 : 980.0;
    final maxHeightFactor = isCompactLayout ? 0.9 : 0.85;

    return NipaplayWindow.show(
      context: context,
      enableAnimation: enableAnimation,
      child: NipaplayWindowScaffold(
        maxWidth: maxWidth,
        maxHeightFactor: maxHeightFactor,
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Builder(
              builder: (innerContext) {
                final titleStyle = Theme.of(innerContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold);
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    NipaplayWindowPositionProvider.of(innerContext)
                        ?.onMove(details.delta);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      '设置',
                      locale: const Locale("zh-Hans", "zh"),
                      style: titleStyle,
                    ),
                  ),
                );
              },
            ),
            Expanded(child: SettingsPage(initialEntryId: initialEntryId)),
          ],
        ),
      ),
    );
  }

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
  static const Color _selectedColor = Color(0xFFFF2E55);
  static const String _entryAppearance = 'appearance';
  static const String _entryGeneral = 'general';
  static const String _entryStorage = 'storage';
  static const String _entryNetwork = 'network';
  static const String _entryBackupRestore = 'backup_restore';
  static const String _entryPlayer = 'player';
  static const String _entryShortcuts = 'shortcuts';
  static const String _entryRemoteMediaLibrary = 'remote_media_library';
  static const String _entryDeveloperOptions = 'developer_options';
  static const String _entryAbout = 'about';
  String? _selectedEntryId;

  @override
  void initState() {
    super.initState();
    // 初始化TabController
    _tabController = TabController(length: 1, vsync: this);

    // 可以在这里为桌面端和平板设备设置一个默认显示的页面
    if (globals.isDesktop || globals.isTablet) {
      currentPage = const AboutPage(); // 例如默认显示 AboutPage
      _selectedEntryId = _entryAbout;
    }

    _applyInitialEntry();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _applyInitialEntry() {
    final entryId = widget.initialEntryId;
    if (entryId == null) return;
    final entry = _findEntryById(entryId);
    if (entry == null) return;

    if (globals.isDesktop || globals.isTablet) {
      currentPage = entry.page;
      _selectedEntryId = entry.id;
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _handleItemTap(entry.id, entry.page, entry.pageTitle);
      });
    }
  }

  _SettingEntry? _findEntryById(String entryId) {
    final entries = _buildSettingEntries(context);
    for (final entry in entries) {
      if (entry.id == entryId) {
        return entry;
      }
    }
    return null;
  }

  // 封装导航或更新状态的逻辑
  void _handleItemTap(String entryId, Widget pageToShow, String title) {
    List<Widget> settingsTabLabels() {
      final colorScheme = Theme.of(context).colorScheme;
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(title,
              locale: _titleLocale,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface)),
        ),
      ];
    }

    final List<Widget> pages = [pageToShow];
    if (globals.isDesktop || globals.isTablet) {
      // 桌面端和平板设备：更新状态，改变右侧面板内容
      setState(() {
        currentPage = pageToShow;
        _selectedEntryId = entryId;
      });
    } else {
      setState(() {
        _selectedEntryId = entryId;
      });
      // 移动端：导航到新页面
      Navigator.push(
        context,
        MaterialPageRoute(
            builder: (context) => Selector<VideoPlayerState, bool>(
                  selector: (context, videoState) =>
                      videoState.shouldShowAppBar(),
                  builder: (context, shouldShowAppBar, child) {
                    return SettingsNoRippleTheme(
                      child: CustomScaffold(
                        pages: pages,
                        tabPage: settingsTabLabels(),
                        pageIsHome: false,
                        shouldShowAppBar: shouldShowAppBar,
                        tabController: _tabController,
                      ),
                    );
                  },
                )),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildSettingEntries(context);
    final colorScheme = Theme.of(context).colorScheme;
    // ResponsiveContainer 会根据 isDesktop 决定是否显示 currentPage
    return SettingsNoRippleTheme(
      child: ResponsiveContainer(
        currentPage: currentPage ?? Container(), // 将当前页面状态传递给 ResponsiveContainer
        // child 是 ListView，始终显示
        child: ListView.separated(
          itemCount: entries.length,
          itemBuilder: (context, index) => _buildSettingTile(entries[index]),
          separatorBuilder: (context, index) => Divider(
            height: 1,
            color: colorScheme.onSurface.withOpacity(0.08),
          ),
        ),
      ),
    );
  }

  List<_SettingEntry> _buildSettingEntries(BuildContext context) {
    final themeNotifier = context.read<ThemeNotifier>();
    final entries = <_SettingEntry>[
      _SettingEntry(
        id: _entryAppearance,
        title: "外观",
        icon: Ionicons.color_palette_outline,
        pageTitle: "外观设置",
        page: ThemeModePage(themeNotifier: themeNotifier),
      ),
    ];

    entries.addAll([
      _SettingEntry(
        id: _entryGeneral,
        title: "通用",
        icon: Ionicons.settings_outline,
        pageTitle: "通用设置",
        page: const GeneralPage(),
      ),
      _SettingEntry(
        id: _entryStorage,
        title: "存储",
        icon: Ionicons.folder_open_outline,
        pageTitle: "存储设置",
        page: const StoragePage(),
      ),
      _SettingEntry(
        id: _entryNetwork,
        title: "网络",
        icon: Ionicons.wifi_outline,
        pageTitle: "网络设置",
        page: const NetworkSettingsPage(),
      ),
    ]);

    if (!globals.isPhone) {
      entries.add(
        _SettingEntry(
          id: _entryBackupRestore,
          title: "备份与恢复",
          icon: Ionicons.cloud_upload_outline,
          pageTitle: "备份与恢复",
          page: const BackupRestorePage(),
        ),
      );
    }

    entries.add(
      _SettingEntry(
        id: _entryPlayer,
        title: "播放器",
        icon: Ionicons.play_circle_outline,
        pageTitle: "播放器设置",
        page: const PlayerSettingsPage(),
      ),
    );

    if (!globals.isPhone) {
      entries.addAll([
        _SettingEntry(
          id: _entryShortcuts,
          title: "快捷键",
          icon: Ionicons.key_outline,
          pageTitle: "快捷键设置",
          page: const ShortcutsSettingsPage(),
        ),
        _SettingEntry(
          id: SettingsPage.entryRemoteAccess,
          title: "远程访问",
          icon: Ionicons.link_outline,
          pageTitle: "远程访问",
          page: const RemoteAccessPage(),
        ),
      ]);
    }

    entries.addAll([
      _SettingEntry(
        id: _entryRemoteMediaLibrary,
        title: "远程媒体库",
        icon: Ionicons.library_outline,
        pageTitle: "远程媒体库",
        page: const RemoteMediaLibraryPage(),
      ),
      _SettingEntry(
        id: _entryDeveloperOptions,
        title: "开发者选项",
        icon: Ionicons.code_slash_outline,
        pageTitle: "开发者选项",
        page: const DeveloperOptionsPage(),
      ),
      _SettingEntry(
        id: _entryAbout,
        title: "关于",
        icon: Ionicons.information_circle_outline,
        pageTitle: "关于",
        page: const AboutPage(),
      ),
    ]);

    return entries;
  }

  Widget _buildSettingTile(_SettingEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = entry.id == _selectedEntryId;
    final itemColor = isSelected ? _selectedColor : colorScheme.onSurface;
    return ListTile(
      leading: Icon(entry.icon, color: itemColor),
      title: Text(entry.title,
          locale: _titleLocale,
          style: TextStyle(
              color: itemColor, fontWeight: FontWeight.bold)),
      onTap: () => _handleItemTap(entry.id, entry.page, entry.pageTitle),
    );
  }
}

class _SettingEntry {
  const _SettingEntry({
    required this.id,
    required this.title,
    required this.icon,
    required this.pageTitle,
    required this.page,
  });

  final String id;
  final String title;
  final IconData icon;
  final String pageTitle;
  final Widget page;
}

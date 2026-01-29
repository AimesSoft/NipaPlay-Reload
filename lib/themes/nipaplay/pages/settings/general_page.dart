import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/services/desktop_exit_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define the key for SharedPreferences
const String defaultPageIndexKey = 'default_page_index';

class GeneralPage extends StatefulWidget {
  const GeneralPage({super.key});

  @override
  State<GeneralPage> createState() => _GeneralPageState();
}

class _GeneralPageState extends State<GeneralPage> {
  int _defaultPageIndex = 0;
  final GlobalKey _defaultPageDropdownKey = GlobalKey();
  DesktopExitBehavior _desktopExitBehavior = DesktopExitBehavior.askEveryTime;
  final GlobalKey _desktopExitBehaviorDropdownKey = GlobalKey();

  // 生成默认页面选项
  List<DropdownMenuItemData<int>> _getDefaultPageItems() {
    List<DropdownMenuItemData<int>> items = [
      DropdownMenuItemData(title: "主页", value: 0, isSelected: _defaultPageIndex == 0),
      DropdownMenuItemData(title: "视频播放", value: 1, isSelected: _defaultPageIndex == 1),
      DropdownMenuItemData(title: "媒体库", value: 2, isSelected: _defaultPageIndex == 2),
    ];

    items.add(DropdownMenuItemData(title: "个人中心", value: 3, isSelected: _defaultPageIndex == 3));

    return items;
  }

  List<DropdownMenuItemData<DesktopExitBehavior>> _getDesktopExitItems() {
    return [
      DropdownMenuItemData(
        title: "每次询问",
        value: DesktopExitBehavior.askEveryTime,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.askEveryTime,
      ),
      DropdownMenuItemData(
        title: "最小化到系统托盘",
        value: DesktopExitBehavior.minimizeToTrayOrTaskbar,
        isSelected:
            _desktopExitBehavior == DesktopExitBehavior.minimizeToTrayOrTaskbar,
      ),
      DropdownMenuItemData(
        title: "直接退出",
        value: DesktopExitBehavior.closePlayer,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.closePlayer,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final desktopExitBehavior = await DesktopExitPreferences.load();
    if (mounted) {
      setState(() {
        var storedIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
        _desktopExitBehavior = desktopExitBehavior;

        if (storedIndex < 0) {
          storedIndex = 0;
        } else if (storedIndex > 3) {
          storedIndex = 3;
        }

        _defaultPageIndex = storedIndex;
      });
    }
  }

  Future<void> _saveDefaultPagePreference(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(defaultPageIndexKey, index);
  }

  Future<void> _saveDesktopExitBehavior(DesktopExitBehavior behavior) async {
    await DesktopExitPreferences.save(behavior);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<int>(
      future: _loadDefaultPageIndex(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        _defaultPageIndex = snapshot.data ?? 0;

        final colorScheme = Theme.of(context).colorScheme;

        return ListView(
          children: [
            if (globals.isDesktop)
            SettingsItem.dropdown(
              title: "关闭窗口时",
              subtitle: "设置关闭按钮的默认行为，可随时修改“记住我的选择”",
              icon: Ionicons.close_outline,
              items: _getDesktopExitItems(),
              onChanged: (behavior) {
                setState(() {
                  _desktopExitBehavior = behavior as DesktopExitBehavior;
                });
                _saveDesktopExitBehavior(behavior as DesktopExitBehavior);
              },
              dropdownKey: _desktopExitBehaviorDropdownKey,
            ),
            if (globals.isDesktop)
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            SettingsItem.dropdown(
              title: "默认展示页面",
              subtitle: "选择应用启动后默认显示的页面",
              icon: Ionicons.home_outline,
              items: _getDefaultPageItems(),
              onChanged: (index) {
                setState(() {
                  _defaultPageIndex = index;
                });
                _saveDefaultPagePreference(index);
              },
              dropdownKey: _defaultPageDropdownKey,
            ),
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          ],
        );
      },
    );
  }
}

Future<int> _loadDefaultPageIndex() async {
  final prefs = await SharedPreferences.getInstance();
  final index = prefs.getInt(defaultPageIndexKey) ?? 0;
  if (index < 0) {
    return 0;
  }
  if (index > 3) {
    return 3;
  }
  return index;
}
 

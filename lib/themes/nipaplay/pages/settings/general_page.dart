import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
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

  Widget _buildHomeSectionSettingsCard(
      BuildContext context, HomeSectionsSettingsProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final sections = provider.orderedSections;

    return SettingsCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Ionicons.home_outline,
                  color: colorScheme.onSurface, size: 18),
              const SizedBox(width: 8),
              Text(
                '主页板块',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              _HoverScaleActionButton(
                icon: Icons.settings_backup_restore,
                label: '恢复默认',
                onTap: () {
                  provider.restoreDefaults();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '拖拽调整显示顺序，关闭不需要的板块。',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 8),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            buildDefaultDragHandles: false,
            itemCount: sections.length,
            onReorder: (oldIndex, newIndex) {
              provider.reorderSections(oldIndex, newIndex);
            },
            itemBuilder: (context, index) {
              final section = sections[index];
              final enabled = provider.isSectionEnabled(section);
              final showDivider = index != sections.length - 1;
              return _buildHomeSectionItem(
                context,
                section,
                enabled: enabled,
                index: index,
                showDivider: showDivider,
                onToggle: (value) {
                  provider.setSectionEnabled(section, value);
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSectionItem(
    BuildContext context,
    HomeSectionType section, {
    required bool enabled,
    required int index,
    required bool showDivider,
    required ValueChanged<bool> onToggle,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final dividerColor = colorScheme.onSurface.withOpacity(0.12);
    return Container(
      key: ValueKey(section.storageKey),
      decoration: BoxDecoration(
        border: showDivider ? Border(bottom: BorderSide(color: dividerColor)) : null,
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        title: Text(
          section.title,
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FluentSettingsSwitch(
              value: enabled,
              onChanged: onToggle,
            ),
            const SizedBox(width: 6),
            ReorderableDragStartListener(
              index: index,
              child: Icon(
                Icons.drag_handle,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
        onTap: () => onToggle(!enabled),
      ),
    );
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Consumer<HomeSectionsSettingsProvider>(
                builder: (context, provider, child) {
                  return _buildHomeSectionSettingsCard(context, provider);
                },
              ),
            ),
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
 
class _HoverScaleActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? idleColor;
  final Color hoverColor;
  final double iconSize;
  final double hoverScale;
  final EdgeInsetsGeometry padding;
  final Duration duration;
  final Curve curve;

  const _HoverScaleActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.idleColor,
    this.hoverColor = const Color(0xFFFF2E55),
    this.iconSize = 16,
    this.hoverScale = 1.1,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
    this.duration = const Duration(milliseconds: 200),
    this.curve = Curves.easeOutBack,
  });

  @override
  State<_HoverScaleActionButton> createState() => _HoverScaleActionButtonState();
}

class _HoverScaleActionButtonState extends State<_HoverScaleActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor =
        widget.idleColor ?? Theme.of(context).colorScheme.onSurface;
    final color = _isHovered ? widget.hoverColor : baseColor;
    final textStyle =
        Theme.of(context).textTheme.labelLarge ?? const TextStyle(fontSize: 14);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? widget.hoverScale : 1.0,
          duration: widget.duration,
          curve: widget.curve,
          child: Padding(
            padding: widget.padding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: widget.iconSize, color: color),
                const SizedBox(width: 6),
                Text(
                  widget.label,
                  locale: const Locale("zh-Hans", "zh"),
                  style: textStyle.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

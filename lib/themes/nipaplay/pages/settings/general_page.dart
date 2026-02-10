import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/fluent_settings_switch.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/services/desktop_exit_preferences.dart';
import 'package:nipaplay/services/desktop_startup_window_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Define the key for SharedPreferences
const String defaultPageIndexKey = 'default_page_index';

class _WindowSizePreset {
  final String id;
  final String label;
  final Size size;

  const _WindowSizePreset(this.id, this.label, this.size);
}

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
  DesktopStartupWindowState _startupWindowState =
      DesktopStartupWindowPreferences.defaultState;
  DesktopStartupWindowPosition _startupWindowPosition =
      DesktopStartupWindowPreferences.defaultPosition;
  Size _startupWindowSize = DesktopStartupWindowPreferences.defaultWindowSize;
  final GlobalKey _startupWindowStateDropdownKey = GlobalKey();
  final GlobalKey _startupWindowPositionDropdownKey = GlobalKey();
  final GlobalKey _startupWindowSizeDropdownKey = GlobalKey();

  static const List<_WindowSizePreset> _windowSizePresets = [
    _WindowSizePreset('compact', '紧凑 (960 × 600)', Size(960, 600)),
    _WindowSizePreset('standard', '标准 (1280 × 720)', Size(1280, 720)),
    _WindowSizePreset('large', '宽屏 (1440 × 900)', Size(1440, 900)),
    _WindowSizePreset('xlarge', '超大 (1920 × 1080)', Size(1920, 1080)),
  ];

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
    final startupState = await DesktopStartupWindowPreferences.loadState();
    final startupPosition =
        await DesktopStartupWindowPreferences.loadPosition();
    final startupSize = await DesktopStartupWindowPreferences.loadSize();
    if (mounted) {
      setState(() {
        var storedIndex = prefs.getInt(defaultPageIndexKey) ?? 0;
        _desktopExitBehavior = desktopExitBehavior;
        _startupWindowState = startupState;
        _startupWindowPosition = startupPosition;
        _startupWindowSize = startupSize;

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

  List<DropdownMenuItemData<DesktopStartupWindowState>>
      _getStartupWindowStateItems() {
    return [
      DropdownMenuItemData(
        title: '窗口化',
        value: DesktopStartupWindowState.windowed,
        isSelected: _startupWindowState == DesktopStartupWindowState.windowed,
      ),
      DropdownMenuItemData(
        title: '最大化',
        value: DesktopStartupWindowState.maximized,
        isSelected: _startupWindowState == DesktopStartupWindowState.maximized,
      ),
    ];
  }

  List<DropdownMenuItemData<DesktopStartupWindowPosition>>
      _getStartupWindowPositionItems() {
    return [
      DropdownMenuItemData(
        title: '左上角',
        value: DesktopStartupWindowPosition.topLeft,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.topLeft,
      ),
      DropdownMenuItemData(
        title: '右上角',
        value: DesktopStartupWindowPosition.topRight,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.topRight,
      ),
      DropdownMenuItemData(
        title: '居中',
        value: DesktopStartupWindowPosition.center,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.center,
      ),
      DropdownMenuItemData(
        title: '左下角',
        value: DesktopStartupWindowPosition.bottomLeft,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.bottomLeft,
      ),
      DropdownMenuItemData(
        title: '右下角',
        value: DesktopStartupWindowPosition.bottomRight,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.bottomRight,
      ),
    ];
  }

  _WindowSizePreset? _matchWindowSizePreset(Size size) {
    for (final preset in _windowSizePresets) {
      if (preset.size.width == size.width &&
          preset.size.height == size.height) {
        return preset;
      }
    }
    return null;
  }

  String _formatWindowSize(Size size) {
    return size.width.round().toString() +
        ' × ' +
        size.height.round().toString();
  }

  List<DropdownMenuItemData<String>> _getStartupWindowSizeItems() {
    final matchedPreset = _matchWindowSizePreset(_startupWindowSize);
    final items = _windowSizePresets
        .map(
          (preset) => DropdownMenuItemData(
            title: preset.label,
            value: preset.id,
            isSelected: matchedPreset?.id == preset.id,
          ),
        )
        .toList();
    final customLabel = matchedPreset == null
        ? '自定义 (' + _formatWindowSize(_startupWindowSize) + ')'
        : '自定义';
    items.add(
      DropdownMenuItemData(
        title: customLabel,
        value: 'custom',
        isSelected: matchedPreset == null,
      ),
    );
    return items;
  }

  _WindowSizePreset? _findWindowSizePreset(String id) {
    for (final preset in _windowSizePresets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  Future<void> _saveStartupWindowState(
      DesktopStartupWindowState state) async {
    await DesktopStartupWindowPreferences.saveState(state);
  }

  Future<void> _saveStartupWindowPosition(
      DesktopStartupWindowPosition position) async {
    await DesktopStartupWindowPreferences.savePosition(position);
  }

  Future<void> _saveStartupWindowSize(Size size) async {
    final resolved = DesktopStartupWindowPreferences.sanitizeSize(size);
    await DesktopStartupWindowPreferences.saveSize(resolved);
    if (!mounted) return;
    setState(() {
      _startupWindowSize = resolved;
    });
  }

  Future<void> _resetStartupWindowSize() async {
    await DesktopStartupWindowPreferences.resetSize();
    if (!mounted) return;
    setState(() {
      _startupWindowSize = DesktopStartupWindowPreferences.defaultWindowSize;
    });
    if (!mounted) return;
    BlurSnackBar.show(context, '已恢复默认窗口尺寸');
  }

  Future<void> _showCustomWindowSizeDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final widthController = TextEditingController(
      text: _startupWindowSize.width.round().toString(),
    );
    final heightController = TextEditingController(
      text: _startupWindowSize.height.round().toString(),
    );

    final Size? result = await BlurDialog.show<Size>(
      context: context,
      title: '自定义窗口尺寸',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widthController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  cursorColor: const Color(0xFFFF2E55),
                  decoration: InputDecoration(
                    labelText: '宽度 (px)',
                    labelStyle:
                        TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.onSurface),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: colorScheme.onSurface.withOpacity(0.38)),
                    ),
                  ),
                  style: const TextStyle(color: Color(0xFFFF2E55)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  cursorColor: const Color(0xFFFF2E55),
                  decoration: InputDecoration(
                    labelText: '高度 (px)',
                    labelStyle:
                        TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: colorScheme.onSurface),
                    ),
                    enabledBorder: UnderlineInputBorder(
                      borderSide:
                          BorderSide(color: colorScheme.onSurface.withOpacity(0.38)),
                    ),
                  ),
                  style: const TextStyle(color: Color(0xFFFF2E55)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '最小尺寸 ' +
                _formatWindowSize(
                    DesktopStartupWindowPreferences.minWindowSize),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: '取消',
          idleColor: colorScheme.onSurface.withOpacity(0.7),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: '确定',
          idleColor: colorScheme.onSurface,
          onPressed: () {
            final width = int.tryParse(widthController.text);
            final height = int.tryParse(heightController.text);
            if (width == null || height == null) {
              BlurSnackBar.show(context, '请输入有效的宽高数值');
              return;
            }
            if (width < DesktopStartupWindowPreferences.minWindowSize.width ||
                height < DesktopStartupWindowPreferences.minWindowSize.height) {
              BlurSnackBar.show(context, '窗口尺寸不能小于最小限制');
              return;
            }
            Navigator.of(context)
                .pop(Size(width.toDouble(), height.toDouble()));
          },
        ),
      ],
    );

    widthController.dispose();
    heightController.dispose();

    if (result != null) {
      await _saveStartupWindowSize(result);
      if (!mounted) return;
      BlurSnackBar.show(context, '已保存启动窗口尺寸');
    }
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

        final List<Widget> items = [];

        if (globals.isDesktop) {
          items.add(
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
          );
          items.add(
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          );
          items.add(
            SettingsItem.dropdown(
              title: "播放器启动时状态",
              subtitle: "设置启动时窗口状态",
              icon: Ionicons.expand_outline,
              items: _getStartupWindowStateItems(),
              onChanged: (state) {
                setState(() {
                  _startupWindowState = state as DesktopStartupWindowState;
                });
                _saveStartupWindowState(state as DesktopStartupWindowState);
                if (_startupWindowState != DesktopStartupWindowState.windowed) {
                  BlurSnackBar.show(context, "启动时窗口状态已更新");
                }
              },
              dropdownKey: _startupWindowStateDropdownKey,
            ),
          );

          if (_startupWindowState == DesktopStartupWindowState.windowed) {
            items.add(
              Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            );
            items.add(
              SettingsItem.dropdown(
                title: "播放器启动时窗口位置",
                subtitle: "窗口化启动时的位置",
                icon: Ionicons.move_outline,
                items: _getStartupWindowPositionItems(),
                onChanged: (position) {
                  setState(() {
                    _startupWindowPosition =
                        position as DesktopStartupWindowPosition;
                  });
                  _saveStartupWindowPosition(
                      position as DesktopStartupWindowPosition);
                  BlurSnackBar.show(context, "启动窗口位置已保存");
                },
                dropdownKey: _startupWindowPositionDropdownKey,
              ),
            );
            items.add(
              Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            );
            items.add(
              SettingsItem.dropdown(
                title: "播放器启动时窗口尺寸",
                subtitle: "支持预设与自定义尺寸",
                icon: Ionicons.resize_outline,
                items: _getStartupWindowSizeItems(),
                onChanged: (value) {
                  if (value is! String) return;
                  if (value == 'custom') {
                    _showCustomWindowSizeDialog();
                    return;
                  }
                  final preset = _findWindowSizePreset(value);
                  if (preset == null) return;
                  _saveStartupWindowSize(preset.size).then((_) {
                    if (!mounted) return;
                    BlurSnackBar.show(context, "启动窗口尺寸已保存");
                  });
                },
                dropdownKey: _startupWindowSizeDropdownKey,
              ),
            );
            items.add(
              Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
            );
            items.add(
              SettingsItem.button(
                title: "恢复默认窗口尺寸",
                subtitle: "重置为默认的启动窗口大小",
                icon: Ionicons.refresh_outline,
                onTap: _resetStartupWindowSize,
              ),
            );
          }

          items.add(
            Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
          );
        }

        items.add(
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
        );
        items.add(
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        );
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Consumer<HomeSectionsSettingsProvider>(
              builder: (context, provider, child) {
                return _buildHomeSectionSettingsCard(context, provider);
              },
            ),
          ),
        );

        return ListView(children: items);
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

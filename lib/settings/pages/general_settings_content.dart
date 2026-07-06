import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/home_sections_settings_provider.dart';
import 'package:nipaplay/providers/webdav_quick_access_provider.dart';
import 'package:nipaplay/services/desktop_exit_preferences.dart';
import 'package:nipaplay/services/desktop_startup_window_preferences.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/common_setting_tiles.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String defaultPageIndexKey = 'default_page_index';

class GeneralSettingsContent extends StatefulWidget {
  const GeneralSettingsContent({super.key});

  @override
  State<GeneralSettingsContent> createState() => _GeneralSettingsContentState();
}

class _WindowSizePreset {
  const _WindowSizePreset(this.id, this.label, this.size);

  final String id;
  final String label;
  final Size size;
}

class _GeneralSettingsContentState extends State<GeneralSettingsContent> {
  static const String _defaultHomeTabKey = 'default_home_tab';

  final GlobalKey _defaultPageDropdownKey = GlobalKey();
  final GlobalKey _desktopExitBehaviorDropdownKey = GlobalKey();
  final GlobalKey _startupWindowStateDropdownKey = GlobalKey();
  final GlobalKey _startupWindowPositionDropdownKey = GlobalKey();
  final GlobalKey _startupWindowSizeDropdownKey = GlobalKey();

  int _defaultPageIndex = 0;
  DesktopExitBehavior _desktopExitBehavior = DesktopExitBehavior.askEveryTime;
  DesktopStartupWindowState _startupWindowState =
      DesktopStartupWindowPreferences.defaultState;
  DesktopStartupWindowPosition _startupWindowPosition =
      DesktopStartupWindowPreferences.defaultPosition;
  Size _startupWindowSize = DesktopStartupWindowPreferences.defaultWindowSize;

  static const List<_WindowSizePreset> _windowSizePresets = [
    _WindowSizePreset('compact', '紧凑 (960 × 600)', Size(960, 600)),
    _WindowSizePreset('standard', '标准 (1280 × 720)', Size(1280, 720)),
    _WindowSizePreset('large', '宽屏 (1440 × 900)', Size(1440, 900)),
    _WindowSizePreset('xlarge', '超大 (1920 × 1080)', Size(1920, 1080)),
  ];

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  @override
  Widget build(BuildContext context) {
    final homeSections = context.watch<HomeSectionsSettingsProvider>();
    final children = <Widget>[];

    if (globals.isDesktop) {
      children.add(
        AdaptiveSettingsSection(
          children: [
            AdaptiveSettingsTile<DesktopExitBehavior>.dropdown(
              title: _text(context, '关闭窗口时', '關閉視窗時', 'When Closing Window'),
              subtitle: _text(
                context,
                '设置关闭按钮的默认行为，可随时修改“记住我的选择”',
                '設定關閉按鈕的預設行為，可隨時修改「記住我的選擇」',
                'Set the default close-button behavior.',
              ),
              icon: Ionicons.close_outline,
              cupertinoIcon: cupertino.CupertinoIcons.xmark_circle,
              items: _desktopExitItems(context),
              onChanged: (behavior) async {
                setState(() {
                  _desktopExitBehavior = behavior;
                });
                await DesktopExitPreferences.save(behavior);
              },
              dropdownKey: _desktopExitBehaviorDropdownKey,
            ),
            AdaptiveSettingsTile<DesktopStartupWindowState>.dropdown(
              title: _text(
                context,
                '播放器启动时状态',
                '播放器啟動時狀態',
                'Startup Window State',
              ),
              subtitle: _text(
                context,
                '设置启动时窗口状态',
                '設定啟動時視窗狀態',
                'Set the player window state on startup.',
              ),
              icon: Ionicons.expand_outline,
              cupertinoIcon: cupertino.CupertinoIcons.rectangle_expand_vertical,
              items: _startupWindowStateItems(context),
              onChanged: (state) async {
                final savedMessage = _text(
                  context,
                  '启动时窗口状态已更新',
                  '啟動時視窗狀態已更新',
                  'Startup window state updated.',
                );
                setState(() {
                  _startupWindowState = state;
                });
                await DesktopStartupWindowPreferences.saveState(state);
                if (!mounted) return;
                if (state != DesktopStartupWindowState.windowed) {
                  AdaptiveSnackBar.show(
                    this.context,
                    message: savedMessage,
                  );
                }
              },
              dropdownKey: _startupWindowStateDropdownKey,
            ),
            if (_startupWindowState == DesktopStartupWindowState.windowed) ...[
              AdaptiveSettingsTile<DesktopStartupWindowPosition>.dropdown(
                title: _text(
                  context,
                  '播放器启动时窗口位置',
                  '播放器啟動時視窗位置',
                  'Startup Window Position',
                ),
                subtitle: _text(
                  context,
                  '窗口化启动时的位置',
                  '視窗化啟動時的位置',
                  'Position used when starting in windowed mode.',
                ),
                icon: Ionicons.move_outline,
                cupertinoIcon: cupertino.CupertinoIcons.move,
                items: _startupWindowPositionItems(context),
                onChanged: (position) async {
                  final savedMessage = _text(
                    context,
                    '启动窗口位置已保存',
                    '啟動視窗位置已儲存',
                    'Startup window position saved.',
                  );
                  setState(() {
                    _startupWindowPosition = position;
                  });
                  await DesktopStartupWindowPreferences.savePosition(position);
                  if (!mounted) return;
                  AdaptiveSnackBar.show(
                    this.context,
                    message: savedMessage,
                  );
                },
                dropdownKey: _startupWindowPositionDropdownKey,
              ),
              AdaptiveSettingsTile<String>.dropdown(
                title: _text(
                  context,
                  '播放器启动时窗口尺寸',
                  '播放器啟動時視窗尺寸',
                  'Startup Window Size',
                ),
                subtitle: _text(
                  context,
                  '支持预设与自定义尺寸',
                  '支援預設與自訂尺寸',
                  'Choose a preset or custom startup size.',
                ),
                icon: Ionicons.resize_outline,
                cupertinoIcon: cupertino.CupertinoIcons.resize,
                items: _startupWindowSizeItems(),
                onChanged: (value) async {
                  if (value == 'custom') {
                    await _showCustomWindowSizeDialog();
                    return;
                  }
                  final preset = _findWindowSizePreset(value);
                  if (preset == null) return;
                  final savedMessage = _text(
                    context,
                    '启动窗口尺寸已保存',
                    '啟動視窗尺寸已儲存',
                    'Startup window size saved.',
                  );
                  await _saveStartupWindowSize(preset.size);
                  if (!mounted) return;
                  AdaptiveSnackBar.show(
                    this.context,
                    message: savedMessage,
                  );
                },
                dropdownKey: _startupWindowSizeDropdownKey,
              ),
              AdaptiveSettingsTile<void>.card(
                title: _text(
                  context,
                  '恢复默认窗口尺寸',
                  '恢復預設視窗尺寸',
                  'Restore Default Window Size',
                ),
                subtitle: _text(
                  context,
                  '重置为默认的启动窗口大小',
                  '重設為預設的啟動視窗大小',
                  'Reset to the default startup window size.',
                ),
                icon: Ionicons.refresh_outline,
                cupertinoIcon: cupertino.CupertinoIcons.refresh,
                onTap: _resetStartupWindowSize,
              ),
            ],
          ],
        ),
      );
      children.add(const SizedBox(height: 16));
    }

    children.add(
      AdaptiveSettingsSection(
        children: [
          AdaptiveSettingsTile<int>.dropdown(
            title: _text(context, '默认展示页面', '預設顯示頁面', 'Default Page'),
            subtitle: _text(
              context,
              '选择应用启动后默认显示的页面',
              '選擇應用啟動後預設顯示的頁面',
              'Choose the page shown after app startup.',
            ),
            icon: Ionicons.home_outline,
            cupertinoIcon: cupertino.CupertinoIcons.house,
            items: _defaultPageItems(context),
            onChanged: (index) async {
              setState(() {
                _defaultPageIndex = index;
              });
              await _saveDefaultPagePreference(index);
            },
            dropdownKey: _defaultPageDropdownKey,
          ),
          const AutoUpdateSettingTile(),
        ],
      ),
    );

    children.add(const SizedBox(height: 16));
    children.add(
      AdaptiveSettingsDragList<HomeSectionType>(
        items: [
          for (final section in homeSections.orderedSections)
            AdaptiveSettingsDragListItem<HomeSectionType>(
              value: section,
              title: section.title,
              subtitle: homeSections.isSectionEnabled(section)
                  ? _text(context, '显示在首页', '顯示在首頁', 'Shown on Home')
                  : _text(context, '已隐藏', '已隱藏', 'Hidden'),
              icon: Ionicons.home_outline,
              cupertinoIcon: cupertino.CupertinoIcons.square_grid_2x2,
              enabled: homeSections.isSectionEnabled(section),
            ),
        ],
        onReorder: homeSections.reorderSections,
        onEnabledChanged: (section, value) {
          homeSections.setSectionEnabled(section, value);
        },
      ),
    );
    children.add(const SizedBox(height: 8));
    children.add(
      AdaptiveSettingsSection(
        children: [
          AdaptiveSettingsTile<void>.card(
            title: context.l10n.restoreDefaults,
            subtitle: context.l10n.restoreDefaultsSubtitle,
            icon: Ionicons.refresh_outline,
            cupertinoIcon: cupertino.CupertinoIcons.refresh,
            onTap: homeSections.restoreDefaults,
          ),
        ],
      ),
    );

    return AdaptiveSettingsPage(
      title: context.l10n.generalSettings,
      children: children,
    );
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final desktopExitBehavior = await DesktopExitPreferences.load();
    final startupState = await DesktopStartupWindowPreferences.loadState();
    final startupPosition =
        await DesktopStartupWindowPreferences.loadPosition();
    final startupSize = await DesktopStartupWindowPreferences.loadSize();
    final storedHomeTab = prefs.getString(_defaultHomeTabKey);
    final storedTabIndex = _defaultPageIndexForTab(storedHomeTab);
    var resolvedIndex =
        storedTabIndex ?? prefs.getInt(defaultPageIndexKey) ?? 0;

    if (resolvedIndex == 3 && !globals.isDownloaderSupportedPlatform) {
      resolvedIndex = 0;
    } else if (resolvedIndex < 0) {
      resolvedIndex = 0;
    } else if (resolvedIndex > 4) {
      resolvedIndex = 4;
    }

    if (!mounted) return;
    setState(() {
      _desktopExitBehavior = desktopExitBehavior;
      _startupWindowState = startupState;
      _startupWindowPosition = startupPosition;
      _startupWindowSize = startupSize;
      _defaultPageIndex = resolvedIndex;
    });
  }

  List<DropdownMenuItemData<int>> _defaultPageItems(BuildContext context) {
    final items = [
      DropdownMenuItemData(
        title: context.l10n.tabHome,
        value: 0,
        isSelected: _defaultPageIndex == 0,
      ),
      DropdownMenuItemData(
        title: context.l10n.tabVideoPlay,
        value: 1,
        isSelected: _defaultPageIndex == 1,
      ),
      DropdownMenuItemData(
        title: context.l10n.tabMediaLibrary,
        value: 2,
        isSelected: _defaultPageIndex == 2,
      ),
    ];

    if (globals.isDownloaderSupportedPlatform) {
      items.add(
        DropdownMenuItemData(
          title: context.l10n.tabTorrentDownload,
          value: 3,
          isSelected: _defaultPageIndex == 3,
        ),
      );
    }

    items.add(
      DropdownMenuItemData(
        title: context.l10n.tabAccount,
        value: 4,
        isSelected: _defaultPageIndex == 4,
      ),
    );
    return items;
  }

  List<DropdownMenuItemData<DesktopExitBehavior>> _desktopExitItems(
    BuildContext context,
  ) {
    return [
      DropdownMenuItemData(
        title: _text(context, '每次询问', '每次詢問', 'Ask Every Time'),
        value: DesktopExitBehavior.askEveryTime,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.askEveryTime,
      ),
      DropdownMenuItemData(
        title: _text(
          context,
          '最小化到系统托盘',
          '最小化到系統匣',
          'Minimize to Tray',
        ),
        value: DesktopExitBehavior.minimizeToTrayOrTaskbar,
        isSelected:
            _desktopExitBehavior == DesktopExitBehavior.minimizeToTrayOrTaskbar,
      ),
      DropdownMenuItemData(
        title: _text(context, '直接退出', '直接結束', 'Quit App'),
        value: DesktopExitBehavior.closePlayer,
        isSelected: _desktopExitBehavior == DesktopExitBehavior.closePlayer,
      ),
    ];
  }

  List<DropdownMenuItemData<DesktopStartupWindowState>>
      _startupWindowStateItems(BuildContext context) {
    return [
      DropdownMenuItemData(
        title: _text(context, '窗口化', '視窗化', 'Windowed'),
        value: DesktopStartupWindowState.windowed,
        isSelected: _startupWindowState == DesktopStartupWindowState.windowed,
      ),
      DropdownMenuItemData(
        title: _text(context, '最大化', '最大化', 'Maximized'),
        value: DesktopStartupWindowState.maximized,
        isSelected: _startupWindowState == DesktopStartupWindowState.maximized,
      ),
    ];
  }

  List<DropdownMenuItemData<DesktopStartupWindowPosition>>
      _startupWindowPositionItems(BuildContext context) {
    return [
      DropdownMenuItemData(
        title: _text(context, '左上角', '左上角', 'Top Left'),
        value: DesktopStartupWindowPosition.topLeft,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.topLeft,
      ),
      DropdownMenuItemData(
        title: _text(context, '右上角', '右上角', 'Top Right'),
        value: DesktopStartupWindowPosition.topRight,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.topRight,
      ),
      DropdownMenuItemData(
        title: _text(context, '居中', '置中', 'Center'),
        value: DesktopStartupWindowPosition.center,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.center,
      ),
      DropdownMenuItemData(
        title: _text(context, '左下角', '左下角', 'Bottom Left'),
        value: DesktopStartupWindowPosition.bottomLeft,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.bottomLeft,
      ),
      DropdownMenuItemData(
        title: _text(context, '右下角', '右下角', 'Bottom Right'),
        value: DesktopStartupWindowPosition.bottomRight,
        isSelected:
            _startupWindowPosition == DesktopStartupWindowPosition.bottomRight,
      ),
    ];
  }

  List<DropdownMenuItemData<String>> _startupWindowSizeItems() {
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
        ? '自定义 (${_formatWindowSize(_startupWindowSize)})'
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

  Future<void> _saveDefaultPagePreference(int index) async {
    if (!globals.isDownloaderSupportedPlatform && index == 3) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(defaultPageIndexKey, index);
    await prefs.setString(_defaultHomeTabKey, _defaultHomeTabName(index));
  }

  String _defaultHomeTabName(int index) {
    switch (index) {
      case 1:
        return WebDAVQuickAccessProvider.tabVideo;
      case 2:
        return WebDAVQuickAccessProvider.tabMediaLibrary;
      case 3:
        return WebDAVQuickAccessProvider.tabTorrent;
      case 4:
        return WebDAVQuickAccessProvider.tabAccount;
      case 0:
      default:
        return WebDAVQuickAccessProvider.tabHome;
    }
  }

  int? _defaultPageIndexForTab(String? tabName) {
    switch (tabName) {
      case WebDAVQuickAccessProvider.tabHome:
        return 0;
      case WebDAVQuickAccessProvider.tabVideo:
        return 1;
      case WebDAVQuickAccessProvider.tabMediaLibrary:
        return 2;
      case WebDAVQuickAccessProvider.tabTorrent:
        return 3;
      case WebDAVQuickAccessProvider.tabAccount:
        return 4;
      default:
        return null;
    }
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

  _WindowSizePreset? _findWindowSizePreset(String id) {
    for (final preset in _windowSizePresets) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  String _formatWindowSize(Size size) {
    return '${size.width.round()} × ${size.height.round()}';
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
    AdaptiveSnackBar.show(
      context,
      message: _text(
        context,
        '已恢复默认窗口尺寸',
        '已恢復預設視窗尺寸',
        'Default window size restored.',
      ),
    );
  }

  Future<void> _showCustomWindowSizeDialog() async {
    final colorScheme = Theme.of(context).colorScheme;
    final widthController = TextEditingController(
      text: _startupWindowSize.width.round().toString(),
    );
    final heightController = TextEditingController(
      text: _startupWindowSize.height.round().toString(),
    );

    final result = await BlurDialog.show<Size>(
      context: context,
      title: _text(
        context,
        '自定义窗口尺寸',
        '自訂視窗尺寸',
        'Custom Window Size',
      ),
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
                  cursorColor: AppAccentColors.current,
                  decoration: InputDecoration(
                    labelText: _text(context, '宽度 (px)', '寬度 (px)', 'Width'),
                    labelStyle: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  style: TextStyle(color: AppAccentColors.current),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: heightController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  cursorColor: AppAccentColors.current,
                  decoration: InputDecoration(
                    labelText: _text(context, '高度 (px)', '高度 (px)', 'Height'),
                    labelStyle: TextStyle(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  style: TextStyle(color: AppAccentColors.current),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _text(
              context,
              '最小尺寸 ${_formatWindowSize(DesktopStartupWindowPreferences.minWindowSize)}',
              '最小尺寸 ${_formatWindowSize(DesktopStartupWindowPreferences.minWindowSize)}',
              'Minimum size ${_formatWindowSize(DesktopStartupWindowPreferences.minWindowSize)}',
            ),
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ],
      ),
      actions: [
        HoverScaleTextButton(
          text: _text(context, '取消', '取消', 'Cancel'),
          idleColor: colorScheme.onSurface.withValues(alpha: 0.7),
          onPressed: () => Navigator.of(context).pop(),
        ),
        HoverScaleTextButton(
          text: _text(context, '确定', '確定', 'OK'),
          idleColor: colorScheme.onSurface,
          onPressed: () {
            final width = int.tryParse(widthController.text);
            final height = int.tryParse(heightController.text);
            if (width == null || height == null) {
              BlurSnackBar.show(
                context,
                _text(
                  context,
                  '请输入有效的宽高数值',
                  '請輸入有效的寬高數值',
                  'Enter valid width and height values.',
                ),
              );
              return;
            }
            if (width < DesktopStartupWindowPreferences.minWindowSize.width ||
                height < DesktopStartupWindowPreferences.minWindowSize.height) {
              BlurSnackBar.show(
                context,
                _text(
                  context,
                  '窗口尺寸不能小于最小限制',
                  '視窗尺寸不能小於最小限制',
                  'Window size cannot be smaller than the minimum.',
                ),
              );
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

    if (result == null) return;
    await _saveStartupWindowSize(result);
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: _text(
        context,
        '已保存启动窗口尺寸',
        '已儲存啟動視窗尺寸',
        'Startup window size saved.',
      ),
    );
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') {
      return english;
    }
    if (locale == 'zh_Hant') {
      return traditional;
    }
    return simplified;
  }
}

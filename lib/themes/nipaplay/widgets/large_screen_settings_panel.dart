import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/app_language_provider.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/update_service.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/settings_entries.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_bottom_hint_overlay.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_side_panel.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:nipaplay/utils/theme_notifier.dart';
import 'package:provider/provider.dart';

const double kNipaplayLargeScreenSettingsPanelWidth = 900;
const double _kNipaplayLargeScreenSettingsMenuWidth = 230;
const Color _kNipaplayLargeScreenActiveColor = Color(0xFFFF2E55);

enum NipaplayLargeScreenSettingsPanelCommand {
  activateFocused,
  navigateUp,
  navigateDown,
  navigateLeft,
  navigateRight,
}

class NipaplayLargeScreenSettingsPanel extends StatefulWidget {
  const NipaplayLargeScreenSettingsPanel({
    super.key,
    required this.isDarkMode,
    this.focusedIndex = 0,
    this.commandNotifier,
    this.onFocusedIndexChanged,
    this.onEntryCountChanged,
    this.onRequestClose,
  });

  final bool isDarkMode;
  final int focusedIndex;
  final ValueListenable<NipaplayLargeScreenSettingsPanelCommand?>?
      commandNotifier;
  final ValueChanged<int>? onFocusedIndexChanged;
  final ValueChanged<int>? onEntryCountChanged;
  final VoidCallback? onRequestClose;

  @override
  State<NipaplayLargeScreenSettingsPanel> createState() =>
      _NipaplayLargeScreenSettingsPanelState();
}

class _NipaplayLargeScreenSettingsPanelState
    extends State<NipaplayLargeScreenSettingsPanel> {
  late List<NipaplaySettingEntry> _entries;
  int _selectedIndex = 0;
  bool _isContentFocused = false;
  int _contentCursor = 0;

  String _currentServer = NetworkSettings.defaultServer;
  bool _isServerLoading = true;

  @override
  void initState() {
    super.initState();
    _entries = const <NipaplaySettingEntry>[];
    _loadNetworkSettings();
  }

  Future<void> _loadNetworkSettings() async {
    final server = await NetworkSettings.getDandanplayServer();
    if (!mounted) {
      return;
    }
    setState(() {
      _currentServer = server;
      _isServerLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    _entries = buildNipaplaySettingEntries(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      widget.onEntryCountChanged?.call(_entries.length);
    });

    final Color inactiveColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;
    final Color panelBackgroundColor =
        widget.isDarkMode ? const Color(0xFF1E1E1E) : const Color(0xFFF2F2F2);

    if (_entries.isEmpty) {
      return ColoredBox(
        color: panelBackgroundColor,
        child: const SizedBox.expand(),
      );
    }

    if (_selectedIndex < 0 || _selectedIndex >= _entries.length) {
      _selectedIndex = widget.focusedIndex.clamp(0, _entries.length - 1);
    }

    final normalizedFocusedIndex =
        widget.focusedIndex.clamp(0, _entries.length - 1);
    if (normalizedFocusedIndex != widget.focusedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFocusedIndexChanged?.call(normalizedFocusedIndex);
      });
    }

    final contentItems = _buildCurrentContentItems(context);
    if (_contentCursor >= contentItems.length) {
      _contentCursor = contentItems.isEmpty ? 0 : contentItems.length - 1;
    }

    return ColoredBox(
      color: panelBackgroundColor,
      child: _NipaplayLargeScreenSettingsPanelCommandHost(
        commandNotifier: widget.commandNotifier,
        onNavigateUp: () => _handleNavigateUp(contentItems.length),
        onNavigateDown: () => _handleNavigateDown(contentItems.length),
        onNavigateLeft: _handleNavigateLeft,
        onNavigateRight: _handleNavigateRight,
        onActivateFocused: () async {
          if (_isContentFocused) {
            if (contentItems.isEmpty) {
              return;
            }
            await contentItems[_contentCursor].onActivate();
            if (!mounted) {
              return;
            }
            setState(() {});
            return;
          }
          _selectIndex(normalizedFocusedIndex);
        },
        child: Row(
          children: [
            SizedBox(
              width: _kNipaplayLargeScreenSettingsMenuWidth,
              child: NipaplayLargeScreenSidePanel(
                isDarkMode: widget.isDarkMode,
                width: _kNipaplayLargeScreenSettingsMenuWidth,
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: kNipaplayLargeScreenBottomHintHeight,
                    bottom: kNipaplayLargeScreenBottomHintHeight,
                  ),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _entries.length,
                    itemBuilder: (context, index) {
                      final entry = _entries[index];
                      final bool isSelectedByFocus =
                          !_isContentFocused && index == normalizedFocusedIndex;
                      final bool isSelectedByPage = index == _selectedIndex;
                      final bool isActive = isSelectedByFocus || isSelectedByPage;
                      final Color itemColor =
                          isActive ? Colors.white : inactiveColor;
                      return NipaplayLargeScreenSidePanelItem(
                        isSelected: isActive,
                        activeColor: _kNipaplayLargeScreenActiveColor,
                        inactiveColor: inactiveColor,
                        onTap: () {
                          _setContentFocused(false);
                          widget.onFocusedIndexChanged?.call(index);
                          _selectIndex(index);
                        },
                        child: Row(
                          children: [
                            Icon(entry.icon, size: 19, color: itemColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: itemColor,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  top: kNipaplayLargeScreenBottomHintHeight,
                  bottom: kNipaplayLargeScreenBottomHintHeight,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _entries[_selectedIndex].pageTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: widget.isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭设置',
                            onPressed: widget.onRequestClose,
                            icon: Icon(
                              Icons.close_rounded,
                              color: widget.isDarkMode
                                  ? Colors.white70
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color:
                          widget.isDarkMode ? Colors.white12 : Colors.black12,
                    ),
                    Expanded(
                      child: contentItems.isEmpty
                          ? Center(
                              child: Text(
                                '该设置项暂未提供大屏幕键盘交互版本',
                                style: TextStyle(
                                  color: widget.isDarkMode
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(16),
                              itemCount: contentItems.length,
                              itemBuilder: (context, index) {
                                return _buildContentItemCard(
                                  item: contentItems[index],
                                  isSelected:
                                      _isContentFocused && index == _contentCursor,
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentItemCard({
    required _LargeScreenSettingsContentItem item,
    required bool isSelected,
  }) {
    final Color titleColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final Color subtitleColor =
        widget.isDarkMode ? Colors.white70 : Colors.black54;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isSelected
            ? _kNipaplayLargeScreenActiveColor
            : (widget.isDarkMode
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    color: isSelected ? Colors.white : titleColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (item.subtitle != null && item.subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle!,
                    style: TextStyle(
                      color: isSelected ? Colors.white : subtitleColor,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.valueText,
            style: TextStyle(
              color: isSelected ? Colors.white : titleColor,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _selectIndex(int index) {
    if (_entries.isEmpty) {
      return;
    }
    final clamped = index.clamp(0, _entries.length - 1);
    if (_selectedIndex == clamped) {
      return;
    }
    setState(() {
      _selectedIndex = clamped;
      _contentCursor = 0;
    });
  }

  void _setContentFocused(bool value) {
    if (_isContentFocused == value) {
      return;
    }
    setState(() {
      _isContentFocused = value;
      if (!_isContentFocused) {
        _contentCursor = 0;
      }
    });
  }

  void _handleNavigateUp(int contentItemCount) {
    if (_isContentFocused) {
      if (contentItemCount <= 0) {
        return;
      }
      setState(() {
        _contentCursor = (_contentCursor - 1) % contentItemCount;
        if (_contentCursor < 0) {
          _contentCursor += contentItemCount;
        }
      });
      return;
    }
    widget.onFocusedIndexChanged?.call(widget.focusedIndex - 1);
  }

  void _handleNavigateDown(int contentItemCount) {
    if (_isContentFocused) {
      if (contentItemCount <= 0) {
        return;
      }
      setState(() {
        _contentCursor = (_contentCursor + 1) % contentItemCount;
      });
      return;
    }
    widget.onFocusedIndexChanged?.call(widget.focusedIndex + 1);
  }

  void _handleNavigateLeft() {
    if (_isContentFocused) {
      _setContentFocused(false);
    }
  }

  void _handleNavigateRight() {
    if (!_isContentFocused) {
      _setContentFocused(true);
    }
  }

  List<_LargeScreenSettingsContentItem> _buildCurrentContentItems(
      BuildContext context) {
    final selectedEntryId = _entries[_selectedIndex].id;
    switch (selectedEntryId) {
      case NipaplaySettingEntryIds.appearance:
        return _buildAppearanceContentItems(context);
      case NipaplaySettingEntryIds.language:
        return _buildLanguageContentItems(context);
      case NipaplaySettingEntryIds.general:
        return _buildGeneralContentItems(context);
      case NipaplaySettingEntryIds.network:
        return _buildNetworkContentItems(context);
      default:
        return const <_LargeScreenSettingsContentItem>[];
    }
  }

  List<_LargeScreenSettingsContentItem> _buildAppearanceContentItems(
      BuildContext context) {
    final themeNotifier = context.read<ThemeNotifier>();
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final settingsProvider = context.watch<SettingsProvider>();

    final themeText = switch (themeNotifier.themeMode) {
      ThemeMode.light => '日间模式',
      ThemeMode.dark => '夜间模式',
      ThemeMode.system => '跟随系统',
    };

    return [
      _LargeScreenSettingsContentItem(
        title: '主题模式',
        subtitle: '回车切换: 日间 -> 夜间 -> 跟随系统',
        valueText: themeText,
        onActivate: () async {
          final current = themeNotifier.themeMode;
          final next = switch (current) {
            ThemeMode.light => ThemeMode.dark,
            ThemeMode.dark => ThemeMode.system,
            ThemeMode.system => ThemeMode.light,
          };
          themeNotifier.themeMode = next;
        },
      ),
      _LargeScreenSettingsContentItem(
        title: '控件毛玻璃效果',
        subtitle: '回车开关',
        valueText: appearanceSettings.enableWidgetBlurEffect ? '开启' : '关闭',
        onActivate: () => appearanceSettings
            .setEnableWidgetBlurEffect(!appearanceSettings.enableWidgetBlurEffect),
      ),
      _LargeScreenSettingsContentItem(
        title: '番剧卡片显示介绍',
        subtitle: '回车开关',
        valueText: appearanceSettings.showAnimeCardSummary ? '开启' : '关闭',
        onActivate: () => appearanceSettings
            .setShowAnimeCardSummary(!appearanceSettings.showAnimeCardSummary),
      ),
      _LargeScreenSettingsContentItem(
        title: '界面缩放',
        subtitle: '回车步进 +0.05，超过最大值回到最小值',
        valueText: appearanceSettings.uiScale.toStringAsFixed(2),
        onActivate: () {
          final current = appearanceSettings.uiScale;
          const step = AppearanceSettingsProvider.uiScaleStep;
          const min = AppearanceSettingsProvider.uiScaleMin;
          const max = AppearanceSettingsProvider.uiScaleMax;
          var next = current + step;
          if (next > max + 0.0001) {
            next = min;
          }
          return appearanceSettings.setUiScale(next.clamp(min, max));
        },
      ),
      _LargeScreenSettingsContentItem(
        title: '全局背景模糊',
        subtitle: '回车在 0 / 10 之间切换',
        valueText: settingsProvider.blurPower.toStringAsFixed(0),
        onActivate: () async {
          final bool enabled = settingsProvider.isBlurEnabled;
          await settingsProvider.setBlurPower(enabled ? 0 : 10);
        },
      ),
    ];
  }

  List<_LargeScreenSettingsContentItem> _buildLanguageContentItems(
      BuildContext context) {
    final provider = context.watch<AppLanguageProvider>();

    final modeText = switch (provider.mode) {
      AppLanguageMode.auto => '自动',
      AppLanguageMode.simplifiedChinese => '简体中文',
      AppLanguageMode.traditionalChinese => '繁体中文',
    };

    return [
      _LargeScreenSettingsContentItem(
        title: '应用语言',
        subtitle: '回车切换: 自动 -> 简体 -> 繁体',
        valueText: modeText,
        onActivate: () async {
          final next = switch (provider.mode) {
            AppLanguageMode.auto => AppLanguageMode.simplifiedChinese,
            AppLanguageMode.simplifiedChinese =>
              AppLanguageMode.traditionalChinese,
            AppLanguageMode.traditionalChinese => AppLanguageMode.auto,
          };
          await context.read<AppLanguageProvider>().setMode(next);
        },
      ),
    ];
  }

  List<_LargeScreenSettingsContentItem> _buildGeneralContentItems(
      BuildContext context) {
    final l10n = context.l10n;
    final settingsProvider = context.watch<SettingsProvider>();

    return [
      _LargeScreenSettingsContentItem(
        title: l10n.aboutAutoCheckUpdates,
        subtitle: '回车开关',
        valueText: '动态读取',
        onActivate: () async {
          final enabled = await UpdateService.isAutoCheckEnabled();
          await UpdateService.setAutoCheckEnabled(!enabled);
          if (!mounted) {
            return;
          }
          setState(() {});
        },
      ),
      _LargeScreenSettingsContentItem(
        title: '弹幕转简体',
        subtitle: '回车开关',
        valueText: settingsProvider.danmakuConvertToSimplified ? '开启' : '关闭',
        onActivate: () => context.read<SettingsProvider>().setDanmakuConvertToSimplified(
            !context.read<SettingsProvider>().danmakuConvertToSimplified),
      ),
      _LargeScreenSettingsContentItem(
        title: '自动匹配弹幕(哈希失败)',
        subtitle: '回车开关',
        valueText:
            settingsProvider.autoMatchDanmakuFirstSearchResultOnHashFail
                ? '开启'
                : '关闭',
        onActivate: () => context
            .read<SettingsProvider>()
            .setAutoMatchDanmakuFirstSearchResultOnHashFail(
                !context
                    .read<SettingsProvider>()
                    .autoMatchDanmakuFirstSearchResultOnHashFail),
      ),
      _LargeScreenSettingsContentItem(
        title: '播放时自动匹配弹幕',
        subtitle: '回车开关',
        valueText: settingsProvider.autoMatchDanmakuOnPlay ? '开启' : '关闭',
        onActivate: () => context.read<SettingsProvider>().setAutoMatchDanmakuOnPlay(
            !context.read<SettingsProvider>().autoMatchDanmakuOnPlay),
      ),
    ];
  }

  List<_LargeScreenSettingsContentItem> _buildNetworkContentItems(
      BuildContext context) {
    final l10n = context.l10n;
    final serverText = _isServerLoading
        ? '加载中'
        : (_currentServer == NetworkSettings.primaryServer
            ? l10n.primaryServer
            : (_currentServer == NetworkSettings.backupServer
                ? l10n.backupServer
                : _currentServer));

    return [
      _LargeScreenSettingsContentItem(
        title: l10n.dandanplayServer,
        subtitle: '回车切换主服务器 / 备用服务器',
        valueText: serverText,
        onActivate: () async {
          final next = _currentServer == NetworkSettings.primaryServer
              ? NetworkSettings.backupServer
              : NetworkSettings.primaryServer;
          await NetworkSettings.setDandanplayServer(next);
          if (!mounted) {
            return;
          }
          setState(() {
            _currentServer = next;
          });
        },
      ),
    ];
  }
}

class _LargeScreenSettingsContentItem {
  const _LargeScreenSettingsContentItem({
    required this.title,
    required this.valueText,
    required this.onActivate,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final String valueText;
  final Future<void> Function() onActivate;
}

class _NipaplayLargeScreenSettingsPanelCommandHost extends StatefulWidget {
  const _NipaplayLargeScreenSettingsPanelCommandHost({
    required this.child,
    required this.onActivateFocused,
    required this.onNavigateUp,
    required this.onNavigateDown,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    this.commandNotifier,
  });

  final Widget child;
  final Future<void> Function() onActivateFocused;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final ValueListenable<NipaplayLargeScreenSettingsPanelCommand?>?
      commandNotifier;

  @override
  State<_NipaplayLargeScreenSettingsPanelCommandHost> createState() =>
      _NipaplayLargeScreenSettingsPanelCommandHostState();
}

class _NipaplayLargeScreenSettingsPanelCommandHostState
    extends State<_NipaplayLargeScreenSettingsPanelCommandHost> {
  @override
  void initState() {
    super.initState();
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void didUpdateWidget(
      covariant _NipaplayLargeScreenSettingsPanelCommandHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commandNotifier == widget.commandNotifier) {
      return;
    }
    oldWidget.commandNotifier?.removeListener(_handleCommand);
    widget.commandNotifier?.addListener(_handleCommand);
  }

  @override
  void dispose() {
    widget.commandNotifier?.removeListener(_handleCommand);
    super.dispose();
  }

  void _handleCommand() {
    final command = widget.commandNotifier?.value;
    switch (command) {
      case NipaplayLargeScreenSettingsPanelCommand.activateFocused:
        widget.onActivateFocused();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateUp:
        widget.onNavigateUp();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateDown:
        widget.onNavigateDown();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateLeft:
        widget.onNavigateLeft();
        break;
      case NipaplayLargeScreenSettingsPanelCommand.navigateRight:
        widget.onNavigateRight();
        break;
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

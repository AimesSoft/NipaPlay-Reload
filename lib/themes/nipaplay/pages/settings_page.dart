import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/about_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/settings_entries.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/responsive_container.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class SettingsPage extends StatefulWidget {
  static const String entryRemoteAccess = NipaplaySettingEntryIds.remoteAccess;
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
                      innerContext.l10n.settingsLabel,
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
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with SingleTickerProviderStateMixin {
  Widget? currentPage;
  late TabController _tabController;
  static Color get _selectedColor => AppAccentColors.current;
  String? _selectedEntryId;
  bool _didApplyInitialEntry = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);

    if (globals.isDesktop || globals.isTablet) {
      currentPage = const AboutPage();
      _selectedEntryId = NipaplaySettingEntryIds.about;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didApplyInitialEntry) return;
    _didApplyInitialEntry = true;
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

  NipaplaySettingEntry? _findEntryById(String entryId) {
    final entries = _buildSettingEntries(context);
    for (final entry in entries) {
      if (entry.id == entryId) {
        return entry;
      }
    }
    return null;
  }

  void _handleItemTap(String entryId, Widget pageToShow, String title) {
    List<Widget> settingsTabLabels() {
      final colorScheme = Theme.of(context).colorScheme;
      return [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
        ),
      ];
    }

    final List<Widget> pages = [pageToShow];
    if (globals.isDesktop || globals.isTablet) {
      setState(() {
        currentPage = pageToShow;
        _selectedEntryId = entryId;
      });
    } else {
      setState(() {
        _selectedEntryId = entryId;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Selector<VideoPlayerState, bool>(
            selector: (context, videoState) => videoState.shouldShowAppBar(),
            builder: (context, shouldShowAppBar, child) {
              return SettingsNoRippleTheme(
                disableBlurEffect: true,
                child: CustomScaffold(
                  pages: pages,
                  tabPage: settingsTabLabels(),
                  pageIsHome: false,
                  shouldShowAppBar: shouldShowAppBar,
                  tabController: _tabController,
                ),
              );
            },
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildSettingEntries(context);
    final colorScheme = Theme.of(context).colorScheme;
    return SettingsNoRippleTheme(
      disableBlurEffect: true,
      child: NipaplayLargeScreenModeScope.isActiveOf(context)
          ? _buildLargeScreenSettingsPage(entries)
          : ResponsiveContainer(
              currentPage: currentPage ?? Container(),
              child: ListView.separated(
                itemCount: entries.length,
                itemBuilder: (context, index) =>
                    _buildSettingTile(entries[index]),
                separatorBuilder: (context, index) => Divider(
                  height: 1,
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
            ),
    );
  }

  Widget _buildLargeScreenSettingsPage(List<NipaplaySettingEntry> entries) {
    if (entries.isEmpty) {
      return NipaplayLargeScreenPageScaffold(
        title: context.l10n.settingsLabel,
        child: const NipaplayLargeScreenEmptyState(
          icon: Icons.settings_rounded,
          title: '暂无设置',
          subtitle: '',
        ),
      );
    }

    final selectedIndex = _effectiveSelectedIndex(entries);
    final selectedEntry = entries[selectedIndex];
    final selectedPage = currentPage ?? selectedEntry.page;

    return NipaplayLargeScreenPageScaffold(
      title: context.l10n.settingsLabel,
      subtitle: selectedEntry.pageTitle,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 292,
            child: NipaplayLargeScreenPanel(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _buildLargeScreenSettingTile(
                    entry,
                    isSelected: index == selectedIndex,
                    autofocus: index == selectedIndex,
                  );
                },
                separatorBuilder: (context, index) => const SizedBox(height: 4),
              ),
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                NipaplayLargeScreenSectionHeader(
                  title: selectedEntry.pageTitle,
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey<String>(selectedEntry.id),
                    child: selectedPage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<NipaplaySettingEntry> _buildSettingEntries(BuildContext context) {
    return buildNipaplaySettingEntries(context);
  }

  int _effectiveSelectedIndex(List<NipaplaySettingEntry> entries) {
    final selectedIndex =
        entries.indexWhere((entry) => entry.id == _selectedEntryId);
    if (selectedIndex >= 0) {
      return selectedIndex;
    }
    final aboutIndex = entries
        .indexWhere((entry) => entry.id == NipaplaySettingEntryIds.about);
    if (aboutIndex >= 0) {
      return aboutIndex;
    }
    return 0;
  }

  Widget _buildLargeScreenSettingTile(
    NipaplaySettingEntry entry, {
    required bool isSelected,
    required bool autofocus,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? Colors.white.withValues(alpha: 0.72) : Colors.black54;
    final activeColor = isSelected ? Colors.white : inactiveColor;
    final activeBackground = isSelected ? _selectedColor : Colors.transparent;

    return NipaplayLargeScreenFocusableAction(
      autofocus: autofocus,
      onActivate: () => _handleItemTap(entry.id, entry.page, entry.pageTitle),
      borderRadius: BorderRadius.circular(8),
      focusScale: 1.018,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: activeBackground,
        idleBackgroundLight: activeBackground,
        contentColorDark: activeColor,
        contentColorLight: activeColor,
        focusStrokeColor: isSelected ? Colors.white : _selectedColor,
      ),
      child: Row(
        children: [
          Icon(entry.icon, size: 20),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingTile(NipaplaySettingEntry entry) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = entry.id == _selectedEntryId;
    final itemColor = isSelected ? _selectedColor : colorScheme.onSurface;
    return ListTile(
      leading: Icon(entry.icon, color: itemColor),
      title: Text(
        entry.title,
        style: TextStyle(color: itemColor, fontWeight: FontWeight.bold),
      ),
      onTap: () => _handleItemTap(entry.id, entry.page, entry.pageTitle),
    );
  }
}

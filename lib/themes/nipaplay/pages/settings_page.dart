import 'package:flutter/material.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/about_page.dart';
import 'package:nipaplay/themes/nipaplay/pages/settings/settings_entries.dart';
import 'package:nipaplay/themes/nipaplay/widgets/custom_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/responsive_container.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

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
  static const Color _selectedColor = Color(0xFFFF2E55);
  String? _selectedEntryId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);

    if (globals.isDesktop || globals.isTablet) {
      currentPage = const AboutPage();
      _selectedEntryId = NipaplaySettingEntryIds.about;
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
      child: ResponsiveContainer(
        currentPage: currentPage ?? Container(),
        child: ListView.separated(
          itemCount: entries.length,
          itemBuilder: (context, index) => _buildSettingTile(entries[index]),
          separatorBuilder: (context, index) => Divider(
            height: 1,
            color: colorScheme.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
    );
  }

  List<NipaplaySettingEntry> _buildSettingEntries(BuildContext context) {
    return buildNipaplaySettingEntries(context);
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

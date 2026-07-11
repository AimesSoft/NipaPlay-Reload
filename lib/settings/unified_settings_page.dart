import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/unified_settings_entries.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class UnifiedSettingsPage extends material.StatefulWidget {
  const UnifiedSettingsPage({
    super.key,
    this.initialEntryId,
  });

  final String? initialEntryId;

  @override
  material.State<UnifiedSettingsPage> createState() =>
      _UnifiedSettingsPageState();
}

class _UnifiedSettingsPageState extends material.State<UnifiedSettingsPage> {
  final material.ScrollController _phoneScrollController =
      material.ScrollController();
  String? _selectedEntryId;
  bool _didOpenPhoneInitialEntry = false;

  @override
  void dispose() {
    _phoneScrollController.dispose();
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    final surface = AppDisplaySurfaceScope.of(context);
    return switch (surface) {
      AppDisplaySurface.phone => _buildPhone(context),
      AppDisplaySurface.desktopTablet ||
      AppDisplaySurface.television =>
        _buildDesktopTablet(context),
    };
  }

  material.Widget _buildPhone(material.BuildContext context) {
    final entries = buildUnifiedSettingEntries(
      context,
      surface: UnifiedSettingsSurface.phone,
    );
    _openPhoneInitialEntry(entries);

    final background = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.systemGroupedBackground,
      context,
    );
    final bottomPadding =
        material.MediaQuery.viewPaddingOf(context).bottom + 32;

    return AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.phone,
      child: CupertinoBottomSheetContentLayout(
        controller: _phoneScrollController,
        backgroundColor: background,
        sliversBuilder: (context, topSpacing) => [
          material.SliverPadding(
            padding: material.EdgeInsets.only(top: topSpacing + 8),
            sliver: material.SliverToBoxAdapter(
              child: material.Column(
                crossAxisAlignment: material.CrossAxisAlignment.stretch,
                children: [
                  for (final section in UnifiedSettingSection.values) ...[
                    UnifiedCupertinoSettingsSectionView(
                      section: section,
                      entries: entries
                          .where((entry) => entry.section == section)
                          .toList(growable: false),
                    ),
                    if (section != UnifiedSettingSection.values.last)
                      const material.SizedBox(height: 24),
                  ],
                ],
              ),
            ),
          ),
          material.SliverToBoxAdapter(
            child: material.SizedBox(height: bottomPadding),
          ),
        ],
      ),
    );
  }

  void _openPhoneInitialEntry(List<UnifiedSettingEntry> entries) {
    final initialEntryId = widget.initialEntryId;
    if (_didOpenPhoneInitialEntry || initialEntryId == null) return;

    UnifiedSettingEntry? target;
    for (final entry in entries) {
      if (entry.id == initialEntryId) {
        target = entry;
        break;
      }
    }
    if (target == null) return;

    _didOpenPhoneInitialEntry = true;
    material.WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      openUnifiedCupertinoSettingEntry(context, target!);
    });
  }

  material.Widget _buildDesktopTablet(material.BuildContext context) {
    final entries = buildUnifiedSettingEntries(
      context,
      surface: UnifiedSettingsSurface.desktopTablet,
    );
    if (entries.isEmpty) {
      return const material.SizedBox.shrink();
    }

    final selectedEntry = _effectiveDesktopEntry(entries);
    final content = material.KeyedSubtree(
      key: material.ValueKey<String>(selectedEntry.id),
      child: selectedEntry.buildPage(
        context,
        UnifiedSettingsSurface.desktopTablet,
      ),
    );

    return AdaptiveSettingsScope(
      style: AdaptiveSettingsStyle.desktopTablet,
      child: SettingsNoRippleTheme(
        disableBlurEffect: true,
        child: NipaplayLargeScreenModeScope.isActiveOf(context)
            ? _buildLargeScreen(context, entries, selectedEntry, content)
            : _buildDesktopSplit(context, entries, selectedEntry, content),
      ),
    );
  }

  UnifiedSettingEntry _effectiveDesktopEntry(
    List<UnifiedSettingEntry> entries,
  ) {
    final requestedId = _selectedEntryId ?? widget.initialEntryId;
    for (final entry in entries) {
      if (entry.id == requestedId) return entry;
    }
    for (final entry in entries) {
      if (entry.id == UnifiedSettingEntryIds.about) return entry;
    }
    return entries.first;
  }

  material.Widget _buildDesktopSplit(
    material.BuildContext context,
    List<UnifiedSettingEntry> entries,
    UnifiedSettingEntry selectedEntry,
    material.Widget content,
  ) {
    final dividerColor = material.Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.12);
    return material.LayoutBuilder(
      builder: (context, constraints) {
        final navigationWidth =
            (constraints.maxWidth * 0.25).clamp(230.0, 320.0);
        return material.Row(
          children: [
            material.SizedBox(
              width: navigationWidth,
              child: _DesktopSettingsNavigation(
                entries: entries,
                selectedEntryId: selectedEntry.id,
                onSelected: _selectDesktopEntry,
              ),
            ),
            material.ColoredBox(
              color: dividerColor,
              child: const material.SizedBox(width: 1),
            ),
            material.Expanded(child: content),
          ],
        );
      },
    );
  }

  material.Widget _buildLargeScreen(
    material.BuildContext context,
    List<UnifiedSettingEntry> entries,
    UnifiedSettingEntry selectedEntry,
    material.Widget content,
  ) {
    return NipaplayLargeScreenPageScaffold(
      title: context.l10n.settingsLabel,
      subtitle: selectedEntry.pageTitle(
        context,
        UnifiedSettingsSurface.desktopTablet,
      ),
      child: material.Row(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          material.SizedBox(
            width: 292,
            child: NipaplayLargeScreenPanel(
              padding: const material.EdgeInsets.symmetric(vertical: 8),
              child: _DesktopSettingsNavigation(
                entries: entries,
                selectedEntryId: selectedEntry.id,
                onSelected: _selectDesktopEntry,
              ),
            ),
          ),
          const material.SizedBox(width: 24),
          material.Expanded(
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                NipaplayLargeScreenSectionHeader(
                  title: selectedEntry.pageTitle(
                    context,
                    UnifiedSettingsSurface.desktopTablet,
                  ),
                ),
                const material.SizedBox(height: 18),
                material.Expanded(child: content),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _selectDesktopEntry(String id) {
    if (_selectedEntryId == id) return;
    setState(() => _selectedEntryId = id);
  }
}

class _DesktopSettingsNavigation extends material.StatelessWidget {
  const _DesktopSettingsNavigation({
    required this.entries,
    required this.selectedEntryId,
    required this.onSelected,
  });

  final List<UnifiedSettingEntry> entries;
  final String selectedEntryId;
  final material.ValueChanged<String> onSelected;

  @override
  material.Widget build(material.BuildContext context) {
    return material.ListView.separated(
      padding: const material.EdgeInsets.symmetric(vertical: 8),
      itemCount: entries.length,
      separatorBuilder: (_, __) => const material.SizedBox(height: 4),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final selected = entry.id == selectedEntryId;
        final isDark =
            material.Theme.of(context).brightness == material.Brightness.dark;
        final inactiveColor = isDark
            ? material.Colors.white.withValues(alpha: 0.72)
            : material.Colors.black54;
        final foreground = selected ? material.Colors.white : inactiveColor;
        final background =
            selected ? AppAccentColors.current : material.Colors.transparent;

        return NipaplayLargeScreenFocusableAction(
          onActivate: () => onSelected(entry.id),
          borderRadius: material.BorderRadius.circular(8),
          focusScale: 1.018,
          padding: const material.EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          style: NipaplayLargeScreenFocusableStyle(
            idleBackgroundDark: background,
            idleBackgroundLight: background,
            contentColorDark: foreground,
            contentColorLight: foreground,
            focusStrokeColor:
                selected ? material.Colors.white : AppAccentColors.current,
          ),
          child: material.Row(
            children: [
              material.Icon(entry.icon, size: 20),
              const material.SizedBox(width: 11),
              material.Expanded(
                child: material.Text(
                  entry.title(
                    context,
                    UnifiedSettingsSurface.desktopTablet,
                  ),
                  maxLines: 1,
                  overflow: material.TextOverflow.ellipsis,
                  style: const material.TextStyle(
                    fontSize: 15,
                    fontWeight: material.FontWeight.w800,
                  ),
                ),
              ),
              if (selected) ...[
                const material.SizedBox(width: 8),
                const material.Icon(
                  material.Icons.chevron_right_rounded,
                  size: 20,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

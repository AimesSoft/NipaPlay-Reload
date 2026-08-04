import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/media_library/media_source_option.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_library_section_picker.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_header.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_source_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/dandanplay_remote_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_tab.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_view_container.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_server_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_main_tab_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/widgets/in_view_dialog.dart';

class AdaptiveMediaLibraryScaffold extends material.StatelessWidget {
  const AdaptiveMediaLibraryScaffold({
    super.key,
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.onSectionOrderChanged,
    required this.onRemoteAccess,
    required this.onAddMedia,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
  final material.ValueChanged<List<String>> onSectionOrderChanged;
  final material.VoidCallback onRemoteAccess;
  final material.VoidCallback onAddMedia;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    if (_useTelevisionMediaLibraryLayout(context)) {
      return _TelevisionMediaLibraryScaffold(
        sections: sections,
        selectedSection: selectedSection,
        onSectionSelected: onSectionSelected,
        onSectionOrderChanged: onSectionOrderChanged,
        onRemoteAccess: onRemoteAccess,
        onAddMedia: onAddMedia,
        child: child,
      );
    }
    return switch (AppDisplaySurfaceScope.of(context)) {
      AppDisplaySurface.phone => _CupertinoMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: onSectionSelected,
          onSectionOrderChanged: onSectionOrderChanged,
          child: child,
        ),
      AppDisplaySurface.desktopTablet ||
      AppDisplaySurface.television =>
        _DesktopMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: onSectionSelected,
          onSectionOrderChanged: onSectionOrderChanged,
          onRemoteAccess: onRemoteAccess,
          onAddMedia: onAddMedia,
          child: child,
        ),
    };
  }
}

bool _useTelevisionMediaLibraryLayout(material.BuildContext context) {
  return AppDisplaySurfaceScope.of(context) == AppDisplaySurface.television ||
      NipaplayLargeScreenModeScope.isActiveOf(context);
}

class _TelevisionMediaLibraryScaffold extends material.StatelessWidget {
  const _TelevisionMediaLibraryScaffold({
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.onSectionOrderChanged,
    required this.onRemoteAccess,
    required this.onAddMedia,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
  final material.ValueChanged<List<String>> onSectionOrderChanged;
  final material.VoidCallback onRemoteAccess;
  final material.VoidCallback onAddMedia;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    return NipaplayLargeScreenModeScope(
      isActive: true,
      child: NipaplayLargeScreenPageScaffold(
        key: const material.ValueKey<String>('television-media-library'),
        title: '媒体库',
        subtitle: '${selectedSection.label} · 使用方向键浏览，按确认键打开',
        icon: material.Icons.video_library_rounded,
        padding: const material.EdgeInsets.fromLTRB(30, 24, 30, 30),
        headerBottomSpacing: 16,
        actions: [
          NipaplayLargeScreenActionButton(
            icon: material.Icons.swap_vert_rounded,
            label: '调整顺序',
            onPressed: () => _showSectionOrderEditor(
              context,
              sections,
              onSectionOrderChanged,
            ),
          ),
          NipaplayLargeScreenActionButton(
            icon: material.Icons.link_rounded,
            label: '远程访问',
            onPressed: onRemoteAccess,
          ),
          NipaplayLargeScreenActionButton(
            icon: material.Icons.add_to_queue_rounded,
            label: '添加媒体',
            onPressed: onAddMedia,
          ),
        ],
        child: material.Column(
          crossAxisAlignment: material.CrossAxisAlignment.stretch,
          children: [
            NipaplayLargeScreenPanel(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              child: material.SizedBox(
                height: 58,
                child: material.ListView.separated(
                  scrollDirection: material.Axis.horizontal,
                  physics: const material.ClampingScrollPhysics(),
                  itemCount: sections.length,
                  separatorBuilder: (_, __) =>
                      const material.SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final section = sections[index];
                    return _TelevisionMediaLibrarySectionButton(
                      section: section,
                      selected: section.id == selectedSection.id,
                      autofocus: section.id == selectedSection.id,
                      onPressed: () => onSectionSelected(section.id),
                    );
                  },
                ),
              ),
            ),
            const material.SizedBox(height: 16),
            material.Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _TelevisionMediaLibrarySectionButton extends material.StatelessWidget {
  const _TelevisionMediaLibrarySectionButton({
    required this.section,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
  });

  final UnifiedMediaLibrarySection section;
  final bool selected;
  final bool autofocus;
  final material.VoidCallback onPressed;

  @override
  material.Widget build(material.BuildContext context) {
    final foreground = selected
        ? material.Colors.white
        : material.Theme.of(context).colorScheme.onSurface;
    final background =
        selected ? AppAccentColors.current : material.Colors.transparent;
    return NipaplayLargeScreenFocusableAction(
      key: material.ValueKey<String>(
        'large-screen-media-library-tab-${section.id}',
      ),
      autofocus: autofocus,
      onActivate: onPressed,
      borderRadius: material.BorderRadius.circular(9),
      focusScale: 1.035,
      padding: const material.EdgeInsets.symmetric(horizontal: 18),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: background,
        idleBackgroundLight: background,
        contentColorDark: foreground,
        contentColorLight: foreground,
        focusStrokeColor:
            selected ? material.Colors.white : AppAccentColors.current,
      ),
      child: material.Row(
        mainAxisSize: material.MainAxisSize.min,
        children: [
          material.Icon(_mediaLibrarySectionIcon(section), size: 21),
          const material.SizedBox(width: 9),
          material.Text(
            section.label,
            style: const material.TextStyle(
              fontSize: 15,
              fontWeight: material.FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class AdaptiveMediaLibrarySectionContent extends material.StatelessWidget {
  const AdaptiveMediaLibrarySectionContent({
    super.key,
    required this.section,
    required this.onPlayEpisode,
    required this.onSourcesUpdated,
    required this.managementViewMode,
    required this.onManagementViewModeChanged,
  });

  final UnifiedMediaLibrarySection section;
  final material.ValueChanged<WatchHistoryItem> onPlayEpisode;
  final material.VoidCallback onSourcesUpdated;
  final LibraryManagementViewMode managementViewMode;
  final material.ValueChanged<LibraryManagementViewMode>
      onManagementViewModeChanged;

  @override
  material.Widget build(material.BuildContext context) {
    if (section.contentType == UnifiedMediaLibraryContentType.mediaCollection) {
      return AdaptiveMediaCollectionView(
        key: material.ValueKey<String>('collection-${section.id}'),
        source: section.source!,
        onPlayEpisode: onPlayEpisode,
      );
    }
    return _UnifiedMediaLibrarySectionContent(
      key: material.ValueKey<String>('section-${section.id}'),
      section: section,
      onPlayEpisode: onPlayEpisode,
      onSourcesUpdated: onSourcesUpdated,
      managementViewMode: managementViewMode,
      onManagementViewModeChanged: onManagementViewModeChanged,
    );
  }
}

class _UnifiedMediaLibrarySectionContent extends material.StatelessWidget {
  const _UnifiedMediaLibrarySectionContent({
    super.key,
    required this.section,
    required this.onPlayEpisode,
    required this.onSourcesUpdated,
    required this.managementViewMode,
    required this.onManagementViewModeChanged,
  });

  final UnifiedMediaLibrarySection section;
  final material.ValueChanged<WatchHistoryItem> onPlayEpisode;
  final material.VoidCallback onSourcesUpdated;
  final LibraryManagementViewMode managementViewMode;
  final material.ValueChanged<LibraryManagementViewMode>
      onManagementViewModeChanged;

  @override
  material.Widget build(material.BuildContext context) {
    return switch (section.contentType) {
      UnifiedMediaLibraryContentType.mediaCollection =>
        const material.SizedBox.shrink(),
      UnifiedMediaLibraryContentType.libraryManagement => LibraryManagementTab(
          section: _desktopManagementSource(section.source!),
          onPlayEpisode: onPlayEpisode,
          viewMode: managementViewMode,
          onViewModeChanged: onManagementViewModeChanged,
        ),
      UnifiedMediaLibraryContentType.sharedCollection =>
        SharedRemoteLibraryView(
          mode: SharedRemoteViewMode.mediaLibrary,
          onPlayEpisode: onPlayEpisode,
        ),
      UnifiedMediaLibraryContentType.sharedManagement =>
        SharedRemoteLibraryView(
          mode: SharedRemoteViewMode.libraryManagement,
          onPlayEpisode: onPlayEpisode,
        ),
      UnifiedMediaLibraryContentType.dandanplay => DandanplayRemoteLibraryView(
          onPlayEpisode: onPlayEpisode,
        ),
      UnifiedMediaLibraryContentType.networkServer => NetworkMediaLibraryView(
          serverType: section.server == UnifiedMediaLibraryServer.jellyfin
              ? NetworkMediaServerType.jellyfin
              : NetworkMediaServerType.emby,
          onPlayEpisode: onPlayEpisode,
        ),
    };
  }

  LibraryManagementSection _desktopManagementSource(
    UnifiedMediaLibrarySource source,
  ) {
    return switch (source) {
      UnifiedMediaLibrarySource.local => LibraryManagementSection.local,
      UnifiedMediaLibrarySource.webdav => LibraryManagementSection.webdav,
      UnifiedMediaLibrarySource.smb => LibraryManagementSection.smb,
    };
  }
}

class _DesktopMediaLibraryScaffold extends material.StatelessWidget {
  const _DesktopMediaLibraryScaffold({
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.onSectionOrderChanged,
    required this.onRemoteAccess,
    required this.onAddMedia,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
  final material.ValueChanged<List<String>> onSectionOrderChanged;
  final material.VoidCallback onRemoteAccess;
  final material.VoidCallback onAddMedia;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    final isDark =
        material.Theme.of(context).brightness == material.Brightness.dark;
    final idleColor =
        isDark ? material.Colors.white60 : material.Colors.black54;
    return material.Column(
      children: [
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(6, 12, 32, 0),
          child: material.Row(
            crossAxisAlignment: material.CrossAxisAlignment.end,
            children: [
              material.Expanded(
                child: material.SingleChildScrollView(
                  scrollDirection: material.Axis.horizontal,
                  child: material.Row(
                    children: [
                      for (final section in sections)
                        _DesktopSectionButton(
                          section: section,
                          selected: section.id == selectedSection.id,
                          onPressed: () => onSectionSelected(section.id),
                        ),
                    ],
                  ),
                ),
              ),
              const material.SizedBox(width: 8),
              HoverScaleTextButton(
                onPressed: () => _showSectionOrderEditor(
                  context,
                  sections,
                  onSectionOrderChanged,
                ),
                idleColor: idleColor,
                hoverColor: AppAccentColors.current,
                padding: material.EdgeInsets.zero,
                child: const material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Icon(material.Icons.swap_vert, size: 18),
                    material.SizedBox(width: 6),
                    material.Text(
                      '排序',
                      style: material.TextStyle(
                        fontSize: 18,
                        fontWeight: material.FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const material.SizedBox(width: 12),
              HoverScaleTextButton(
                onPressed: onRemoteAccess,
                idleColor: idleColor,
                hoverColor: AppAccentColors.current,
                padding: material.EdgeInsets.zero,
                child: const material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Icon(material.Icons.link, size: 18),
                    material.SizedBox(width: 6),
                    material.Text('远程访问',
                        style: material.TextStyle(
                            fontSize: 18,
                            fontWeight: material.FontWeight.bold)),
                  ],
                ),
              ),
              const material.SizedBox(width: 12),
              HoverScaleTextButton(
                onPressed: onAddMedia,
                idleColor: idleColor,
                hoverColor: AppAccentColors.current,
                padding: material.EdgeInsets.zero,
                child: const material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    material.Icon(material.Icons.add_to_queue_outlined,
                        size: 18),
                    material.SizedBox(width: 6),
                    material.Text('添加媒体',
                        style: material.TextStyle(
                            fontSize: 18,
                            fontWeight: material.FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const material.SizedBox(height: 8),
        material.Expanded(child: child),
      ],
    );
  }
}

class _DesktopSectionButton extends material.StatelessWidget {
  const _DesktopSectionButton({
    required this.section,
    required this.selected,
    required this.onPressed,
  });

  final UnifiedMediaLibrarySection section;
  final bool selected;
  final material.VoidCallback onPressed;

  @override
  material.Widget build(material.BuildContext context) {
    const labelStyle = material.TextStyle(
      fontSize: 18,
      fontWeight: material.FontWeight.w600,
    );
    final color = selected
        ? AppAccentColors.current
        : material.Theme.of(context)
            .colorScheme
            .onSurface
            .withValues(alpha: 0.58);
    return material.Padding(
      padding: const material.EdgeInsets.symmetric(horizontal: 4),
      child: HoverScaleTextButton(
        onPressed: onPressed,
        idleColor: color,
        hoverColor: AppAccentColors.current,
        padding: const material.EdgeInsets.fromLTRB(10, 8, 10, 12),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Row(
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Icon(_mediaLibrarySectionIcon(section), size: 18),
                const material.SizedBox(width: 7),
                material.Text(section.label, style: labelStyle),
              ],
            ),
            const material.SizedBox(height: 8),
            NipaplayLabelTabIndicator(
              label: section.label,
              labelStyle: labelStyle,
              selected: selected,
            ),
          ],
        ),
      ),
    );
  }
}

material.IconData _mediaLibrarySectionIcon(
  UnifiedMediaLibrarySection section,
) {
  return switch (section.contentType) {
    UnifiedMediaLibraryContentType.mediaCollection =>
      material.Icons.video_library_outlined,
    UnifiedMediaLibraryContentType.libraryManagement =>
      material.Icons.folder_open_outlined,
    UnifiedMediaLibraryContentType.sharedCollection =>
      material.Icons.devices_other_outlined,
    UnifiedMediaLibraryContentType.sharedManagement =>
      material.Icons.settings_suggest_outlined,
    UnifiedMediaLibraryContentType.dandanplay =>
      material.Icons.live_tv_outlined,
    UnifiedMediaLibraryContentType.networkServer => material.Icons.dns_outlined,
  };
}

class _CupertinoMediaLibraryScaffold extends material.StatelessWidget {
  const _CupertinoMediaLibraryScaffold({
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.onSectionOrderChanged,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
  final material.ValueChanged<List<String>> onSectionOrderChanged;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    return material.ColoredBox(
      color: material.Colors.transparent,
      child: material.Column(
        children: [
          const CupertinoAppPageHeader(title: '媒体库', bottomPadding: 8),
          const material.SizedBox(height: 8),
          material.Padding(
            padding: const material.EdgeInsets.symmetric(horizontal: 20),
            child: material.Row(
              children: [
                material.Expanded(
                  child: material.Align(
                    alignment: material.Alignment.centerLeft,
                    child: CupertinoMediaLibrarySectionPicker(
                      sections: sections,
                      selectedId: selectedSection.id,
                      onSelected: onSectionSelected,
                    ),
                  ),
                ),
                cupertino.CupertinoButton(
                  padding: const material.EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => _showSectionOrderEditor(
                    context,
                    sections,
                    onSectionOrderChanged,
                  ),
                  child: const material.Row(
                    mainAxisSize: material.MainAxisSize.min,
                    children: [
                      material.Icon(cupertino.CupertinoIcons.sort_down,
                          size: 18),
                      material.SizedBox(width: 4),
                      material.Text('排序'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const material.SizedBox(height: 4),
          material.Expanded(child: child),
        ],
      ),
    );
  }
}

Future<void> _showSectionOrderEditor(
  material.BuildContext context,
  List<UnifiedMediaLibrarySection> sections,
  material.ValueChanged<List<String>> onSectionOrderChanged,
) async {
  final result = await showAdaptiveMediaLibrarySectionOrder(context, sections);
  if (result != null) {
    onSectionOrderChanged(result);
  }
}

Future<List<String>?> showAdaptiveMediaLibrarySectionOrder(
  material.BuildContext context,
  List<UnifiedMediaLibrarySection> sections,
) {
  if (_useTelevisionMediaLibraryLayout(context)) {
    return NipaplayLargeScreenViewContainer.show<List<String>>(
      context: context,
      title: '媒体库顺序',
      subtitle: '使用每一行右侧的按钮调整位置',
      maxWidth: 820,
      maxHeightFactor: 0.82,
      builder: (_) => _TelevisionMediaLibrarySectionOrderEditor(
        sections: sections,
      ),
    );
  }
  if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
    return CupertinoBottomSheet.show<List<String>>(
      context: context,
      title: '媒体库排序',
      heightRatio: 0.72,
      child: material.Localizations.override(
        context: context,
        delegates: const <material.LocalizationsDelegate<dynamic>>[
          material.DefaultMaterialLocalizations.delegate,
        ],
        child: _MediaLibrarySectionOrderEditor(
          sections: sections,
          isPhone: true,
        ),
      ),
    );
  }

  return showInViewDialog<List<String>>(
    context: context,
    builder: (dialogContext) {
      final viewport = material.MediaQuery.sizeOf(dialogContext);
      final maximumWidth = (viewport.width - 96).clamp(0.0, 720.0);
      final minimumWidth = maximumWidth.clamp(0.0, 640.0);
      final dialogWidth = (viewport.width * 0.64).clamp(
        minimumWidth,
        maximumWidth,
      );
      final maximumHeight = (viewport.height * 0.72).clamp(0.0, 600.0);
      final desiredHeight = 128.0 + sections.length * 58.0;
      final dialogHeight = desiredHeight.clamp(0.0, maximumHeight);

      return material.AlertDialog(
        title: const material.Text('媒体库排序'),
        content: material.SizedBox(
          key: const material.ValueKey<String>(
            'media-library-order-dialog-content',
          ),
          width: dialogWidth,
          height: dialogHeight,
          child: _MediaLibrarySectionOrderEditor(sections: sections),
        ),
      );
    },
  );
}

class _TelevisionMediaLibrarySectionOrderEditor
    extends material.StatefulWidget {
  const _TelevisionMediaLibrarySectionOrderEditor({required this.sections});

  final List<UnifiedMediaLibrarySection> sections;

  @override
  material.State<_TelevisionMediaLibrarySectionOrderEditor> createState() =>
      _TelevisionMediaLibrarySectionOrderEditorState();
}

class _TelevisionMediaLibrarySectionOrderEditorState
    extends material.State<_TelevisionMediaLibrarySectionOrderEditor> {
  late List<UnifiedMediaLibrarySection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = List<UnifiedMediaLibrarySection>.of(widget.sections);
  }

  void _move(int index, int delta) {
    final nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= _sections.length) return;
    setState(() {
      final section = _sections.removeAt(index);
      _sections.insert(nextIndex, section);
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    return material.Padding(
      padding: const material.EdgeInsets.fromLTRB(22, 20, 22, 22),
      child: material.Column(
        children: [
          material.Expanded(
            child: material.ListView.separated(
              itemCount: _sections.length,
              separatorBuilder: (_, __) => const material.SizedBox(height: 10),
              itemBuilder: (context, index) {
                final section = _sections[index];
                return NipaplayLargeScreenPanel(
                  padding: const material.EdgeInsets.fromLTRB(16, 9, 9, 9),
                  child: material.Row(
                    children: [
                      material.Icon(
                        _mediaLibrarySectionIcon(section),
                        size: 24,
                      ),
                      const material.SizedBox(width: 13),
                      material.Expanded(
                        child: material.Text(
                          section.label,
                          style: const material.TextStyle(
                            fontSize: 16,
                            fontWeight: material.FontWeight.w800,
                          ),
                        ),
                      ),
                      NipaplayLargeScreenIconButton(
                        icon: material.Icons.arrow_upward_rounded,
                        tooltip: '上移 ${section.label}',
                        onPressed: index == 0 ? null : () => _move(index, -1),
                      ),
                      const material.SizedBox(width: 8),
                      NipaplayLargeScreenIconButton(
                        icon: material.Icons.arrow_downward_rounded,
                        tooltip: '下移 ${section.label}',
                        onPressed: index == _sections.length - 1
                            ? null
                            : () => _move(index, 1),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const material.SizedBox(height: 16),
          material.Align(
            alignment: material.Alignment.centerRight,
            child: NipaplayLargeScreenActionButton(
              icon: material.Icons.check_rounded,
              label: '保存顺序',
              onPressed: () => material.Navigator.of(context).pop(
                _sections.map((section) => section.id).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MediaLibrarySectionOrderEditor extends material.StatefulWidget {
  const _MediaLibrarySectionOrderEditor({
    required this.sections,
    this.isPhone = false,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final bool isPhone;

  @override
  material.State<_MediaLibrarySectionOrderEditor> createState() =>
      _MediaLibrarySectionOrderEditorState();
}

class _MediaLibrarySectionOrderEditorState
    extends material.State<_MediaLibrarySectionOrderEditor> {
  late List<UnifiedMediaLibrarySection> _sections;

  @override
  void initState() {
    super.initState();
    _sections = List<UnifiedMediaLibrarySection>.of(widget.sections);
  }

  void _reorder(int oldIndex, int newIndex) {
    final reorderedIds = reorderMediaLibrarySectionIds(
      _sections.map((section) => section.id).toList(),
      oldIndex,
      newIndex,
    );
    final sectionsById = <String, UnifiedMediaLibrarySection>{
      for (final section in _sections) section.id: section,
    };
    setState(() {
      _sections = [for (final id in reorderedIds) sectionsById[id]!];
    });
  }

  @override
  material.Widget build(material.BuildContext context) {
    final foreground = widget.isPhone
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.label,
            context,
          )
        : material.Theme.of(context).colorScheme.onSurface;
    final background = widget.isPhone
        ? cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondarySystemGroupedBackground,
            context,
          )
        : material.Theme.of(context).colorScheme.surfaceContainerHighest;

    return material.Column(
      children: [
        material.Expanded(
          child: material.ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: _sections.length,
            onReorder: _reorder,
            itemBuilder: (context, index) {
              final section = _sections[index];
              return material.Padding(
                key: material.ValueKey<String>(
                  'media-library-order-row-${section.id}',
                ),
                padding: const material.EdgeInsets.only(bottom: 6),
                child: material.DecoratedBox(
                  decoration: material.BoxDecoration(
                    color: background,
                    borderRadius: material.BorderRadius.circular(10),
                  ),
                  child: material.ReorderableDragStartListener(
                    key: material.ValueKey<String>(
                      'media-library-order-drag-${section.id}',
                    ),
                    index: index,
                    child: material.SizedBox(
                      height: 52,
                      child: material.Padding(
                        padding: const material.EdgeInsets.symmetric(
                          horizontal: 14,
                        ),
                        child: material.Row(
                          children: [
                            material.Expanded(
                              child: material.Text(
                                section.label,
                                style: material.TextStyle(
                                  color: foreground,
                                  fontSize: 16,
                                  fontWeight: material.FontWeight.w600,
                                ),
                              ),
                            ),
                            material.Icon(
                              material.Icons.drag_handle,
                              color: foreground.withValues(alpha: 0.55),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const material.SizedBox(height: 10),
        if (widget.isPhone)
          material.Padding(
            padding: const material.EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: material.SizedBox(
              width: double.infinity,
              child: cupertino.CupertinoButton.filled(
                onPressed: () => material.Navigator.of(context).pop(
                  _sections.map((section) => section.id).toList(),
                ),
                child: const material.Text('保存'),
              ),
            ),
          )
        else
          material.Align(
            alignment: material.Alignment.centerRight,
            child: material.TextButton(
              onPressed: () => material.Navigator.of(context).pop(
                _sections.map((section) => section.id).toList(),
              ),
              child: const material.Text('保存'),
            ),
          ),
      ],
    );
  }
}

Future<String?> showAdaptiveMediaSourcePicker(material.BuildContext context) {
  final options = availableMediaSourceOptions(
    isTelevision: globals.isTelevision,
  );
  if (_useTelevisionMediaLibraryLayout(context)) {
    return NipaplayLargeScreenViewContainer.show<String>(
      context: context,
      title: '添加媒体',
      subtitle: '选择要连接的媒体来源',
      maxWidth: 960,
      maxHeightFactor: 0.82,
      autofocusClose: false,
      builder: (_) => _TelevisionMediaSourcePicker(options: options),
    );
  }
  if (AppDisplaySurfaceScope.of(context) != AppDisplaySurface.phone) {
    return MediaServerSelectionSheet.show(
      context,
      options: options,
    );
  }

  return CupertinoMediaSourceSheet.show(
    context,
    options: options,
  );
}

class _TelevisionMediaSourcePicker extends material.StatelessWidget {
  const _TelevisionMediaSourcePicker({required this.options});

  final List<MediaSourceOption> options;

  @override
  material.Widget build(material.BuildContext context) {
    final textColor = material.Theme.of(context).colorScheme.onSurface;
    return material.SingleChildScrollView(
      padding: const material.EdgeInsets.fromLTRB(24, 20, 24, 28),
      child: material.Column(
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          for (final category in MediaSourceCategory.values)
            if (options.any(
              (option) => option.category == category,
            )) ...[
              material.Text(
                category.label,
                style: material.TextStyle(
                  color: textColor.withValues(alpha: 0.68),
                  fontSize: 15,
                  fontWeight: material.FontWeight.w800,
                ),
              ),
              const material.SizedBox(height: 10),
              material.LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 12.0;
                  final itemWidth = (constraints.maxWidth - spacing) / 2;
                  final categoryOptions = options
                      .where((option) => option.category == category)
                      .toList(growable: false);
                  return material.Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final option in categoryOptions)
                        material.SizedBox(
                          width: itemWidth,
                          child: NipaplayLargeScreenFocusableAction(
                            autofocus: option == options.first,
                            onActivate: () =>
                                material.Navigator.of(context).pop(option.id),
                            borderRadius: material.BorderRadius.circular(10),
                            focusScale: 1.025,
                            padding: const material.EdgeInsets.all(16),
                            child: material.Row(
                              children: [
                                material.Icon(
                                  _mediaSourceIcon(option.iconKind),
                                  size: 32,
                                  color: AppAccentColors.current,
                                ),
                                const material.SizedBox(width: 14),
                                material.Expanded(
                                  child: material.Column(
                                    crossAxisAlignment:
                                        material.CrossAxisAlignment.start,
                                    children: [
                                      material.Text(
                                        option.title,
                                        style: const material.TextStyle(
                                          fontSize: 16,
                                          fontWeight: material.FontWeight.w900,
                                        ),
                                      ),
                                      const material.SizedBox(height: 4),
                                      material.Text(
                                        option.subtitle,
                                        maxLines: 1,
                                        overflow:
                                            material.TextOverflow.ellipsis,
                                        style: material.TextStyle(
                                          color: textColor.withValues(
                                            alpha: 0.62,
                                          ),
                                          fontSize: 13,
                                          fontWeight: material.FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const material.SizedBox(width: 8),
                                const material.Icon(
                                  material.Icons.chevron_right_rounded,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const material.SizedBox(height: 20),
            ],
        ],
      ),
    );
  }
}

material.IconData _mediaSourceIcon(MediaSourceIconKind kind) {
  return switch (kind) {
    MediaSourceIconKind.localFolder => material.Icons.folder_open_rounded,
    MediaSourceIconKind.nipaplay => material.Icons.devices_rounded,
    MediaSourceIconKind.jellyfin => material.Icons.movie_filter_rounded,
    MediaSourceIconKind.dandanplay => material.Icons.live_tv_rounded,
    MediaSourceIconKind.emby => material.Icons.video_library_rounded,
    MediaSourceIconKind.webdav => material.Icons.cloud_rounded,
    MediaSourceIconKind.smb => material.Icons.lan_rounded,
  };
}

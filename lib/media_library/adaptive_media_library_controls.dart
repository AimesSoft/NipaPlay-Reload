import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/unified_media_library_sections.dart';
import 'package:nipaplay/media_library/adaptive_media_collection_view.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_library_section_picker.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_header.dart';
import 'package:nipaplay/themes/nipaplay/widgets/dandanplay_remote_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_tab.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_server_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_library_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_library_view.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class AdaptiveMediaLibraryScaffold extends material.StatelessWidget {
  const AdaptiveMediaLibraryScaffold({
    super.key,
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.onRemoteAccess,
    required this.onAddMedia,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
  final material.VoidCallback onRemoteAccess;
  final material.VoidCallback onAddMedia;
  final material.Widget child;

  @override
  material.Widget build(material.BuildContext context) {
    return switch (AppDisplaySurfaceScope.of(context)) {
      AppDisplaySurface.phone => _CupertinoMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: onSectionSelected,
          child: child,
        ),
      AppDisplaySurface.desktopTablet ||
      AppDisplaySurface.television =>
        _DesktopMediaLibraryScaffold(
          sections: sections,
          selectedSection: selectedSection,
          onSectionSelected: onSectionSelected,
          onRemoteAccess: onRemoteAccess,
          onAddMedia: onAddMedia,
          child: child,
        ),
    };
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
    required this.onRemoteAccess,
    required this.onAddMedia,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
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
                material.Icon(_desktopIcon(section), size: 18),
                const material.SizedBox(width: 7),
                material.Text(section.label,
                    style: const material.TextStyle(
                        fontSize: 18, fontWeight: material.FontWeight.w600)),
              ],
            ),
            const material.SizedBox(height: 8),
            material.AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? 32 : 0,
              height: 3,
              decoration: material.BoxDecoration(
                color: AppAccentColors.current,
                borderRadius: material.BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  material.IconData _desktopIcon(UnifiedMediaLibrarySection section) {
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
      UnifiedMediaLibraryContentType.networkServer =>
        material.Icons.dns_outlined,
    };
  }
}

class _CupertinoMediaLibraryScaffold extends material.StatelessWidget {
  const _CupertinoMediaLibraryScaffold({
    required this.sections,
    required this.selectedSection,
    required this.onSectionSelected,
    required this.child,
  });

  final List<UnifiedMediaLibrarySection> sections;
  final UnifiedMediaLibrarySection selectedSection;
  final material.ValueChanged<String> onSectionSelected;
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
            child: material.Align(
              alignment: material.Alignment.centerLeft,
              child: CupertinoMediaLibrarySectionPicker(
                sections: sections,
                selectedId: selectedSection.id,
                onSelected: onSectionSelected,
              ),
            ),
          ),
          const material.SizedBox(height: 4),
          material.Expanded(child: child),
        ],
      ),
    );
  }
}

Future<String?> showAdaptiveMediaSourcePicker(material.BuildContext context) {
  if (AppDisplaySurfaceScope.of(context) != AppDisplaySurface.phone) {
    return MediaServerSelectionSheet.show(context);
  }

  return cupertino.showCupertinoModalPopup<String>(
    context: context,
    builder: (sheetContext) => cupertino.CupertinoActionSheet(
      title: const material.Text('添加媒体'),
      actions: [
        _mediaSourceAction(sheetContext, 'local_folder', '本地文件夹'),
        _mediaSourceAction(sheetContext, 'nipaplay', 'NipaPlay 共享媒体库'),
        _mediaSourceAction(sheetContext, 'jellyfin', 'Jellyfin'),
        _mediaSourceAction(sheetContext, 'emby', 'Emby'),
        _mediaSourceAction(sheetContext, 'dandanplay', '弹弹play'),
        _mediaSourceAction(sheetContext, 'webdav', 'WebDAV'),
        _mediaSourceAction(sheetContext, 'smb', 'SMB'),
      ],
      cancelButton: cupertino.CupertinoActionSheetAction(
        onPressed: () => material.Navigator.of(sheetContext).pop(),
        child: const material.Text('取消'),
      ),
    ),
  );
}

cupertino.CupertinoActionSheetAction _mediaSourceAction(
  material.BuildContext context,
  String id,
  String label,
) {
  return cupertino.CupertinoActionSheetAction(
    onPressed: () => material.Navigator.of(context).pop(id),
    child: material.Text(label),
  );
}

import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart' as material;
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_library_management_overview.dart';
import 'package:nipaplay/themes/nipaplay/widgets/library_management_layout.dart';
import 'package:provider/provider.dart';

class AdaptiveLibraryManagementOverview extends material.StatelessWidget {
  const AdaptiveLibraryManagementOverview({
    super.key,
    required this.items,
    required this.viewMode,
    required this.emptyContent,
  });

  final List<UnifiedLibraryManagementItem> items;
  final LibraryManagementViewMode viewMode;
  final LibraryManagementEmptyContent emptyContent;

  @override
  material.Widget build(material.BuildContext context) {
    return switch (AppDisplaySurfaceScope.of(context)) {
      AppDisplaySurface.phone => CupertinoLibraryManagementOverview(
          items: items,
          viewMode: viewMode,
          emptyTitle: emptyContent.title,
          emptySubtitle: emptyContent.subtitle,
        ),
      AppDisplaySurface.desktopTablet ||
      AppDisplaySurface.television =>
        _DesktopLibraryManagementOverview(
          items: items,
          viewMode: viewMode,
          emptyContent: emptyContent,
        ),
    };
  }
}

class _DesktopLibraryManagementOverview extends material.StatelessWidget {
  const _DesktopLibraryManagementOverview({
    required this.items,
    required this.viewMode,
    required this.emptyContent,
  });

  final List<UnifiedLibraryManagementItem> items;
  final LibraryManagementViewMode viewMode;
  final LibraryManagementEmptyContent emptyContent;

  @override
  material.Widget build(material.BuildContext context) {
    if (items.isEmpty) {
      return LibraryManagementEmptyState(
        icon: _desktopIcon(LibraryManagementIcon.folder),
        title: emptyContent.title,
        subtitle: emptyContent.subtitle,
      );
    }

    return LibraryManagementList<UnifiedLibraryManagementItem>(
      items: items,
      viewMode: viewMode,
      minItemWidth: 320,
      padding: const material.EdgeInsets.fromLTRB(16, 10, 16, 24),
      itemBuilder: (context, item) => _DesktopManagementItem(item: item),
    );
  }
}

class _DesktopManagementItem extends material.StatelessWidget {
  const _DesktopManagementItem({required this.item});

  final UnifiedLibraryManagementItem item;

  @override
  material.Widget build(material.BuildContext context) {
    final colors = material.Theme.of(context).colorScheme;
    final secondary = colors.onSurface.withValues(alpha: 0.58);
    // 根据外观设置决定目录名是省略号截断还是多行完整显示
    final appearance = context.watch<AppearanceSettingsProvider>();
    final enabledActions = item.actions
        .where((action) => action.onPressed != null)
        .toList(growable: false);

    return LibraryManagementCard(
      child: material.MouseRegion(
        cursor: item.onOpen == null
            ? material.SystemMouseCursors.basic
            : material.SystemMouseCursors.click,
        child: material.GestureDetector(
          behavior: material.HitTestBehavior.opaque,
          onTap: item.onOpen,
          child: material.Padding(
            padding: const material.EdgeInsets.fromLTRB(14, 12, 12, 12),
            child: material.Column(
              crossAxisAlignment: material.CrossAxisAlignment.start,
              mainAxisSize: material.MainAxisSize.min,
              children: [
                material.Row(
                  children: [
                    material.Icon(
                      _desktopIcon(item.icon),
                      size: 26,
                      color: colors.onSurface.withValues(alpha: 0.72),
                    ),
                    const material.SizedBox(width: 12),
                    material.Expanded(
                      child: material.Column(
                        crossAxisAlignment: material.CrossAxisAlignment.start,
                        mainAxisSize: material.MainAxisSize.min,
                        children: [
                          material.Text(
                            item.title,
                            maxLines: appearance.folderNameMaxLines,
                            overflow: appearance.folderNameOverflow,
                            style: const material.TextStyle(
                              fontSize: 15,
                              fontWeight: material.FontWeight.w600,
                            ),
                          ),
                          const material.SizedBox(height: 3),
                          material.Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: material.TextOverflow.ellipsis,
                            style: material.TextStyle(
                              fontSize: 12,
                              color: secondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.status != null) ...[
                      const material.SizedBox(width: 10),
                      material.Text(
                        item.status!,
                        style: material.TextStyle(
                          fontSize: 12,
                          color: secondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (enabledActions.isNotEmpty) ...[
                  const material.SizedBox(height: 8),
                  material.Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final action in enabledActions)
                        AdaptiveMediaActionButton(
                          desktopIcon: _desktopIcon(action.icon),
                          phoneIcon: _phoneFallbackIcon(action.icon),
                          label: action.label,
                          compact: true,
                          emphasis: action.destructive
                              ? AdaptiveMediaActionEmphasis.destructive
                              : AdaptiveMediaActionEmphasis.plain,
                          onPressed: action.onPressed,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

material.IconData _desktopIcon(LibraryManagementIcon icon) {
  return switch (icon) {
    LibraryManagementIcon.folder => material.Icons.folder_outlined,
    LibraryManagementIcon.video => material.Icons.videocam_outlined,
    LibraryManagementIcon.file => material.Icons.insert_drive_file_outlined,
    LibraryManagementIcon.cloud => material.Icons.cloud_outlined,
    LibraryManagementIcon.server => material.Icons.dns_outlined,
    LibraryManagementIcon.browse => material.Icons.folder_open_outlined,
    LibraryManagementIcon.refresh => material.Icons.refresh,
    LibraryManagementIcon.scan => material.Icons.auto_fix_high,
    LibraryManagementIcon.info => material.Icons.info_outline,
    LibraryManagementIcon.subtitles => material.Icons.subtitles_outlined,
    LibraryManagementIcon.edit => material.Icons.edit_outlined,
    LibraryManagementIcon.delete => material.Icons.delete_outline,
  };
}

material.IconData _phoneFallbackIcon(LibraryManagementIcon icon) {
  return switch (icon) {
    LibraryManagementIcon.folder => cupertino.CupertinoIcons.folder,
    LibraryManagementIcon.video => cupertino.CupertinoIcons.play_rectangle,
    LibraryManagementIcon.file => cupertino.CupertinoIcons.doc,
    LibraryManagementIcon.cloud => cupertino.CupertinoIcons.cloud,
    LibraryManagementIcon.server => cupertino.CupertinoIcons.desktopcomputer,
    LibraryManagementIcon.browse => cupertino.CupertinoIcons.folder_open,
    LibraryManagementIcon.refresh => cupertino.CupertinoIcons.refresh,
    LibraryManagementIcon.scan => cupertino.CupertinoIcons.sparkles,
    LibraryManagementIcon.info => cupertino.CupertinoIcons.info,
    LibraryManagementIcon.subtitles => cupertino.CupertinoIcons.captions_bubble,
    LibraryManagementIcon.edit => cupertino.CupertinoIcons.pencil,
    LibraryManagementIcon.delete => cupertino.CupertinoIcons.delete,
  };
}

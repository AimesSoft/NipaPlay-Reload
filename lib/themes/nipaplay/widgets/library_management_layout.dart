import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

const double _libraryManagementTreeBaseIndent = 12.0;
const double _libraryManagementTreeIndentStep = 16.0;

double libraryManagementTreeIndent(int depth) {
  return _libraryManagementTreeBaseIndent +
      depth * _libraryManagementTreeIndentStep;
}

class LibraryManagementCard extends StatelessWidget {
  const LibraryManagementCard({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color borderColor =
        isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.1);
    final Color bgColor = isDark
        ? Colors.white.withOpacity(0.05)
        : Colors.black.withOpacity(0.03);

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: borderColor,
          width: 0.5,
        ),
      ),
      child: child,
    );
  }
}

class LibraryManagementEmptyState extends StatelessWidget {
  const LibraryManagementEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final bool isDark = theme.brightness == Brightness.dark;
    final Color iconColor = onSurface.withOpacity(isDark ? 0.55 : 0.4);
    final Color titleColor = onSurface.withOpacity(isDark ? 0.75 : 0.7);
    final Color subtitleColor = onSurface.withOpacity(isDark ? 0.6 : 0.55);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: iconColor),
            SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(color: titleColor, fontSize: 16),
            ),
            if (subtitle != null) ...[
              SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: subtitleColor, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class LibraryManagementList<T> extends StatelessWidget {
  const LibraryManagementList({
    super.key,
    required this.items,
    required this.itemBuilder,
    this.scrollController,
    this.minItemWidth = 300.0,
    this.spacing = 16.0,
    this.padding = const EdgeInsets.all(8),
    this.viewMode = LibraryManagementViewMode.icons,
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final ScrollController? scrollController;
  final double minItemWidth;
  final double spacing;
  final EdgeInsets padding;
  final LibraryManagementViewMode viewMode;

  @override
  Widget build(BuildContext context) {
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return ListView.builder(
        controller: scrollController,
        padding: padding,
        itemCount: items.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: itemBuilder(context, items[index]),
          );
        },
      );
    }

    if (viewMode == LibraryManagementViewMode.list) {
      return AdaptiveMediaScrollbar(
        controller: scrollController,
        child: ListView.builder(
          controller: scrollController,
          padding: padding,
          itemCount: items.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: itemBuilder(context, items[index]),
          ),
        ),
      );
    }

    return AdaptiveMediaScrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth - 16.0;
            final crossAxisCount =
                (availableWidth / minItemWidth).floor().clamp(1, 3);

            final columnItems = List.generate(crossAxisCount, (_) => <T>[]);
            for (var i = 0; i < items.length; i++) {
              columnItems[i % crossAxisCount].add(items[i]);
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(crossAxisCount, (colIndex) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: colIndex < crossAxisCount - 1 ? spacing : 0,
                    ),
                    child: Column(
                      children: columnItems[colIndex]
                          .map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: itemBuilder(context, item),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

class LibraryManagementFolderRow extends StatelessWidget {
  const LibraryManagementFolderRow({
    super.key,
    required this.title,
    required this.expanded,
    required this.loading,
    required this.onTap,
    this.indent = 0.0,
    this.leadingIcon = Ionicons.folder_outline,
    this.iconColor,
    this.textColor,
    this.secondaryTextColor,
    this.locale,
    this.trailingActions,
  });

  final String title;
  final bool expanded;
  final bool loading;
  final VoidCallback onTap;
  final double indent;
  final IconData leadingIcon;
  final Color? iconColor;
  final Color? textColor;
  final Color? secondaryTextColor;
  final Locale? locale;
  final List<Widget>? trailingActions;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color resolvedTextColor =
        textColor ?? (isDark ? Colors.white : Colors.black87);
    final Color resolvedSecondaryTextColor =
        secondaryTextColor ?? (isDark ? Colors.white70 : Colors.black54);
    final Color resolvedIconColor = iconColor ?? resolvedSecondaryTextColor;
    // 根据外观设置决定目录名是省略号截断还是多行完整显示
    final appearance = context.watch<AppearanceSettingsProvider>();

    final content = Padding(
      padding: EdgeInsets.fromLTRB(indent, 7, 8, 7),
      child: Row(
        children: [
          Icon(leadingIcon, color: resolvedIconColor, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              locale: locale,
              style: TextStyle(color: resolvedTextColor, fontSize: 13),
              maxLines: appearance.folderNameMaxLines,
              overflow: appearance.folderNameOverflow,
            ),
          ),
          if (loading)
            SizedBox(
              width: 14,
              height: 14,
              child: AdaptiveMediaActivityIndicator(
                size: 14,
                color: AppAccentColors.current,
              ),
            )
          else ...[
            if (trailingActions != null) ...trailingActions!,
            Icon(
              expanded
                  ? Ionicons.chevron_down_outline
                  : Ionicons.chevron_forward,
              color: resolvedSecondaryTextColor,
              size: 16,
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone
          ? cupertino.CupertinoButton(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(8),
              onPressed: onTap,
              child: content,
            )
          : MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTap,
                child: content,
              ),
            ),
    );
  }
}

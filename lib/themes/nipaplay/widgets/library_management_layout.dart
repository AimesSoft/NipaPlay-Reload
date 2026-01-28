import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart';

const double _libraryManagementTreeBaseIndent = 12.0;
const double _libraryManagementTreeIndentStep = 16.0;

double libraryManagementTreeIndent(int depth) {
  return _libraryManagementTreeBaseIndent + depth * _libraryManagementTreeIndentStep;
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
    final Color bgColor =
        isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03);

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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.white54),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 13),
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
  });

  final List<T> items;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final ScrollController? scrollController;
  final double minItemWidth;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    if (isPhone) {
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

    return Scrollbar(
      controller: scrollController,
      radius: const Radius.circular(2),
      thickness: 4,
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

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color resolvedTextColor =
        textColor ?? (isDark ? Colors.white : Colors.black87);
    final Color resolvedSecondaryTextColor =
        secondaryTextColor ?? (isDark ? Colors.white70 : Colors.black54);
    final Color resolvedIconColor = iconColor ?? resolvedSecondaryTextColor;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: ListTile(
        dense: true,
        contentPadding: EdgeInsets.fromLTRB(indent, 0, 8, 0),
        leading: Icon(leadingIcon, color: resolvedIconColor, size: 18),
        title: Text(
          title,
          locale: locale,
          style: TextStyle(color: resolvedTextColor, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: loading
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: resolvedIconColor,
                ),
              )
            : Icon(
                expanded
                    ? Ionicons.chevron_down_outline
                    : Ionicons.chevron_forward,
                color: resolvedSecondaryTextColor,
                size: 16,
              ),
        onTap: onTap,
      ),
    );
  }
}

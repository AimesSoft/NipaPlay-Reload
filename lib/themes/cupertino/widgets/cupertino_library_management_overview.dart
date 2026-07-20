import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:provider/provider.dart';

class CupertinoLibraryManagementOverview extends StatelessWidget {
  const CupertinoLibraryManagementOverview({
    super.key,
    required this.items,
    required this.viewMode,
    required this.emptyTitle,
    required this.emptySubtitle,
  });

  final List<UnifiedLibraryManagementItem> items;
  final LibraryManagementViewMode viewMode;
  final String emptyTitle;
  final String emptySubtitle;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final secondary = CupertinoDynamicColor.resolve(
        CupertinoColors.secondaryLabel,
        context,
      );
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(CupertinoIcons.folder, size: 46, color: secondary),
              const SizedBox(height: 12),
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: secondary, height: 1.35),
              ),
            ],
          ),
        ),
      );
    }

    return switch (viewMode) {
      LibraryManagementViewMode.icons => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 84),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.28,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) => _ManagementGridItem(
            item: items[index],
          ),
        ),
      LibraryManagementViewMode.list => ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 84),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _ManagementListItem(
            item: items[index],
          ),
        ),
    };
  }
}

class _ManagementGridItem extends StatelessWidget {
  const _ManagementGridItem({required this.item});

  final UnifiedLibraryManagementItem item;

  @override
  Widget build(BuildContext context) {
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final label = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    // 根据外观设置决定目录名是省略号截断还是多行完整显示
    final appearance = context.watch<AppearanceSettingsProvider>();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: item.onOpen,
      onLongPress:
          item.actions.isEmpty ? null : () => _showActions(context, item),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(_phoneIcon(item.icon), size: 28, color: label),
                  const Spacer(),
                  if (item.actions.isNotEmpty)
                    CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size.square(30),
                      onPressed: () => _showActions(context, item),
                      child: const Icon(CupertinoIcons.ellipsis, size: 18),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                item.title,
                maxLines: appearance.folderNameMaxLines,
                overflow: appearance.folderNameOverflow,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ).copyWith(color: label),
              ),
              const SizedBox(height: 3),
              Text(
                item.status ?? item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: secondary),
              ),
              if (item.matchSubtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  item.matchSubtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: CupertinoDynamicColor.resolve(
                      CupertinoColors.activeBlue,
                      context,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ManagementListItem extends StatelessWidget {
  const _ManagementListItem({required this.item});

  final UnifiedLibraryManagementItem item;

  @override
  Widget build(BuildContext context) {
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.secondarySystemGroupedBackground,
      context,
    );
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final label = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    // 根据外观设置决定目录名是省略号截断还是多行完整显示
    final appearance = context.watch<AppearanceSettingsProvider>();

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: const EdgeInsets.fromLTRB(14, 11, 8, 11),
              alignment: Alignment.centerLeft,
              borderRadius: BorderRadius.circular(8),
              onPressed: item.onOpen,
              child: Row(
                children: [
                  Icon(_phoneIcon(item.icon), size: 24, color: label),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: appearance.folderNameMaxLines,
                          overflow: appearance.folderNameOverflow,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ).copyWith(color: label),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: secondary),
                        ),
                        if (item.matchSubtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.matchSubtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: CupertinoDynamicColor.resolve(
                                CupertinoColors.activeBlue,
                                context,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (item.status != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      item.status!,
                      style: TextStyle(fontSize: 11, color: secondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (item.actions.isNotEmpty)
            CupertinoButton(
              padding: const EdgeInsets.all(10),
              minimumSize: const Size.square(42),
              onPressed: () => _showActions(context, item),
              child: const Icon(CupertinoIcons.ellipsis_circle, size: 20),
            ),
        ],
      ),
    );
  }
}

Future<void> _showActions(
  BuildContext context,
  UnifiedLibraryManagementItem item,
) async {
  final enabled = item.actions.where((action) => action.onPressed != null);
  final selected =
      await CupertinoBottomSheet.showSelection<UnifiedLibraryManagementAction>(
    context: context,
    title: item.title,
    options: [
      for (final action in enabled)
        CupertinoBottomSheetOption(
          label: action.label,
          value: action,
          icon: _phoneIcon(action.icon),
          destructive: action.destructive,
        ),
    ],
  );
  selected?.onPressed?.call();
}

IconData _phoneIcon(LibraryManagementIcon icon) {
  return switch (icon) {
    LibraryManagementIcon.folder => CupertinoIcons.folder_fill,
    LibraryManagementIcon.video => CupertinoIcons.play_rectangle_fill,
    LibraryManagementIcon.file => CupertinoIcons.doc_fill,
    LibraryManagementIcon.cloud => CupertinoIcons.cloud_fill,
    LibraryManagementIcon.server => CupertinoIcons.desktopcomputer,
    LibraryManagementIcon.browse => CupertinoIcons.folder_open,
    LibraryManagementIcon.refresh => CupertinoIcons.refresh,
    LibraryManagementIcon.scan => CupertinoIcons.sparkles,
    LibraryManagementIcon.info => CupertinoIcons.info,
    LibraryManagementIcon.subtitles => CupertinoIcons.captions_bubble,
    LibraryManagementIcon.edit => CupertinoIcons.pencil,
    LibraryManagementIcon.delete => CupertinoIcons.delete,
  };
}

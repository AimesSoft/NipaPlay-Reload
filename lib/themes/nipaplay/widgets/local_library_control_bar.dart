import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';

enum LocalLibrarySortType {
  name,
  dateAdded,
  rating,
}

class LocalLibraryActionControl extends StatelessWidget {
  const LocalLibraryActionControl({
    super.key,
    required this.label,
    required this.desktopIcon,
    required this.phoneIcon,
    required this.onPressed,
    this.isDestructive = false,
  });

  final String label;
  final IconData desktopIcon;
  final IconData phoneIcon;
  final VoidCallback? onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    return AdaptiveMediaIconButton(
      desktopIcon: desktopIcon,
      phoneIcon: phoneIcon,
      tooltip: label,
      color: isDestructive ? Colors.redAccent : null,
      onPressed: onPressed,
    );
  }
}

class LocalLibraryControlBar extends StatefulWidget {
  final Function(String) onSearchChanged;
  final LocalLibrarySortType? currentSort;
  final Function(LocalLibrarySortType)? onSortChanged;
  final VoidCallback? onClearSearch;
  final TextEditingController searchController;
  final bool showBackButton;
  final VoidCallback? onBack;
  final String? title;
  final bool showSort;
  final List<LocalLibraryActionControl>? trailingActions;
  final LibraryManagementViewMode? viewMode;
  final VoidCallback? onToggleViewMode;

  LocalLibraryControlBar({
    super.key,
    required this.onSearchChanged,
    this.currentSort,
    this.onSortChanged,
    required this.searchController,
    this.onClearSearch,
    this.showBackButton = false,
    this.onBack,
    this.title,
    this.showSort = true,
    this.trailingActions,
    this.viewMode,
    this.onToggleViewMode,
  });

  @override
  State<LocalLibraryControlBar> createState() => _LocalLibraryControlBarState();
}

class _LocalLibraryControlBarState extends State<LocalLibraryControlBar> {
  final GlobalKey _dropdownKey = GlobalKey();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      setState(() {}); // 刷新以更新描边颜色
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    assert(!widget.showSort ||
        (widget.currentSort != null && widget.onSortChanged != null));
    assert((widget.viewMode == null) == (widget.onToggleViewMode == null));
    if (AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone) {
      return _buildPhoneControlBar(context);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSort = widget.currentSort ?? LocalLibrarySortType.dateAdded;

    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 56, // 占据一行的高度
      child: Row(
        children: [
          if (widget.showBackButton) ...[
            SearchBarActionButton(
              icon: Ionicons.arrow_back,
              size: 24,
              color: primaryTextColor,
              tooltip: '返回',
              onPressed: widget.onBack,
            ),
            SizedBox(width: 12),
          ],
          if (widget.title != null && widget.title!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.25),
              child: Text(
                widget.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            SizedBox(width: 16),
          ],
          // 搜索框
          Expanded(
            child: AdaptiveMediaSearchField(
              controller: widget.searchController,
              focusNode: _searchFocusNode,
              placeholder: '搜索…',
              onChanged: widget.onSearchChanged,
              onClear: widget.onClearSearch,
            ),
          ),
          if (widget.viewMode != null) ...[
            const SizedBox(width: 10),
            SearchBarActionButton(
              icon: widget.viewMode == LibraryManagementViewMode.icons
                  ? Ionicons.list_outline
                  : Ionicons.grid_outline,
              size: 20,
              color: primaryTextColor,
              tooltip: widget.viewMode == LibraryManagementViewMode.icons
                  ? '切换到列表视图'
                  : '切换到图标视图',
              onPressed: widget.onToggleViewMode,
            ),
          ],
          if (widget.trailingActions != null &&
              widget.trailingActions!.isNotEmpty) ...[
            SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.trailingActions!
                  .expand((action) => [SizedBox(width: 8), action])
                  .skip(1)
                  .toList(),
            ),
          ],
          if (widget.showSort) ...[
            SizedBox(width: 12),
            // 排序按钮直接使用本体
            BlurDropdown<LocalLibrarySortType>(
              dropdownKey: _dropdownKey,
              onItemSelected: widget.onSortChanged!,
              items: [
                DropdownMenuItemData(
                  title: '最近观看',
                  value: LocalLibrarySortType.dateAdded,
                  isSelected: currentSort == LocalLibrarySortType.dateAdded,
                ),
                DropdownMenuItemData(
                  title: '名称排序',
                  value: LocalLibrarySortType.name,
                  isSelected: currentSort == LocalLibrarySortType.name,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhoneControlBar(BuildContext context) {
    final labelColor = cupertino.CupertinoDynamicColor.resolve(
      cupertino.CupertinoColors.label,
      context,
    );
    return SizedBox(
      height: 54,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(
          children: [
            if (widget.showBackButton) ...[
              cupertino.CupertinoButton(
                padding: const EdgeInsets.all(6),
                minimumSize: const Size.square(34),
                onPressed: widget.onBack,
                child: const Icon(cupertino.CupertinoIcons.back, size: 20),
              ),
              const SizedBox(width: 6),
            ],
            if (widget.title != null && widget.title!.isNotEmpty) ...[
              Flexible(
                child: Text(
                  widget.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: labelColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: AdaptiveMediaSearchField(
                controller: widget.searchController,
                focusNode: _searchFocusNode,
                placeholder: '搜索…',
                onChanged: widget.onSearchChanged,
                onClear: widget.onClearSearch,
              ),
            ),
            if (widget.trailingActions != null &&
                widget.trailingActions!.isNotEmpty) ...[
              const SizedBox(width: 6),
              _buildPhoneActions(context, widget.trailingActions!),
            ],
            if (widget.showSort) ...[
              const SizedBox(width: 4),
              cupertino.CupertinoButton(
                padding: const EdgeInsets.all(7),
                minimumSize: const Size.square(34),
                onPressed: () => _showPhoneSortMenu(context),
                child: const Icon(
                  cupertino.CupertinoIcons.arrow_up_arrow_down,
                  size: 18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneActions(
    BuildContext context,
    List<LocalLibraryActionControl> actions,
  ) {
    if (actions.length == 1) return actions.single;
    return cupertino.CupertinoButton(
      padding: const EdgeInsets.all(7),
      minimumSize: const Size.square(34),
      onPressed: () => _showPhoneActions(context, actions),
      child: const Icon(cupertino.CupertinoIcons.ellipsis_circle, size: 19),
    );
  }

  Future<void> _showPhoneActions(
    BuildContext context,
    List<LocalLibraryActionControl> actions,
  ) async {
    final enabledActions =
        actions.where((action) => action.onPressed != null).toList();
    final selected =
        await cupertino.showCupertinoModalPopup<LocalLibraryActionControl>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: const Text('页面操作'),
        actions: [
          for (final action in enabledActions)
            cupertino.CupertinoActionSheetAction(
              isDestructiveAction: action.isDestructive,
              onPressed: () => Navigator.of(sheetContext).pop(action),
              child: Text(action.label),
            ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    selected?.onPressed?.call();
  }

  Future<void> _showPhoneSortMenu(BuildContext context) async {
    final selected =
        await cupertino.showCupertinoModalPopup<LocalLibrarySortType>(
      context: context,
      builder: (sheetContext) => cupertino.CupertinoActionSheet(
        title: const Text('排序'),
        actions: [
          _phoneSortAction(
            sheetContext,
            LocalLibrarySortType.dateAdded,
            '最近观看',
          ),
          _phoneSortAction(
            sheetContext,
            LocalLibrarySortType.name,
            '名称排序',
          ),
          _phoneSortAction(
            sheetContext,
            LocalLibrarySortType.rating,
            '评分排序',
          ),
        ],
        cancelButton: cupertino.CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          child: const Text('取消'),
        ),
      ),
    );
    if (selected != null) {
      widget.onSortChanged?.call(selected);
    }
  }

  cupertino.CupertinoActionSheetAction _phoneSortAction(
    BuildContext context,
    LocalLibrarySortType type,
    String label,
  ) {
    final selected = widget.currentSort == type;
    return cupertino.CupertinoActionSheetAction(
      onPressed: () => Navigator.of(context).pop(type),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label),
          if (selected) ...[
            const SizedBox(width: 8),
            const Icon(cupertino.CupertinoIcons.check_mark, size: 16),
          ],
        ],
      ),
    );
  }
}

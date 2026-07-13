import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/media_library/adaptive_media_library_primitives.dart';
import 'package:nipaplay/media_library/unified_library_management_model.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_media_search_toolbar.dart';

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
    final actions = <CupertinoMediaSearchToolbarAction>[
      if (widget.viewMode != null)
        CupertinoMediaSearchToolbarAction(
          label: widget.viewMode == LibraryManagementViewMode.icons
              ? '切换到列表视图'
              : '切换到图标视图',
          icon: widget.viewMode == LibraryManagementViewMode.icons
              ? cupertino.CupertinoIcons.list_bullet
              : cupertino.CupertinoIcons.square_grid_2x2,
          onPressed: widget.onToggleViewMode,
        ),
      for (final action in widget.trailingActions ?? const [])
        CupertinoMediaSearchToolbarAction(
          label: action.label,
          icon: action.phoneIcon,
          onPressed: action.onPressed,
        ),
      if (widget.showSort)
        CupertinoMediaSearchToolbarAction(
          label: '排序',
          icon: cupertino.CupertinoIcons.arrow_up_arrow_down,
          onPressed: () => _showPhoneSortMenu(context),
        ),
    ];
    return CupertinoMediaSearchToolbar(
      controller: widget.searchController,
      placeholder:
          widget.title?.isNotEmpty == true ? '搜索${widget.title}' : '搜索…',
      onChanged: (value) {
        widget.onSearchChanged(value);
        if (value.isEmpty) widget.onClearSearch?.call();
      },
      leadingAction: widget.showBackButton
          ? CupertinoMediaSearchToolbarAction(
              label: '返回',
              icon: cupertino.CupertinoIcons.back,
              onPressed: widget.onBack,
            )
          : null,
      actions: actions,
    );
  }

  Future<void> _showPhoneSortMenu(BuildContext context) async {
    final selected =
        await CupertinoBottomSheet.showSelection<LocalLibrarySortType>(
      context: context,
      title: '排序',
      options: [
        _phoneSortOption(LocalLibrarySortType.dateAdded, '最近观看'),
        _phoneSortOption(LocalLibrarySortType.name, '名称排序'),
        _phoneSortOption(LocalLibrarySortType.rating, '评分排序'),
      ],
    );
    if (selected != null) {
      widget.onSortChanged?.call(selected);
    }
  }

  CupertinoBottomSheetOption<LocalLibrarySortType> _phoneSortOption(
    LocalLibrarySortType type,
    String label,
  ) {
    return CupertinoBottomSheetOption(
      label: label,
      value: type,
      selected: widget.currentSort == type,
    );
  }
}

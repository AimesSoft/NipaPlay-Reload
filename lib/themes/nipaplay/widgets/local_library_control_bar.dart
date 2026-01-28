import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';

enum LocalLibrarySortType {
  name,
  dateAdded,
  rating,
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
  final List<Widget>? trailingActions;

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
  });

  @override
  State<LocalLibraryControlBar> createState() => _LocalLibraryControlBarState();
}

class _LocalLibraryControlBarState extends State<LocalLibraryControlBar> {
  final GlobalKey _dropdownKey = GlobalKey();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isBackHovered = false;

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
    assert(!widget.showSort || (widget.currentSort != null && widget.onSortChanged != null));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentSort = widget.currentSort ?? LocalLibrarySortType.dateAdded;
    
    const activeColor = Color(0xFFFF2E55);
    final idleBorderColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1);
    
    // 提高背景对比度，日间模式下使用纯白
    final bgColor = isDark 
        ? Colors.white.withValues(alpha: 0.12) 
        : Colors.white;
    
    final textColor = isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black.withValues(alpha: 0.7);
    final primaryTextColor = isDark ? Colors.white : Colors.black;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 56, // 占据一行的高度
      child: Row(
        children: [
          if (widget.showBackButton) ...[
            MouseRegion(
              onEnter: (_) => setState(() => _isBackHovered = true),
              onExit: (_) => setState(() => _isBackHovered = false),
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                onTap: widget.onBack,
                behavior: HitTestBehavior.opaque,
                child: AnimatedScale(
                  scale: _isBackHovered ? 1.2 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Icon(
                      Ionicons.arrow_back,
                      size: 24,
                      color: primaryTextColor,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (widget.title != null && widget.title!.isNotEmpty) ...[
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.25),
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
            const SizedBox(width: 16),
          ],
          // 搜索框
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(8), 
                border: Border.all(
                  color: _searchFocusNode.hasFocus ? activeColor : idleBorderColor,
                  width: _searchFocusNode.hasFocus ? 1.5 : 1,
                ),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: TextSelectionThemeData(
                    selectionColor: activeColor.withValues(alpha: 0.3),
                    selectionHandleColor: activeColor,
                  ),
                ),
                child: TextField(
                  controller: widget.searchController,
                  focusNode: _searchFocusNode,
                  onChanged: widget.onSearchChanged,
                  style: TextStyle(color: primaryTextColor, fontSize: 14),
                  cursorColor: activeColor,
                  decoration: InputDecoration(
                    hintText: '搜索...',
                    hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 14),
                    prefixIcon: Icon(Ionicons.search_outline, size: 18, color: _searchFocusNode.hasFocus ? activeColor : textColor.withValues(alpha: 0.5)),
                    suffixIcon: widget.searchController.text.isNotEmpty 
                        ? SearchBarActionButton(
                            icon: Ionicons.close_circle,
                            onPressed: () {
                              widget.searchController.clear();
                              widget.onSearchChanged('');
                              widget.onClearSearch?.call();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                ),
              ),
            ),
          ),
          if (widget.trailingActions != null && widget.trailingActions!.isNotEmpty) ...[
            const SizedBox(width: 12),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: widget.trailingActions!
                  .expand((action) => [const SizedBox(width: 8), action])
                  .skip(1)
                  .toList(),
            ),
          ],
          if (widget.showSort) ...[
            const SizedBox(width: 12),
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
}

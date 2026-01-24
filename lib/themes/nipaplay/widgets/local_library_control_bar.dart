import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:provider/provider.dart';

enum LocalLibrarySortType {
  name,
  dateAdded,
  rating,
}

class LocalLibraryControlBar extends StatelessWidget {
  final Function(String) onSearchChanged;
  final LocalLibrarySortType currentSort;
  final Function(LocalLibrarySortType) onSortChanged;
  final VoidCallback? onClearSearch;
  final TextEditingController searchController;
  final GlobalKey _dropdownKey = GlobalKey();

  LocalLibraryControlBar({
    super.key,
    required this.onSearchChanged,
    required this.currentSort,
    required this.onSortChanged,
    required this.searchController,
    this.onClearSearch,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final bgColor = isDark 
        ? Colors.white.withValues(alpha: 0.05) 
        : Colors.black.withValues(alpha: 0.05);
    
    final textColor = isDark ? Colors.white70 : Colors.black87;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 56, // 占据一行的高度
      child: Row(
        children: [
          // 搜索框
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: searchController,
                onChanged: onSearchChanged,
                style: TextStyle(color: textColor, fontSize: 14),
                cursorColor: Theme.of(context).primaryColor,
                decoration: InputDecoration(
                  hintText: '搜索本地媒体...',
                  hintStyle: TextStyle(color: textColor.withValues(alpha: 0.5), fontSize: 14),
                  prefixIcon: Icon(Ionicons.search_outline, size: 18, color: textColor.withValues(alpha: 0.5)),
                  suffixIcon: searchController.text.isNotEmpty 
                      ? IconButton(
                          icon: Icon(Ionicons.close_circle, size: 18, color: textColor.withValues(alpha: 0.5)),
                          onPressed: () {
                            searchController.clear();
                            onSearchChanged('');
                            onClearSearch?.call();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 使用 BlurDropdown 替代 PopupMenuButton
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: BlurDropdown<LocalLibrarySortType>(
              dropdownKey: _dropdownKey,
              onItemSelected: onSortChanged,
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
          ),
        ],
      ),
    );
  }
}


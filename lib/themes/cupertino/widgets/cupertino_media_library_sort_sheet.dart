import 'package:flutter/cupertino.dart';
import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';

/// 排序选项
enum SortOption {
  dateCreatedDesc,
  dateCreatedAsc,
  nameAsc,
  nameDesc,
  premiereDateAsc,
  premiereDateDesc,
  datePlayedAsc,
  datePlayedDesc,
  productionYearAsc,
  productionYearDesc,
  communityRatingAsc,
  communityRatingDesc,
  runtimeAsc,
  runtimeDesc,
  playCountAsc,
  playCountDesc,
}

/// 原生 iOS 26 风格的媒体库排序选择表
class CupertinoMediaLibrarySortSheet extends StatefulWidget {
  const CupertinoMediaLibrarySortSheet({
    super.key,
    required this.currentSortBy,
    required this.currentSortOrder,
    required this.serverType,
    required this.onSortChanged,
  });

  final String currentSortBy;
  final String currentSortOrder;
  final String serverType; // 'jellyfin' or 'emby'
  final Function(String sortBy, String sortOrder) onSortChanged;

  @override
  State<CupertinoMediaLibrarySortSheet> createState() =>
      _CupertinoMediaLibrarySortSheetState();
}

class _CupertinoMediaLibrarySortSheetState
    extends State<CupertinoMediaLibrarySortSheet> {
  late String _selectedSortBy;
  late String _selectedSortOrder;

  final List<(String, String, String)> _jellyfinOptions = [
    ('DateCreated,SortName', '创建时间', '按文件创建时间排序'),
    ('SortName', '名称', '按名称字母顺序排序'),
    ('PremiereDate', '首播日期', '按首播日期排序'),
    ('DatePlayed', '播放时间', '按最后播放时间排序'),
    ('ProductionYear', '制作年份', '按制作年份排序'),
    ('CommunityRating', '社区评分', '按社区评分排序'),
    ('Runtime', '时长', '按视频时长排序'),
    ('PlayCount', '播放次数', '按播放次数排序'),
  ];

  final List<(String, String, String)> _embyOptions = [
    ('DateCreated', '创建时间', '按文件创建时间排序'),
    ('SortName', '名称', '按名称字母顺序排序'),
    ('PremiereDate', '首播日期', '按首播日期排序'),
    ('DatePlayed', '播放时间', '按最后播放时间排序'),
    ('ProductionYear', '制作年份', '按制作年份排序'),
    ('CommunityRating', '社区评分', '按社区评分排序'),
    ('CriticRating', '影评人评分', '按影评人评分排序'),
    ('Runtime', '时长', '按视频时长排序'),
    ('PlayCount', '播放次数', '按播放次数排序'),
    ('Random', '随机', '随机排序'),
  ];

  final List<(String, String)> _sortOrders = [
    ('Ascending', '升序'),
    ('Descending', '降序'),
  ];

  @override
  void initState() {
    super.initState();
    _selectedSortBy = widget.currentSortBy;
    _selectedSortOrder = widget.currentSortOrder;
  }

  List<(String, String, String)> get _sortOptions =>
      widget.serverType == 'jellyfin' ? _jellyfinOptions : _embyOptions;

  @override
  Widget build(BuildContext context) {
    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: '排序方式',
        useNativeToolbar: true,
        actions: [
          AdaptiveAppBarAction(
            iosSymbol: 'checkmark',
            icon: CupertinoIcons.check_mark,
            onPressed: () {
              widget.onSortChanged(_selectedSortBy, _selectedSortOrder);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: CupertinoPageScaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: CupertinoDynamicColor.resolve(
          CupertinoColors.systemGroupedBackground,
          context,
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              // 顶部空间
              const SliverToBoxAdapter(
                child: SizedBox(height: 70),
              ),
              // 排序方式选择
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '排序方式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label,
                        context,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final (sortBy, label, desc) = _sortOptions[index];
                      final isSelected = _selectedSortBy == sortBy;

                      return CupertinoButton(
                        padding: EdgeInsets.zero,
                        onPressed: () {
                          setState(() {
                            _selectedSortBy = sortBy;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            color: isSelected
                                ? CupertinoColors.systemBlue.withValues(alpha: 0.1)
                                : CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemBackground,
                                    context,
                                  ),
                            border: Border.all(
                              color: isSelected
                                  ? CupertinoColors.systemBlue
                                  : CupertinoDynamicColor.resolve(
                                      CupertinoColors.systemGrey3,
                                      context,
                                    ),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? CupertinoIcons.checkmark_circle_fill
                                      : CupertinoIcons.circle,
                                  color: isSelected
                                      ? CupertinoColors.systemBlue
                                      : CupertinoDynamicColor.resolve(
                                          CupertinoColors.secondaryLabel,
                                          context,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isSelected
                                              ? CupertinoColors.systemBlue
                                              : CupertinoDynamicColor.resolve(
                                                  CupertinoColors.label,
                                                  context,
                                                ),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        desc,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: CupertinoDynamicColor.resolve(
                                            CupertinoColors.secondaryLabel,
                                            context,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                    childCount: _sortOptions.length,
                  ),
                ),
              ),

              // 排序顺序选择
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Text(
                    '排序顺序',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.label,
                        context,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverToBoxAdapter(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: CupertinoDynamicColor.resolve(
                        CupertinoColors.systemBackground,
                        context,
                      ),
                    ),
                    child: Column(
                      children: List.generate(
                        _sortOrders.length,
                        (index) {
                          final (value, label) = _sortOrders[index];
                          final isSelected = _selectedSortOrder == value;

                          return Column(
                            children: [
                              if (index > 0)
                                Container(
                                  height: 1,
                                  color: CupertinoDynamicColor.resolve(
                                    CupertinoColors.systemGrey5,
                                    context,
                                  ),
                                ),
                              CupertinoButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedSortOrder = value;
                                  });
                                },
                                child: Row(
                                  children: [
                                    Icon(
                                      isSelected
                                          ? CupertinoIcons.checkmark_alt_circle_fill
                                          : CupertinoIcons.circle,
                                      color: isSelected
                                          ? CupertinoColors.systemBlue
                                          : CupertinoDynamicColor.resolve(
                                              CupertinoColors.secondaryLabel,
                                              context,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        label,
                                        style: TextStyle(
                                          color: isSelected
                                              ? CupertinoColors.systemBlue
                                              : CupertinoDynamicColor.resolve(
                                                  CupertinoColors.label,
                                                  context,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),

              // 底部空间
              SliverToBoxAdapter(
                child: SizedBox(
                  height: MediaQuery.of(context).padding.bottom + 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

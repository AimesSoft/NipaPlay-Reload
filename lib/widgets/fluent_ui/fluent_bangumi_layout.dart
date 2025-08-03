import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';

/// FluentUI风格的新番更新页面布局
class FluentBangumiLayout extends StatefulWidget {
  final List<BangumiItem> bangumiList;
  final Function(BangumiItem)? onItemTap;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRefresh;
  final String? searchQuery;
  final Function(String)? onSearchChanged;
  final List<String>? filterTags;
  final Function(List<String>)? onFilterChanged;

  const FluentBangumiLayout({
    super.key,
    required this.bangumiList,
    this.onItemTap,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
    this.searchQuery,
    this.onSearchChanged,
    this.filterTags,
    this.onFilterChanged,
  });

  @override
  State<FluentBangumiLayout> createState() => _FluentBangumiLayoutState();
}

class _FluentBangumiLayoutState extends State<FluentBangumiLayout> {
  final TextEditingController _searchController = TextEditingController();
  String _sortBy = 'default';
  bool _showFilters = false;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.searchQuery ?? '';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<BangumiItem> get _filteredBangumiList {
    List<BangumiItem> filtered = List.from(widget.bangumiList);
    
    // 搜索过滤
    if (widget.searchQuery?.isNotEmpty == true) {
      filtered = filtered.where((item) => 
        item.name.toLowerCase().contains(widget.searchQuery!.toLowerCase())
      ).toList();
    }
    
    // 标签过滤
    if (widget.filterTags?.isNotEmpty == true) {
      filtered = filtered.where((item) => 
        widget.filterTags!.any((tag) => item.tags?.contains(tag) == true)
      ).toList();
    }
    
    // 排序
    switch (_sortBy) {
      case 'name':
        filtered.sort((a, b) => a.name.compareTo(b.name));
        break;
      case 'rating':
        filtered.sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));
        break;
      case 'year':
        filtered.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        break;
      case 'onAir':
        filtered.sort((a, b) => b.isOnAir ? 1 : (a.isOnAir ? -1 : 0));
        break;
      default:
        // 保持默认顺序
        break;
    }
    
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    
    return Column(
      children: [
        // 顶部工具栏 - 使用Fluent UI风格
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.8),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: theme.resources.controlStrokeColorDefault,
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  // 搜索框
                  Expanded(
                    child: TextBox(
                      controller: _searchController,
                      placeholder: '搜索番剧...',
                      prefix: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(FluentIcons.search, size: 16),
                      ),
                      suffix: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(FluentIcons.chrome_close, size: 16),
                              onPressed: () {
                                _searchController.clear();
                                widget.onSearchChanged?.call('');
                              },
                            )
                          : null,
                      onChanged: widget.onSearchChanged,
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 排序选择
                  ComboBox<String>(
                    value: _sortBy,
                    items: const [
                      ComboBoxItem(value: 'default', child: Text('默认排序')),
                      ComboBoxItem(value: 'name', child: Text('按名称')),
                      ComboBoxItem(value: 'rating', child: Text('按评分')),
                      ComboBoxItem(value: 'year', child: Text('按年份')),
                      ComboBoxItem(value: 'onAir', child: Text('连载优先')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sortBy = value);
                      }
                    },
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 过滤器按钮
                  ToggleButton(
                    checked: _showFilters,
                    onChanged: (checked) => setState(() => _showFilters = checked),
                    child: const Icon(FluentIcons.filter),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // 刷新按钮
                  IconButton(
                    icon: Icon(
                      FluentIcons.refresh,
                      color: widget.isLoading ? theme.inactiveColor : null,
                    ),
                    onPressed: widget.isLoading ? null : widget.onRefresh,
                  ),
                ],
              ),
              
              // 过滤器展开面板
              if (_showFilters) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.acrylicBackgroundColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.resources.controlStrokeColorSecondary,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '标签过滤',
                        style: theme.typography.caption,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          '动作', '冒险', '喜剧', '校园', '恋爱', '科幻', '奇幻', '悬疑', '日常'
                        ].map((tag) {
                          final isSelected = widget.filterTags?.contains(tag) == true;
                          return ToggleButton(
                            checked: isSelected,
                            onChanged: (checked) {
                              final currentTags = List<String>.from(widget.filterTags ?? []);
                              if (checked) {
                                currentTags.add(tag);
                              } else {
                                currentTags.remove(tag);
                              }
                              widget.onFilterChanged?.call(currentTags);
                            },
                            child: Text(tag),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 统计信息
        if (!widget.isLoading && widget.errorMessage == null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  '共 ${_filteredBangumiList.length} 部番剧',
                  style: theme.typography.caption?.copyWith(
                    color: theme.inactiveColor,
                  ),
                ),
                const Spacer(),
                if (widget.searchQuery?.isNotEmpty == true || widget.filterTags?.isNotEmpty == true)
                  Text(
                    '已筛选',
                    style: theme.typography.caption?.copyWith(
                      color: theme.accentColor,
                    ),
                  ),
              ],
            ),
          ),
        
        const SizedBox(height: 8),
        
        // 内容区域
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (widget.isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ProgressRing(),
            SizedBox(height: 16),
            Text('正在加载番剧列表...'),
          ],
        ),
      );
    }
    
    if (widget.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.error,
              size: 48,
              color: FluentTheme.of(context).inactiveColor,
            ),
            const SizedBox(height: 16),
            Text(
              widget.errorMessage!,
              style: FluentTheme.of(context).typography.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Button(
              onPressed: widget.onRefresh,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    
    if (_filteredBangumiList.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              FluentIcons.search,
              size: 48,
              color: FluentTheme.of(context).inactiveColor,
            ),
            const SizedBox(height: 16),
            Text(
              widget.searchQuery?.isNotEmpty == true
                  ? '没有找到匹配的番剧'
                  : '暂无番剧数据',
              style: FluentTheme.of(context).typography.body,
            ),
          ],
        ),
      );
    }
    
    // 网格布局
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: _filteredBangumiList.length,
      itemBuilder: (context, index) {
        final item = _filteredBangumiList[index];
        return FluentAnimeCard(
          name: item.name,
          imageUrl: item.imageUrl,
          isOnAir: item.isOnAir,
          source: item.source,
          rating: item.rating,
          year: item.year,
          onTap: () => widget.onItemTap?.call(item),
        );
      },
    );
  }
}

/// 番剧数据模型
class BangumiItem {
  final String id;
  final String name;
  final String imageUrl;
  final bool isOnAir;
  final String? source;
  final double? rating;
  final int? year;
  final String? description;
  final List<String>? tags;

  const BangumiItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.isOnAir = false,
    this.source,
    this.rating,
    this.year,
    this.description,
    this.tags,
  });
}
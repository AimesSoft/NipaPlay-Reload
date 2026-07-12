import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/search_model.dart';
import 'package:nipaplay/search/tag_search_controller.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';

class CupertinoTagSearchView extends StatefulWidget {
  const CupertinoTagSearchView({
    super.key,
    required this.controller,
    required this.onOpenAnimeDetail,
    required this.onMessage,
  });

  final TagSearchController controller;
  final ValueChanged<int> onOpenAnimeDetail;
  final ValueChanged<String> onMessage;

  @override
  State<CupertinoTagSearchView> createState() => _CupertinoTagSearchViewState();
}

class _CupertinoTagSearchViewState extends State<CupertinoTagSearchView> {
  final TextEditingController _tagController = TextEditingController();
  late final TextEditingController _keywordController = TextEditingController(
    text: widget.controller.keyword,
  );

  @override
  void dispose() {
    _tagController.dispose();
    _keywordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) => CupertinoBottomSheetContentLayout(
        sliversBuilder: (context, topSpacing) => [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, topSpacing, 16, 32),
            sliver: SliverList.list(
              children: [
                _buildTagSection(context),
                const SizedBox(height: 12),
                _buildFilterSection(context),
                const SizedBox(height: 14),
                _buildSearchButton(context),
                const SizedBox(height: 22),
                _buildResults(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTagSection(BuildContext context) {
    final controller = widget.controller;
    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: const Text('标签'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: CupertinoTextField(
                  controller: _tagController,
                  placeholder: '输入标签名称',
                  textInputAction: TextInputAction.done,
                  clearButtonMode: OverlayVisibilityMode.editing,
                  onSubmitted: (_) => _addTag(),
                ),
              ),
              const SizedBox(width: 6),
              CupertinoButton(
                padding: const EdgeInsets.all(8),
                minimumSize: const Size.square(38),
                onPressed: _addTag,
                child: const Icon(CupertinoIcons.add, size: 20),
              ),
            ],
          ),
        ),
        if (controller.suggestedTags.isNotEmpty)
          _TagWrap(
            title: '当前标签',
            tags: controller.suggestedTags,
            selected: controller.textTags.toSet(),
            onPressed: (tag) {
              final error = controller.addTextTag(tag);
              if (error != null) widget.onMessage(error);
            },
          ),
        if (controller.textTags.isNotEmpty)
          _TagWrap(
            title: '已添加',
            tags: controller.textTags,
            selected: controller.textTags.toSet(),
            removable: true,
            onPressed: controller.removeTextTag,
          ),
      ],
    );
  }

  Widget _buildFilterSection(BuildContext context) {
    final controller = widget.controller;
    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: const Text('筛选'),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: CupertinoSearchTextField(
            controller: _keywordController,
            placeholder: '作品标题关键词',
            onChanged: controller.setKeyword,
            onSubmitted: (_) => controller.performSmartSearch(),
          ),
        ),
        CupertinoListTile(
          title: const Text('年份'),
          additionalInfo: Text(
            controller.selectedYear?.toString() ?? '全部年份',
          ),
          trailing: const Icon(CupertinoIcons.chevron_down, size: 16),
          onTap: controller.config == null
              ? controller.loadConfig
              : () => _showYearPicker(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: _RatingSlider(
            label: '最低评分',
            value: controller.minRating,
            onChanged: controller.setMinRating,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          child: _RatingSlider(
            label: '最高评分',
            value: controller.maxRating,
            onChanged: controller.setMaxRating,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchButton(BuildContext context) {
    final controller = widget.controller;
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton.filled(
        onPressed:
            controller.isSearching ? null : controller.performSmartSearch,
        child: controller.isSearching
            ? const CupertinoActivityIndicator(color: CupertinoColors.white)
            : const Text('搜索'),
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    final controller = widget.controller;
    if (controller.isSearching && controller.visibleResults.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: CupertinoActivityIndicator(radius: 12)),
      );
    }
    if (controller.mode == TagSearchMode.none) {
      return const _EmptyResults(
        message: '添加标签或设置筛选条件后开始搜索',
      );
    }
    if (controller.visibleResults.isEmpty) {
      return const _EmptyResults(message: '没有找到匹配的番剧');
    }

    return CupertinoListSection.insetGrouped(
      margin: EdgeInsets.zero,
      header: Text('搜索结果·${controller.totalResults}'),
      children: [
        for (final anime in controller.visibleResults)
          _ResultTile(
            anime: anime,
            onPressed: () => widget.onOpenAnimeDetail(anime.animeId),
          ),
        if ((controller.mode == TagSearchMode.text && controller.hasMoreText) ||
            (controller.mode == TagSearchMode.advanced &&
                controller.hasMoreAdvanced))
          CupertinoButton(
            onPressed: controller.mode == TagSearchMode.text
                ? controller.loadMoreTextResults
                : controller.loadMoreAdvancedResults,
            child:
                controller.isLoadingMoreText || controller.isLoadingMoreAdvanced
                    ? const CupertinoActivityIndicator()
                    : const Text('加载更多'),
          ),
      ],
    );
  }

  void _addTag() {
    final error = widget.controller.addTextTag(_tagController.text);
    if (error != null) {
      widget.onMessage(error);
      return;
    }
    _tagController.clear();
  }

  Future<void> _showYearPicker(BuildContext context) async {
    final config = widget.controller.config;
    if (config == null) return;
    final allYearsValue = config.minYear - 1;
    final selected = await CupertinoBottomSheet.showSelection<int>(
      context: context,
      title: '选择年份',
      heightRatio: 0.72,
      options: [
        CupertinoBottomSheetOption(
          label: '全部年份',
          value: allYearsValue,
          selected: widget.controller.selectedYear == null,
        ),
        for (var year = config.maxYear; year >= config.minYear; year--)
          CupertinoBottomSheetOption(
            label: year.toString(),
            value: year,
            selected: widget.controller.selectedYear == year,
          ),
      ],
    );
    if (selected != null) {
      widget.controller.setSelectedYear(
        selected == allYearsValue ? null : selected,
      );
    }
  }
}

class _TagWrap extends StatelessWidget {
  const _TagWrap({
    required this.title,
    required this.tags,
    required this.selected,
    required this.onPressed,
    this.removable = false,
  });

  final String title;
  final Iterable<String> tags;
  final Set<String> selected;
  final ValueChanged<String> onPressed;
  final bool removable;

  @override
  Widget build(BuildContext context) {
    final labelColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final fillColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final tag in tags)
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  color: fillColor,
                  onPressed: () => onPressed(tag),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (selected.contains(tag)) ...[
                        Icon(
                          removable
                              ? CupertinoIcons.xmark
                              : CupertinoIcons.checkmark,
                          size: 12,
                          color: labelColor,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(tag,
                          style: TextStyle(color: labelColor, fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RatingSlider extends StatelessWidget {
  const _RatingSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
            Text(value.round().toString()),
          ],
        ),
        AdaptiveSlider(
          value: value,
          min: 0,
          max: 10,
          divisions: 10,
          activeColor: CupertinoTheme.of(context).primaryColor,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _ResultTile extends StatelessWidget {
  const _ResultTile({required this.anime, required this.onPressed});

  final SearchResultAnime anime;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final label = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    final imageUrl = kIsWeb
        ? WebRemoteAccessService.imageProxyUrl(anime.imageUrl ?? '') ??
            anime.imageUrl ??
            ''
        : anime.imageUrl ?? '';
    final details = <String>[
      if (anime.typeDescription?.isNotEmpty == true) anime.typeDescription!,
      if (anime.rating > 0) '评分 ${anime.rating.toStringAsFixed(1)}',
      if (anime.episodeCount > 0) '${anime.episodeCount} 集',
    ].join(' · ');

    return CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      onPressed: onPressed,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 54,
              height: 72,
              child: imageUrl.isEmpty
                  ? const ColoredBox(
                      color: CupertinoColors.systemGrey5,
                      child: Icon(CupertinoIcons.photo, size: 20),
                    )
                  : CachedNetworkImageWidget(
                      imageUrl: imageUrl,
                      fit: BoxFit.cover,
                      loadMode: CachedImageLoadMode.legacy,
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anime.animeTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ).copyWith(color: label),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    details,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(CupertinoIcons.chevron_forward, size: 15, color: secondary),
        ],
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  const _EmptyResults({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final secondary = CupertinoDynamicColor.resolve(
      CupertinoColors.secondaryLabel,
      context,
    );
    return SizedBox(
      height: 150,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.search, size: 32, color: secondary),
            const SizedBox(height: 10),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(color: secondary)),
          ],
        ),
      ),
    );
  }
}

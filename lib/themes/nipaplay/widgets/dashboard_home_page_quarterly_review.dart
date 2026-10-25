part of dashboard_home_page;

extension _DashboardQuarterlyReviewUi on _DashboardHomePageState {
  Widget _buildQuarterlyReviewSection() {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark ? Colors.white : Colors.black87;
    final muted = foreground.withValues(alpha: 0.62);
    final seasonMonth = _quarterlyReviewMonth!;
    final items = _sortedQuarterlyReviewItems;
    final cardWidth = isPhone ? 320.0 : 360.0;
    final detailsWidth = cardWidth - 132;
    final titleStyle =
        TextStyle(color: foreground, fontSize: 16, fontWeight: FontWeight.w600);
    final dateStyle = TextStyle(color: muted, fontSize: 12);
    final ratingStyle =
        TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w600);
    double textHeight(String text, TextStyle style, {int? maxLines}) {
      final painter = TextPainter(
        text: TextSpan(
            text: text, style: DefaultTextStyle.of(context).style.merge(style)),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        textHeightBehavior: DefaultTextStyle.of(context).textHeightBehavior,
        locale: Localizations.maybeLocaleOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: detailsWidth);
      final height = painter.height;
      painter.dispose();
      return height;
    }

    // Keep every card aligned while ensuring even a two-line title cannot
    // squeeze a two-line short comment into a scrolling viewport.
    final cardHeight = items.fold<double>(196, (height, item) {
      final title =
          item.anime.nameCn.isNotEmpty ? item.anime.nameCn : item.anime.name;
      final requiredHeight = textHeight(title, titleStyle, maxLines: 2) +
          5 +
          textHeight(
              '${item.airDate.month}月${item.airDate.day}日${item.dateLabel}',
              dateStyle) +
          (item.rating != null
              ? 10 +
                  math.max(15, textHeight('${item.rating} / 10', ratingStyle))
              : 0) +
          (item.comment != null
              ? 8 +
                  QuarterlyReviewComment.minimumHeight(context,
                      width: detailsWidth,
                      comment: item.comment!,
                      hasTimestamp: item.commentAt != null,
                      editable: BangumiApiService.isLoggedIn &&
                          QuarterlyReviewCache.subjectId(
                                  item.anime.bangumiUrl) !=
                              null)
              : 0);
      return math.max(height, requiredHeight.ceilToDouble());
    });
    final daysUntilClose = QuarterlyReviewCache.daysUntilReviewCloses(
      DateTime(_quarterlyReviewYear!, seasonMonth),
      DateTime.now(),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$seasonMonth月新番回顾',
                style: TextStyle(
                  color: foreground,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                )),
            if (!isPhone) ...[
              const SizedBox(width: 8),
              _buildScrollButtons(
                  _quarterlyReviewScrollController, cardWidth + 12),
            ],
            const SizedBox(width: 12),
            BlurDropdown<_QuarterlyReviewSort>(
              dropdownKey: _quarterlyReviewSortDropdownKey,
              menuWidth: 188,
              items: [
                for (final sort in _QuarterlyReviewSort.values)
                  DropdownMenuItemData<_QuarterlyReviewSort>(
                    title: sort.label,
                    value: sort,
                    isSelected: _quarterlyReviewSort == sort,
                  ),
              ],
              onItemSelected: _setQuarterlyReviewSort,
              controlBuilder: (context, selectedLabel) => Tooltip(
                message: '回顾排序：$selectedLabel',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Icon(Icons.sort_rounded, color: foreground, size: 24),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text('${items.length} 部',
                style: TextStyle(color: muted, fontSize: 13)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 16, top: 2),
          child: Text('限时栏目：将于$daysUntilClose天后关闭',
              style: TextStyle(color: muted, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: cardHeight + 20,
          child: ListView.separated(
            controller: _quarterlyReviewScrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final item = items[index];
              final anime = item.anime;
              final title = anime.nameCn.isNotEmpty ? anime.nameCn : anime.name;
              final onTap = () => _showAnimeDetail(anime);
              final card = MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: SizedBox(
                    width: cardWidth,
                    height: cardHeight,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: SizedBox(
                              width: 120,
                              height: cardHeight,
                              child: anime.imageUrl.isEmpty
                                  ? Icon(Icons.movie_outlined, color: muted)
                                  : CachedNetworkImageWidget(
                                      imageUrl: anime.imageUrl,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 220,
                                    ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(title,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: titleStyle),
                              const SizedBox(height: 5),
                              Text(
                                  '${item.airDate.month}月${item.airDate.day}日${item.dateLabel}',
                                  style: dateStyle),
                              if (item.rating != null) ...[
                                const SizedBox(height: 10),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.star_rounded,
                                        size: 15, color: Colors.amber),
                                    const SizedBox(width: 4),
                                    Text('${item.rating} / 10',
                                        style: ratingStyle),
                                  ],
                                ),
                              ],
                              if (item.comment != null) ...[
                                const SizedBox(height: 8),
                                Expanded(
                                  child: QuarterlyReviewComment(
                                    key: ValueKey(anime.id),
                                    comment: item.comment!,
                                    updatedAt: item.commentAt,
                                    onEdit: BangumiApiService.isLoggedIn &&
                                            QuarterlyReviewCache.subjectId(
                                                    anime.bangumiUrl) !=
                                                null
                                        ? () =>
                                            _editQuarterlyReviewComment(item)
                                        : null,
                                  ),
                                ),
                              ],
                            ],
                          )),
                        ]),
                  ),
                ),
              );
              return Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: _wrapLargeScreenFocusable(
                  child: card,
                  onActivate: onTap,
                  borderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

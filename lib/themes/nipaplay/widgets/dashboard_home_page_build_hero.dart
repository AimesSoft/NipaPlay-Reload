part of dashboard_home_page;

extension DashboardHomePageHeroBuild on _DashboardHomePageState {
  Widget _buildHeroBanner({required bool isPhone}) {
    if (_isLoadingRecommended) {
      return Container(
        height: isPhone ? 220 : 400, // 保持一致的高度
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white10,
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF2E55)),
        ),
      );
    }

    if (_recommendedItems.isEmpty) {
      return Container(
        height: isPhone ? 220 : 400, // 保持一致的高度
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white10,
        ),
        child: Center(
          child: Text(
            '暂无推荐内容',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.white54
                  : Colors.black54,
              fontSize: 16,
            ),
          ),
        ),
      );
    }

    // 确保至少有7个项目用于布局
    final items = _recommendedItems.length >= 7 ? _recommendedItems.take(7).toList() : _recommendedItems;
    if (items.length < 7) {
      // 如果不足7个，填充占位符
      while (items.length < 7) {
        items.add(RecommendedItem(
          id: 'placeholder_${items.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }
    }

    final int pageCount = math.min(5, items.length);

    // 手机：改为全宽轮播；桌面：左大图 + 右两张小卡
    return Container(
      height: isPhone ? 220 : 400, // 手机端更矩形，降低高度
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          if (isPhone)
            // 全宽轮播
            PageView.builder(
              controller: _heroBannerPageController,
              itemCount: pageCount,
              onPageChanged: (index) {
                _currentHeroBannerIndex = index;
                _heroBannerIndexNotifier.value = index;
                _stopAutoSwitch();
                Timer(const Duration(seconds: 3), () {
                  _resumeAutoSwitch();
                });
              },
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildMainHeroBannerItem(item, compact: true);
              },
            )
          else
            Row(
              children: [
                // 左侧主推荐横幅 - 占据大部分宽度，支持滑动（前5个）
                Expanded(
                  flex: 2,
                  child: PageView.builder(
                    controller: _heroBannerPageController,
                    itemCount: pageCount, // 固定显示前5个
                    onPageChanged: (index) {
                      _currentHeroBannerIndex = index;
                      _heroBannerIndexNotifier.value = index;
                      _stopAutoSwitch();
                      Timer(const Duration(seconds: 3), () {
                        _resumeAutoSwitch();
                      });
                    },
                    itemBuilder: (context, index) {
                      final item = items[index]; // 使用前5个
                      return _buildMainHeroBannerItem(item);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // 右侧小卡片区域 - 上下两个（第6和第7个）
                Expanded(
                  flex: 1,
                  child: Column(
                    children: [
                      Expanded(child: _buildSmallRecommendationCard(items[5], 5)),
                      const SizedBox(height: 8),
                      Expanded(child: _buildSmallRecommendationCard(items[6], 6)),
                    ],
                  ),
                ),
              ],
            ),
          
          // 页面指示器
          _buildPageIndicator(fullWidth: isPhone, count: pageCount),
        ],
      ),
    );
  }

  Widget _buildMainHeroBannerItem(RecommendedItem item, {bool compact = false}) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('hero_banner_${item.id}_${item.source.name}'), // 添加唯一key
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 使用高效缓存组件
            if (item.backgroundImageUrl != null && item.backgroundImageUrl!.isNotEmpty)
              Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.white),
                  CachedNetworkImageWidget(
                    key: ValueKey('hero_img_${item.id}_${item.backgroundImageUrl}'),
                    imageUrl: item.backgroundImageUrl!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                    blurIfLowRes: item.source != RecommendedItemSource.dandanplay,
                    forceBlur: item.source != RecommendedItemSource.dandanplay ? item.isLowRes : false,
                    lowResBlurSigma: 40,
                    lowResMinScale: 0.8,
                    errorBuilder: (context, error) => Container(
                      color: Colors.white10,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.white30),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.black12,
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 16,
                right: 16,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(1.0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角Logo - 使用高效缓存组件
            if (item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 120 : 200, // 手机端更小
                      maxHeight: compact ? 50 : 80,  // 手机端更小
                    ),
                    child: CachedNetworkImageWidget(
                      key: ValueKey('hero_logo_${item.id}_${item.logoImageUrl}'),
                      imageUrl: item.logoImageUrl!,
                      delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: compact ? 120 : 200, // 手机端更小
                      maxHeight: compact ? 50 : 80,  // 手机端更小
                    ),
                    child: Image.network(
                      item.logoImageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: compact ? 120 : 200,
                          height: compact ? 50 : 80,
                          color: Colors.transparent,
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: compact ? 120 : 200,
                        height: compact ? 50 : 80,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左侧中间位置的标题和简介
            Positioned(
              left: 16,
              right: compact ? 16 : MediaQuery.of(context).size.width * 0.3, // 手机上不预留右侧空间
              top: 0,
              bottom: 0,
              child: Align(
                alignment: Alignment.centerLeft, // 左对齐而不是居中
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 媒体名字（加粗显示）
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildServiceIcon(item.source, size: compact ? 22 : 24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            item.title,
                            locale: const Locale("zh-Hans", "zh"),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: compact ? 22 : 24, // 手机端调整为20px，比18px稍大
                              fontWeight: FontWeight.bold,
                              shadows: const [
                                Shadow(
                                  color: Colors.black,
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            maxLines: compact ? 3 : 2, // 手机端可以显示更多行
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    // 桌面端显示间距和简介，手机端不显示
                    if (!compact) ...[
                      const SizedBox(height: 12),
                      
                      // 剧情简介（只在桌面端显示）
                      if (item.subtitle.isNotEmpty)
                        Text(
                          item.subtitle.replaceAll('<br>', ' ').replaceAll('<br/>', ' ').replaceAll('<br />', ' '),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            shadows: [
                              Shadow(
                                color: Colors.black,
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallRecommendationCard(RecommendedItem item, int index) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        key: ValueKey('small_card_${item.id}_${item.source.name}_$index'), // 添加唯一key包含索引
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图 - 使用高效缓存组件
            if (item.backgroundImageUrl != null && item.backgroundImageUrl!.isNotEmpty)
              Stack(
                fit: StackFit.expand,
                children: [
                  Container(color: Colors.white),
                  CachedNetworkImageWidget(
                    key: ValueKey('small_img_${item.id}_${item.backgroundImageUrl}_$index'),
                    imageUrl: item.backgroundImageUrl!,
                    fit: BoxFit.cover,
                    delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                    width: double.infinity,
                    height: double.infinity,
                    blurIfLowRes: item.source != RecommendedItemSource.dandanplay,
                    forceBlur: item.source != RecommendedItemSource.dandanplay ? item.isLowRes : false,
                    lowResBlurSigma: 40,
                    lowResMinScale: 0.8,
                    errorBuilder: (context, error) => Container(
                      color: Colors.white10,
                      child: const Center(
                        child: Icon(Icons.broken_image, color: Colors.white30, size: 16),
                      ),
                    ),
                  ),
                ],
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white10
                      : Colors.black12,
                ),
              ),
            
            // 遮罩层
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withOpacity(0.7),
                  ],
                ),
              ),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 8,
                right: 8,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.white.withOpacity(1.0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 12,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左下角小Logo（如果有的话）
            // Logo图片 - 使用高效缓存组件
            if (item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: CachedNetworkImageWidget(
                    key: ValueKey('small_logo_${item.id}_${item.logoImageUrl}_$index'),
                    imageUrl: item.logoImageUrl!,
                    fit: BoxFit.contain,
                    delayLoad: _shouldDelayImageLoad(), // 根据推荐内容来源决定是否延迟
                  ),
                ),
              )
            else if (item.logoImageUrl != null)
              Positioned(
                left: 8,
                bottom: 8,
                child: Container(
                  constraints: const BoxConstraints(
                    maxWidth: 120,
                    maxHeight: 45,
                  ),
                  child: Image.network(
                    item.logoImageUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        width: 120,
                        height: 45,
                        color: Colors.transparent,
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 120,
                      height: 45,
                      color: Colors.transparent,
                    ),
                  ),
                ),
              ),
            
            // 右下角标题（总是显示，不论是否有Logo）
            Positioned(
              right: 8,
              bottom: item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty
                ? 66
                  : 8,
              left: item.logoImageUrl != null && item.logoImageUrl!.isNotEmpty
                  ? 8
                  : 8,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildServiceIcon(item.source, size: 12),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceIcon(RecommendedItemSource source, {double size = 20}) {
    switch (source) {
      case RecommendedItemSource.jellyfin:
        return SvgPicture.asset(
          'assets/jellyfin.svg',
          width: size,
          height: size,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
      case RecommendedItemSource.emby:
        return SvgPicture.asset(
          'assets/emby.svg',
          width: size,
          height: size,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
      case RecommendedItemSource.local:
        return Icon(
          Icons.folder,
          color: Colors.white,
          size: size,
        );
      case RecommendedItemSource.dandanplay:
        return Icon(
          Icons.cloud_outlined,
          color: Colors.white,
          size: size,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

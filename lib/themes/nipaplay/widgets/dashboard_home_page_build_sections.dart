part of dashboard_home_page;

extension DashboardHomePageSectionsBuild on _DashboardHomePageState {
  Widget _buildContinueWatching({required bool isPhone}) {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final validHistory = historyProvider.continueWatchingItems;

        final actionWidgets = <Widget>[];
        if (!isPhone && validHistory.isNotEmpty) {
          actionWidgets.add(_buildScrollButtons(_continueWatchingScrollController, 292));
          actionWidgets.add(const SizedBox(width: 12));
        }
        actionWidgets.add(_buildWatchHistoryButton());

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '继续播放',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white
                          : Colors.black,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ...actionWidgets,
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (validHistory.isEmpty)
              Container(
                height: 180,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white10,
                ),
                child: Center(
                  child: Text(
                    '暂无播放记录',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.white54
                          : Colors.black54,
                      fontSize: 16,
                    ),
                  ),
                ),
              )
            else
              SizedBox(
                height: isPhone ? 200 : 280, // 进一步减少手机端高度
                child: ListView.builder(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: math.min(validHistory.length, 10),
                  itemBuilder: (context, index) {
                    final item = validHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContinueWatchingCard(item, compact: isPhone),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingCard(WatchHistoryItem item, {bool compact = false}) {
    return GestureDetector(
      onTap: _isHistoryAutoMatching ? null : () => _onWatchHistoryItemTap(item),
      child: SizedBox(
        key: ValueKey('continue_${item.animeId ?? 0}_${item.filePath.hashCode}'), // 添加唯一key
        width: compact ? 220 : 280, // 手机更窄
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片容器
            Container(
              height: compact ? 110 : 158, // 进一步减少手机端高度
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
              ),
              clipBehavior: Clip.antiAlias,
              child: _getVideoThumbnail(item),
            ),
            
            const SizedBox(height: 8),
            
            // 媒体名称
            Text(
              item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white
                    : Colors.black,
                fontSize: 16, // 增加字体大小
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2, // 增加显示行数
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 4),
            
            // 进度和集数信息
            Text(
              "${(item.watchProgress * 100).toInt()}%${item.episodeTitle != null ? ' · ${item.episodeTitle}' : ''}",
              style: TextStyle(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.white70
                    : Colors.black87,
                fontSize: 14, // 增加字体大小
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _showWatchHistoryDialog() {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = math.min(screenSize.width, screenSize.height);
    final isPhone = shortestSide < 600;

    NipaplayWindow.show(
      context: context,
      child: NipaplayWindowScaffold(
        backgroundImageUrl: null,
        blurBackground: true, // 内部已固定为 40 模糊
        maxWidth: isPhone ? screenSize.width * 0.95 : 800,
        maxHeightFactor: isPhone ? 0.85 : 0.7,
        onClose: () => Navigator.of(context).pop(),
        child: Column(
          children: [
            Builder(
              builder: (innerContext) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    NipaplayWindowPositionProvider.of(innerContext)?.onMove(details.delta);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      children: [
                        Text(
                          '观看记录',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
            ),
            const Expanded(
              child: WatchHistoryPage(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWatchHistoryButton() {
    return Tooltip(
      message: '观看记录',
      child: _HoverScaleButton(
        onTap: _showWatchHistoryDialog,
        child: const Icon(
          Icons.history_rounded,
          size: 24,
        ),
      ),
    );
  }

  Widget _buildTodaySeriesSection() {
    // 只有当加载完成且确实没有数据时，才隐藏。
    // 如果正在加载中，我们需要显示骨架屏。
    if (_todayAnimes.isEmpty && !_isLoadingTodayAnimes) {
      // 检查是否是因为加载失败导致的空列表
      // 如果我们希望在首页保持整洁，确实可以隐藏
      return const SizedBox.shrink();
    }

    final now = DateTime.now();
    const weekdayNames = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
    // Dandanplay weekday: 0-6 (Sun-Sat)
    int weekdayIndex = now.weekday;
    if (weekdayIndex == 7) weekdayIndex = 0;
    final weekdayStr = weekdayNames[weekdayIndex];

    return _buildRecentSection(
      title: '今日新番 - $weekdayStr',
      items: _todayAnimes,
      scrollController: _getTodayAnimesScrollController(),
      onItemTap: (item) => _showAnimeDetail(item as BangumiAnime),
      isLoading: _isLoadingTodayAnimes,
    );
  }

  void _showAnimeDetail(BangumiAnime anime) {
    ThemedAnimeDetail.show(context, anime.id);
  }

  Widget _buildRecentSection({
    required String title,
    required List<dynamic> items,
    required ScrollController scrollController,
    required Function(dynamic) onItemTap,
    bool isLoading = false,
  }) {
    final bool isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisSize: MainAxisSize.min, // 紧凑排列
            children: [
              Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Colors.black,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 8),
              if (!isPhone && (items.isNotEmpty || isLoading))
                _buildScrollButtons(scrollController, 162), 
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 160,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: isLoading ? 3 : items.length,
            itemBuilder: (context, index) {
              if (isLoading) {
                return const HorizontalAnimeSkeleton();
              }
              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _buildMediaCard(item, onItemTap),
              );
            },
          ),
        ),
      ],
    );
  }

  String? _getWatchProgressForDashboard(dynamic item) {
    int? animeId;
    int? totalEpisodes;
    
    if (item is JellyfinMediaItem) {
      // 对于Jellyfin/Emby，优先使用其自带的UserData信息
      if (item.userData?.played == true) return '已看完';
      // 如果没有具体的集数信息，Jellyfin通常只给出一个已看标记
      return null;
    } else if (item is EmbyMediaItem) {
      if (item.userData?.played == true) return '已看完';
      return null;
    } else if (item is WatchHistoryItem) {
      animeId = item.animeId;
    } else if (item is LocalAnimeItem) {
      animeId = item.animeId;
    } else if (item is DandanplayRemoteAnimeGroup) {
      animeId = item.animeId;
      totalEpisodes = item.episodeCount;
    } else if (item is BangumiAnime) {
      animeId = item.id;
      totalEpisodes = item.totalEpisodes;
    }

    if (!_isValidAnimeId(animeId)) return null;

    final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
    final allHistory = watchHistoryProvider.history.where((h) => h.animeId == animeId).toList();
    
    if (allHistory.isEmpty) return '未观看';

    final watchedIds = <int>{};
    for (var h in allHistory) {
      if (h.episodeId != null && h.episodeId! > 0) {
        watchedIds.add(h.episodeId!);
      }
    }
    
    int watchedCount = watchedIds.length;
    if (watchedCount == 0) watchedCount = allHistory.length;

    if (totalEpisodes != null && totalEpisodes > 0) {
      if (watchedCount >= totalEpisodes) return '已看完';
      return '已看 $watchedCount / $totalEpisodes 集';
    }
    
    return '已看 $watchedCount 集';
  }

  Widget _buildMediaCard(dynamic item, Function(dynamic) onItemTap) {
    String name = '';
    String imageUrl = '';
    String uniqueId = '';
    String? sourceLabel;
    double? rating;
    String? summaryStr;
    Future<BangumiAnime>? detailFuture;
    
    if (item is JellyfinMediaItem) {
      name = item.name;
      uniqueId = 'jellyfin_${item.id}';
      sourceLabel = 'Jellyfin';
      rating = item.communityRating != null ? double.tryParse(item.communityRating!) : null;
      try {
        imageUrl = JellyfinService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
      if (item.overview != null && item.overview!.isNotEmpty) {
        summaryStr = item.overview;
      }
    } else if (item is EmbyMediaItem) {
      name = item.name;
      uniqueId = 'emby_${item.id}';
      sourceLabel = 'Emby';
      rating = item.communityRating != null ? double.tryParse(item.communityRating!) : null;
      try {
        imageUrl = EmbyService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
      if (item.overview != null && item.overview!.isNotEmpty) {
        summaryStr = item.overview;
      }
    } else if (item is WatchHistoryItem) {
      name = item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画');
      uniqueId = 'history_${item.animeId ?? 0}_${item.filePath.hashCode}';
      imageUrl = item.thumbnailPath ?? '';
      sourceLabel = '本地';
      // 观看历史如果有animeId也可以尝试获取简介
      if (_isValidAnimeId(item.animeId)) {
        detailFuture = BangumiService.instance.getAnimeDetails(item.animeId!);
      }
    } else if (item is LocalAnimeItem) {
      name = item.animeName;
      uniqueId = 'local_${item.animeId}_${item.animeName}';
      // 优先使用item中的imageUrl，如果为空则尝试从缓存获取
      imageUrl = item.imageUrl ?? '';
      if (imageUrl.isEmpty && _isValidAnimeId(item.animeId)) {
         imageUrl = _localImageCache[item.animeId] ?? '';
      }
      sourceLabel = '本地';
      
      if (_isValidAnimeId(item.animeId)) {
        detailFuture = BangumiService.instance.getAnimeDetails(item.animeId!);
      }
    } else if (item is DandanplayRemoteAnimeGroup) {
      name = item.title;
      uniqueId = 'dandan_${item.animeId ?? item.title.hashCode}_${item.episodeCount}';
      imageUrl = _getDandanGroupImage(item);
      sourceLabel = '弹弹play';
      rating = null;
      if (_isValidAnimeId(item.animeId)) {
        detailFuture = BangumiService.instance.getAnimeDetails(item.animeId!);
      }
    } else if (item is BangumiAnime) {
      name = item.nameCn.isNotEmpty ? item.nameCn : item.name;
      uniqueId = 'bangumi_${item.id}';
      imageUrl = item.imageUrl;
      sourceLabel = 'Bangumi';
      rating = item.rating;
      // 动画详情通常需要异步获取更详细的简介
      detailFuture = BangumiService.instance.getAnimeDetails(item.id);
    }

    const double cardWidth = 320;
    const double cardHeight = 140;

    Widget buildCard(String? summary, {String? progress}) {
      return SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: HorizontalAnimeCard(
          key: ValueKey(uniqueId),
          title: name,
          imageUrl: imageUrl,
          onTap: () => onItemTap(item),
          source: sourceLabel,
          rating: rating,
          summary: summary,
          progress: progress ?? _getWatchProgressForDashboard(item),
        ),
      );
    }

    if (detailFuture != null) {
      return FutureBuilder<BangumiAnime>(
        future: detailFuture,
        builder: (context, snapshot) {
          String? asyncSummary;
          String? asyncProgress;
          if (snapshot.hasData) {
            if (snapshot.data!.summary != null) {
              asyncSummary = snapshot.data!.summary;
            }
            // 如果从详情中拿到了总集数，更新进度显示
            if (snapshot.data!.totalEpisodes != null && snapshot.data!.totalEpisodes! > 0) {
              asyncProgress = _getWatchProgressForDashboard(item);
            }
          }
          return buildCard(asyncSummary, progress: asyncProgress);
        },
      );
    }

    return buildCard(summaryStr);
  }

  String _buildDandanRecommendedId(DandanplayRemoteAnimeGroup group) {
    final animeId = group.animeId;
    if (_isValidAnimeId(animeId)) {
      return 'dandan_$animeId';
    }
    final hash = group.primaryHash;
    if (hash != null && hash.isNotEmpty) {
      return 'dandan_hash_$hash';
    }
    return 'dandan_${group.title.hashCode}_${group.episodeCount}_${group.latestPlayTime?.millisecondsSinceEpoch ?? 0}';
  }

  String _getDandanGroupImage(DandanplayRemoteAnimeGroup group) {
    final animeId = group.animeId;
    if (_isValidAnimeId(animeId)) {
      final id = animeId!;
      final cached = _localImageCache[id];
      if (cached != null && cached.isNotEmpty) {
        return cached;
      }
    }
    try {
      final provider = Provider.of<DandanplayRemoteProvider>(context, listen: false);
      return provider.buildImageUrl(group.primaryHash ?? '') ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String?> _resolveDandanCoverForGroup(
    DandanplayRemoteAnimeGroup group,
    DandanplayRemoteProvider? provider,
  ) async {
    final animeId = group.animeId;
    final providerImage = provider?.buildImageUrl(group.primaryHash ?? '');
    if (!_isValidAnimeId(animeId)) {
      return providerImage;
    }

    final validId = animeId!;
    String? nonHdFallback;

    final cached = _localImageCache[validId];
    if (cached != null && cached.isNotEmpty) {
      if (_looksHighQualityUrl(cached)) {
        return cached;
      }
      nonHdFallback = cached;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(
          '${_DashboardHomePageState._localPrefsKeyPrefix}$validId');
      if (persisted != null && persisted.isNotEmpty) {
        if (_looksHighQualityUrl(persisted)) {
          _localImageCache[validId] = persisted;
          return persisted;
        }
        nonHdFallback ??= persisted;
        _localImageCache[validId] = persisted;
      }
    } catch (e) {
      debugPrint('[Dandan封面] 读取持久化缓存失败 animeId=$validId error=$e');
    }

    try {
      final detail = await BangumiService.instance.getAnimeDetails(validId);
      final highQuality = await _getHighQualityImage(validId, detail);
      if (highQuality != null && highQuality.isNotEmpty) {
        _localImageCache[validId] = highQuality;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              '${_DashboardHomePageState._localPrefsKeyPrefix}$validId',
              highQuality);
        } catch (e) {
          debugPrint('[Dandan封面] 写入持久化缓存失败 animeId=$validId error=$e');
        }
        return highQuality;
      }

      final fallbackImage = detail.imageUrl;
      if (fallbackImage.isNotEmpty) {
        _localImageCache[validId] = fallbackImage;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(
              '${_DashboardHomePageState._localPrefsKeyPrefix}$validId',
              fallbackImage);
        } catch (e) {
          debugPrint('[Dandan封面] 写入持久化缓存失败 animeId=$validId error=$e');
        }
        return fallbackImage;
      }
    } catch (e) {
      debugPrint('[Dandan封面] 获取Bangumi详情失败 animeId=$validId error=$e');
    }

    debugPrint('[Dandan封面] Bangumi高清失败，尝试使用弹弹play原图 animeId=$validId');
    final fallback = nonHdFallback ?? providerImage;
    if (fallback != null && fallback.isNotEmpty) {
      _localImageCache[validId] = fallback;
      return fallback;
    }
    return providerImage;
  }

  SharedRemoteEpisode? _mapDandanEpisodeToShared(
    DandanplayRemoteEpisode episode,
    DandanplayRemoteProvider provider,
  ) {
    final streamUrl = provider.buildStreamUrlForEpisode(episode);
    if (streamUrl == null || streamUrl.isEmpty) {
      return null;
    }

    final resolvedEpisodeId = episode.episodeId ??
        (episode.entryId.isNotEmpty
            ? episode.entryId.hashCode
            : (episode.hash.isNotEmpty
                ? episode.hash.hashCode
                : episode.name.hashCode));

    final shareKey = episode.entryId.isNotEmpty
        ? episode.entryId
        : (episode.hash.isNotEmpty ? episode.hash : episode.path);

    return SharedRemoteEpisode(
      shareId: 'dandan_$shareKey',
      title:
          episode.episodeTitle.isNotEmpty ? episode.episodeTitle : episode.name,
      fileName: episode.name,
      streamPath: streamUrl,
      fileExists: true,
      animeId: episode.animeId,
      episodeId: resolvedEpisodeId,
      duration: episode.duration,
      lastPosition: 0,
      progress: 0,
      fileSize: episode.size,
      lastWatchTime: episode.lastPlay ?? episode.created,
      videoHash: episode.hash.isNotEmpty ? episode.hash : null,
    );
  }

  WatchHistoryItem _buildDandanWatchHistoryItem({
    required SharedRemoteAnimeSummary summary,
    required SharedRemoteEpisode episode,
  }) {
    final duration = episode.duration ?? 0;
    final lastPosition = episode.lastPosition ?? 0;
    double progress = episode.progress ?? 0;
    if (progress <= 0 && duration > 0 && lastPosition > 0) {
      progress = (lastPosition / duration).clamp(0.0, 1.0);
    }

    return WatchHistoryItem(
      filePath: episode.streamPath,
      animeName:
          summary.nameCn?.isNotEmpty == true ? summary.nameCn! : summary.name,
      episodeTitle: episode.title,
      episodeId: episode.episodeId,
      animeId: summary.animeId,
      watchProgress: progress,
      lastPosition: lastPosition,
      duration: duration,
      lastWatchTime: episode.lastWatchTime ?? summary.lastWatchTime,
      thumbnailPath: summary.imageUrl,
      isFromScan: false,
      videoHash: episode.videoHash,
    );
  }

  PlayableItem _buildDandanPlayableFromShared({
    required SharedRemoteAnimeSummary summary,
    required SharedRemoteEpisode episode,
  }) {
    final watchItem = _buildDandanWatchHistoryItem(
      summary: summary,
      episode: episode,
    );
    return PlayableItem(
      videoPath: watchItem.filePath,
      title: watchItem.animeName,
      subtitle: watchItem.episodeTitle,
      animeId: watchItem.animeId,
      episodeId: watchItem.episodeId,
      historyItem: watchItem,
      actualPlayUrl: watchItem.filePath,
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    final now = DateTime.now();
    
    // iOS平台特殊处理：检查截图文件的修改时间
    if (Platform.isIOS && item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        try {
          final fileModified = thumbnailFile.lastModifiedSync();
          final cacheKey = '${item.filePath}_${fileModified.millisecondsSinceEpoch}';
          
          // 使用包含文件修改时间的缓存key，确保文件更新后缓存失效
          if (_thumbnailCache.containsKey(cacheKey)) {
            final cachedData = _thumbnailCache[cacheKey]!;
            final lastRenderTime = cachedData['time'] as DateTime;
            
            if (now.difference(lastRenderTime).inSeconds < 60) {
              return cachedData['widget'] as Widget;
            }
          }
          
          // 清理旧的缓存条目（相同filePath但不同修改时间）
          _thumbnailCache.removeWhere((key, value) => key.startsWith('${item.filePath}_'));
          
          final thumbnailWidget = FutureBuilder<Uint8List>(
            future: thumbnailFile.readAsBytes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Container(color: Colors.white10);
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return _buildDefaultThumbnail(item);
              }
              if (snapshot.data!.isEmpty) {
                return _buildDefaultThumbnail(item);
              }
              try {
                return Image.memory(
                  snapshot.data!,
                  key: ValueKey('${item.filePath}_${fileModified.millisecondsSinceEpoch}'),
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, __, ___) => _buildDefaultThumbnail(item),
                );
              } catch (e) {
                return _buildDefaultThumbnail(item);
              }
            },
          );
          
          // 使用新的缓存key存储
          _thumbnailCache[cacheKey] = {
            'widget': thumbnailWidget,
            'time': now
          };
          
          return thumbnailWidget;
        } catch (e) {
          debugPrint('获取截图文件修改时间失败: $e');
        }
      }
    }
    
    // 非iOS平台或获取修改时间失败时的原有逻辑
    if (_thumbnailCache.containsKey(item.filePath)) {
      final cachedData = _thumbnailCache[item.filePath]!;
      final lastRenderTime = cachedData['time'] as DateTime;
      
      if (now.difference(lastRenderTime).inSeconds < 60) {
        return cachedData['widget'] as Widget;
      }
    }
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        final thumbnailWidget = FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(color: Colors.white10);
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildDefaultThumbnail(item);
            }
            if (snapshot.data!.isEmpty) {
              return _buildDefaultThumbnail(item);
            }
            try {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (_, __, ___) => _buildDefaultThumbnail(item),
              );
            } catch (e) {
              return _buildDefaultThumbnail(item);
            }
          },
        );
        
        // 缓存生成的缩略图和当前时间
        _thumbnailCache[item.filePath] = {
          'widget': thumbnailWidget,
          'time': now
        };
        
        return thumbnailWidget;
      }
    }

    final defaultThumbnail = _buildDefaultThumbnail(item);
    
    // 缓存默认缩略图和当前时间
    _thumbnailCache[item.filePath] = {
      'widget': defaultThumbnail,
      'time': now
    };
    
    return defaultThumbnail;
  }

  Widget _buildDefaultThumbnail(WatchHistoryItem item) {
    if (item.animeId == null) {
      return Container(
        color: Colors.white10,
        child: const Center(
          child: Icon(Icons.video_library, color: Colors.white30, size: 32),
        ),
      );
    }

    return FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        String? imageUrl;
        if (snapshot.hasData) {
          imageUrl = snapshot.data!.getString(
              '${_DashboardHomePageState._localPrefsKeyPrefix}${item.animeId}');
        }

        if (imageUrl == null || imageUrl.isEmpty) {
          return Container(
            color: Colors.white10,
            child: const Center(
              child: Icon(Icons.video_library, color: Colors.white30, size: 32),
            ),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.white),
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (context, url, error) => Container(color: Colors.white10),
              ),
            ),
            Container(color: Colors.black.withValues(alpha: 0.2)), // 稍微调暗一点
            const Center(
              child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 32),
            ),
          ],
        );
      },
    );
  }
}

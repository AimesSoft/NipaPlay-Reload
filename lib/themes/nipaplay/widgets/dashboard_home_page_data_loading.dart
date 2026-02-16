part of dashboard_home_page;

extension DashboardHomePageDataLoading on _DashboardHomePageState {
  Future<void> _loadData({
    bool forceRefreshRecommended = false,
    bool forceRefreshRandom = false,
    bool forceRefreshToday = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    _lastLoadTime = DateTime.now();
    
    // 检查Widget状态
    if (!mounted) {
      return;
    }
    
    // 如果播放器处于活跃状态，跳过数据加载
    if (_isVideoPlayerActive()) {
      return;
    }
    
    // 如果正在加载，先检查是否需要强制重新加载
    if (_isLoadingRecommended) {
      return;
    }
    
    // 🔥 修复仪表盘启动问题：确保WatchHistoryProvider已加载
    try {
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!watchHistoryProvider.isLoaded && !watchHistoryProvider.isLoading) {
        await watchHistoryProvider.loadHistory();
      }
    } catch (_) {
    }
    
    
    final shouldForceRecommended = forceRefreshRecommended ||
        _recommendedItems.isEmpty ||
        _recommendedItems.every((item) => item.source == RecommendedItemSource.placeholder);

    // 并行加载推荐内容、最近内容、今日新番和随机推荐
    try {
      final futures = <Future<void>>[
        _loadRecommendedContent(forceRefresh: shouldForceRecommended),
        _loadRecentContent(),
      ];
      futures.addAll([
        _loadTodayAnimes(forceRefresh: forceRefreshToday),
        _loadRandomRecommendations(forceRefresh: forceRefreshRandom),
      ]);
      await Future.wait(futures);
    } catch (_) {
      // 如果并行加载失败，尝试串行加载
      try {
        await _loadRecommendedContent(forceRefresh: shouldForceRecommended);
        await _loadRecentContent();
        await _loadTodayAnimes(forceRefresh: forceRefreshToday);
        await _loadRandomRecommendations(forceRefresh: forceRefreshRandom);
      } catch (_) {
      }
    }
    
    stopwatch.stop();
  }

  void _handleManualRefresh() {
    if (_isLoadingRecommended) {
      return;
    }
    unawaited(_loadData(
      forceRefreshRecommended: true,
      forceRefreshRandom: true,
      forceRefreshToday: true,
    ));
    final syncService = ServerHistorySyncService.instance;
    unawaited(syncService.syncJellyfinResume());
    unawaited(syncService.syncEmbyResume());
  }

  // 检查并处理待处理的刷新请求
  void _checkPendingRefresh() {
    if (_pendingRefreshAfterLoad && mounted) {
      _pendingRefreshAfterLoad = false;
      _pendingRefreshReason = '';
      // 使用短延迟避免连续调用，并检查播放器状态
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_isLoadingRecommended && !_isVideoPlayerActive()) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadTodayAnimes({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoadingTodayAnimes = true);
    try {
      List<BangumiAnime> allAnimes;
      if (kIsWeb) {
        final apiUri = WebRemoteAccessService.apiUri('/api/bangumi/calendar');
        if (apiUri == null) {
          throw Exception('未配置远程访问地址');
        }
        final response = await http.get(apiUri);
        if (response.statusCode == 200) {
          final List<dynamic> data =
              json.decode(utf8.decode(response.bodyBytes));
          allAnimes = data
              .map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>))
              .toList();
        } else {
          throw Exception('Failed to load from API: ${response.statusCode}');
        }
      } else {
        final prefs = await SharedPreferences.getInstance();
        final bool filterAdultContentGlobally =
            prefs.getBool('global_filter_adult_content') ?? true;
        allAnimes = await BangumiService.instance.getCalendar(
          forceRefresh: forceRefresh,
          filterAdultContent: filterAdultContentGlobally,
        );
      }

      final now = DateTime.now();
      // Bangumi API (Dandanplay): 0 为周日, 1-6 为周一至周六
      // Flutter DateTime: 1-7 (周一至周日)
      int weekday = now.weekday;
      if (weekday == 7) weekday = 0; // 将周日从 7 转换为 0

      if (mounted) {
        setState(() {
          final List<BangumiAnime> todayList =
              allAnimes.where((a) => a.airWeekday == weekday).toList();
          
          // 如果今天确实没有（虽然不常见），但在 allAnimes 不为空的情况下，
          // 我们可能不需要清空 _todayAnimes 如果它之前有数据？
          // 但这里是 forceRefresh，所以我们应该信任最新的。
          
          _todayAnimes = todayList;
          _isLoadingTodayAnimes = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTodayAnimes = false);
    }
  }

  Future<void> _loadRecommendedContent({bool forceRefresh = false}) async {
    if (!mounted) {
      return;
    }
    
    // 检查是否强制刷新或缓存已过期
    final shouldBypassCache = _shouldBypassRecommendedCache();
    if (!forceRefresh &&
        !shouldBypassCache &&
        _DashboardHomePageState._cachedRecommendedItems.isNotEmpty &&
        _DashboardHomePageState._lastRecommendedLoadTime != null &&
        DateTime.now()
                .difference(_DashboardHomePageState._lastRecommendedLoadTime!)
                .inHours <
            24) {
      setState(() {
        _recommendedItems = _DashboardHomePageState._cachedRecommendedItems;
        _recommendedDandanLookup =
            Map.from(_DashboardHomePageState._cachedDandanLookup);
        _isLoadingRecommended = false;
      });
      
      // 推荐内容加载完成后启动自动切换
      if (_recommendedItems.length >= 5) {
        _startAutoSwitch();
      }
      
      return;
    }

    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      // 第一步：快速收集所有候选项目（只收集基本信息）
      List<dynamic> allCandidates = [];
      DandanplayRemoteProvider? dandanProvider;
      try {
        dandanProvider = Provider.of<DandanplayRemoteProvider>(context, listen: false);
      } catch (_) {}
      final dandanSource = dandanProvider;
      final Map<String, DandanplayRemoteAnimeGroup> dandanLookup = {};

      // 从Jellyfin收集候选项目（按媒体库并行）
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        final jellyfinFutures = <Future<List<JellyfinMediaItem>>>[];
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            jellyfinFutures.add(
              jellyfinService
                  .getRandomMediaItemsByLibrary(library.id, limit: 50)
                  .then((items) {
                    return items;
                  })
                  .catchError((e) {
                    return <JellyfinMediaItem>[];
                  }),
            );
          }
        }
        if (jellyfinFutures.isNotEmpty) {
          final results = await Future.wait(jellyfinFutures, eagerError: false);
          for (final items in results) {
            allCandidates.addAll(items);
          }
        }
      }

      // 从Emby收集候选项目（按媒体库并行）
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        final embyFutures = <Future<List<EmbyMediaItem>>>[];
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            embyFutures.add(
              embyService
                  .getRandomMediaItemsByLibrary(library.id, limit: 50)
                  .then((items) {
                    return items;
                  })
                  .catchError((e) {
                    return <EmbyMediaItem>[];
                  }),
            );
          }
        }
        if (embyFutures.isNotEmpty) {
          final results = await Future.wait(embyFutures, eagerError: false);
          for (final items in results) {
            allCandidates.addAll(items);
          }
        }
      }

      // 从本地媒体库收集候选项目
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://') &&
            !MediaSourceUtils.isSmbPath(item.filePath) &&
            !MediaSourceUtils.isWebDavPath(item.filePath) &&
            !item.isDandanplayRemote
          ).toList();
          
          // 按animeId分组，获取每个动画的最新观看记录
          final Map<int, WatchHistoryItem> latestLocalItems = {};
          for (var item in localHistory) {
            final animeId = item.animeId;
            if (!_isValidAnimeId(animeId)) {
              continue;
            }
            final id = animeId!;
            if (latestLocalItems.containsKey(id)) {
              if (item.lastWatchTime.isAfter(latestLocalItems[id]!.lastWatchTime)) {
                latestLocalItems[id] = item;
              }
            } else {
              latestLocalItems[id] = item;
            }
          }
          
          // 随机选择一些本地项目 - 直接使用WatchHistoryItem作为候选
          final localItems = latestLocalItems.values.toList();
          localItems.shuffle(math.Random());
          final selectedLocalItems = localItems.take(math.min(30, localItems.length)).toList();
          allCandidates.addAll(selectedLocalItems);
        } catch (_) {
        }
      }

      // 从弹弹play远程媒体库收集候选项目
      if (dandanSource != null &&
          dandanSource.isConnected &&
          dandanSource.animeGroups.isNotEmpty) {
        final groups = List<DandanplayRemoteAnimeGroup>.from(dandanSource.animeGroups);
        groups.shuffle(math.Random());
        final selectedGroups = groups.take(math.min(30, groups.length)).toList();
        final dandanAnimeIds = selectedGroups
            .map((group) => group.animeId)
            .whereType<int>()
            .toSet();
        if (dandanAnimeIds.isNotEmpty) {
          await _loadPersistedLocalImageUrls(dandanAnimeIds);
        }
        allCandidates.addAll(selectedGroups);
      }

      // 第二步：从所有候选中随机选择7个（去重）
      List<dynamic> selectedCandidates = [];
      if (allCandidates.isNotEmpty) {
        allCandidates.shuffle(math.Random());
        final seenKeys = <String>{};
        for (final candidate in allCandidates) {
          final keys = _buildRecommendationDedupKeys(candidate);
          if (keys.isNotEmpty && keys.any(seenKeys.contains)) {
            continue;
          }
          selectedCandidates.add(candidate);
          if (keys.isNotEmpty) {
            seenKeys.addAll(keys);
          }
          if (selectedCandidates.length >= 7) {
            break;
          }
        }
      }

      // 第二点五步：预加载本地媒体项目的图片缓存，确保立即显示
      final localAnimeIds = selectedCandidates
          .whereType<WatchHistoryItem>()
          .where((item) => _isValidAnimeId(item.animeId))
          .map((item) => item.animeId!)
          .toSet();
      if (localAnimeIds.isNotEmpty) {
        await _loadPersistedLocalImageUrls(localAnimeIds);
      }

      final dandanAnimeIds = selectedCandidates
          .whereType<DandanplayRemoteAnimeGroup>()
          .map((group) => group.animeId)
          .whereType<int>()
          .where(_isValidAnimeId)
          .toSet();
      if (dandanAnimeIds.isNotEmpty) {
        await _loadPersistedLocalImageUrls(dandanAnimeIds);
      }

      // 第三步：快速构建基础推荐项目，先用缓存的封面图片
      List<RecommendedItem> basicItems = [];
      final itemFutures = selectedCandidates.map((item) async {
        try {
          if (item is JellyfinMediaItem) {
            // Jellyfin项目 - 首屏即加载 Backdrop/Logo/详情（带验证与回退）
            final jellyfinService = JellyfinService.instance;
            final results = await Future.wait([
              _tryGetJellyfinImage(jellyfinService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetJellyfinImage(jellyfinService, item.id, ['Logo', 'Thumb']),
              _getJellyfinItemSubtitle(jellyfinService, item),
            ]);
            final backdropCandidate = results[0] as MapEntry<String, String>?;
            final logoCandidate = results[1] as MapEntry<String, String>?;
            final subtitle = results[2] as String?;
            final backdropUrl = backdropCandidate?.value;
            final logoUrl = logoCandidate?.value;
            final normalizedBackdropUrl = _normalizeRecommendationImageUrl(backdropUrl);
            final normalizedLogoUrl = _normalizeRecommendationImageUrl(logoUrl);

            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: (subtitle?.isNotEmpty == true) ? subtitle! : (item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息'),
              backgroundImageUrl: normalizedBackdropUrl,
              logoImageUrl: normalizedLogoUrl,
              source: RecommendedItemSource.jellyfin,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
              isLowRes: _shouldBlurLowResCover(imageType: backdropCandidate?.key, imageUrl: backdropUrl),
            );
            
          } else if (item is EmbyMediaItem) {
            // Emby项目 - 首屏即加载 Backdrop/Logo/详情（带验证与回退）
            final embyService = EmbyService.instance;
            final results = await Future.wait([
              _tryGetEmbyImage(embyService, item.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
              _tryGetEmbyImage(embyService, item.id, ['Logo', 'Thumb']),
              _getEmbyItemSubtitle(embyService, item),
            ]);
            final backdropCandidate = results[0] as MapEntry<String, String>?;
            final logoCandidate = results[1] as MapEntry<String, String>?;
            final subtitle = results[2] as String?;
            final backdropUrl = backdropCandidate?.value;
            final logoUrl = logoCandidate?.value;
            final normalizedBackdropUrl = _normalizeRecommendationImageUrl(backdropUrl);
            final normalizedLogoUrl = _normalizeRecommendationImageUrl(logoUrl);

            return RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: (subtitle?.isNotEmpty == true) ? subtitle! : (item.overview?.isNotEmpty == true ? item.overview!
                  .replaceAll('<br>', ' ')
                  .replaceAll('<br/>', ' ')
                  .replaceAll('<br />', ' ') : '暂无简介信息'),
              backgroundImageUrl: normalizedBackdropUrl,
              logoImageUrl: normalizedLogoUrl,
              source: RecommendedItemSource.emby,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
              isLowRes: _shouldBlurLowResCover(imageType: backdropCandidate?.key, imageUrl: backdropUrl),
            );
            
          } else if (item is WatchHistoryItem) {
            // 本地媒体库项目 - 先用缓存的封面图片
            String? cachedImageUrl;
            String subtitle = '暂无简介信息';
            
            if (_isValidAnimeId(item.animeId)) {
              final animeId = item.animeId!;
              // 从缓存获取图片URL（来自本地图片缓存）
              cachedImageUrl = _localImageCache[animeId];
              
              // 优先读取持久化的高清图缓存（与媒体库页复用同一Key前缀）
              if (cachedImageUrl == null) {
                try {
                  final prefs = await SharedPreferences.getInstance();
                  final persisted = prefs.getString(
                      '${_DashboardHomePageState._localPrefsKeyPrefix}$animeId');
                  if (persisted != null && persisted.isNotEmpty) {
                    cachedImageUrl = persisted;
                    _localImageCache[animeId] = persisted; // 写回内存缓存
                  }
                } catch (_) {}
              }

              // 尝试从SharedPreferences获取已缓存的详情信息
              try {
                final prefs = await SharedPreferences.getInstance();
                final cacheKey = 'bangumi_detail_$animeId';
                final String? cachedString = prefs.getString(cacheKey);
                if (cachedString != null) {
                  final data = json.decode(cachedString);
                  final animeData = data['animeDetail'] as Map<String, dynamic>?;
                  if (animeData != null) {
                    final summary = animeData['summary'] as String?;
                    final imageUrl = animeData['imageUrl'] as String?;
                    if (summary?.isNotEmpty == true) {
                      subtitle = summary!;
                    }
                    if (cachedImageUrl == null && imageUrl?.isNotEmpty == true) {
                      cachedImageUrl = imageUrl;
                    }
                  }
                }
              } catch (_) {
                // 忽略缓存访问错误
              }
            }

            if (cachedImageUrl == null || cachedImageUrl.isEmpty) {
              cachedImageUrl = item.thumbnailPath;
            }
            cachedImageUrl = _normalizeRecommendationImageUrl(cachedImageUrl);
            
            return RecommendedItem(
              id: item.animeId?.toString() ?? item.filePath,
              title: item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画'),
              subtitle: subtitle,
              backgroundImageUrl: cachedImageUrl,
              logoImageUrl: null,
              source: RecommendedItemSource.local,
              rating: null,
              isLowRes: cachedImageUrl != null, // 初始加载封面通常是低清
            );
          } else if (item is DandanplayRemoteAnimeGroup) {
            final dandanId = _buildDandanRecommendedId(item);
            final dandanLookupKey = dandanId;
            dandanLookup[dandanLookupKey] = item;
            
            final coverUrl = await _resolveDandanCoverForGroup(item, dandanSource);
            final normalizedCoverUrl = _normalizeRecommendationImageUrl(coverUrl);
            final subtitle = item.latestEpisode.episodeTitle.isNotEmpty
                ? item.latestEpisode.episodeTitle
                : '弹弹play远程媒体';
            return RecommendedItem(
              id: dandanId,
              title: item.title,
              subtitle: subtitle,
              backgroundImageUrl: normalizedCoverUrl,
              logoImageUrl: null,
              source: RecommendedItemSource.dandanplay,
              rating: null,
              isLowRes: coverUrl != null ? !_looksHighQualityUrl(coverUrl) : false,
            );
          }
        } catch (_) {
          return null;
        }
        return null;
      });
      
      // 等待基础项目构建完成
      final processedItems = await Future.wait(itemFutures);
      basicItems = processedItems.where((item) => item != null).cast<RecommendedItem>().toList();

      // 如果还不够7个，添加占位符
      while (basicItems.length < 7) {
        basicItems.add(RecommendedItem(
          id: 'placeholder_${basicItems.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }

      // 第四步：立即显示基础项目
      if (mounted) {
        setState(() {
          _recommendedItems = basicItems;
          _recommendedDandanLookup = Map.from(dandanLookup);
          _isLoadingRecommended = false;
        });
        
        // 缓存推荐内容和加载时间
        _DashboardHomePageState._cachedRecommendedItems = basicItems;
        _DashboardHomePageState._lastRecommendedLoadTime = DateTime.now();
        _DashboardHomePageState._cachedDandanLookup = Map.from(dandanLookup);
        
        // 推荐内容加载完成后启动自动切换
        if (basicItems.length >= 5) {
          _startAutoSwitch();
        }
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
      
      // 第五步：后台异步升级为高清图片（针对本地和弹弹play远程媒体）
      final upgradeCandidates = <dynamic>[];
      final upgradeBasicItems = <RecommendedItem>[];
      final upgradeIndices = <int>[];
      for (int i = 0; i < selectedCandidates.length && i < basicItems.length; i++) {
        final cand = selectedCandidates[i];
        if (cand is WatchHistoryItem || cand is DandanplayRemoteAnimeGroup) {
          // 只对非占位项进行升级，避免索引错位导致更新失败
          final item = basicItems[i];
          if (item.source == RecommendedItemSource.placeholder) {
            continue;
          }
          upgradeCandidates.add(cand);
          upgradeBasicItems.add(item);
          upgradeIndices.add(i);
        }
      }
      if (upgradeCandidates.isNotEmpty) {
        debugPrint(
          '[DashboardHomePage] 推荐高清升级触发: total=${upgradeCandidates.length}, '
          'dandan=${upgradeCandidates.whereType<DandanplayRemoteAnimeGroup>().length}, '
          'local=${upgradeCandidates.whereType<WatchHistoryItem>().length}',
        );
        debugPrint('[DashboardHomePage] 升级索引: $upgradeIndices');
        _upgradeToHighQualityImages(upgradeCandidates, upgradeBasicItems, upgradeIndices);
      } else {
        debugPrint('[DashboardHomePage] 推荐高清升级跳过: 无可升级项');
      }
      
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingRecommended = false;
        });
        
        // 检查是否有待处理的刷新请求
        _checkPendingRefresh();
      }
    }
  }

  String? _normalizeRecommendationImageUrl(String? url) {
    if (url == null) return null;
    var value = url.trim();
    if (value.isEmpty) return null;
    if (value == 'assets/backempty.png' || value == 'assets/backEmpty.png') {
      return null;
    }
    if (value.startsWith('file://')) {
      value = value.substring('file://'.length);
    }
    if (!kIsWeb) return value;
    if (value.startsWith('data:') || value.startsWith('blob:')) {
      return value;
    }
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return WebRemoteAccessService.proxyUrl(value) ?? value;
    }
    return WebRemoteAccessService.imageProxyUrl(value) ?? value;
  }

  bool _shouldBypassRecommendedCache() {
    if (_DashboardHomePageState._cachedRecommendedItems.isEmpty) {
      return false;
    }

    bool jellyfinConnected = false;
    bool jellyfinHasLibraries = false;
    bool embyConnected = false;
    bool embyHasLibraries = false;
    bool dandanConnected = false;
    bool dandanHasGroups = false;

    try {
      final jellyfinProvider =
          Provider.of<JellyfinProvider>(context, listen: false);
      jellyfinConnected = jellyfinProvider.isConnected;
      jellyfinHasLibraries = jellyfinProvider.selectedLibraryIds.isNotEmpty;
    } catch (_) {}
    try {
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      embyConnected = embyProvider.isConnected;
      embyHasLibraries = embyProvider.selectedLibraryIds.isNotEmpty;
    } catch (_) {}
    try {
      final dandanProvider =
          Provider.of<DandanplayRemoteProvider>(context, listen: false);
      dandanConnected = dandanProvider.isConnected;
      dandanHasGroups = dandanProvider.animeGroups.isNotEmpty;
    } catch (_) {}

    final cached = _DashboardHomePageState._cachedRecommendedItems;
    final hasJellyfin =
        cached.any((item) => item.source == RecommendedItemSource.jellyfin);
    final hasEmby =
        cached.any((item) => item.source == RecommendedItemSource.emby);
    final hasDandan =
        cached.any((item) => item.source == RecommendedItemSource.dandanplay);

    if (jellyfinConnected && jellyfinHasLibraries && !hasJellyfin) {
      return true;
    }
    if (embyConnected && embyHasLibraries && !hasEmby) return true;
    if (dandanConnected && dandanHasGroups && !hasDandan) return true;
    return false;
  }

  String _normalizeRecommendationTitle(String title) {
    final trimmed = title.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return '';
    }
    return trimmed.replaceAll(RegExp(r'\s+'), ' ');
  }

  void _addTitleKey(List<String> keys, String? title) {
    if (title == null || title.isEmpty) return;
    final normalized = _normalizeRecommendationTitle(title);
    if (normalized.isEmpty) return;
    keys.add('title:$normalized');
  }

  List<String> _buildRecommendationDedupKeys(dynamic candidate) {
    final keys = <String>[];

    if (candidate is JellyfinMediaItem) {
      _addTitleKey(keys, candidate.name);
      _addTitleKey(keys, candidate.originalTitle);
    } else if (candidate is EmbyMediaItem) {
      _addTitleKey(keys, candidate.name);
      _addTitleKey(keys, candidate.originalTitle);
    } else if (candidate is WatchHistoryItem) {
      if (_isValidAnimeId(candidate.animeId)) {
        keys.add('anime:${candidate.animeId}');
      }
      _addTitleKey(keys, candidate.animeName);
    } else if (candidate is DandanplayRemoteAnimeGroup) {
      if (_isValidAnimeId(candidate.animeId)) {
        keys.add('anime:${candidate.animeId}');
      }
      _addTitleKey(keys, candidate.title);
    }

    if (keys.length <= 1) return keys;
    return keys.toSet().toList();
  }

  Future<void> _loadRecentContent({bool includeRemote = true}) async {
    if (_isLoadingRecentContent) {
      return;
    }
    _isLoadingRecentContent = true;
    try {
      DandanplayRemoteProvider? dandanProvider;
      try {
        dandanProvider = Provider.of<DandanplayRemoteProvider>(context, listen: false);
      } catch (_) {}
      if (includeRemote) {
        // 从Jellyfin按媒体库获取最近添加（按库并行）
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        if (jellyfinProvider.isConnected) {
          final jellyfinService = JellyfinService.instance;
          _recentJellyfinItemsByLibrary.clear();
          final jfFutures = <Future<void>>[];
          for (final library in jellyfinService.availableLibraries) {
            if (jellyfinService.selectedLibraryIds.contains(library.id)) {
              jfFutures.add(() async {
                try {
                  final libraryItems = await jellyfinService.getLatestMediaItemsByLibrary(library.id, limit: 25);
                  if (libraryItems.isNotEmpty) {
                    _recentJellyfinItemsByLibrary[library.name] = libraryItems;
                  }
                } catch (_) {
                }
              }());
            }
          }
          if (jfFutures.isNotEmpty) {
            await Future.wait(jfFutures, eagerError: false);
          }
        } else {
          // 未连接时确保清空
          _recentJellyfinItemsByLibrary.clear();
        }

        // 从Emby按媒体库获取最近添加（按库并行）
        final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
        if (embyProvider.isConnected) {
          final embyService = EmbyService.instance;
          _recentEmbyItemsByLibrary.clear();
          final emFutures = <Future<void>>[];
          for (final library in embyService.availableLibraries) {
            if (embyService.selectedLibraryIds.contains(library.id)) {
              emFutures.add(() async {
                try {
                  final libraryItems = await embyService.getLatestMediaItemsByLibrary(library.id, limit: 25);
                  if (libraryItems.isNotEmpty) {
                    _recentEmbyItemsByLibrary[library.name] = libraryItems;
                  }
                } catch (_) {
                }
              }());
            }
          }
          if (emFutures.isNotEmpty) {
            await Future.wait(emFutures, eagerError: false);
          }
        } else {
          // 未连接时确保清空
          _recentEmbyItemsByLibrary.clear();
        }
      }

      // 从本地媒体库获取最近添加（优化：不做逐文件stat，按历史记录时间排序，图片懒加载+持久化）
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://') &&
            !MediaSourceUtils.isSmbPath(item.filePath) &&
            !MediaSourceUtils.isWebDavPath(item.filePath) &&
            !item.isDandanplayRemote
          ).toList();

          // 按animeId分组，选取"添加时间"代表：
          // 优先使用 isFromScan 为 true 的记录的 lastWatchTime（扫描入库时间），否则用最近一次 lastWatchTime
          final Map<int, WatchHistoryItem> representativeItems = {};
          final Map<int, DateTime> addedTimeMap = {};

          for (final item in localHistory) {
            final animeId = item.animeId;
            if (!_isValidAnimeId(animeId)) continue;
            final id = animeId!;

            final candidateTime = item.lastWatchTime;
            if (!representativeItems.containsKey(id)) {
              representativeItems[id] = item;
              addedTimeMap[id] = candidateTime;
            } else {
              // 对于同一番组，取时间更新的那条作为代表
              if (candidateTime.isAfter(addedTimeMap[id]!)) {
                representativeItems[id] = item;
                addedTimeMap[id] = candidateTime;
              }
            }
          }

          // 提前从本地持久化中加载图片URL缓存，避免首屏大量网络请求
          await _loadPersistedLocalImageUrls(addedTimeMap.keys.toSet());

          // 构建 LocalAnimeItem 列表（先用缓存命中图片，未命中先留空，稍后后台补齐）
          List<LocalAnimeItem> localAnimeItems = representativeItems.entries.map((entry) {
            final animeId = entry.key;
            final latestEpisode = entry.value;
            final addedTime = addedTimeMap[animeId]!;
            final cachedImg = _localImageCache[animeId];
            return LocalAnimeItem(
              animeId: animeId,
              animeName: latestEpisode.animeName.isNotEmpty ? latestEpisode.animeName : '未知动画',
              imageUrl: cachedImg,
              backdropImageUrl: cachedImg,
              addedTime: addedTime,
              latestEpisode: latestEpisode,
            );
          }).toList();

          // 排序（最新在前）并限制数量
          localAnimeItems.sort((a, b) => b.addedTime.compareTo(a.addedTime));
          if (localAnimeItems.length > 25) {
            localAnimeItems = localAnimeItems.take(25).toList();
          }

          _localAnimeItems = localAnimeItems;
        } catch (_) {
        }
      } else {
        _localAnimeItems = []; // 清空本地项目列表
      }

      // 弹弹play远程媒体库最近添加
      final dandanSource = dandanProvider;
      if (dandanSource != null &&
          dandanSource.isConnected &&
          dandanSource.animeGroups.isNotEmpty) {
        List<DandanplayRemoteAnimeGroup> groups =
            List<DandanplayRemoteAnimeGroup>.from(dandanSource.animeGroups);
        groups.sort((a, b) {
          final aTime = a.latestPlayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = b.latestPlayTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });
        if (groups.length > 25) {
          groups = groups.take(25).toList();
        }
        final ids = groups
          .map((g) => g.animeId)
          .whereType<int>()
          .where(_isValidAnimeId)
          .toSet();
        if (ids.isNotEmpty) {
          await _loadPersistedLocalImageUrls(ids);
        }
        _recentDandanplayGroups = groups;
      } else {
        _recentDandanplayGroups = [];
      }

      if (mounted) {
        setState(() {
          // 触发UI更新
        });

        // 首屏渲染后，后台限流补齐缺失图片与番组详情（避免阻塞UI）
        _fetchLocalAnimeImagesInBackground();
        if (dandanSource != null && dandanSource.isConnected) {
          _fetchDandanGroupImagesInBackground(dandanSource);
        }
      }
    } catch (_) {
    } finally {
      _isLoadingRecentContent = false;
    }
  }

  // 加载持久化的本地番组图片URL（与媒体库页复用同一Key前缀）
  Future<void> _loadPersistedLocalImageUrls(Set<int> animeIds) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final id in animeIds) {
        if (!_isValidAnimeId(id)) continue;
        if (_localImageCache.containsKey(id)) continue;
        final url = prefs.getString(
            '${_DashboardHomePageState._localPrefsKeyPrefix}$id');
        if (url != null && url.isNotEmpty) {
          _localImageCache[id] = url;
        }
      }
    } catch (_) {
    }
  }

  // 后台抓取缺失的番组图片，限流并写入持久化缓存（优化版本）
  Future<void> _fetchLocalAnimeImagesInBackground() async {
    if (_isLoadingLocalImages) return;
    _isLoadingLocalImages = true;
    
    
    const int maxConcurrent = 3;
    final inflight = <Future<void>>[];
    int processedCount = 0;
    int updatedCount = 0;

    for (final item in _localAnimeItems) {
      final id = item.animeId;
      if (!_isValidAnimeId(id)) {
        continue;
      }
      if (_localImageCache.containsKey(id) && 
          _localImageCache[id]?.isNotEmpty == true) {
        continue; // 已有缓存且不为空，跳过
      }

      Future<void> task() async {
        try {
          // 先尝试从BangumiService缓存获取
          String? imageUrl;
          // String? summary; // 暂时不需要summary变量
          
          // 尝试从SharedPreferences获取已缓存的详情
          try {
            final prefs = await SharedPreferences.getInstance();
            final cacheKey = 'bangumi_detail_$id';
            final String? cachedString = prefs.getString(cacheKey);
            if (cachedString != null) {
              final data = json.decode(cachedString);
              final animeData = data['animeDetail'] as Map<String, dynamic>?;
              if (animeData != null) {
                imageUrl = animeData['imageUrl'] as String?;
                // summary = animeData['summary'] as String?; // 不需要summary
              }
            }
          } catch (_) {
            // 忽略缓存读取错误
          }
          
          // 如果缓存中没有，再从网络获取
          if (imageUrl?.isEmpty != false) {
            final detail = await BangumiService.instance.getAnimeDetails(id);
            imageUrl = detail.imageUrl;
            // summary = detail.summary; // 不需要summary
          }
          
          if (imageUrl?.isNotEmpty == true) {
            _localImageCache[id] = imageUrl!;
            
            // 异步保存到持久化缓存
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(
                  '${_DashboardHomePageState._localPrefsKeyPrefix}$id',
                  imageUrl);
            } catch (_) {}
            
            if (mounted) {
              // 批量更新，减少UI重绘次数
              final idx = _localAnimeItems.indexWhere((e) => e.animeId == id);
              if (idx != -1) {
                _localAnimeItems[idx] = LocalAnimeItem(
                  animeId: _localAnimeItems[idx].animeId,
                  animeName: _localAnimeItems[idx].animeName,
                  imageUrl: imageUrl,
                  backdropImageUrl: imageUrl,
                  addedTime: _localAnimeItems[idx].addedTime,
                  latestEpisode: _localAnimeItems[idx].latestEpisode,
                );
                updatedCount++;
              }
            }
          }
          processedCount++;
        } catch (_) {
          // 静默失败，避免刷屏
          processedCount++;
        }
      }

      final fut = task();
      inflight.add(fut);
      fut.whenComplete(() {
        inflight.remove(fut);
      });
      
      if (inflight.length >= maxConcurrent) {
        try { 
          await Future.any(inflight); 
          // 每处理几个项目就更新一次UI，而不是等全部完成
          if (updatedCount > 0 && processedCount % 5 == 0 && mounted) {
            setState(() {});
          }
        } catch (_) {}
      }
    }

    try { 
      await Future.wait(inflight); 
    } catch (_) {}
    
    // 最终更新UI
    if (mounted && updatedCount > 0) {
      setState(() {});
    }
    
    _isLoadingLocalImages = false;
  }

  Future<void> _fetchDandanGroupImagesInBackground(DandanplayRemoteProvider provider) async {
    if (_isLoadingDandanImages) return;
    if (_recentDandanplayGroups.isEmpty) return;

    final targets = _recentDandanplayGroups
      .where((group) => _isValidAnimeId(group.animeId))
      .toList();
    if (targets.isEmpty) return;

    _isLoadingDandanImages = true;
    int updatedCount = 0;
    const int maxConcurrent = 3;
    final inflight = <Future<void>>[];

    Future<void> task(DandanplayRemoteAnimeGroup group) async {
      final animeId = group.animeId;
      if (!_isValidAnimeId(animeId)) return;
      final validId = animeId!;
      if (_localImageCache[validId]?.isNotEmpty == true) {
        return;
      }

      final cover = await _resolveDandanCoverForGroup(group, provider);
      if (cover != null && cover.isNotEmpty && mounted) {
        updatedCount++;
        if (updatedCount % 4 == 0) {
          setState(() {});
        }
      }
    }

    for (final group in targets) {
      final fut = task(group);
      inflight.add(fut);
      fut.whenComplete(() {
        inflight.remove(fut);
      });

      if (inflight.length >= maxConcurrent) {
        try {
          await Future.any(inflight);
        } catch (_) {}
      }
    }

    try {
      await Future.wait(inflight);
    } catch (_) {}

    if (mounted && updatedCount > 0) {
      setState(() {});
    }

    _isLoadingDandanImages = false;
  }
}

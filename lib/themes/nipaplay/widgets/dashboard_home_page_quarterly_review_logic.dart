part of dashboard_home_page;

enum _QuarterlyReviewSort {
  airDate('季度日期'),
  commentNewest('评论时间：新到旧'),
  commentOldest('评论时间：旧到新'),
  ratingHigh('用户评分：高到低'),
  ratingLow('用户评分：低到高');

  const _QuarterlyReviewSort(this.label);
  final String label;
}

class _QuarterlyReviewItem {
  const _QuarterlyReviewItem(this.anime, this.airDate,
      {this.dateLabel = '开播', this.rating, this.comment, this.commentAt});

  final BangumiAnime anime;
  final DateTime airDate;
  final String dateLabel;
  final int? rating;
  final String? comment;
  final int? commentAt;
}

extension _DashboardQuarterlyReviewLogic on _DashboardHomePageState {
  bool get _isQuarterlyReviewEnabled => (_appearanceSettingsProviderRef ??
          Provider.of<AppearanceSettingsProvider>(context, listen: false))
      .showQuarterlyAnimeReview;

  void _onReviewAppearanceChanged() {
    if (!mounted) return;
    final enabled = _isQuarterlyReviewEnabled;
    if (_lastQuarterlyReviewEnabled == enabled) return;
    _lastQuarterlyReviewEnabled = enabled;
    if (enabled) {
      unawaited(_loadQuarterlyReview());
    } else {
      setState(() => _quarterlyReviewItems = []);
    }
  }

  bool _hasQuarterlyReviewForToday() {
    final now = DateTime.now();
    final visibleSeason = QuarterlyReviewCache.visibleReviewSeason(now);
    return _isQuarterlyReviewEnabled &&
        _quarterlyReviewItems.isNotEmpty &&
        visibleSeason != null &&
        _quarterlyReviewYear == visibleSeason.year &&
        _quarterlyReviewMonth == visibleSeason.month;
  }

  void _onReviewCacheChanged() {
    if (mounted && _isQuarterlyReviewEnabled) unawaited(_loadQuarterlyReview());
  }

  void _onReviewLoginChanged() {
    if (!mounted || !_isQuarterlyReviewEnabled) return;
    if (!BangumiApiService.isLoggedIn && _quarterlyReviewItems.isNotEmpty) {
      setState(() {
        _quarterlyReviewItems = _quarterlyReviewItems
            .map((item) => _QuarterlyReviewItem(item.anime, item.airDate,
                dateLabel: item.dateLabel))
            .toList();
      });
    }
    unawaited(_loadQuarterlyReview());
  }

  Set<int> _reviewLibraryIds() {
    final ids = <int>{};
    final history = Provider.of<WatchHistoryProvider>(context, listen: false);
    if (history.isLoaded) {
      ids.addAll(history.history
          .map((item) => item.animeId)
          .whereType<int>()
          .where((id) => id > 0));
    }
    final dandan =
        Provider.of<DandanplayRemoteProvider>(context, listen: false);
    if (dandan.isConnected) {
      ids.addAll(dandan.animeGroups
          .map((group) => group.animeId)
          .whereType<int>()
          .where((id) => id > 0));
    }
    try {
      final shared =
          Provider.of<SharedRemoteLibraryProvider>(context, listen: false);
      ids.addAll(shared.animeSummaries
          .map((item) => item.animeId)
          .where((id) => id > 0));
    } catch (_) {}
    return ids;
  }

  Future<void> _loadQuarterlyReview() async {
    if (!mounted || !_isQuarterlyReviewEnabled) return;
    if (_isLoadingQuarterlyReview) {
      _reviewReloadAfterCurrent = true;
      return;
    }
    _isLoadingQuarterlyReview = true;
    try {
      final now = DateTime.now();
      final ids = _reviewLibraryIds();
      final cache = QuarterlyReviewCache.instance;
      await cache.adoptExistingDetails(ids);
      final userInfo = BangumiApiService.userInfo;
      final username = BangumiApiService.isLoggedIn && userInfo != null
          ? userInfo['username']?.toString()
          : null;
      final cached = await cache.itemsFor(ids, now, username);
      if (!mounted || !_isQuarterlyReviewEnabled) return;
      final targetSeason = QuarterlyReviewCache.visibleReviewSeason(now) ??
          DateTime(now.year, QuarterlyReviewCache.seasonMonth(now));
      setState(() {
        _quarterlyReviewItems = cached
            .map((item) => _QuarterlyReviewItem(item.anime, item.airDate,
                dateLabel: item.dateLabel,
                rating: item.rating,
                comment: item.comment,
                commentAt: item.commentAt))
            .toList();
        _quarterlyReviewYear = targetSeason.year;
        _quarterlyReviewMonth = targetSeason.month;
      });
      if (!_reviewCollectionsScheduled) {
        _reviewCollectionsScheduled = true;
        unawaited(_syncQuarterlyReviewCollections());
      }
      if (!_reviewWarmScheduled) {
        _reviewWarmScheduled = true;
        unawaited(_warmQuarterlyReview(ids));
      }
    } catch (error) {
      debugPrint('读取季度回顾缓存失败: $error');
    } finally {
      _isLoadingQuarterlyReview = false;
      if (_reviewReloadAfterCurrent && mounted) {
        _reviewReloadAfterCurrent = false;
        unawaited(_loadQuarterlyReview());
      }
    }
  }

  /// Metadata still uses the small daily quota. Known subjects have a separate
  /// paced collection queue so an uncached detail cannot delay their comments.
  Future<void> _warmQuarterlyReview(Set<int> ids) async {
    try {
      await Future.delayed(const Duration(seconds: 5));
      if (!mounted || !_isQuarterlyReviewEnabled || ids.isEmpty) return;
      final cache = QuarterlyReviewCache.instance;
      final id = await cache.reserveMetadataProbe(ids, DateTime.now());
      if (!mounted || !_isQuarterlyReviewEnabled) return;
      if (id != null) {
        try {
          if (kIsWeb) {
            final uri =
                WebRemoteAccessService.apiUri('/api/bangumi/detail/$id');
            if (uri != null) {
              final response = await http.get(uri);
              if (response.statusCode == 200) {
                final anime = BangumiAnime.fromJson(
                    json.decode(utf8.decode(response.bodyBytes))
                        as Map<String, dynamic>);
                await cache.recordAnime(anime);
              }
            }
          } else {
            await BangumiService.instance.getAnimeDetails(id);
          }
        } catch (_) {}
      }
    } catch (error) {
      debugPrint('季度回顾后台补全失败: $error');
    } finally {
      _reviewWarmScheduled = false;
    }
  }

  Future<void> _syncQuarterlyReviewCollections() async {
    String? username;
    try {
      await BangumiApiService.initialize();
      username = BangumiApiService.isLoggedIn
          ? (BangumiApiService.userInfo?['username']?.toString())
          : null;
      if (username == null || username.isEmpty) return;
      final account = username;
      final cache = QuarterlyReviewCache.instance;
      bool canContinue() =>
          mounted &&
          _isQuarterlyReviewEnabled &&
          BangumiApiService.isLoggedIn &&
          BangumiApiService.userInfo?['username']?.toString() == account;

      Future<bool> fetchCollection(int subjectId) async {
        try {
          final result = await BangumiApiService.getUserCollection(
            subjectId,
            username: account,
          );
          if (result['success'] == true) return true;
          await cache.deferCollectionProbes(DateTime.now(),
              statusCode: result['statusCode'] as int?);
        } catch (_) {
          await cache.deferCollectionProbes(DateTime.now());
        }
        return false;
      }

      // Start after the local cards are rendered. Each reservation persists
      // before sending, so reopening Home cannot restart a failed request burst.
      await Future.delayed(QuarterlyReviewCache.collectionProbeInterval);
      while (canContinue()) {
        final subjectId = await cache.reserveCollectionProbe(
          _reviewLibraryIds(),
          account,
          DateTime.now(),
          initialOnly: true,
        );
        if (subjectId == null || !canContinue()) break;
        if (!await fetchCollection(subjectId)) return;
        await Future.delayed(QuarterlyReviewCache.collectionProbeInterval);
      }
      if (!canContinue()) return;
      // Existing collections retain the slower one-per-day refresh quota.
      final subjectId = await cache.reserveCollectionProbe(
          _reviewLibraryIds(), account, DateTime.now());
      if (subjectId != null && canContinue()) {
        await fetchCollection(subjectId);
      }
    } catch (error) {
      debugPrint('季度回顾评论补全失败: $error');
    } finally {
      _reviewCollectionsScheduled = false;
      final currentUsername = BangumiApiService.isLoggedIn
          ? (BangumiApiService.userInfo?['username']?.toString())
          : null;
      if (mounted &&
          _isQuarterlyReviewEnabled &&
          currentUsername != null &&
          currentUsername != username) {
        unawaited(_loadQuarterlyReview());
      }
    }
  }

  Future<void> _editQuarterlyReviewComment(_QuarterlyReviewItem item) async {
    final subjectId = QuarterlyReviewCache.subjectId(item.anime.bangumiUrl);
    final username = BangumiApiService.userInfo?['username']?.toString();
    if (_isEditingQuarterlyReviewComment ||
        !BangumiApiService.isLoggedIn ||
        username == null ||
        subjectId == null) {
      return;
    }
    _isEditingQuarterlyReviewComment = true;
    try {
      await BangumiCommentDialog.show(
        context: context,
        animeTitle:
            item.anime.nameCn.isNotEmpty ? item.anime.nameCn : item.anime.name,
        initialRating: item.rating ?? 0,
        initialComment: item.comment,
        // The short-comment editor does not expose collection status. Saving
        // below only sends rating/comment to preserve status and progress.
        collectionType: 3,
        onSubmit: (submission) async {
          try {
            if (!BangumiApiService.isLoggedIn ||
                BangumiApiService.userInfo?['username']?.toString() !=
                    username) {
              throw StateError('Bangumi账号已变更，请重新打开短评编辑');
            }
            final result = await BangumiApiService.updateUserCollection(
              subjectId,
              rate: submission.rating,
              comment: submission.comment.trim(),
            );
            if (result['success'] != true) {
              throw StateError(result['message']?.toString() ?? '短评保存失败');
            }
          } catch (error) {
            if (mounted) BlurSnackBar.show(context, '短评保存失败：$error');
            rethrow;
          }
          if (mounted) {
            await _loadQuarterlyReview();
            if (mounted) BlurSnackBar.show(context, '短评已更新');
          }
        },
      );
    } finally {
      _isEditingQuarterlyReviewComment = false;
    }
  }

  List<_QuarterlyReviewItem> get _sortedQuarterlyReviewItems {
    final items = List<_QuarterlyReviewItem>.from(_quarterlyReviewItems);
    int compareNullable(num? a, num? b, {required bool descending}) {
      if (a == null) return b == null ? 0 : 1;
      if (b == null) return -1;
      return descending ? b.compareTo(a) : a.compareTo(b);
    }

    items.sort((a, b) {
      int order;
      switch (_quarterlyReviewSort) {
        case _QuarterlyReviewSort.airDate:
          order = a.airDate.compareTo(b.airDate);
          break;
        case _QuarterlyReviewSort.commentNewest:
          order = compareNullable(a.commentAt, b.commentAt, descending: true);
          break;
        case _QuarterlyReviewSort.commentOldest:
          order = compareNullable(a.commentAt, b.commentAt, descending: false);
          break;
        case _QuarterlyReviewSort.ratingHigh:
          order = compareNullable(a.rating, b.rating, descending: true);
          break;
        case _QuarterlyReviewSort.ratingLow:
          order = compareNullable(a.rating, b.rating, descending: false);
          break;
      }
      return order != 0 ? order : a.airDate.compareTo(b.airDate);
    });
    return items;
  }

  Future<void> _setQuarterlyReviewSort(_QuarterlyReviewSort sort) async {
    if (_quarterlyReviewSort == sort) return;
    setState(() => _quarterlyReviewSort = sort);
    if (_quarterlyReviewScrollController.hasClients) {
      _quarterlyReviewScrollController.jumpTo(0);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('quarterly_review_sort_v1', sort.name);
    } catch (_) {}
  }

  Future<void> _loadQuarterlyReviewSort() async {
    String? saved;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = prefs.getString('quarterly_review_sort_v1');
    } catch (_) {
      return;
    }
    if (!mounted || saved == null) return;
    for (final sort in _QuarterlyReviewSort.values) {
      if (sort.name == saved) {
        setState(() => _quarterlyReviewSort = sort);
        break;
      }
    }
  }
}

part of dashboard_home_page;

extension DashboardHomePageActions on _DashboardHomePageState {
  void _showTagSearchModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TagSearchModal(),
    );
  }

  void _onRecommendedItemTap(RecommendedItem item) {
    if (item.source == RecommendedItemSource.placeholder) return;
    
    if (item.source == RecommendedItemSource.jellyfin) {
      _navigateToJellyfinDetail(item.id);
    } else if (item.source == RecommendedItemSource.emby) {
      _navigateToEmbyDetail(item.id);
    } else if (item.source == RecommendedItemSource.local) {
      // 对于本地媒体库项目，使用animeId直接打开详情页
      if (item.id.contains(RegExp(r'^\d+$'))) {
        final animeId = int.tryParse(item.id);
        if (animeId != null) {
          AnimeDetailPage.show(context, animeId).then((result) {
            if (result != null) {
              // 刷新观看历史
              Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
              // 🔥 修复Flutter状态错误：使用addPostFrameCallback
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  _loadData();
                }
              });
            }
          });
        }
      }
    } else if (item.source == RecommendedItemSource.dandanplay) {
      final group = _recommendedDandanLookup[item.id];
      if (group != null) {
        _onDandanplayGroupTap(group);
      } else {
        BlurSnackBar.show(context, '无法找到对应的弹弹play条目');
      }
    }
  }

  void _onJellyfinItemTap(JellyfinMediaItem item) {
    _navigateToJellyfinDetail(item.id);
  }

  void _onEmbyItemTap(EmbyMediaItem item) {
    _navigateToEmbyDetail(item.id);
  }

  void _onLocalAnimeItemTap(LocalAnimeItem item) {
    // 打开动画详情页
    AnimeDetailPage.show(context, item.animeId).then((result) {
      if (result != null) {
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
        // 🔥 修复Flutter状态错误：使用addPostFrameCallback
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _loadData();
          }
        });
      }
    });
  }

  void _onDandanplayGroupTap(DandanplayRemoteAnimeGroup group) async {
    DandanplayRemoteProvider? provider;
    try {
      provider = Provider.of<DandanplayRemoteProvider>(context, listen: false);
    } catch (_) {}

    if (provider == null || !provider.isConnected) {
      BlurSnackBar.show(context, '未连接到弹弹play远程服务');
      return;
    }

    final DandanplayRemoteProvider resolvedProvider = provider;

    final animeId = group.animeId;
    if (animeId == null) {
      BlurSnackBar.show(context, '该条目缺少 Bangumi ID，无法打开详情');
      return;
    }

    final coverUrl = await _resolveDandanCoverForGroup(group, resolvedProvider);
    if (!mounted) return;

    final summary = SharedRemoteAnimeSummary(
      animeId: animeId,
      name: group.title,
      nameCn: group.title,
      summary: null,
      imageUrl: coverUrl,
      lastWatchTime: group.latestPlayTime ?? DateTime.now(),
      episodeCount: group.episodeCount,
      hasMissingFiles: false,
    );

    Future<List<SharedRemoteEpisode>> episodeLoader() async {
      final episodes = group.episodes.reversed
          .map((episode) => _mapDandanEpisodeToShared(episode, resolvedProvider))
          .whereType<SharedRemoteEpisode>()
          .toList();
      if (episodes.isEmpty) {
        throw Exception('该番剧暂无可播放的剧集');
      }
      return episodes;
    }

    try {
      final result = await ThemedAnimeDetail.show(
        context,
        summary.animeId,
        sharedSummary: summary,
        sharedEpisodeLoader: episodeLoader,
        sharedEpisodeBuilder: (episode) => _buildDandanPlayableFromShared(
          summary: summary,
          episode: episode,
        ),
        sharedSourceLabel: resolvedProvider.serverUrl ?? '弹弹play',
      );

      if (result != null) {
        _onWatchHistoryItemTap(result);
        if (mounted) {
          Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
        }
      }
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '打开详情失败：$e');
    }
  }

  // 已移除旧的创建本地动画项目的重量级方法，改为快速路径+后台补齐。

  void _navigateToJellyfinDetail(String jellyfinId) {
    MediaServerDetailPage.showJellyfin(context, jellyfinId).then((result) async {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
            final jellyfinService = JellyfinService.instance;
            if (jellyfinService.isConnected) {
              actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            } else {
              BlurSnackBar.show(context, '未连接到Jellyfin服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
            return;
          }
        } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
            final embyService = EmbyService.instance;
            if (embyService.isConnected) {
              actualPlayUrl = await embyService.getStreamUrl(embyId);
            } else {
              BlurSnackBar.show(context, '未连接到Emby服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
            return;
          }
        }
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _navigateToEmbyDetail(String embyId) {
    MediaServerDetailPage.showEmby(context, embyId).then((result) async {
      if (result != null) {
        // 检查是否需要获取实际播放URL
        String? actualPlayUrl;
        final isJellyfinProtocol = result.filePath.startsWith('jellyfin://');
        final isEmbyProtocol = result.filePath.startsWith('emby://');
        
        if (isJellyfinProtocol) {
          try {
            final jellyfinId = result.filePath.replaceFirst('jellyfin://', '');
            final jellyfinService = JellyfinService.instance;
            if (jellyfinService.isConnected) {
              actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
            } else {
              BlurSnackBar.show(context, '未连接到Jellyfin服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
            return;
          }
    } else if (isEmbyProtocol) {
          try {
            final embyId = result.filePath.replaceFirst('emby://', '');
            final embyService = EmbyService.instance;
            if (embyService.isConnected) {
      actualPlayUrl = await embyService.getStreamUrl(embyId);
            } else {
              BlurSnackBar.show(context, '未连接到Emby服务器');
              return;
            }
          } catch (e) {
            BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
            return;
          }
        }
        
        // 创建PlayableItem并播放
        final playableItem = PlayableItem(
          videoPath: result.filePath,
          title: result.animeName,
          subtitle: result.episodeTitle,
          animeId: result.animeId,
          episodeId: result.episodeId,
          historyItem: result,
          actualPlayUrl: actualPlayUrl,
        );
        
        PlaybackService().play(playableItem);
        
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    if (_isHistoryAutoMatching) {
      BlurSnackBar.show(context, '正在自动匹配，请稍候');
      return;
    }

    var currentItem = item;
    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = currentItem.filePath.startsWith('http://') || currentItem.filePath.startsWith('https://');
    final isJellyfinProtocol = currentItem.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = currentItem.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = currentItem.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = currentItem.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (jellyfinService.isConnected) {
            actualPlayUrl = jellyfinService.getStreamUrl(jellyfinId);
          } else {
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Jellyfin流媒体URL失败: $e');
          return;
        }
      }
      
  if (isEmbyProtocol) {
        try {
          final embyId = currentItem.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
    actualPlayUrl = await embyService.getStreamUrl(embyId);
          } else {
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return;
          }
        } catch (e) {
          BlurSnackBar.show(context, '获取Emby流媒体URL失败: $e');
          return;
        }
      }
    } else {
      final videoFile = File(currentItem.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          currentItem = currentItem.copyWith(filePath: filePath);
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(currentItem.filePath)}');
      return;
    }

    if (WatchHistoryAutoMatchHelper.shouldAutoMatch(currentItem)) {
      final matchablePath = actualPlayUrl ?? currentItem.filePath;
      currentItem = await _performHistoryAutoMatch(currentItem, matchablePath);
    }

    final playableItem = PlayableItem(
      videoPath: currentItem.filePath,
      title: currentItem.animeName,
      subtitle: currentItem.episodeTitle,
      animeId: currentItem.animeId,
      episodeId: currentItem.episodeId,
      historyItem: currentItem,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }

  Future<WatchHistoryItem> _performHistoryAutoMatch(
    WatchHistoryItem currentItem,
    String matchablePath,
  ) async {
    _updateHistoryAutoMatchingState(true);
    _showHistoryAutoMatchingDialog();
    String? notification;

    try {
      return await WatchHistoryAutoMatchHelper.tryAutoMatch(
        context,
        currentItem,
        matchablePath: matchablePath,
        onMatched: (message) => notification = message,
      );
    } finally {
      _hideHistoryAutoMatchingDialog();
      _updateHistoryAutoMatchingState(false);
      if (notification != null && mounted) {
        BlurSnackBar.show(context, notification!);
      }
    }
  }

  void _updateHistoryAutoMatchingState(bool value) {
    if (!mounted) {
      _isHistoryAutoMatching = value;
      return;
    }
    if (_isHistoryAutoMatching == value) {
      return;
    }
    setState(() {
      _isHistoryAutoMatching = value;
    });
  }

  void _showHistoryAutoMatchingDialog() {
    if (_historyAutoMatchDialogVisible || !mounted) return;
    _historyAutoMatchDialogVisible = true;
    BlurDialog.show(
      context: context,
      title: '正在自动匹配',
      barrierDismissible: false,
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          SizedBox(height: 8),
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          SizedBox(height: 16),
          Text(
            '正在为历史记录匹配弹幕，请稍候…',
            style: TextStyle(color: Colors.white, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).whenComplete(() {
      _historyAutoMatchDialogVisible = false;
    });
  }

  void _hideHistoryAutoMatchingDialog() {
    if (!_historyAutoMatchDialogVisible) {
      return;
    }
    if (!mounted) {
      _historyAutoMatchDialogVisible = false;
      return;
    }
    Navigator.of(context, rootNavigator: true).pop();
  }

  // 导航到媒体库-库管理页面
  void _navigateToMediaLibraryManagement() {
    debugPrint('[DashboardHomePage] 准备导航到媒体库-库管理页面');
    
    // 先发送子标签切换请求，避免Widget销毁后无法访问
    try {
      final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
      tabChangeNotifier.changeToMediaLibrarySubTab(1); // 直接切换到库管理标签
      debugPrint('[DashboardHomePage] 已发送子标签切换请求');
    } catch (e) {
      debugPrint('[DashboardHomePage] 发送子标签切换请求失败: $e');
    }
    
    // 然后切换到媒体库页面
    MainPageState? mainPageState = MainPageState.of(context);
    if (mainPageState != null && mainPageState.globalTabController != null) {
      // 切换到媒体库页面（索引2）
      if (mainPageState.globalTabController!.index != 2) {
        mainPageState.globalTabController!.animateTo(2);
        debugPrint('[DashboardHomePage] 直接调用了globalTabController.animateTo(2)');
      } else {
        debugPrint('[DashboardHomePage] globalTabController已经在媒体库页面');
        // 如果已经在媒体库页面，立即触发子标签切换
        try {
          final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
          tabChangeNotifier.changeToMediaLibrarySubTab(1);
          debugPrint('[DashboardHomePage] 已在媒体库页面，立即触发子标签切换');
        } catch (e) {
          debugPrint('[DashboardHomePage] 立即触发子标签切换失败: $e');
        }
      }
    } else {
      debugPrint('[DashboardHomePage] 无法找到MainPageState或globalTabController');
      // 如果直接访问失败，使用TabChangeNotifier作为备选方案
      try {
        final tabChangeNotifier = Provider.of<TabChangeNotifier>(context, listen: false);
        tabChangeNotifier.changeToMediaLibrarySubTab(1); // 直接切换到媒体库-库管理标签
        debugPrint('[DashboardHomePage] 备选方案: 使用TabChangeNotifier请求切换到媒体库-库管理标签');
      } catch (e) {
        debugPrint('[DashboardHomePage] TabChangeNotifier也失败: $e');
      }
    }
  }
  
  // 构建页面指示器（分离出来避免不必要的重建），支持点击和悬浮效果
  Widget _buildPageIndicator({bool fullWidth = false, int count = 5}) {
    return Positioned(
      bottom: 16,
      left: 0,
      // 手机全宽；桌面只在左侧PageView区域显示：总宽度的2/3减去间距
      right: fullWidth ? 0 : (MediaQuery.of(context).size.width - 32) / 3 + 12,
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: _heroBannerIndexNotifier,
          builder: (context, currentIndex, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(count, (index) {
                final bool isHovered = _hoveredIndicatorIndex == index;
                final bool isSelected = currentIndex == index;
                double size;
                if (isSelected && isHovered) {
                  size = 16.0; // 选中且悬浮时最大
                } else if (isHovered) {
                  size = 12.0; // 仅悬浮时变大
                } else {
                  size = 8.0; // 默认大小
                }

                return MouseRegion(
                  onEnter: (event) => setState(() => _hoveredIndicatorIndex = index),
                  onExit: (event) => setState(() => _hoveredIndicatorIndex = null),
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: () {
                      // 点击圆点时切换到对应页面
                      _stopAutoSwitch();
                      _currentHeroBannerIndex = index;
                      _heroBannerIndexNotifier.value = index;
                      _heroBannerPageController.animateToPage(
                        index,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                      Timer(const Duration(seconds: 3), () {
                        _resumeAutoSwitch();
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      width: size,
                      height: size,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? Colors.white
                            : (isHovered
                                ? Colors.white.withOpacity(0.8)
                                : Colors.white.withOpacity(0.5)),
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

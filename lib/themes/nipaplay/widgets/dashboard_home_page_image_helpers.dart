part of dashboard_home_page;

extension DashboardHomePageImageHelpers on _DashboardHomePageState {
  Future<String?> _getHighQualityImage(int animeId, BangumiAnime animeDetail) async {
    try {
      // 优先尝试本地缓存中的 bangumiId/bangumiUrl，避免再请求弹弹play
      try {
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'bangumi_detail_$animeId';
        final String? cachedString = prefs.getString(cacheKey);
        if (cachedString != null) {
          final data = json.decode(cachedString);
          final animeData = data['animeDetail'] as Map<String, dynamic>?;
          final bangumi = data['bangumi'] as Map<String, dynamic>?;
          String? cachedBangumiId;
          // 1) 直接字段
          if (bangumi != null && bangumi['bangumiId'] != null && bangumi['bangumiId'].toString().isNotEmpty) {
            cachedBangumiId = bangumi['bangumiId'].toString();
          }
          // 2) 从 bangumiUrl 解析
          if (cachedBangumiId == null) {
            final String? bangumiUrl = (bangumi?['bangumiUrl'] as String?) ?? (animeData?['bangumiUrl'] as String?);
            if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
              final RegExp regex = RegExp(r'bangumi\.tv/subject/(\d+)');
              final match = regex.firstMatch(bangumiUrl);
              if (match != null) {
                cachedBangumiId = match.group(1);
              }
            }
          }
          if (cachedBangumiId != null && cachedBangumiId.isNotEmpty) {
            final bangumiImageUrl = await _getBangumiHighQualityImage(cachedBangumiId);
            if (bangumiImageUrl != null && bangumiImageUrl.isNotEmpty) {
              return bangumiImageUrl;
            }
          }
        }
      } catch (_) {}

      // 首先尝试从弹弹play获取bangumi ID
      String? bangumiId = await _getBangumiIdFromDandanplay(animeId);
      
      if (bangumiId != null && bangumiId.isNotEmpty) {
        // 如果获取到bangumi ID，尝试从Bangumi API获取高清图片
        final bangumiImageUrl = await _getBangumiHighQualityImage(bangumiId);
        if (bangumiImageUrl != null && bangumiImageUrl.isNotEmpty) {
          return bangumiImageUrl;
        }
      }
      
      // 如果Bangumi API失败，回退到弹弹play的图片
      if (animeDetail.imageUrl.isNotEmpty) {
        return animeDetail.imageUrl;
      }
      
      return null;
    } catch (_) {
      // 出错时回退到弹弹play的图片
      return animeDetail.imageUrl;
    }
  }
  
  // 从弹弹play API获取bangumi ID
  Future<String?> _getBangumiIdFromDandanplay(int animeId) async {
    try {
      // 使用弹弹play的番剧详情API获取bangumi ID
      final Map<String, dynamic> result = await DandanplayService.getBangumiDetails(animeId);
      
      if (result['success'] == true && result['bangumi'] != null) {
        final bangumi = result['bangumi'] as Map<String, dynamic>;
        
        // 检查是否有bangumiUrl，从中提取ID
        final String? bangumiUrl = bangumi['bangumiUrl'] as String?;
        if (bangumiUrl != null && bangumiUrl.contains('bangumi.tv/subject/')) {
          // 从URL中提取bangumi ID: https://bangumi.tv/subject/123456
          final RegExp regex = RegExp(r'bangumi\.tv/subject/(\d+)');
          final match = regex.firstMatch(bangumiUrl);
          if (match != null) {
            final bangumiId = match.group(1);
            return bangumiId;
          }
        }
        
        // 也检查是否直接有bangumiId字段
        final dynamic directBangumiId = bangumi['bangumiId'];
        if (directBangumiId != null) {
          final String bangumiIdStr = directBangumiId.toString();
          if (bangumiIdStr.isNotEmpty && bangumiIdStr != '0') {
            return bangumiIdStr;
          }
        }
      }
      
      return null;
    } catch (_) {
      return null;
    }
  }
  
  // 从Bangumi API获取高清图片
  Future<String?> _getBangumiHighQualityImage(String bangumiId) async {
    try {
      // 使用Bangumi API的图片接口获取large尺寸的图片
      // GET /v0/subjects/{subject_id}/image?type=large
      final String imageApiUrl = 'https://api.bgm.tv/v0/subjects/$bangumiId/image?type=large';
      
      
      final response = await http.head(
        WebRemoteAccessService.proxyUri(Uri.parse(imageApiUrl)),
        headers: {
          'User-Agent': 'NipaPlay/1.0',
        },
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 302) {
        // Bangumi API返回302重定向到实际图片URL
        final String? location = response.headers['location'];
        if (location != null && location.isNotEmpty) {
          return location;
        }
      } else if (response.statusCode == 200) {
        // 有些情况下可能直接返回200
        return imageApiUrl;
      }
      
      return null;
    } catch (_) {
      return null;
    }
  }

  // 升级为高清图片（后台异步处理）
  Future<void> _upgradeToHighQualityImages(List<dynamic> candidates, List<RecommendedItem> currentItems) async {
    
    if (candidates.isEmpty || currentItems.isEmpty) {
      return;
    }
    
    // 为每个候选项目升级图片
    final upgradeFutures = <Future<void>>[];
    
    for (int i = 0; i < candidates.length && i < currentItems.length; i++) {
      final candidate = candidates[i];
      final currentItem = currentItems[i];
      
      upgradeFutures.add(_upgradeItemToHighQuality(candidate, currentItem, i));
    }
    
    // 异步处理所有升级，不阻塞UI
    unawaited(Future.wait(upgradeFutures, eagerError: false));
  }
  
  // 升级单个项目为高清图片
  Future<void> _upgradeItemToHighQuality(dynamic candidate, RecommendedItem currentItem, int index) async {
    try {
      RecommendedItem? upgradedItem;
      
      if (candidate is JellyfinMediaItem) {
        // Jellyfin项目 - 获取高清图片和详细信息
        final jellyfinService = JellyfinService.instance;
        
        // 并行获取背景图片、Logo图片和详细信息
        final results = await Future.wait([
          _tryGetJellyfinImage(jellyfinService, candidate.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
          _tryGetJellyfinImage(jellyfinService, candidate.id, ['Logo', 'Thumb']),
          _getJellyfinItemSubtitle(jellyfinService, candidate),
        ]);
        
        final backdropCandidate = results[0] as MapEntry<String, String>?;
        final logoCandidate = results[1] as MapEntry<String, String>?;
        final subtitle = results[2] as String?;
        final backdropUrl = backdropCandidate?.value;
        final logoUrl = logoCandidate?.value;
        final normalizedBackdropUrl = _normalizeRecommendationImageUrl(backdropUrl);
        final normalizedLogoUrl = _normalizeRecommendationImageUrl(logoUrl);
        
        // 如果获取到了更好的图片或信息，创建升级版本
        if (normalizedBackdropUrl != currentItem.backgroundImageUrl || 
            normalizedLogoUrl != currentItem.logoImageUrl ||
            subtitle != currentItem.subtitle) {
          upgradedItem = currentItem.copyWith(
            subtitle: subtitle,
            backgroundImageUrl: normalizedBackdropUrl,
            logoImageUrl: normalizedLogoUrl,
            isLowRes: normalizedBackdropUrl == null
                ? currentItem.isLowRes
                : _shouldBlurLowResCover(imageType: backdropCandidate?.key, imageUrl: backdropUrl),
          );
        }
        
      } else if (candidate is EmbyMediaItem) {
        // Emby项目 - 获取高清图片和详细信息
        final embyService = EmbyService.instance;
        
        // 并行获取背景图片、Logo图片和详细信息
        final results = await Future.wait([
          _tryGetEmbyImage(embyService, candidate.id, ['Backdrop', 'Primary', 'Art', 'Banner']),
          _tryGetEmbyImage(embyService, candidate.id, ['Logo', 'Thumb']),
          _getEmbyItemSubtitle(embyService, candidate),
        ]);
        
        final backdropCandidate = results[0] as MapEntry<String, String>?;
        final logoCandidate = results[1] as MapEntry<String, String>?;
        final subtitle = results[2] as String?;
        final backdropUrl = backdropCandidate?.value;
        final logoUrl = logoCandidate?.value;
        final normalizedBackdropUrl = _normalizeRecommendationImageUrl(backdropUrl);
        final normalizedLogoUrl = _normalizeRecommendationImageUrl(logoUrl);
        
        // 如果获取到了更好的图片或信息，创建升级版本
        if (normalizedBackdropUrl != currentItem.backgroundImageUrl || 
            normalizedLogoUrl != currentItem.logoImageUrl ||
            subtitle != currentItem.subtitle) {
          upgradedItem = currentItem.copyWith(
            subtitle: subtitle,
            backgroundImageUrl: normalizedBackdropUrl,
            logoImageUrl: normalizedLogoUrl,
            isLowRes: normalizedBackdropUrl == null
                ? currentItem.isLowRes
                : _shouldBlurLowResCover(imageType: backdropCandidate?.key, imageUrl: backdropUrl),
          );
        }
        
      } else if (candidate is WatchHistoryItem) {
        // 本地媒体库项目 - 获取高清图片和详细信息
        String? highQualityImageUrl;
        String? detailedSubtitle;
        
        if (_isValidAnimeId(candidate.animeId)) {
          final animeId = candidate.animeId!;
          try {
            // 先尝试使用持久化缓存，避免重复请求网络
            final prefs = await SharedPreferences.getInstance();
            final persisted = prefs.getString(
                '${_DashboardHomePageState._localPrefsKeyPrefix}$animeId');

            final persistedLooksHQ = persisted != null && persisted.isNotEmpty && _looksHighQualityUrl(persisted);

            if (persistedLooksHQ) {
              highQualityImageUrl = persisted;
            } else {
              // 获取详细信息和高清图片
              final bangumiService = BangumiService.instance;
              final animeDetail = await bangumiService.getAnimeDetails(animeId);
              detailedSubtitle = animeDetail.summary?.isNotEmpty == true
                  ? animeDetail.summary!
                      .replaceAll('<br>', ' ')
                      .replaceAll('<br/>', ' ')
                      .replaceAll('<br />', ' ')
                      .replaceAll('```', '')
                  : null;
              
              // 获取高清图片
              highQualityImageUrl = await _getHighQualityImage(animeId, animeDetail);

              // 将获取到的高清图持久化，避免后续重复请求
              if (highQualityImageUrl != null && highQualityImageUrl.isNotEmpty) {
                _localImageCache[animeId] = highQualityImageUrl;
                try {
                  await prefs.setString(
                      '${_DashboardHomePageState._localPrefsKeyPrefix}$animeId',
                      highQualityImageUrl);
                } catch (_) {}
              } else if (persisted != null && persisted.isNotEmpty) {
                // 如果没拿到更好的，只能继续沿用已持久化的（即使它可能是 medium），避免空图
                highQualityImageUrl = persisted;
              }
            }
          } catch (_) {
          }
        }
        
        // 如果获取到了更好的图片或信息，创建升级版本
        final normalizedHighQualityUrl =
            _normalizeRecommendationImageUrl(highQualityImageUrl);
        if (normalizedHighQualityUrl != currentItem.backgroundImageUrl ||
            detailedSubtitle != currentItem.subtitle) {
          upgradedItem = currentItem.copyWith(
            subtitle: detailedSubtitle,
            backgroundImageUrl: normalizedHighQualityUrl,
            isLowRes: normalizedHighQualityUrl != null && highQualityImageUrl != null
                ? !_looksHighQualityUrl(highQualityImageUrl)
                : currentItem.isLowRes,
          );
        }
      } else if (candidate is DandanplayRemoteAnimeGroup) {
        // 弹弹play远程媒体 - 获取高清背景图
        if (_isValidAnimeId(candidate.animeId)) {
          final animeId = candidate.animeId!;
          try {
            final prefs = await SharedPreferences.getInstance();
            final persisted = prefs.getString(
                '${_DashboardHomePageState._localPrefsKeyPrefix}$animeId');
            
            String? hqUrl;
            if (persisted != null && persisted.isNotEmpty && _looksHighQualityUrl(persisted)) {
              hqUrl = persisted;
            } else {
              final bangumiService = BangumiService.instance;
              final detail = await bangumiService.getAnimeDetails(animeId);
              hqUrl = await _getHighQualityImage(animeId, detail);
              
              if (hqUrl != null && hqUrl.isNotEmpty) {
                try {
                  await prefs.setString(
                      '${_DashboardHomePageState._localPrefsKeyPrefix}$animeId',
                      hqUrl);
                } catch (_) {}
              }
            }
            
            final normalizedHqUrl = _normalizeRecommendationImageUrl(hqUrl);
            if (normalizedHqUrl != null &&
                normalizedHqUrl != currentItem.backgroundImageUrl) {
              upgradedItem = currentItem.copyWith(
                backgroundImageUrl: normalizedHqUrl,
                isLowRes: hqUrl != null ? !_looksHighQualityUrl(hqUrl) : currentItem.isLowRes,
              );
            }
          } catch (_) {
          }
        }
      }
      
      // 如果有升级版本，更新UI
      if (upgradedItem != null && mounted) {
        setState(() {
          if (index < _recommendedItems.length) {
            _recommendedItems[index] = upgradedItem!;
          }
        });
        
        // CachedNetworkImageWidget 会自动处理图片预加载和缓存
        
      }
      
    } catch (_) {
    }
  }

  // 经验性判断一个图片URL是否"看起来"是高清图
  bool _looksHighQualityUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('bgm.tv') || lower.contains('type=large') || lower.contains('original')) {
      return true;
    }
    if (lower.contains('medium') || lower.contains('small')) {
      return false;
    }
    // 解析 width= 参数
    final widthMatch = RegExp(r'[?&]width=(\d+)').firstMatch(lower);
    if (widthMatch != null) {
      final w = int.tryParse(widthMatch.group(1)!);
      if (w != null && w >= 1000) return true;
    }
    // 否则未知，默认当作高清，避免不必要的重复网络请求
    return true;
  }

  bool _shouldBlurLowResCover({String? imageType, String? imageUrl}) {
    if (imageUrl == null || imageUrl.isEmpty) {
      return false;
    }
    final type = imageType?.toLowerCase();
    if (type == 'primary' || type == 'thumb') {
      return !_looksHighQualityCoverUrl(imageUrl);
    }
    if (type == 'backdrop') {
      return !_looksHighQualityUrl(imageUrl);
    }
    if (type == 'banner' || type == 'art') {
      return !_looksHighQualityCoverUrl(imageUrl);
    }
    return !_looksHighQualityUrl(imageUrl);
  }

  bool _looksHighQualityCoverUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('bgm.tv') || lower.contains('type=large') || lower.contains('original')) {
      return true;
    }
    if (lower.contains('medium') || lower.contains('small')) {
      return false;
    }
    final widthMatch = RegExp(r'[?&](?:width|maxwidth)=(\d+)').firstMatch(lower);
    if (widthMatch != null) {
      final w = int.tryParse(widthMatch.group(1)!);
      if (w != null && w >= 1000) return true;
      if (w != null && w > 0 && w < 1000) return false;
    }
    return false;
  }

  // 已移除老的图片下载缓存函数，现在使用 CachedNetworkImageWidget 的内置缓存系统

  // 辅助方法：尝试获取Jellyfin图片 - 带验证与回退，按优先级返回第一个有效URL
  Future<MapEntry<String, String>?> _tryGetJellyfinImage(
      JellyfinService service, String itemId, List<String> imageTypes) async {
    // 先构建候选URL列表
    final List<MapEntry<String, String>> candidates = [];
    for (final imageType in imageTypes) {
      try {
        final url = imageType == 'Backdrop'
            ? service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95)
            : service.getImageUrl(itemId, type: imageType);
        if (url.isNotEmpty) {
          candidates.add(MapEntry(imageType, url));
        }
      } catch (_) {
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    // 并行验证所有候选URL
    final validations = await Future.wait(candidates.map((entry) async {
      final ok = await _validateImageUrl(entry.value);
      return ok ? entry : null;
    }));

    // 按优先级返回第一个有效的
    for (final t in imageTypes) {
      for (final res in validations) {
        if (res != null && res.key == t) {
          return res;
        }
      }
    }

    return null;
  }

  // 辅助方法：尝试获取Emby图片 - 带验证与回退，按优先级返回第一个有效URL
  Future<MapEntry<String, String>?> _tryGetEmbyImage(
      EmbyService service, String itemId, List<String> imageTypes) async {
    final List<MapEntry<String, String>> candidates = [];
    for (final imageType in imageTypes) {
      try {
        final url = imageType == 'Backdrop'
            ? service.getImageUrl(itemId, type: imageType, width: 1920, height: 1080, quality: 95)
            : service.getImageUrl(itemId, type: imageType);
        if (url.isNotEmpty) {
          candidates.add(MapEntry(imageType, url));
        }
      } catch (_) {
      }
    }

    if (candidates.isEmpty) {
      return null;
    }

    final validations = await Future.wait(candidates.map((entry) async {
      final ok = await _validateImageUrl(entry.value);
      return ok ? entry : null;
    }));

    for (final t in imageTypes) {
      for (final res in validations) {
        if (res != null && res.key == t) {
          return res;
        }
      }
    }

    return null;
  }

  // 辅助方法：验证图片URL是否有效（HEAD校验，确保非404并且为图片）
  Future<bool> _validateImageUrl(String url) async {
    try {
      final response = await http
          .head(WebRemoteAccessService.proxyUri(Uri.parse(url)))
          .timeout(
        const Duration(seconds: 2),
        onTimeout: () => throw TimeoutException('图片验证超时', const Duration(seconds: 2)),
      );

      if (response.statusCode != 200) return false;
      final contentType = response.headers['content-type'];
      if (contentType == null || !contentType.startsWith('image/')) return false;

      final contentLength = response.headers['content-length'];
      if (contentLength != null) {
        final len = int.tryParse(contentLength);
        if (len != null && len < 100) return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // 辅助方法：获取Jellyfin项目简介
  Future<String> _getJellyfinItemSubtitle(JellyfinService service, JellyfinMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    } catch (_) {
      return item.overview?.isNotEmpty == true ? item.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    }
  }

  // 辅助方法：获取Emby项目简介
  Future<String> _getEmbyItemSubtitle(EmbyService service, EmbyMediaItem item) async {
    try {
      final detail = await service.getMediaItemDetails(item.id);
      return detail.overview?.isNotEmpty == true ? detail.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    } catch (_) {
      return item.overview?.isNotEmpty == true ? item.overview!
          .replaceAll('<br>', ' ')
          .replaceAll('<br/>', ' ')
          .replaceAll('<br />', ' ') : '暂无简介信息';
    }
  }


  
  // 构建滚动按钮
  Widget _buildScrollButtons(ScrollController controller, double itemWidth) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // 如果没有绑定或内容不足以滚动，直接不显示整个区域
        if (!controller.hasClients || controller.position.maxScrollExtent <= 0) {
          return const SizedBox.shrink();
        }

        final canScrollLeft = controller.offset > 5;
        final canScrollRight =
            controller.offset < controller.position.maxScrollExtent - 5;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: canScrollLeft ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !canScrollLeft,
                child: _buildScrollButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => _scrollToPrevious(controller, itemWidth),
                  message: '上一页',
                  enabled: true,
                ),
              ),
            ),
            const SizedBox(width: 12), // 保持固定间距
            Opacity(
              opacity: canScrollRight ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !canScrollRight,
                child: _buildScrollButton(
                  icon: Icons.arrow_forward_ios_rounded,
                  onTap: () => _scrollToNext(controller, itemWidth),
                  message: '下一页',
                  enabled: true,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
  
  // 构建单个滚动按钮
  Widget _buildScrollButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String message,
    bool enabled = true,
  }) {
    return Tooltip(
      message: message,
      child: _HoverScaleButton(
        enabled: enabled,
        onTap: onTap,
        child: Icon(
          icon,
          size: 24, // 与标题字体大小一致
        ),
      ),
    );
  }
  
  // 滚动到上一页
  void _scrollToPrevious(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = math.max(0.0, controller.offset - scrollDistance);
    
    controller.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
  
  // 滚动到下一页
  void _scrollToNext(ScrollController controller, double itemWidth) {
    final screenWidth = MediaQuery.of(context).size.width;
    final visibleWidth = screenWidth - 32; // 减去左右边距
    final itemsPerPage = (visibleWidth / itemWidth).floor();
    final scrollDistance = itemsPerPage * itemWidth;
    
    final targetOffset = controller.offset + scrollDistance;
    final maxScrollExtent = controller.position.maxScrollExtent;
    
    // 如果目标位置超过了最大滚动范围，就滚动到最大位置
    final finalTargetOffset = targetOffset > maxScrollExtent ? maxScrollExtent : targetOffset;
    
    controller.animateTo(
      finalTargetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}

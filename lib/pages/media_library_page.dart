import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/themes/nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/themed_anime_detail.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/network_media_server_dialog.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/dandanplay_remote_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/media_server_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/shared_remote_host_selection_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/cached_network_image_widget.dart';
import 'package:nipaplay/themes/nipaplay/widgets/horizontal_anime_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/local_library_control_bar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/smb_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/webdav_connection_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/search_bar_action_button.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'dart:ui' as ui;
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/chinese_converter.dart';
import 'package:nipaplay/constants/settings_keys.dart';

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

enum MediaLibrarySourceType {
  local,
  webdav,
  smb,
}

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback
  final bool jellyfinMode; // 是否为Jellyfin媒体库模式
  final VoidCallback? onSourcesUpdated;
  final MediaLibrarySourceType sourceType;

  const MediaLibraryPage({
    super.key,
    this.onPlayEpisode,
    this.jellyfinMode = false,
    this.onSourcesUpdated,
    this.sourceType = MediaLibrarySourceType.local,
  }); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  static const Color _accentColor = Color(0xFFFF2E55);
  // 🔥 临时禁用页面保活，测试是否解决CPU泄漏问题
  // with AutomaticKeepAliveClientMixin {
  List<WatchHistoryItem> _uniqueLibraryItems = [];
  Map<int, String> _persistedImageUrls = {};
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {};
  bool _isLoadingInitial = true;
  String? _error;

  // 🔥 CPU优化：防止重复处理相同的历史数据
  int _lastProcessedHistoryHashCode = 0;
  bool _isBackgroundFetching = false;
  bool _hasWebDataLoaded = false; // 添加Web数据加载标记

  // 🔥 CPU优化：缓存已构建的卡片Widget
  final Map<String, Widget> _cardWidgetCache = {};

  final ScrollController _gridScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  LocalLibrarySortType _currentSort = LocalLibrarySortType.dateAdded;
  List<WatchHistoryItem> _filteredItems = [];

  static const String _prefsKeyPrefix = 'media_library_image_url_';

  bool _isJellyfinConnected = false;
  bool _isSyncing = false;

  // 新增状态变量
  String? _lastLanguageSetting; // 上次检查的语言设置
  bool _isManualRefresh = false; // 是否是手动刷新
  Set<int> _existingAnimeIds = {}; // 已存在的番剧ID
  bool _languageUpdated = false; // 语言是否已更新

  // 🔥 临时禁用页面保活
  // @override
  // bool get wantKeepAlive => true;

  @override
  void initState() {
    //debugPrint('[媒体库CPU] MediaLibraryPage initState 开始');
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        //debugPrint('[媒体库CPU] 开始加载初始数据');
        _loadInitialMediaLibraryData();
        final jellyfinProvider =
            Provider.of<JellyfinProvider>(context, listen: false);
        _isJellyfinConnected = jellyfinProvider.isConnected; // Initialize
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    //debugPrint('[CPU-泄漏排查] MediaLibraryPage dispose 被调用！！！');
    _searchController.dispose();
    try {
      if (mounted) {
        final jellyfinProvider =
            Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("移除Provider监听器时出错: $e");
    }

    _gridScrollController.dispose();
    super.dispose();
  }

  void _onJellyfinProviderChanged() {
    if (mounted) {
      final jellyfinProvider =
          Provider.of<JellyfinProvider>(context, listen: false);
      if (_isJellyfinConnected != jellyfinProvider.isConnected) {
        setState(() {
          _isJellyfinConnected = jellyfinProvider.isConnected;
        });
      }
    }
  }

  void _applyFilter() {
    if (!mounted) return;
    setState(() {
      String query = _searchController.text.toLowerCase().trim();
      _filteredItems = _uniqueLibraryItems.where((item) {
        return item.animeName.toLowerCase().contains(query);
      }).toList();

      // 排序逻辑
      switch (_currentSort) {
        case LocalLibrarySortType.name:
          _filteredItems.sort((a, b) => a.animeName.compareTo(b.animeName));
          break;
        case LocalLibrarySortType.dateAdded:
          _filteredItems
              .sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));
          break;
        case LocalLibrarySortType.rating:
          break;
      }
    });
  }

  String get _sourceDisplayName {
    switch (widget.sourceType) {
      case MediaLibrarySourceType.webdav:
        return 'WebDAV媒体库';
      case MediaLibrarySourceType.smb:
        return 'SMB媒体库';
      case MediaLibrarySourceType.local:
      default:
        return '本地媒体库';
    }
  }

  String get _emptyMessage {
    switch (widget.sourceType) {
      case MediaLibrarySourceType.webdav:
        return 'WebDAV媒体库为空。\n刮削后的动画将显示在这里。';
      case MediaLibrarySourceType.smb:
        return 'SMB媒体库为空。\n刮削后的动画将显示在这里。';
      case MediaLibrarySourceType.local:
      default:
        return '媒体库为空。\n观看过的动画将显示在这里。';
    }
  }

  bool _isLocalSourceItem(WatchHistoryItem item) {
    return !item.filePath.startsWith('jellyfin://') &&
        !item.filePath.startsWith('emby://') &&
        !MediaSourceUtils.isSmbPath(item.filePath) &&
        !MediaSourceUtils.isWebDavPath(item.filePath) &&
        !item.filePath.contains('/api/media/local/share/') &&
        !item.isDandanplayRemote;
  }

  bool _matchesSource(WatchHistoryItem item) {
    switch (widget.sourceType) {
      case MediaLibrarySourceType.webdav:
        return MediaSourceUtils.isWebDavPath(item.filePath) &&
            !item.isDandanplayRemote;
      case MediaLibrarySourceType.smb:
        return MediaSourceUtils.isSmbPath(item.filePath) &&
            !item.isDandanplayRemote;
      case MediaLibrarySourceType.local:
      default:
        return _isLocalSourceItem(item);
    }
  }

  Future<void> _processAndSortHistory(
      List<WatchHistoryItem> watchHistory) async {
    if (!mounted) return;

    // 🔥 CPU优化：检查数据是否已经处理过，避免重复处理
    final currentHashCode = watchHistory.hashCode;
    if (currentHashCode == _lastProcessedHistoryHashCode) {
      //debugPrint('[媒体库CPU] 跳过重复处理历史数据 - 哈希码: $currentHashCode');
      return;
    }
    //debugPrint('[媒体库CPU] 开始处理历史数据 - 哈希码: $currentHashCode (上次: $_lastProcessedHistoryHashCode)');
    _lastProcessedHistoryHashCode = currentHashCode;

    if (watchHistory.isEmpty) {
      setState(() {
        _uniqueLibraryItems = [];
        _isLoadingInitial = false;
      });
      return;
    }

    final filteredHistory = watchHistory.where(_matchesSource).toList();

    final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
    for (var item in filteredHistory) {
      if (item.animeId != null) {
        if (latestHistoryItemMap.containsKey(item.animeId!)) {
          if (item.lastWatchTime
              .isAfter(latestHistoryItemMap[item.animeId!]!.lastWatchTime)) {
            latestHistoryItemMap[item.animeId!] = item;
          }
        } else {
          latestHistoryItemMap[item.animeId!] = item;
        }
      }
    }
    final uniqueAnimeItemsFromHistory = latestHistoryItemMap.values.toList();
    uniqueAnimeItemsFromHistory
        .sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

    // 记录已存在的番剧ID
    _existingAnimeIds = latestHistoryItemMap.keys.toSet();

    // 检查语言设置是否变化
    _checkLanguageChange();

    Map<int, String> loadedPersistedUrls = {};
    final prefs = await SharedPreferences.getInstance();
    for (var item in uniqueAnimeItemsFromHistory) {
      if (item.animeId != null) {
        String? persistedUrl =
            prefs.getString('$_prefsKeyPrefix${item.animeId}');
        if (persistedUrl != null && persistedUrl.isNotEmpty) {
          loadedPersistedUrls[item.animeId!] = persistedUrl;
        }

        // 尝试从BangumiService内存缓存中恢复详情数据
        final cachedDetail =
            BangumiService.instance.getAnimeDetailsFromMemory(item.animeId!);
        if (cachedDetail != null) {
          _fetchedFullAnimeData[item.animeId!] = cachedDetail;
        }
      }
    }

    setState(() {
      _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
      _persistedImageUrls = loadedPersistedUrls;
      _isLoadingInitial = false;
      // 🔥 CPU优化：清空卡片缓存，因为数据已更新
      _cardWidgetCache.clear();
      _applyFilter();
    });
    _fetchAndPersistFullDetailsInBackground();
  }

  Future<void> _loadInitialMediaLibraryData() async {
    if (!mounted) return;
    setState(() {
      _isLoadingInitial = true;
      _error = null;
    });

    try {
      if (kIsWeb) {
        if (widget.sourceType != MediaLibrarySourceType.local) {
          if (mounted) {
            setState(() {
              _uniqueLibraryItems = [];
              _isLoadingInitial = false;
              _hasWebDataLoaded = true;
            });
          }
          return;
        }
        // Web environment: 完全模仿新番更新页面的逻辑
        List<BangumiAnime> animes;

        try {
          final apiUri =
              WebRemoteAccessService.apiUri('/api/media/local/items');
          if (apiUri == null) {
            throw Exception('未配置远程访问地址');
          }
          final response = await http.get(apiUri);
          if (response.statusCode == 200) {
            final List<dynamic> data =
                json.decode(utf8.decode(response.bodyBytes));
            animes = data
                .map((d) => BangumiAnime.fromJson(d as Map<String, dynamic>))
                .toList();
          } else {
            throw Exception('Failed to load from API: ${response.statusCode}');
          }
        } catch (e) {
          throw Exception('Failed to connect to the local API: $e');
        }

        // 转换为WatchHistoryItem（保持兼容性）
        final webHistoryItems = animes.map((anime) {
          final animeJson = anime.toJson();
          return WatchHistoryItem(
            animeId: anime.id,
            animeName: anime.nameCn.isNotEmpty ? anime.nameCn : anime.name,
            episodeTitle: '',
            filePath: 'web_${anime.id}',
            lastWatchTime: animeJson['_localLastWatchTime'] != null
                ? DateTime.parse(animeJson['_localLastWatchTime'])
                : DateTime.now(),
            watchProgress: 0.0,
            lastPosition: 0,
            duration: 0,
            thumbnailPath: anime.imageUrl,
          );
        }).toList();

        // 缓存BangumiAnime数据
        for (var anime in animes) {
          _fetchedFullAnimeData[anime.id] = anime;
        }

        if (mounted) {
          setState(() {
            _uniqueLibraryItems = webHistoryItems;
            _isLoadingInitial = false;
            _hasWebDataLoaded = true;
            _cardWidgetCache.clear();
          });
        }
      } else {
        // Mobile/Desktop environment: use local providers
        final historyProvider =
            Provider.of<WatchHistoryProvider>(context, listen: false);
        if (!historyProvider.isLoaded && !historyProvider.isLoading) {
          await historyProvider.loadHistory();
        }

        if (historyProvider.isLoaded) {
          await _processAndSortHistory(historyProvider.history);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingInitial = false;
        });
      }
    }
  }

  Future<void> _fetchAndPersistFullDetailsInBackgroundForWeb() async {
    if (_isBackgroundFetching) return;
    _isBackgroundFetching = true;

    final prefs = await SharedPreferences.getInstance();
    const int maxConcurrentRequests = 8; // 增加并发数
    int processed = 0;
    final total =
        _uniqueLibraryItems.where((item) => item.animeId != null).length;

    // 批量处理请求
    final futures = <Future<void>>[];

    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null &&
          !_fetchedFullAnimeData.containsKey(historyItem.animeId!)) {
        final future =
            _fetchSingleAnimeDetail(historyItem.animeId!, prefs).then((_) {
          processed++;
          // 每处理5个项目批量更新一次UI，避免频繁更新
          if (processed % 5 == 0 && mounted) {
            setState(() {});
          }
        });
        futures.add(future);

        // 控制并发数量
        if (futures.length >= maxConcurrentRequests) {
          await Future.any(futures);
          // 移除已完成的Future (简化处理)
          futures.clear();
        }
      }
    }

    // 等待所有剩余请求完成
    if (futures.isNotEmpty) {
      await Future.wait(futures);
    }

    // 最后一次UI更新
    if (mounted) {
      setState(() {});
    }

    _isBackgroundFetching = false;
  }

  Future<void> _fetchSingleAnimeDetail(
      int animeId, SharedPreferences prefs) async {
    try {
      final apiUri =
          WebRemoteAccessService.apiUri('/api/bangumi/detail/$animeId');
      if (apiUri == null) {
        throw Exception('未配置远程访问地址');
      }
      final response = await http.get(apiUri);
      if (response.statusCode == 200) {
        final Map<String, dynamic> animeDetailData =
            json.decode(utf8.decode(response.bodyBytes));
        final animeDetail = BangumiAnime.fromJson(animeDetailData);

        if (mounted) {
          _fetchedFullAnimeData[animeId] = animeDetail;
          if (animeDetail.imageUrl.isNotEmpty) {
            await prefs.setString(
                '$_prefsKeyPrefix$animeId', animeDetail.imageUrl);
            if (mounted) {
              _persistedImageUrls[animeId] = animeDetail.imageUrl;
            }
          } else {
            await prefs.remove('$_prefsKeyPrefix$animeId');
            if (mounted && _persistedImageUrls.containsKey(animeId)) {
              _persistedImageUrls.remove(animeId);
            }
          }
        }
      }
    } catch (e) {
      // Silent fail for background requests
      debugPrint('获取动画详情失败: $animeId - $e');
    }
  }

  Future<void> _syncLibrary(MediaLibrarySourceType type) async {
    if (!mounted || kIsWeb || _isSyncing) return;

    setState(() {
      _isSyncing = true;
    });

    try {
      // 检查语言设置是否变化
      await _checkLanguageChange();

      // 设置为手动刷新模式
      _isManualRefresh = true;

      final historyProvider =
          Provider.of<WatchHistoryProvider>(context, listen: false);
      historyProvider.clearInvalidPathCache();
      await historyProvider.refresh();
      _lastProcessedHistoryHashCode = 0;
      await _processAndSortHistory(historyProvider.history);
      if (!mounted) return;

      String message;
      switch (type) {
        case MediaLibrarySourceType.local:
          message = '已同步本地媒体库';
          break;
        case MediaLibrarySourceType.webdav:
          message = '已同步WebDAV媒体库';
          break;
        case MediaLibrarySourceType.smb:
          message = '已同步SMB媒体库';
          break;
      }
      BlurSnackBar.show(context, message);
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '同步失败: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
        });
      }
    }
  }

  Future<void> _syncLocalLibrary() async {
    await _syncLibrary(MediaLibrarySourceType.local);
  }

  Future<void> _syncWebDavLibrary() async {
    await _syncLibrary(MediaLibrarySourceType.webdav);
  }

  Future<void> _syncSmbLibrary() async {
    await _syncLibrary(MediaLibrarySourceType.smb);
  }

  Widget _buildSyncActionButton({
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return SearchBarActionButton(
      icon: Icons.sync,
      tooltip: _isSyncing ? '同步中…' : tooltip,
      onPressed: _isSyncing ? null : onPressed,
    );
  }

  Future<void> _showJellyfinServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.jellyfin);
  }

  Future<void> _showServerSelectionDialog() async {
    final result = await MediaServerSelectionSheet.show(context);

    if (!mounted || result == null) {
      return;
    }

    bool sourcesUpdated = false;

    switch (result) {
      case 'jellyfin':
        await _showJellyfinServerDialog();
        break;
      case 'emby':
        await _showEmbyServerDialog();
        break;
      case 'webdav':
        sourcesUpdated = await WebDAVConnectionDialog.show(context) == true;
        break;
      case 'smb':
        sourcesUpdated = await SMBConnectionDialog.show(context) == true;
        break;
      case 'nipaplay':
        await _showNipaplayServerDialog();
        break;
      case 'dandanplay':
        await _showDandanplayServerDialog();
        break;
    }

    if (sourcesUpdated) {
      widget.onSourcesUpdated?.call();
    }
  }

  Future<void> _showNipaplayServerDialog() async {
    await SharedRemoteHostSelectionSheet.show(context);
  }

  Future<void> _showDandanplayServerDialog() async {
    final provider =
        Provider.of<DandanplayRemoteProvider>(context, listen: false);
    if (!provider.isInitialized) {
      await provider.initialize();
    }
    final hasExisting = provider.serverUrl?.isNotEmpty == true;

    final result = await BlurLoginDialog.show(
      context,
      title: hasExisting ? '更新弹弹play远程连接' : '连接弹弹play远程服务',
      loginButtonText: hasExisting ? '保存' : '连接',
      fields: [
        LoginField(
          key: 'baseUrl',
          label: '远程服务地址',
          hint: '例如 http://192.168.1.2:23333',
          initialValue: provider.serverUrl ?? '',
        ),
        LoginField(
          key: 'token',
          label: 'API密钥 (可选)',
          hint: provider.tokenRequired ? '服务器已启用 API 验证' : '若服务器开启验证请填写',
          isPassword: true,
          required: false,
        ),
      ],
      onLogin: (values) async {
        final baseUrl = values['baseUrl'] ?? '';
        final token = values['token'];
        if (baseUrl.isEmpty) {
          return const LoginResult(success: false, message: '请输入远程服务地址');
        }
        try {
          await provider.connect(baseUrl, token: token);
          return const LoginResult(
            success: true,
            message: '已连接至弹弹play远程服务',
          );
        } catch (e) {
          return LoginResult(success: false, message: e.toString());
        }
      },
    );

    if (result == true && mounted) {
      BlurSnackBar.show(context, '弹弹play远程服务配置已更新');
    }
  }

  Future<void> _showEmbyServerDialog() async {
    await NetworkMediaServerDialog.show(context, MediaServerType.emby);
  }

  Future<void> _fetchAndPersistFullDetailsInBackground() async {
    // 🔥 CPU优化：防止重复启动后台任务
    if (_isBackgroundFetching) {
      //debugPrint('[媒体库CPU] 后台获取任务已在进行中，跳过');
      return;
    }
    _isBackgroundFetching = true;

    //debugPrint('[媒体库CPU] 开始后台获取详细信息 - 项目数量: ${_uniqueLibraryItems.length}');
    final stopwatch = Stopwatch()..start();
    final prefs = await SharedPreferences.getInstance();
    List<Future> pendingRequests = [];
    const int maxConcurrentRequests = 2; // 🔥 CPU优化：减少并发请求数量

    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null) {
        // 检查是否是手动刷新，如果是，只处理新增的条目，除非语言已更新
        if (_isManualRefresh &&
            !_languageUpdated &&
            _existingAnimeIds.contains(historyItem.animeId!)) {
          continue; // 跳过已存在的条目
        }

        Future<void> fetchDetailForItem() async {
          try {
            // 检查已缓存的详细数据是否语言匹配
            if (_fetchedFullAnimeData.containsKey(historyItem.animeId!)) {
              final cachedAnime = _fetchedFullAnimeData[historyItem.animeId!];
              // 检查语言是否匹配
              final isTraditional =
                  await ChineseConverter.isTraditionalChineseEnvironment(null);
              final expectedLanguage = isTraditional ? 'zh_Hant' : 'zh';
              if (cachedAnime?.language == expectedLanguage) {
                return; // 语言匹配，跳过获取
              }
            }

            final animeDetail = await BangumiService.instance
                .getAnimeDetails(historyItem.animeId!);
            //debugPrint('[媒体库CPU] 获取到动画详情: ${historyItem.animeId} - ${animeDetail.name}');
            if (mounted) {
              _fetchedFullAnimeData[historyItem.animeId!] = animeDetail;
              setState(() {});
              if (animeDetail.imageUrl.isNotEmpty) {
                await prefs.setString('$_prefsKeyPrefix${historyItem.animeId!}',
                    animeDetail.imageUrl);
                if (mounted) {
                  _persistedImageUrls[historyItem.animeId!] =
                      animeDetail.imageUrl;
                  setState(() {});
                }
              } else {
                await prefs.remove('$_prefsKeyPrefix${historyItem.animeId!}');
                if (mounted &&
                    _persistedImageUrls.containsKey(historyItem.animeId!)) {
                  _persistedImageUrls.remove(historyItem.animeId!);
                  setState(() {});
                }
              }
            }
          } catch (e) {
            //debugPrint('[媒体库CPU] 获取动画详情失败: ${historyItem.animeId} - $e');
          }
        }

        if (pendingRequests.length >= maxConcurrentRequests) {
          await Future.any(pendingRequests);
          pendingRequests
              .removeWhere((f) => f.toString().contains('Completed'));
        }

        pendingRequests.add(fetchDetailForItem());
      }
    }

    await Future.wait(pendingRequests);

    // 重置标志
    _isManualRefresh = false;
    _languageUpdated = false; // 重置语言更新标志

    // 🔥 CPU优化：最后一次性刷新UI，而不是每个项目都setState
    if (mounted) {
      setState(() {
        // 触发UI重建，显示所有更新的数据
      });
    }

    //debugPrint('[媒体库CPU] 后台获取完成 - 耗时: ${stopwatch.elapsedMilliseconds}ms');
    _isBackgroundFetching = false;
  }

  Future<void> _preloadAnimeDetail(int animeId) async {
    // 检查已缓存的详细数据是否语言匹配
    if (_fetchedFullAnimeData.containsKey(animeId)) {
      final cachedAnime = _fetchedFullAnimeData[animeId];
      // 检查语言是否匹配
      final isTraditional =
          await ChineseConverter.isTraditionalChineseEnvironment(null);
      final expectedLanguage = isTraditional ? 'zh_Hant' : 'zh';
      if (cachedAnime?.language == expectedLanguage) {
        return; // 语言匹配，跳过获取
      }
    }

    try {
      final animeDetail =
          await BangumiService.instance.getAnimeDetails(animeId);
      if (mounted) {
        setState(() {
          _fetchedFullAnimeData[animeId] = animeDetail;
        });
      }
    } catch (e) {
      // Silent fail
    }
  }

  Future<void> _checkLanguageChange() async {
    // 获取当前语言设置
    final prefs = await SharedPreferences.getInstance();
    final currentLanguage =
        prefs.getString(SettingsKeys.appLanguageMode) ?? 'auto';

    // 检查语言设置是否变化
    if (_lastLanguageSetting != null &&
        _lastLanguageSetting != currentLanguage) {
      // 语言设置变化，标记所有缓存为需要更新
      _fetchedFullAnimeData.clear();
      // 清空卡片Widget缓存，避免显示旧语言的内容
      _cardWidgetCache.clear();
      // 标记语言已更新
      _languageUpdated = true;
      // 重新获取所有番剧详情
      await _fetchAndPersistFullDetailsInBackground();
      // 触发UI重建，确保显示新语言的内容
      if (mounted) {
        setState(() {});
      }
    }

    // 更新上次语言设置
    _lastLanguageSetting = currentLanguage;
  }

  void _navigateToAnimeDetail(int animeId) {
    ThemedAnimeDetail.show(context, animeId).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        widget.onPlayEpisode?.call(result);
      }
    });

    if (!_fetchedFullAnimeData.containsKey(animeId)) {
      _preloadAnimeDetail(animeId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 移除super.build(context)调用，因为已禁用AutomaticKeepAliveClientMixin
    // super.build(context);
    //debugPrint('[媒体库CPU] MediaLibraryPage build 被调用 - mounted: $mounted');
    // This Consumer ensures that we rebuild when the watch history changes.
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        // Trigger processing of history data whenever the provider updates.
        if (historyProvider.isLoaded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _processAndSortHistory(historyProvider.history);
            }
          });
        }

        return _buildLocalMediaLibrary();
      },
    );
  }

  String? _getWatchProgress(int? animeId) {
    if (animeId == null) return null;

    final detail = _fetchedFullAnimeData[animeId];
    final watchHistoryProvider =
        Provider.of<WatchHistoryProvider>(context, listen: false);

    // 获取该动画的所有历史记录并去重（按episodeId或标题，如果有的话）
    final allHistory = watchHistoryProvider.history
        .where((h) => h.animeId == animeId && _matchesSource(h))
        .toList();

    // 如果没有历史记录（理论上不应该，因为这里是媒体库），显示未观看
    if (allHistory.isEmpty) return '未观看';

    final watchedHistory = allHistory.where(_hasWatchProgress).toList();
    if (watchedHistory.isEmpty) return '未观看';

    // 统计已观看的集数
    final watchedIds = <int>{};
    for (var h in watchedHistory) {
      if (h.episodeId != null && h.episodeId! > 0) {
        watchedIds.add(h.episodeId!);
      }
    }

    int watchedCount = watchedIds.length;
    if (watchedCount == 0) {
      // 如果没有episodeId信息，按条目数估算（但不准确）
      watchedCount = watchedHistory.length;
    }

    if (detail != null &&
        detail.totalEpisodes != null &&
        detail.totalEpisodes! > 0) {
      if (watchedCount >= detail.totalEpisodes!) {
        return '已看完';
      }
      return '已看 $watchedCount / ${detail.totalEpisodes} 集';
    }

    return '已看 $watchedCount 集';
  }

  bool _hasWatchProgress(WatchHistoryItem item) {
    if (item.watchProgress > 0.01) {
      return true;
    }
    return item.lastPosition > 0;
  }

  Widget _buildLocalMediaLibrary() {
    if (_isLoadingInitial) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator(color: _accentColor)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载媒体库失败: $_error',
                  style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadInitialMediaLibraryData,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_uniqueLibraryItems.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _emptyMessage,
                textAlign: TextAlign.center,
                locale: const Locale("zh-Hans", "zh"),
                style: const TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        LocalLibraryControlBar(
          searchController: _searchController,
          currentSort: _currentSort,
          title: widget.sourceType == MediaLibrarySourceType.local
              ? null
              : _sourceDisplayName,
          onSearchChanged: (val) => _applyFilter(),
          onSortChanged: (type) {
            _currentSort = type;
            _applyFilter();
          },
          trailingActions: widget.sourceType == MediaLibrarySourceType.local
              ? [
                  _buildSyncActionButton(
                    tooltip: '同步本地媒体库',
                    onPressed: _syncLocalLibrary,
                  ),
                ]
              : widget.sourceType == MediaLibrarySourceType.webdav
                  ? [
                      _buildSyncActionButton(
                        tooltip: '同步WebDAV媒体库',
                        onPressed: _syncWebDavLibrary,
                      ),
                    ]
                  : widget.sourceType == MediaLibrarySourceType.smb
                      ? [
                          _buildSyncActionButton(
                            tooltip: '同步SMB媒体库',
                            onPressed: _syncSmbLibrary,
                          ),
                        ]
                      : null,
        ),
        Expanded(
          child: Stack(
            children: [
              RepaintBoundary(
                child: Scrollbar(
                  controller: _gridScrollController,
                  thickness: kIsWeb
                      ? 4
                      : (defaultTargetPlatform == TargetPlatform.android ||
                              defaultTargetPlatform == TargetPlatform.iOS)
                          ? 0
                          : 4,
                  radius: const Radius.circular(2),
                  child: GridView.builder(
                    controller: _gridScrollController,
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: context
                              .watch<AppearanceSettingsProvider>()
                              .showAnimeCardSummary
                          ? HorizontalAnimeCard.detailedGridMaxCrossAxisExtent
                          : HorizontalAnimeCard.compactGridMaxCrossAxisExtent,
                      mainAxisExtent: context
                              .watch<AppearanceSettingsProvider>()
                              .showAnimeCardSummary
                          ? HorizontalAnimeCard.detailedCardHeight
                          : HorizontalAnimeCard.compactCardHeight,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                    cacheExtent: 800,
                    clipBehavior: Clip.hardEdge,
                    physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics()),
                    addAutomaticKeepAlives: false,
                    addRepaintBoundaries: true,
                    itemCount: _filteredItems.length,
                    itemBuilder: (context, index) {
                      // 🔥 CPU优化：添加itemBuilder监控
                      if (index % 20 == 0) {
                        //debugPrint('[媒体库CPU] GridView itemBuilder - 索引: $index/${_filteredItems.length}');
                      }
                      final historyItem = _filteredItems[index];
                      final animeId = historyItem.animeId;

                      // 🔥 CPU优化：使用文件路径作为缓存键，检查是否已缓存
                      final cacheKey = historyItem.filePath;
                      if (_cardWidgetCache.containsKey(cacheKey)) {
                        return _cardWidgetCache[cacheKey]!;
                      }

                      String imageUrlToDisplay =
                          historyItem.thumbnailPath ?? '';
                      String nameToDisplay = historyItem.animeName.isNotEmpty
                          ? historyItem.animeName
                          : (historyItem.episodeTitle ?? '未知动画');

                      // 尝试从持久化缓存中获取图片（作为初始值）
                      if (animeId != null &&
                          _persistedImageUrls.containsKey(animeId)) {
                        imageUrlToDisplay = _persistedImageUrls[animeId]!;
                      }

                      // 优先使用已获取的详情数据
                      BangumiAnime? detailData;
                      if (animeId != null &&
                          _fetchedFullAnimeData.containsKey(animeId)) {
                        detailData = _fetchedFullAnimeData[animeId];
                      }

                      if (detailData != null) {
                        // 有同步数据，直接构建
                        String displayImage = imageUrlToDisplay;
                        if (detailData.imageUrl.isNotEmpty) {
                          displayImage = detailData.imageUrl;
                        }

                        // 标题：优先使用详情数据中的名称（支持多语言）
                        String displayTitle = nameToDisplay;
                        if (detailData.name.isNotEmpty) {
                          displayTitle = detailData.name;
                        } else if (detailData.nameCn.isNotEmpty) {
                          displayTitle = detailData.nameCn;
                        }

                        final card = HorizontalAnimeCard(
                          imageUrl: displayImage,
                          title: displayTitle,
                          rating: detailData.rating,
                          source: AnimeCard.getSourceFromFilePath(
                              historyItem.filePath),
                          summary: detailData.summary,
                          progress: _getWatchProgress(animeId),
                          onTap: () {
                            if (animeId != null) {
                              _navigateToAnimeDetail(animeId);
                            } else {
                              BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                            }
                          },
                        );

                        if (_cardWidgetCache.length < 100) {
                          _cardWidgetCache[cacheKey] = card;
                        }
                        return card;
                      }

                      // 没有同步数据，使用FutureBuilder来构建卡片
                      final card = FutureBuilder<BangumiAnime>(
                          future: animeId != null
                              ? BangumiService.instance.getAnimeDetails(animeId)
                              : null,
                          builder: (context, snapshot) {
                            final detail = snapshot.data;

                            // 图片：优先用 detail.imageUrl (高清)，其次用 persisted/thumbnail
                            String displayImage = imageUrlToDisplay;
                            if (detail != null && detail.imageUrl.isNotEmpty) {
                              displayImage = detail.imageUrl;
                            }

                            // 标题：优先使用详情数据中的名称（支持多语言）
                            String displayTitle = nameToDisplay;
                            if (detail != null) {
                              if (detail.name.isNotEmpty) {
                                displayTitle = detail.name;
                              } else if (detail.nameCn.isNotEmpty) {
                                displayTitle = detail.nameCn;
                              }
                            }

                            // 评分
                            double? displayRating = detail?.rating;

                            return HorizontalAnimeCard(
                              imageUrl: displayImage,
                              title: displayTitle,
                              rating: displayRating,
                              source: AnimeCard.getSourceFromFilePath(
                                  historyItem.filePath),
                              summary: detail?.summary,
                              progress: _getWatchProgress(animeId),
                              onTap: () {
                                if (animeId != null) {
                                  _navigateToAnimeDetail(animeId);
                                } else {
                                  BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                                }
                              },
                            );
                          });

                      // 🔥 CPU优化：缓存卡片Widget，限制缓存大小避免内存泄漏
                      if (_cardWidgetCache.length < 100) {
                        // 限制最多缓存100个卡片
                        _cardWidgetCache[cacheKey] = card;
                      }

                      return card;
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

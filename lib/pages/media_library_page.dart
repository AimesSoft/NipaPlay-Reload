import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_anime_card.dart';
import 'package:nipaplay/widgets/nipaplay_theme/themed_anime_detail.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_media_library_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/jellyfin_server_dialog.dart'; 
import 'dart:io'; 
import 'dart:async';
import 'dart:ui'; 
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/floating_action_glass_button.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/widgets/nipaplay_theme/emby_server_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/media_server_selection_sheet.dart';

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback
  final bool jellyfinMode; // 是否为Jellyfin媒体库模式

  const MediaLibraryPage({
    super.key, 
    this.onPlayEpisode,
    this.jellyfinMode = false,
  }); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> with AutomaticKeepAliveClientMixin {
  List<WatchHistoryItem> _uniqueLibraryItems = []; 
  Map<int, String> _persistedImageUrls = {}; 
  final Map<int, BangumiAnime> _fetchedFullAnimeData = {}; 
  bool _isLoadingInitial = true; 
  String? _error;
  
  final ScrollController _gridScrollController = ScrollController();

  static const String _prefsKeyPrefix = 'media_library_image_url_';
  
  bool _isJellyfinConnected = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialMediaLibraryData();
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        _isJellyfinConnected = jellyfinProvider.isConnected; // Initialize
        jellyfinProvider.addListener(_onJellyfinProviderChanged);
      }
    });
  }

  @override
  void dispose() {
    try {
      if (mounted) { 
        final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
        jellyfinProvider.removeListener(_onJellyfinProviderChanged);
      }
    } catch (e) {
      // ignore: avoid_print
      print("移除JellyfinProvider监听器时出错: $e");
    }

    _gridScrollController.dispose();
    super.dispose();
  }

  void _onJellyfinProviderChanged() {
    if (mounted) {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (_isJellyfinConnected != jellyfinProvider.isConnected) {
        setState(() {
          _isJellyfinConnected = jellyfinProvider.isConnected;
        });
      }
    }
  }

  Future<void> _processAndSortHistory(List<WatchHistoryItem> watchHistory) async {
    if (!mounted) return;

    if (watchHistory.isEmpty) {
      setState(() {
        _uniqueLibraryItems = [];
        _isLoadingInitial = false; 
      });
      return;
    }

    final filteredHistory = watchHistory.where((item) => 
      !item.filePath.startsWith('jellyfin://') &&
      !item.filePath.startsWith('emby://')
    ).toList();

    final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
    for (var item in filteredHistory) {
      if (item.animeId != null) {
        if (latestHistoryItemMap.containsKey(item.animeId!)) {
          if (item.lastWatchTime.isAfter(latestHistoryItemMap[item.animeId!]!.lastWatchTime)) {
            latestHistoryItemMap[item.animeId!] = item;
          }
        } else {
          latestHistoryItemMap[item.animeId!] = item;
        }
      }
    }
    final uniqueAnimeItemsFromHistory = latestHistoryItemMap.values.toList();
    uniqueAnimeItemsFromHistory.sort((a, b) => b.lastWatchTime.compareTo(a.lastWatchTime));

    Map<int, String> loadedPersistedUrls = {};
    final prefs = await SharedPreferences.getInstance();
    for (var item in uniqueAnimeItemsFromHistory) {
      if (item.animeId != null) {
        String? persistedUrl = prefs.getString('$_prefsKeyPrefix${item.animeId}');
        if (persistedUrl != null && persistedUrl.isNotEmpty) {
          loadedPersistedUrls[item.animeId!] = persistedUrl;
        }
      }
    }

    setState(() {
      _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
      _persistedImageUrls = loadedPersistedUrls;
      _isLoadingInitial = false; 
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
      final historyProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (!historyProvider.isLoaded && !historyProvider.isLoading) {
        await historyProvider.loadHistory(); 
      }
      
      if (historyProvider.isLoaded) {
          await _processAndSortHistory(historyProvider.history);
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
  
  Future<void> _showJellyfinServerDialog() async {
    await JellyfinServerDialog.show(context);
  }

  Future<void> _showServerSelectionDialog() async {
    final result = await MediaServerSelectionSheet.show(context);

    if (result != null && mounted) {
      if (result == 'jellyfin') {
        await _showJellyfinServerDialog();
      } else if (result == 'emby') {
        await _showEmbyServerDialog();
      }
    }
  }

  Future<void> _showEmbyServerDialog() async {
    await EmbyServerDialog.show(context);
  }

  Future<void> _fetchAndPersistFullDetailsInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    List<Future> pendingRequests = [];
    const int maxConcurrentRequests = 3;
    
    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null) { 
        if (_fetchedFullAnimeData.containsKey(historyItem.animeId!) || 
            _persistedImageUrls.containsKey(historyItem.animeId!)) {
            continue;
        }
        
        Future<void> fetchDetailForItem() async {
          try {
            final animeDetail = await BangumiService.instance.getAnimeDetails(historyItem.animeId!);
            if (mounted) {
              setState(() {
                _fetchedFullAnimeData[historyItem.animeId!] = animeDetail;
              });
              if (animeDetail.imageUrl.isNotEmpty) {
                await prefs.setString('$_prefsKeyPrefix${historyItem.animeId!}', animeDetail.imageUrl);
                if (mounted) {
                  setState(() {
                    _persistedImageUrls[historyItem.animeId!] = animeDetail.imageUrl;
                  });
                }
              } else {
                await prefs.remove('$_prefsKeyPrefix${historyItem.animeId!}');
                if(mounted && _persistedImageUrls.containsKey(historyItem.animeId!)){
                  setState(() {
                    _persistedImageUrls.remove(historyItem.animeId!);
                  });
                }
              }
            }
          } catch (e) {
            // Silent fail
          }
        }
        
        if (pendingRequests.length >= maxConcurrentRequests) {
          await Future.any(pendingRequests);
          pendingRequests.removeWhere((f) => f.toString().contains('Completed'));
        }
        
        pendingRequests.add(fetchDetailForItem());
      }
    }
    
    await Future.wait(pendingRequests);
  }

  Future<void> _preloadAnimeDetail(int animeId) async {
    if (_fetchedFullAnimeData.containsKey(animeId)) {
      return;
    }
    
    try {
      final animeDetail = await BangumiService.instance.getAnimeDetails(animeId);
      if (mounted) {
        setState(() {
          _fetchedFullAnimeData[animeId] = animeDetail;
        });
      }
    } catch (e) {
      // Silent fail
    }
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
    super.build(context);
    final uiThemeProvider = Provider.of<UIThemeProvider>(context);

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

        // Decide which UI to render based on the theme.
        if (uiThemeProvider.isFluentUITheme) {
          return FluentMediaLibraryView(
            isLoading: _isLoadingInitial,
            error: _error,
            items: _uniqueLibraryItems,
            fullAnimeData: _fetchedFullAnimeData,
            persistedImageUrls: _persistedImageUrls,
            isJellyfinConnected: _isJellyfinConnected,
            scrollController: _gridScrollController,
            onRefresh: _loadInitialMediaLibraryData,
            onConnectServer: _showServerSelectionDialog,
            onAnimeTap: _navigateToAnimeDetail,
          );
        } else {
          return _buildLocalMediaLibrary();
        }
      },
    );
  }
  
  Widget _buildLocalMediaLibrary() {
    if (_isLoadingInitial) {
      return const SizedBox(
        height: 200, 
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('加载媒体库失败: $_error', style: const TextStyle(color: Colors.white70)),
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
              const Text(
                '媒体库为空。\n观看过的动画将显示在这里。',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 16),
              if (!_isJellyfinConnected)
                _buildGlassButton(
                  onPressed: _showServerSelectionDialog,
                  icon: Icons.cloud,
                  label: '添加媒体服务器',
                ),
            ],
          ),
        ),
      );
    }

    return Stack(
      children: [
        RepaintBoundary(
          child: Scrollbar(
            controller: _gridScrollController,
            thickness: (Platform.isAndroid || Platform.isIOS) ? 0 : 4,
            radius: const Radius.circular(2),
            child: GridView.builder(
              controller: _gridScrollController,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150, 
                childAspectRatio: 7/12,   
                crossAxisSpacing: 8,      
                mainAxisSpacing: 8,       
              ),
              padding: const EdgeInsets.all(0),
              cacheExtent: 800,
              clipBehavior: Clip.hardEdge,
              physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
              addAutomaticKeepAlives: false,
              addRepaintBoundaries: true,
              itemCount: _uniqueLibraryItems.length,
              itemBuilder: (context, index) {
                final historyItem = _uniqueLibraryItems[index];
                final animeId = historyItem.animeId;

                String imageUrlToDisplay = historyItem.thumbnailPath ?? '';
                String nameToDisplay = historyItem.animeName.isNotEmpty 
                    ? historyItem.animeName 
                    : (historyItem.episodeTitle ?? '未知动画');

                if (animeId != null) {
                    if (_fetchedFullAnimeData.containsKey(animeId)) {
                        final fetchedData = _fetchedFullAnimeData[animeId]!;
                        if (fetchedData.imageUrl.isNotEmpty) {
                            imageUrlToDisplay = fetchedData.imageUrl;
                        }
                        if (fetchedData.nameCn.isNotEmpty) {
                            nameToDisplay = fetchedData.nameCn;
                        } else if (fetchedData.name.isNotEmpty) {
                            nameToDisplay = fetchedData.name;
                        }
                    } else if (_persistedImageUrls.containsKey(animeId)) {
                        imageUrlToDisplay = _persistedImageUrls[animeId]!;
                    }
                }

                return _buildAnimeCard(
                  key: ValueKey(animeId ?? historyItem.filePath), 
                  name: nameToDisplay, 
                  imageUrl: imageUrlToDisplay,
                  source: AnimeCard.getSourceFromFilePath(historyItem.filePath),
                  rating: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                      ? _fetchedFullAnimeData[animeId]!.rating 
                      : null,
                  ratingDetails: animeId != null && _fetchedFullAnimeData.containsKey(animeId) 
                      ? _fetchedFullAnimeData[animeId]!.ratingDetails 
                      : null,
                  onTap: () {
                    if (animeId != null) {
                      _navigateToAnimeDetail(animeId);
                    } else {
                      BlurSnackBar.show(context, '无法打开详情，动画ID未知');
                    }
                  },
                );
              },
            ),
          ),
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionGlassButton(
            iconData: Ionicons.cloud_outline,
            onPressed: _showServerSelectionDialog,
            description: '添加媒体服务器\n连接到Jellyfin或Emby服务器\n享受云端媒体库内容',
          ),
        ),
      ],
    );
  }

  Widget _buildAnimeCard({
    required Key key,
    required String name,
    required String imageUrl,
    required String? source,
    required double? rating,
    required Map<String, dynamic>? ratingDetails,
    required VoidCallback onTap,
  }) {
    final uiThemeProvider = Provider.of<UIThemeProvider>(context, listen: false);
    
    if (uiThemeProvider.isFluentUITheme) {
      return FluentAnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    } else {
      return AnimeCard(
        key: key,
        name: name,
        imageUrl: imageUrl,
        source: source,
        rating: rating,
        ratingDetails: ratingDetails,
        onTap: onTap,
      );
    }
  }

  Widget _buildGlassButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        bool isHovered = false;
        
        return MouseRegion(
          onEnter: (_) => setState(() => isHovered = true),
          onExit: (_) => setState(() => isHovered = false),
          cursor: SystemMouseCursors.click,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(isHovered ? 0.2 : 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(isHovered ? 0.4 : 0.2),
                    width: 0.5,
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: onPressed,
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            icon,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
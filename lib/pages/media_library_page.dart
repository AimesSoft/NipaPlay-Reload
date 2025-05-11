import 'package:flutter/material.dart';
import 'package:nipaplay/models/bangumi_model.dart'; // Needed for _fetchedAnimeDetails
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/bangumi_service.dart'; // Needed for getAnimeDetails
import 'package:nipaplay/widgets/anime_card.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/widgets/transparent_page_route.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart'; // For image URL persistence
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';

// Define a callback type for when an episode is selected for playing
typedef OnPlayEpisodeCallback = void Function(WatchHistoryItem item);

class MediaLibraryPage extends StatefulWidget {
  final OnPlayEpisodeCallback? onPlayEpisode; // Add this callback

  const MediaLibraryPage({super.key, this.onPlayEpisode}); // Modify constructor

  @override
  State<MediaLibraryPage> createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage> {
  List<WatchHistoryItem> _uniqueLibraryItems = []; 
  Map<int, String> _persistedImageUrls = {}; // Loaded from SharedPreferences
  Map<int, BangumiAnime> _fetchedFullAnimeData = {}; // Freshly fetched in this session
  bool _isLoadingInitial = true; // For the initial list from history
  String? _error;
  // No longer a single _isLoading; initial load and background fetches are separate concerns.

  static const String _prefsKeyPrefix = 'media_library_image_url_';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadInitialMediaLibraryData();
      }
    });
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
      final watchHistory = historyProvider.history;

      if (watchHistory.isEmpty) {
        if (mounted) {
          setState(() {
            _uniqueLibraryItems = [];
            _isLoadingInitial = false;
          });
        }
        return;
      }

      final Map<int, WatchHistoryItem> latestHistoryItemMap = {};
      for (var item in watchHistory) {
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
      
      // Load persisted image URLs
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

      if (mounted) {
        setState(() {
          _uniqueLibraryItems = uniqueAnimeItemsFromHistory;
          _persistedImageUrls = loadedPersistedUrls; 
          _isLoadingInitial = false;
        });
        _fetchAndPersistFullDetailsInBackground();
      }
    } catch (e) {
      //debugPrint('[MediaLibraryPage] Error loading initial media library data: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingInitial = false;
        });
      }
    }
  }

  Future<void> _fetchAndPersistFullDetailsInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    for (var historyItem in _uniqueLibraryItems) {
      if (historyItem.animeId != null) { 
        // Check if data already fetched in this session to avoid redundant API calls
        if (_fetchedFullAnimeData.containsKey(historyItem.animeId!)) {
            continue;
        }
        try {
          final animeDetail = await BangumiService.instance.getAnimeDetails(historyItem.animeId!);
          if (mounted) {
            setState(() {
              _fetchedFullAnimeData[historyItem.animeId!] = animeDetail;
            });
            if (animeDetail.imageUrl.isNotEmpty) {
              await prefs.setString('$_prefsKeyPrefix${historyItem.animeId!}', animeDetail.imageUrl);
            } else {
              // If fetched URL is empty, remove potentially stale persisted URL
              await prefs.remove('$_prefsKeyPrefix${historyItem.animeId!}');
              // Also update UI state if it was relying on a persisted URL that's now invalid
              if(mounted && _persistedImageUrls.containsKey(historyItem.animeId!)){
                setState(() {
                  _persistedImageUrls.remove(historyItem.animeId!);
                });
              }
            }
          }
        } catch (e) {
          //debugPrint('[MediaLibraryPage] Background fetch error for animeId ${historyItem.animeId}: $e');
          // Consider removing from prefs if fetch consistently fails for a known bad ID?
        }
      }
    }
  }

  void _navigateToAnimeDetail(int animeId) {
    Navigator.push<
        WatchHistoryItem?> // Specify that it can return a WatchHistoryItem
    (
      context,
      TransparentPageRoute(
        builder: (context) => AnimeDetailPage(
          animeId: animeId,
        ),
      ),
    ).then((WatchHistoryItem? result) {
      if (result != null && result.filePath.isNotEmpty) {
        // filePath is from WatchHistoryItem, which should be non-empty if an episode was chosen
        
        // Instead of initializing player here, call the callback
        widget.onPlayEpisode?.call(result);
        
        // Old logic (to be removed or handled by the parent via callback):
        // final videoState = Provider.of<VideoPlayerState>(context, listen: false);
        // videoState.initializePlayer(result.filePath);

        // // Switch to the player tab (assuming index 0 for player)
        // try {
        //   Provider.of<TabChangeNotifier>(context, listen: false).changeTab(0);
        // } catch (e) {
        //   //debugPrint(
        //       '[MediaLibraryPage] Error switching tab with TabChangeNotifier: $e');
        //   // Fallback or alternative tab switching if needed, though TabChangeNotifier is preferred.
        //   // For example, if DefaultTabController is accessible here:
        //   // DefaultTabController.of(context)?.animateTo(0);
        // }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                onPressed: _loadInitialMediaLibraryData, // Changed to load initial data
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_uniqueLibraryItems.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            '媒体库为空。\n观看过的动画将显示在这里。',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150, 
        childAspectRatio: 7/12,   
        crossAxisSpacing: 8,      
        mainAxisSpacing: 8,       
      ),
      padding: const EdgeInsets.all(0), 
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
                // Name remains from historyItem until full details are fetched in this session
            }
        }

        return AnimeCard(
          key: ValueKey(animeId ?? historyItem.filePath), 
          name: nameToDisplay, 
          imageUrl: imageUrlToDisplay,
          onTap: () {
            if (animeId != null) {
              _navigateToAnimeDetail(animeId);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('无法打开详情，动画ID未知')),
              );
            }
          },
        );
      },
    );
  }
} 
import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/providers/jellyfin_provider.dart';
import 'package:nipaplay/providers/emby_provider.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/bangumi_service.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/anime_card.dart';
import 'package:nipaplay/pages/jellyfin_detail_page.dart';
import 'package:nipaplay/pages/emby_detail_page.dart';
import 'package:nipaplay/pages/anime_detail_page.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

class DashboardHomePage extends StatefulWidget {
  const DashboardHomePage({super.key});

  @override
  State<DashboardHomePage> createState() => _DashboardHomePageState();
}

class _DashboardHomePageState extends State<DashboardHomePage>
    with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true;

  // 推荐内容数据
  List<RecommendedItem> _recommendedItems = [];
  bool _isLoadingRecommended = false; // 改为false，避免初始阻止加载

  // 最近添加数据 - 按媒体库分类
  Map<String, List<JellyfinMediaItem>> _recentJellyfinItemsByLibrary = {};
  Map<String, List<EmbyMediaItem>> _recentEmbyItemsByLibrary = {};
  
  // 本地媒体库数据 - 使用番组信息而不是观看历史
  List<LocalAnimeItem> _localAnimeItems = [];

  final PageController _heroBannerPageController = PageController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _continueWatchingScrollController = ScrollController();
  final ScrollController _recentJellyfinScrollController = ScrollController();
  final ScrollController _recentEmbyScrollController = ScrollController();
  
  // 自动切换相关
  Timer? _autoSwitchTimer;
  bool _isAutoSwitching = true;
  int _currentHeroBannerIndex = 0;
  late final ValueNotifier<int> _heroBannerIndexNotifier;

  @override
  void initState() {
    super.initState();
    _heroBannerIndexNotifier = ValueNotifier(0);
    _loadData();
    
    // 添加延迟监听，确保Provider已经初始化
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setupProviderListeners();
      _startAutoSwitch();
    });
  }
  
  void _startAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _autoSwitchTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_isAutoSwitching && _recommendedItems.length >= 5 && mounted) {
        _currentHeroBannerIndex = (_currentHeroBannerIndex + 1) % 5;
        _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
        _heroBannerPageController.animateToPage(
          _currentHeroBannerIndex,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }
  
  void _stopAutoSwitch() {
    _autoSwitchTimer?.cancel();
    _isAutoSwitching = false;
  }
  
  void _resumeAutoSwitch() {
    _isAutoSwitching = true;
    _startAutoSwitch();
  }
  
  void _setupProviderListeners() {
    // 监听Jellyfin连接状态变化
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    jellyfinProvider.addListener(_onJellyfinStateChanged);
    
    // 监听Emby连接状态变化
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    embyProvider.addListener(_onEmbyStateChanged);
  }
  
  void _onJellyfinStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      print('DashboardHomePage: Widget已销毁，跳过Jellyfin状态变化处理');
      return;
    }
    
    final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
    print('DashboardHomePage: Jellyfin连接状态变化 - isConnected: ${jellyfinProvider.isConnected}, mounted: $mounted');
    if (jellyfinProvider.isConnected && mounted) {
      print('DashboardHomePage: Jellyfin连接状态变化，准备刷新数据');
      _loadData();
    }
  }
  
  void _onEmbyStateChanged() {
    // 检查Widget是否仍然处于活动状态
    if (!mounted) {
      print('DashboardHomePage: Widget已销毁，跳过Emby状态变化处理');
      return;
    }
    
    final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
    print('DashboardHomePage: Emby连接状态变化 - isConnected: ${embyProvider.isConnected}, mounted: $mounted');
    if (embyProvider.isConnected && mounted) {
      print('DashboardHomePage: Emby连接状态变化，准备刷新数据');
      _loadData();
    }
  }

  @override
  void dispose() {
    // 清理定时器和ValueNotifier
    _autoSwitchTimer?.cancel();
    _heroBannerIndexNotifier.dispose();
    
    // 移除监听器
    try {
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      jellyfinProvider.removeListener(_onJellyfinStateChanged);
    } catch (e) {
      // Provider可能已经被销毁，忽略错误
    }
    
    try {
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      embyProvider.removeListener(_onEmbyStateChanged);
    } catch (e) {
      // Provider可能已经被销毁，忽略错误
    }
    
    _heroBannerPageController.dispose();
    _mainScrollController.dispose();
    _continueWatchingScrollController.dispose();
    _recentJellyfinScrollController.dispose();
    _recentEmbyScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    print('DashboardHomePage: _loadData 被调用 - _isLoadingRecommended: $_isLoadingRecommended, mounted: $mounted');
    
    // 防止重复加载和检查Widget状态
    if (_isLoadingRecommended || !mounted) {
      print('DashboardHomePage: 跳过数据加载 - _isLoadingRecommended: $_isLoadingRecommended, mounted: $mounted');
      return;
    }
    
    print('DashboardHomePage: 开始加载数据');
    await Future.wait([
      _loadRecommendedContent(),
      _loadRecentContent(),
    ]);
    
    // 再次检查Widget状态
    if (mounted) {
      print('DashboardHomePage: 数据加载完成');
    }
  }

  Future<void> _loadRecommendedContent() async {
    if (!mounted) {
      print('DashboardHomePage: Widget已销毁，跳过推荐内容加载');
      return;
    }
    
    print('DashboardHomePage: 开始加载推荐内容');
    setState(() {
      _isLoadingRecommended = true;
    });

    try {
      // 第一步：快速收集所有候选项目（只收集基本信息）
      List<dynamic> allCandidates = [];

      // 从Jellyfin收集候选项目
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await jellyfinService.getRandomMediaItemsByLibrary(library.id, limit: 50);
              allCandidates.addAll(libraryItems);
              print('从Jellyfin媒体库 ${library.name} 收集到 ${libraryItems.length} 个候选项目');
            } catch (e) {
              print('获取Jellyfin媒体库 ${library.name} 随机内容失败: $e');
            }
          }
        }
      }

      // 从Emby收集候选项目
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              final libraryItems = await embyService.getRandomMediaItemsByLibrary(library.id, limit: 50);
              allCandidates.addAll(libraryItems);
              print('从Emby媒体库 ${library.name} 收集到 ${libraryItems.length} 个候选项目');
            } catch (e) {
              print('获取Emby媒体库 ${library.name} 随机内容失败: $e');
            }
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
            !item.filePath.startsWith('emby://')
          ).toList();
          
          // 按animeId分组，获取每个动画的最新观看记录
          final Map<int, WatchHistoryItem> latestLocalItems = {};
          for (var item in localHistory) {
            if (item.animeId != null) {
              if (latestLocalItems.containsKey(item.animeId!)) {
                if (item.lastWatchTime.isAfter(latestLocalItems[item.animeId!]!.lastWatchTime)) {
                  latestLocalItems[item.animeId!] = item;
                }
              } else {
                latestLocalItems[item.animeId!] = item;
              }
            }
          }
          
          // 随机选择一些本地项目 - 直接使用WatchHistoryItem作为候选
          final localItems = latestLocalItems.values.toList();
          localItems.shuffle(math.Random());
          final selectedLocalItems = localItems.take(math.min(30, localItems.length)).toList();
          allCandidates.addAll(selectedLocalItems);
          print('从本地媒体库收集到 ${selectedLocalItems.length} 个候选项目');
        } catch (e) {
          print('获取本地媒体库随机内容失败: $e');
        }
      }

      // 第二步：从所有候选中随机选择7个
      List<dynamic> selectedCandidates = [];
      if (allCandidates.isNotEmpty) {
        allCandidates.shuffle(math.Random());
        selectedCandidates = allCandidates.take(7).toList();
        print('从${allCandidates.length}个候选项目中随机选择了${selectedCandidates.length}个');
      }

      // 第三步：只为选中的7个项目获取详细信息
      List<RecommendedItem> finalItems = [];
      
      for (var item in selectedCandidates) {
        try {
          if (item is JellyfinMediaItem) {
            // 处理Jellyfin项目
            final jellyfinService = JellyfinService.instance;
            final backdropUrl = jellyfinService.getImageUrl(item.id, type: 'Backdrop', width: 1920, height: 1080, quality: 95);
            String? logoUrl;
            try {
              logoUrl = jellyfinService.getImageUrl(item.id, type: 'Logo');
            } catch (e) {
              logoUrl = null;
            }
            
            String subtitle = '暂无简介信息';
            try {
              final detail = await jellyfinService.getMediaItemDetails(item.id);
              subtitle = detail.overview?.isNotEmpty == true ? detail.overview! : '暂无简介信息';
            } catch (e) {
              print('获取Jellyfin详细信息失败: $e');
              subtitle = item.overview?.isNotEmpty == true ? item.overview! : '暂无简介信息';
            }
            
            finalItems.add(RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: subtitle,
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.jellyfin,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            ));
            print('处理Jellyfin推荐项: ${item.name}');
            
          } else if (item is EmbyMediaItem) {
            // 处理Emby项目
            final embyService = EmbyService.instance;
            final backdropUrl = embyService.getImageUrl(item.id, type: 'Backdrop', width: 1920, height: 1080, quality: 95);
            String? logoUrl;
            try {
              logoUrl = embyService.getImageUrl(item.id, type: 'Logo');
            } catch (e) {
              logoUrl = null;
            }
            
            String subtitle = '暂无简介信息';
            try {
              final detail = await embyService.getMediaItemDetails(item.id);
              subtitle = detail.overview?.isNotEmpty == true ? detail.overview! : '暂无简介信息';
            } catch (e) {
              print('获取Emby详细信息失败: $e');
              subtitle = item.overview?.isNotEmpty == true ? item.overview! : '暂无简介信息';
            }
            
            finalItems.add(RecommendedItem(
              id: item.id,
              title: item.name,
              subtitle: subtitle,
              backgroundImageUrl: backdropUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.emby,
              rating: item.communityRating != null ? double.tryParse(item.communityRating!) : null,
            ));
            print('处理Emby推荐项: ${item.name}');
            
          } else if (item is WatchHistoryItem) {
            // 处理本地媒体库项目
            String subtitle = '暂无简介信息';
            String? backgroundImageUrl;
            String? logoUrl;
            
            // 尝试获取Bangumi详细信息
            if (item.animeId != null) {
              try {
                final bangumiService = BangumiService.instance;
                final animeDetail = await bangumiService.getAnimeDetails(item.animeId!);
                subtitle = animeDetail.summary?.isNotEmpty == true ? animeDetail.summary! : '暂无简介信息';
                backgroundImageUrl = animeDetail.imageUrl;
                // 本地媒体库通常没有logo，使用背景图片
                logoUrl = null;
              } catch (e) {
                print('获取Bangumi详细信息失败 (animeId: ${item.animeId}): $e');
                subtitle = '暂无简介信息';
              }
            }
            
            finalItems.add(RecommendedItem(
              id: item.animeId?.toString() ?? item.filePath,
              title: item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画'),
              subtitle: subtitle,
              backgroundImageUrl: backgroundImageUrl,
              logoImageUrl: logoUrl,
              source: RecommendedItemSource.local,
              rating: null, // 本地媒体库暂时不支持评分
            ));
            print('处理本地推荐项: ${item.animeName}');
          }
        } catch (e) {
          print('处理推荐项目失败: $e');
        }
      }

      // 如果还不够7个，添加占位符
      while (finalItems.length < 7) {
        finalItems.add(RecommendedItem(
          id: 'placeholder_${finalItems.length}',
          title: '暂无推荐内容',
          subtitle: '连接媒体服务器以获取推荐内容',
          backgroundImageUrl: null,
          logoImageUrl: null,
          source: RecommendedItemSource.placeholder,
          rating: null,
        ));
      }

      if (mounted) {
        setState(() {
          _recommendedItems = finalItems;
          _isLoadingRecommended = false;
        });
        // 推荐内容加载完成后启动自动切换
        if (finalItems.length >= 5) {
          _startAutoSwitch();
        }
      }
      print('推荐内容加载完成，总共 ${finalItems.length} 个项目');
    } catch (e) {
      print('加载推荐内容失败: $e');
      if (mounted) {
        setState(() {
          _isLoadingRecommended = false;
        });
      }
    }
  }

  Future<void> _loadRecentContent() async {
    print('DashboardHomePage: 开始加载最近内容');
    try {
      // 从Jellyfin按媒体库获取最近添加
      final jellyfinProvider = Provider.of<JellyfinProvider>(context, listen: false);
      if (jellyfinProvider.isConnected) {
        final jellyfinService = JellyfinService.instance;
        _recentJellyfinItemsByLibrary.clear();
        
        // 获取选中的媒体库
        for (final library in jellyfinService.availableLibraries) {
          if (jellyfinService.selectedLibraryIds.contains(library.id)) {
            try {
              // 按特定媒体库获取内容
              final libraryItems = await jellyfinService.getLatestMediaItemsByLibrary(library.id, limit: 25);
              
              if (libraryItems.isNotEmpty) {
                _recentJellyfinItemsByLibrary[library.name] = libraryItems;
                print('Jellyfin媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
              }
            } catch (e) {
              print('获取Jellyfin媒体库 ${library.name} 最近内容失败: $e');
            }
          }
        }
      }

      // 从Emby按媒体库获取最近添加
      final embyProvider = Provider.of<EmbyProvider>(context, listen: false);
      if (embyProvider.isConnected) {
        final embyService = EmbyService.instance;
        _recentEmbyItemsByLibrary.clear();
        
        // 获取选中的媒体库
        for (final library in embyService.availableLibraries) {
          if (embyService.selectedLibraryIds.contains(library.id)) {
            try {
              // 按特定媒体库获取内容
              final libraryItems = await embyService.getLatestMediaItemsByLibrary(library.id, limit: 25);
              
              if (libraryItems.isNotEmpty) {
                _recentEmbyItemsByLibrary[library.name] = libraryItems;
                print('Emby媒体库 ${library.name} 获取到 ${libraryItems.length} 个项目');
              }
            } catch (e) {
              print('获取Emby媒体库 ${library.name} 最近内容失败: $e');
            }
          }
        }
      }

      // 从本地媒体库获取最近添加
      final watchHistoryProvider = Provider.of<WatchHistoryProvider>(context, listen: false);
      if (watchHistoryProvider.isLoaded) {
        try {
          // 过滤掉Jellyfin和Emby的项目，只保留本地文件
          final localHistory = watchHistoryProvider.history.where((item) => 
            !item.filePath.startsWith('jellyfin://') &&
            !item.filePath.startsWith('emby://')
          ).toList();
          
          // 按animeId分组，获取每个动画的所有集数，然后找到文件修改时间最新的
          final Map<int, WatchHistoryItem> latestAddedItems = {};
          for (var item in localHistory) {
            if (item.animeId != null) {
              try {
                // 获取文件的修改时间
                final file = File(item.filePath);
                if (file.existsSync()) {
                  final stat = file.statSync();
                  final modifiedTime = stat.modified;
                  
                  if (latestAddedItems.containsKey(item.animeId!)) {
                    // 如果该动画已存在，比较文件修改时间，保留更新的
                    final existingFile = File(latestAddedItems[item.animeId!]!.filePath);
                    if (existingFile.existsSync()) {
                      final existingStat = existingFile.statSync();
                      if (modifiedTime.isAfter(existingStat.modified)) {
                        latestAddedItems[item.animeId!] = item;
                      }
                    }
                  } else {
                    latestAddedItems[item.animeId!] = item;
                  }
                }
              } catch (e) {
                print('获取文件 ${item.filePath} 修改时间失败: $e');
                // 如果无法获取文件时间，使用观看时间作为替代
                if (latestAddedItems.containsKey(item.animeId!)) {
                  if (item.lastWatchTime.isAfter(latestAddedItems[item.animeId!]!.lastWatchTime)) {
                    latestAddedItems[item.animeId!] = item;
                  }
                } else {
                  latestAddedItems[item.animeId!] = item;
                }
              }
            }
          }
          
          // 转换为LocalAnimeItem并获取番组信息
          List<LocalAnimeItem> localAnimeItems = [];
          
          // 并行获取所有番组信息以提高性能
          final futures = <Future<LocalAnimeItem>>[];
          for (var entry in latestAddedItems.entries) {
            final animeId = entry.key;
            final latestEpisode = entry.value;
            
            futures.add(_createLocalAnimeItem(animeId, latestEpisode));
          }
          
          // 等待所有番组信息获取完成
          try {
            localAnimeItems = await Future.wait(futures);
          } catch (e) {
            print('批量获取番组信息失败: $e');
            // 如果批量获取失败，创建基本的项目
            for (var entry in latestAddedItems.entries) {
              try {
                final file = File(entry.value.filePath);
                DateTime addedTime = DateTime.now();
                if (file.existsSync()) {
                  final stat = file.statSync();
                  addedTime = stat.modified;
                }
                
                localAnimeItems.add(LocalAnimeItem(
                  animeId: entry.key,
                  animeName: entry.value.animeName.isNotEmpty ? entry.value.animeName : '未知动画',
                  imageUrl: null,
                  backdropImageUrl: null,
                  addedTime: addedTime,
                  latestEpisode: entry.value,
                ));
              } catch (e) {
                print('创建本地动画项目失败: $e');
              }
            }
          }
          
          // 按文件添加时间排序（最新的在前）
          localAnimeItems.sort((a, b) => b.addedTime.compareTo(a.addedTime));
          
          // 限制数量到25个
          if (localAnimeItems.length > 25) {
            localAnimeItems = localAnimeItems.take(25).toList();
          }
          
          _localAnimeItems = localAnimeItems;
          print('本地媒体库获取到 ${_localAnimeItems.length} 个项目');
        } catch (e) {
          print('获取本地媒体库最近内容失败: $e');
        }
      }

      if (mounted) {
        setState(() {
          // 触发UI更新
        });
      }
    } catch (e) {
      print('加载最近内容失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Consumer2<JellyfinProvider, EmbyProvider>(
        builder: (context, jellyfinProvider, embyProvider, child) {
          return SingleChildScrollView(
            controller: _mainScrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  // 大海报推荐区域
                  _buildHeroBanner(),
                  
                  const SizedBox(height: 32),
                  
                  // 继续播放区域
                  _buildContinueWatching(),
                  
                  const SizedBox(height: 32),
                  
                  // Jellyfin按媒体库显示最近添加
                  ..._recentJellyfinItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Jellyfin - 新增${entry.key}',
                      items: entry.value,
                      scrollController: ScrollController(),
                      onItemTap: (item) => _onJellyfinItemTap(item as JellyfinMediaItem),
                    ),
                    const SizedBox(height: 32),
                  ]).expand((x) => x),
                  
                  // Emby按媒体库显示最近添加
                  ..._recentEmbyItemsByLibrary.entries.map((entry) => [
                    _buildRecentSection(
                      title: 'Emby - 新增${entry.key}',
                      items: entry.value,
                      scrollController: ScrollController(),
                      onItemTap: (item) => _onEmbyItemTap(item as EmbyMediaItem),
                    ),
                    const SizedBox(height: 32),
                  ]).expand((x) => x),
                  
                  // 本地媒体库显示最近添加
                  if (_localAnimeItems.isNotEmpty) ...[
                    _buildRecentSection(
                      title: '本地媒体库 - 最近添加',
                      items: _localAnimeItems,
                      scrollController: ScrollController(),
                      onItemTap: (item) => _onLocalAnimeItemTap(item as LocalAnimeItem),
                    ),
                    const SizedBox(height: 32),
                  ],
                  
                  // 空状态提示（当没有任何内容时）
                  if (_recentJellyfinItemsByLibrary.isEmpty && 
                      _recentEmbyItemsByLibrary.isEmpty && 
                      _localAnimeItems.isEmpty && 
                      !_isLoadingRecommended) ...[
                    Container(
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.white10,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.video_library_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              jellyfinProvider.isConnected || embyProvider.isConnected
                                  ? '正在加载内容...'
                                  : '连接媒体服务器或观看本地视频以查看内容',
                              style: const TextStyle(color: Colors.white54, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  
                  // 底部间距
                  const SizedBox(height: 50),
                ],
              ),
            );
        },
      ),
      floatingActionButton: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _isLoadingRecommended 
                  ? Colors.white.withOpacity(0.2) 
                  : Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
                width: 1,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: _isLoadingRecommended ? null : _loadData,
                child: Center(
                  child: _isLoadingRecommended
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(
                          Icons.refresh,
                          color: Colors.white,
                          size: 24,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroBanner() {
    if (_isLoadingRecommended) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white10,
        ),
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_recommendedItems.isEmpty) {
      return Container(
        height: 400,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: Colors.white10,
        ),
        child: const Center(
          child: Text(
            '暂无推荐内容',
            style: TextStyle(color: Colors.white54, fontSize: 16),
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

    return Container(
      height: 400,
      margin: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Row(
            children: [
              // 左侧主推荐横幅 - 占据大部分宽度，支持滑动（前5个）
              Expanded(
                flex: 2,
                child: PageView.builder(
                  controller: _heroBannerPageController,
                  itemCount: 5, // 固定显示5个
                  onPageChanged: (index) {
                    // 只更新当前索引和ValueNotifier，避免重新构建整个UI
                    _currentHeroBannerIndex = index;
                    _heroBannerIndexNotifier.value = index;
                    // 用户手动切换时停止自动切换3秒
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
                    // 上方小卡片（第6个）
                    Expanded(
                      child: _buildSmallRecommendationCard(items[5], 5),
                    ),
                    
                    const SizedBox(height: 8),
                    
                    // 下方小卡片（第7个）
                    Expanded(
                      child: _buildSmallRecommendationCard(items[6], 6),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // 左侧切换按钮
          Positioned(
            left: 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildNavigationButton(
                icon: Icons.chevron_left,
                onTap: () {
                  _stopAutoSwitch();
                  _currentHeroBannerIndex = (_currentHeroBannerIndex - 1 + 5) % 5;
                  _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
                  _heroBannerPageController.animateToPage(
                    _currentHeroBannerIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                  Timer(const Duration(seconds: 3), () {
                    _resumeAutoSwitch();
                  });
                },
              ),
            ),
          ),
          
          // 右侧切换按钮（距离左侧PageView区域右边缘相同距离）
          Positioned(
            // 计算：左侧PageView占2/3宽度，减去12px间距，再减去16px边距保持对称
            right: (MediaQuery.of(context).size.width - 32) / 3 + 12 + 16,
            top: 0,
            bottom: 0,
            child: Center(
              child: _buildNavigationButton(
                icon: Icons.chevron_right,
                onTap: () {
                  _stopAutoSwitch();
                  _currentHeroBannerIndex = (_currentHeroBannerIndex + 1) % 5;
                  _heroBannerIndexNotifier.value = _currentHeroBannerIndex;
                  _heroBannerPageController.animateToPage(
                    _currentHeroBannerIndex,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeInOut,
                  );
                  Timer(const Duration(seconds: 3), () {
                    _resumeAutoSwitch();
                  });
                },
              ),
            ),
          ),
          
          // 页面指示器
          _buildPageIndicator(),
        ],
      ),
    );
  }

  Widget _buildMainHeroBannerItem(RecommendedItem item) {
    return GestureDetector(
      onTap: () => _onRecommendedItemTap(item),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图
            if (item.backgroundImageUrl != null)
              Image.network(
                item.backgroundImageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.white10,
                    child: const Center(
                      child: CircularProgressIndicator(),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
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
            
            // 左上角服务商标识
            Positioned(
              top: 16,
              left: 16,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
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
            
            // 左下角Logo
            if (item.logoImageUrl != null)
              Positioned(
                left: 32,
                bottom: 32,
                child: ClipRect(
                  child: Container(
                    constraints: const BoxConstraints(
                      maxWidth: 200,
                      maxHeight: 80,
                    ),
                    child: Image.network(
                      item.logoImageUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return Container(
                          width: 200,
                          height: 80,
                          color: Colors.transparent,
                        );
                      },
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 200,
                        height: 80,
                        color: Colors.transparent,
                      ),
                    ),
                  ),
                ),
              ),
            
            // 左侧中间位置的标题和简介
            Positioned(
              left: 16,
              right: MediaQuery.of(context).size.width * 0.3, // 留出右侧空间
              top: 0,
              bottom: 0,
              child: Center(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 媒体名字（加粗显示）
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    
                    const SizedBox(height: 12),
                    
                    // 剧情简介（只显示2行）
                    if (item.subtitle.isNotEmpty)
                      Text(
                        item.subtitle,
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
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 背景图
            if (item.backgroundImageUrl != null)
              Image.network(
                item.backgroundImageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.white10,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Container(color: Colors.white10),
              )
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blue.withOpacity(0.3),
                      Colors.purple.withOpacity(0.3),
                    ],
                  ),
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
            
            // 左上角服务商标识
            Positioned(
              top: 8,
              left: 8,
              child: _buildServiceIcon(item.source),
            ),
            
            // 右上角评分
            if (item.rating != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.star,
                        color: Colors.amber,
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
            
            // 左下角小Logo
            if (item.logoImageUrl != null)
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
            
            // 标题（右下角，如果没有Logo时显示）
            if (item.logoImageUrl == null)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
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
    );
  }

  Widget _buildServiceIcon(RecommendedItemSource source) {
    Widget iconWidget;
    
    switch (source) {
      case RecommendedItemSource.jellyfin:
        iconWidget = SvgPicture.asset(
          'assets/jellyfin.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.emby:
        iconWidget = SvgPicture.asset(
          'assets/emby.svg',
          width: 20,
          height: 20,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        );
        break;
      case RecommendedItemSource.local:
        // 本地文件用一个文件夹图标
        iconWidget = const Icon(
          Icons.folder,
          color: Colors.white,
          size: 20,
        );
        break;
      default:
        return const SizedBox.shrink();
    }
    
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: iconWidget,
    );
  }

  Widget _buildContinueWatching() {
    return Consumer<WatchHistoryProvider>(
      builder: (context, historyProvider, child) {
        final history = historyProvider.history;
        final validHistory = history.where((item) => item.duration > 0).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '继续播放',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
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
                child: const Center(
                  child: Text(
                    '暂无播放记录',
                    style: TextStyle(color: Colors.white54, fontSize: 16),
                  ),
                ),
              )
            else
              SizedBox(
                height: 280, // 增加高度以适应更大的卡片样式
                child: ListView.builder(
                  controller: _continueWatchingScrollController,
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: math.min(validHistory.length, 10),
                  itemBuilder: (context, index) {
                    final item = validHistory[index];
                    return Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _buildContinueWatchingCard(item),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildContinueWatchingCard(WatchHistoryItem item) {
    return GestureDetector(
      onTap: () => _onWatchHistoryItemTap(item),
      child: SizedBox(
        width: 280, // 增加宽度使卡片更大
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 图片容器
            Container(
              height: 158, // 16:9比例，280*0.5625=157.5
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景缩略图
                  _getVideoThumbnail(item),
                  
                  // 播放进度条（底部）
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: item.watchProgress,
                      backgroundColor: Colors.white24,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).colorScheme.secondary,
                      ),
                      minHeight: 4,
                    ),
                  ),
                  
                  // 播放图标（中心）
                  const Center(
                    child: Icon(
                      Icons.play_circle_filled,
                      color: Colors.white,
                      size: 50, // 增加播放图标大小
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 8),
            
            // 媒体名称
            Text(
              item.animeName.isNotEmpty ? item.animeName : path.basename(item.filePath),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16, // 增加字体大小
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2, // 增加显示行数
              overflow: TextOverflow.ellipsis,
            ),
            
            const SizedBox(height: 4),
            
            // 集数信息
            if (item.episodeTitle != null)
              Text(
                item.episodeTitle!,
                style: const TextStyle(
                  color: Colors.white70,
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

  Widget _buildRecentSection({
    required String title,
    required List<dynamic> items,
    required ScrollController scrollController,
    required Function(dynamic) onItemTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: ListView.builder(
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            itemBuilder: (context, index) {
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

  Widget _buildMediaCard(dynamic item, Function(dynamic) onItemTap) {
    String name = '';
    String imageUrl = '';
    
    if (item is JellyfinMediaItem) {
      name = item.name;
      try {
        imageUrl = JellyfinService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is EmbyMediaItem) {
      name = item.name;
      try {
        imageUrl = EmbyService.instance.getImageUrl(item.id);
      } catch (e) {
        imageUrl = '';
      }
    } else if (item is WatchHistoryItem) {
      name = item.animeName.isNotEmpty ? item.animeName : (item.episodeTitle ?? '未知动画');
      imageUrl = item.thumbnailPath ?? '';
    } else if (item is LocalAnimeItem) {
      name = item.animeName;
      imageUrl = item.imageUrl ?? '';
    }

    return SizedBox(
      width: 150,
      height: 280,
      child: AnimeCard(
        name: name,
        imageUrl: imageUrl,
        onTap: () => onItemTap(item),
        isOnAir: false,
      ),
    );
  }

  Widget _getVideoThumbnail(WatchHistoryItem item) {
    if (item.thumbnailPath != null) {
      final thumbnailFile = File(item.thumbnailPath!);
      if (thumbnailFile.existsSync()) {
        return FutureBuilder<Uint8List>(
          future: thumbnailFile.readAsBytes(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Container(color: Colors.white10);
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return _buildDefaultThumbnail();
            }
            try {
              return Image.memory(
                snapshot.data!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              );
            } catch (e) {
              return _buildDefaultThumbnail();
            }
          },
        );
      }
    }
    return _buildDefaultThumbnail();
  }

  Widget _buildDefaultThumbnail() {
    return Container(
      color: Colors.white10,
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.white30, size: 32),
      ),
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
              // 重新加载数据
              _loadData();
            }
          });
        }
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
        // 重新加载数据
        _loadData();
      }
    });
  }

  // 创建本地动画项目的辅助方法
  Future<LocalAnimeItem> _createLocalAnimeItem(int animeId, WatchHistoryItem latestEpisode) async {
    String? imageUrl;
    String? backdropImageUrl;
    
    // 尝试从Bangumi获取图片信息
    try {
      final bangumiService = BangumiService.instance;
      final animeDetail = await bangumiService.getAnimeDetails(animeId);
      imageUrl = animeDetail.imageUrl;
      backdropImageUrl = animeDetail.imageUrl; // Bangumi通常只有一个图片，用作背景
    } catch (e) {
      print('获取Bangumi图片信息失败 (animeId: $animeId): $e');
      // 如果Bangumi失败，可以尝试弹弹play
      // 这里暂时留空，后续可以扩展
    }
    
    // 获取文件的修改时间作为添加时间
    DateTime addedTime = latestEpisode.lastWatchTime; // 默认使用观看时间
    try {
      final file = File(latestEpisode.filePath);
      if (file.existsSync()) {
        final stat = file.statSync();
        addedTime = stat.modified;
      }
    } catch (e) {
      print('获取文件修改时间失败: $e');
      // 保留默认值
    }
    
    return LocalAnimeItem(
      animeId: animeId,
      animeName: latestEpisode.animeName.isNotEmpty ? latestEpisode.animeName : '未知动画',
      imageUrl: imageUrl,
      backdropImageUrl: backdropImageUrl,
      addedTime: addedTime,
      latestEpisode: latestEpisode,
    );
  }

  void _navigateToJellyfinDetail(String jellyfinId) {
    JellyfinDetailPage.show(context, jellyfinId).then((result) {
      if (result != null) {
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _navigateToEmbyDetail(String embyId) {
    EmbyDetailPage.show(context, embyId).then((result) {
      if (result != null) {
        // 刷新观看历史
        Provider.of<WatchHistoryProvider>(context, listen: false).refresh();
      }
    });
  }

  void _onWatchHistoryItemTap(WatchHistoryItem item) async {
    // 检查是否为网络URL或流媒体协议URL
    final isNetworkUrl = item.filePath.startsWith('http://') || item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');
    
    bool fileExists = false;
    String filePath = item.filePath;
    String? actualPlayUrl;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
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
          final embyId = item.filePath.replaceFirst('emby://', '');
          final embyService = EmbyService.instance;
          if (embyService.isConnected) {
            actualPlayUrl = embyService.getStreamUrl(embyId);
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
      final videoFile = File(item.filePath);
      fileExists = videoFile.existsSync();
      
      if (!fileExists && Platform.isIOS) {
        String altPath = filePath.startsWith('/private') 
            ? filePath.replaceFirst('/private', '') 
            : '/private$filePath';
        
        final File altFile = File(altPath);
        if (altFile.existsSync()) {
          filePath = altPath;
          item = item.copyWith(filePath: filePath);
          fileExists = true;
        }
      }
    }
    
    if (!fileExists) {
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return;
    }

    final playableItem = PlayableItem(
      videoPath: item.filePath,
      title: item.animeName,
      subtitle: item.episodeTitle,
      animeId: item.animeId,
      episodeId: item.episodeId,
      historyItem: item,
      actualPlayUrl: actualPlayUrl,
    );

    await PlaybackService().play(playableItem);
  }
  
  // 构建导航按钮（参考悬浮按钮样式）
  Widget _buildNavigationButton({
    required IconData icon, 
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  // 构建页面指示器（分离出来避免不必要的重建）
  Widget _buildPageIndicator() {
    return Positioned(
      bottom: 16,
      left: 0,
      // 页面指示器只在左侧PageView区域显示：总宽度的2/3减去间距
      right: (MediaQuery.of(context).size.width - 32) / 3 + 12,
      child: Center(
        child: ValueListenableBuilder<int>(
          valueListenable: _heroBannerIndexNotifier,
          builder: (context, currentIndex, child) {
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index == currentIndex
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
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

// 推荐内容数据模型
class RecommendedItem {
  final String id;
  final String title;
  final String subtitle;
  final String? backgroundImageUrl;
  final String? logoImageUrl;
  final RecommendedItemSource source;
  final double? rating;

  RecommendedItem({
    required this.id,
    required this.title,
    required this.subtitle,
    this.backgroundImageUrl,
    this.logoImageUrl,
    required this.source,
    this.rating,
  });
}

enum RecommendedItemSource {
  jellyfin,
  emby,
  local,
  placeholder,
}

// 本地动画项目数据模型
class LocalAnimeItem {
  final int animeId;
  final String animeName;
  final String? imageUrl;
  final String? backdropImageUrl;
  final DateTime addedTime; // 改为添加时间
  final WatchHistoryItem latestEpisode;

  LocalAnimeItem({
    required this.animeId,
    required this.animeName,
    this.imageUrl,
    this.backdropImageUrl,
    required this.addedTime, // 改为添加时间
    required this.latestEpisode,
  });
}

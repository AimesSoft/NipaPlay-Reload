import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';

class JellyfinProvider extends ChangeNotifier {
  final JellyfinService _jellyfinService = JellyfinService.instance;
  
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  List<JellyfinMediaItem> _mediaItems = [];
  List<JellyfinMovieInfo> _movieItems = [];
  Map<String, JellyfinMediaItemDetail> _mediaDetailsCache = {};
  Map<String, JellyfinMovieInfo> _movieDetailsCache = {};
  Timer? _notifyTimer;
  bool _disposed = false;
  
  // 排序相关状态
  String _currentSortBy = 'DateCreated,SortName';
  String _currentSortOrder = 'Descending';
  
  // 每个媒体库的独立排序设置
  Map<String, Map<String, String>> _librarySpecificSortSettings = {};

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _jellyfinService.isConnected;
  List<JellyfinMediaItem> get mediaItems => _mediaItems;
  List<JellyfinMovieInfo> get movieItems => _movieItems;
  List<JellyfinLibrary> get availableLibraries => _jellyfinService.availableLibraries;
  List<String> get selectedLibraryIds => _jellyfinService.selectedLibraryIds;
  String? get serverUrl => _jellyfinService.serverUrl;
  String? get username => _jellyfinService.username;
  
  // 排序相关getter
  String get currentSortBy => _currentSortBy;
  String get currentSortOrder => _currentSortOrder;
  
  // 获取特定媒体库的排序设置
  Map<String, String> getLibrarySortSettings(String libraryId) {
    return _librarySpecificSortSettings[libraryId] ?? {
      'sortBy': _currentSortBy,
      'sortOrder': _currentSortOrder,
    };
  }
  
  // 设置特定媒体库的排序设置
  void setLibrarySortSettings(String libraryId, String sortBy, String sortOrder) {
    _librarySpecificSortSettings[libraryId] = {
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    };
    print('JellyfinProvider: 为媒体库 $libraryId 设置排序 - sortBy: $sortBy, sortOrder: $sortOrder');
    
    // 保存到SharedPreferences
    _saveSortSettings();
  }
  
  // 保存排序设置到SharedPreferences
  Future<void> _saveSortSettings() async {
    if (kIsWeb) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(_librarySpecificSortSettings);
      await prefs.setString('jellyfin_library_sort_settings', jsonString);
      print('JellyfinProvider: 排序设置已保存');
    } catch (e) {
      print('JellyfinProvider: 保存排序设置失败: $e');
    }
  }
  
  // 加载排序设置
  Future<void> _loadSortSettings() async {
    if (kIsWeb) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final sortSettingsJson = prefs.getString('jellyfin_library_sort_settings');
      if (sortSettingsJson != null) {
        final Map<String, dynamic> decoded = json.decode(sortSettingsJson);
        _librarySpecificSortSettings = decoded.map((key, value) => MapEntry(key, Map<String, String>.from(value)));
        print('JellyfinProvider: 加载了媒体库排序设置: $_librarySpecificSortSettings');
      }
    } catch (e) {
      print('JellyfinProvider: 加载媒体库排序设置失败: $e');
      _librarySpecificSortSettings = {};
    }
  }

  // 将临近多次状态变化合并为一次通知，降低 UI 抖动
  void _notifyCoalesced({Duration delay = const Duration(milliseconds: 800)}) {
    if (_disposed) return;
    _notifyTimer?.cancel();
    _notifyTimer = Timer(delay, () {
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyTimer?.cancel();
    super.dispose();
  }

  // 初始化Jellyfin Provider
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _notifyCoalesced();
    
    try {
      await _jellyfinService.loadSavedSettings();
      await _loadSortSettings(); // 加载排序设置
      _isInitialized = true;
      
      // 添加连接状态监听器
      _jellyfinService.addConnectionStateListener(_onConnectionStateChanged);
      
      print('JellyfinProvider: JellyfinService初始化完成，初始连接状态: ${_jellyfinService.isConnected}');
      print('JellyfinProvider: 连接验证将在后台异步进行');
      
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      _notifyCoalesced();
    }
  }
  
  /// 连接状态变化回调
  void _onConnectionStateChanged(bool isConnected) {
    print('JellyfinProvider: 连接状态变化 - isConnected: $isConnected');
    
    // 连接状态变化需要立即通知UI，不能延迟
    // 这样可以确保媒体库标签页能及时显示/隐藏
    notifyListeners();
    
    if (isConnected) {
      print('JellyfinProvider: Jellyfin已连接，开始加载媒体项目...');
      // 异步加载媒体项目，不阻塞UI
      loadMediaItems();
      loadMovieItems();
    }
  }
  
  // 加载Jellyfin媒体项
  Future<void> loadMediaItems() async {
    if (!_jellyfinService.isConnected) return;
    
    _isLoading = true;
    _hasError = false;
    _notifyCoalesced();
    
    try {
      _mediaItems = await _jellyfinService.getLatestMediaItems(
        sortBy: _currentSortBy,
        sortOrder: _currentSortOrder,
      );
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _mediaItems = [];
    } finally {
      _isLoading = false;
      _notifyCoalesced();
    }
  }
  
  // 加载Jellyfin电影项
  Future<void> loadMovieItems() async {
    if (!_jellyfinService.isConnected) return;
    
    try {
      _movieItems = await _jellyfinService.getLatestMovies();
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _movieItems = [];
    } finally {
      _notifyCoalesced();
    }
  }
  
  // 连接到Jellyfin服务器
  Future<bool> connectToServer(String serverUrl, String username, String password, {String? addressName}) async {
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _notifyCoalesced();
    
    try {
      final success = await _jellyfinService.connect(serverUrl, username, password, addressName: addressName);
      
      if (success) {
        await loadMediaItems();
        await loadMovieItems();
      }
      
      return success;
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      return false;
    } finally {
      _isLoading = false;
      _notifyCoalesced();
    }
  }
  
  // 断开Jellyfin服务器连接
  Future<void> disconnectFromServer() async {
    await _jellyfinService.disconnect();
    _mediaItems = [];
    _movieItems = [];
    _mediaDetailsCache = {};
    _movieDetailsCache = {};
    _notifyCoalesced();
  }
  
  // 更新选中的媒体库
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    await _jellyfinService.updateSelectedLibraries(libraryIds);
    await loadMediaItems();
    await loadMovieItems();
  }
  
  // 获取媒体详情
  Future<JellyfinMediaItemDetail> getMediaItemDetails(String itemId) async {
    // 如果已经缓存了详情，直接返回
    if (_mediaDetailsCache.containsKey(itemId)) {
      return _mediaDetailsCache[itemId]!;
    }
    
    try {
      final details = await _jellyfinService.getMediaItemDetails(itemId);
      _mediaDetailsCache[itemId] = details;
      return details;
    } catch (e) {
      rethrow;
    }
  }
  
  // 获取电影详情
  Future<JellyfinMovieInfo?> getMovieDetails(String movieId) async {
    // 如果已经缓存了详情，直接返回
    if (_movieDetailsCache.containsKey(movieId)) {
      return _movieDetailsCache[movieId]!;
    }
    
    try {
      final details = await _jellyfinService.getMovieDetails(movieId);
      if (details != null) {
        _movieDetailsCache[movieId] = details;
      }
      return details;
    } catch (e) {
      rethrow;
    }
  }
  
  // 将Jellyfin媒体项转换为WatchHistoryItem
  List<WatchHistoryItem> convertToWatchHistoryItems() {
    return _mediaItems.map((item) => item.toWatchHistoryItem()).toList();
  }
  
  // 更新排序设置并重新加载媒体项
  Future<void> updateSortSettings(String sortBy, String sortOrder) async {
    print('JellyfinProvider: 更新排序设置 - sortBy: $sortBy, sortOrder: $sortOrder');
    if (_currentSortBy != sortBy || _currentSortOrder != sortOrder) {
      _currentSortBy = sortBy;
      _currentSortOrder = sortOrder;
      print('JellyfinProvider: 排序设置已更新，开始重新加载媒体项');
      await loadMediaItems();
    } else {
      print('JellyfinProvider: 排序设置未变化，跳过重新加载');
    }
  }
  
  // 只更新排序设置，不重新加载媒体项（用于单个媒体库视图）
  void updateSortSettingsOnly(String sortBy, String sortOrder) {
    print('JellyfinProvider: 仅更新排序设置 - sortBy: $sortBy, sortOrder: $sortOrder');
    if (_currentSortBy != sortBy || _currentSortOrder != sortOrder) {
      _currentSortBy = sortBy;
      _currentSortOrder = sortOrder;
      print('JellyfinProvider: 排序设置已更新，不重新加载媒体项，也不发送通知');
      // 不调用 notifyListeners() 以避免触发其他组件重新加载
    } else {
      print('JellyfinProvider: 排序设置未变化，跳过更新');
    }
  }
  
  // 将Jellyfin电影项转换为WatchHistoryItem
  List<WatchHistoryItem> convertMoviesToWatchHistoryItems() {
    return _movieItems.map((item) => item.toWatchHistoryItem()).toList();
  }
  
  // 获取流媒体URL
  String getStreamUrl(String itemId) {
    return _jellyfinService.getStreamUrl(itemId);
  }
  
  // 获取图片URL
  String getImageUrl(String itemId, {String type = 'Primary', int? width, int? height, int? quality}) {
    return _jellyfinService.getImageUrl(
      itemId,
      type: type,
      width: width,
      height: height,
      quality: quality,
    );
  }
}
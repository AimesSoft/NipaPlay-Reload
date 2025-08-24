import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmbyProvider extends ChangeNotifier {
  final EmbyService _embyService = EmbyService.instance;
  
  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  List<EmbyMediaItem> _mediaItems = [];
  List<EmbyMovieInfo> _movieItems = [];
  Map<String, EmbyMediaItemDetail> _mediaDetailsCache = {};
  Map<String, EmbyMovieInfo> _movieDetailsCache = {};
  Timer? _notifyTimer;
  bool _disposed = false;
  
  // 排序相关状态
  String _currentSortBy = 'DateCreated';
  String _currentSortOrder = 'Descending';
  
  // 每个媒体库的独立排序设置
  Map<String, Map<String, String>> _librarySpecificSortSettings = {};

  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isConnected => _embyService.isConnected;
  List<EmbyMediaItem> get mediaItems => _mediaItems;
  List<EmbyMovieInfo> get movieItems => _movieItems;
  List<EmbyLibrary> get availableLibraries => _embyService.availableLibraries;
  List<String> get selectedLibraryIds => _embyService.selectedLibraryIds;
  String? get serverUrl => _embyService.serverUrl;
  String? get username => _embyService.username;
  
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
    // 保存到SharedPreferences
    _saveSortSettings();
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

  // 初始化Emby Provider
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('EmbyProvider: 开始初始化...');
    
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _notifyCoalesced();
    
    try {
      print('EmbyProvider: 调用EmbyService.loadSavedSettings()...');
  await _embyService.loadSavedSettings();
  await _loadSortSettings(); // 加载排序设置
      _isInitialized = true;
      
      print('EmbyProvider: EmbyService初始化完成，初始连接状态: ${_embyService.isConnected}');
      
      // 添加连接状态监听器
      _embyService.addConnectionStateListener(_onConnectionStateChanged);
      
      // 由于连接验证现在是异步的，我们不再等待它完成
      // 如果连接验证成功，会在后续的异步操作中自动加载媒体项目
      print('EmbyProvider: 连接验证将在后台异步进行');
      
    } catch (e) {
      print('EmbyProvider: 初始化过程中发生异常: $e');
      _hasError = true;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      _notifyCoalesced();
      print('EmbyProvider: 初始化完成');
    }
  }
  
  /// 连接状态变化回调
  void _onConnectionStateChanged(bool isConnected) {
    print('EmbyProvider: 连接状态变化 - isConnected: $isConnected');
    
    // 连接状态变化需要立即通知UI，不能延迟
    // 这样可以确保媒体库标签页能及时显示/隐藏
    notifyListeners();
    
    if (isConnected) {
      print('EmbyProvider: Emby已连接，开始加载媒体项目...');
      // 异步加载媒体项目，不阻塞UI
      loadMediaItems();
      loadMovieItems();
    }
  }
  
  // 加载Emby媒体项
  Future<void> loadMediaItems() async {
    if (!_embyService.isConnected) return;
    
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _notifyCoalesced();
    
    try {
      _mediaItems = await _embyService.getLatestMediaItems(
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
  
  // 加载Emby电影项
  Future<void> loadMovieItems() async {
    if (!_embyService.isConnected) return;
    
    try {
      _movieItems = await _embyService.getLatestMovies();
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _movieItems = [];
    } finally {
      _notifyCoalesced();
    }
  }
  
  // 连接到Emby服务器
  Future<bool> connectToServer(String serverUrl, String username, String password) async {
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    _notifyCoalesced();
    
    try {
      final success = await _embyService.connect(serverUrl, username, password);
      
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
  
  // 断开Emby服务器连接
  Future<void> disconnectFromServer() async {
    await _embyService.disconnect();
    _mediaItems = [];
    _movieItems = [];
    _mediaDetailsCache = {};
    _movieDetailsCache = {};
    _notifyCoalesced();
  }
  
  // 更新选中的媒体库
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    await _embyService.updateSelectedLibraries(libraryIds);
    await loadMediaItems();
    await loadMovieItems();
  }
  
  // 获取媒体详情
  Future<EmbyMediaItemDetail> getMediaItemDetails(String itemId) async {
    // 如果已经缓存了详情，直接返回
    if (_mediaDetailsCache.containsKey(itemId)) {
      return _mediaDetailsCache[itemId]!;
    }
    
    try {
      final details = await _embyService.getMediaItemDetails(itemId);
      _mediaDetailsCache[itemId] = details;
      return details;
    } catch (e) {
      rethrow;
    }
  }
  
  // 获取电影详情
  Future<EmbyMovieInfo?> getMovieDetails(String movieId) async {
    // 如果已经缓存了详情，直接返回
    if (_movieDetailsCache.containsKey(movieId)) {
      return _movieDetailsCache[movieId]!;
    }
    
    try {
      final details = await _embyService.getMovieDetails(movieId);
      if (details != null) {
        _movieDetailsCache[movieId] = details;
      }
      return details;
    } catch (e) {
      rethrow;
    }
  }
  
  // 将Emby媒体项转换为WatchHistoryItem
  List<WatchHistoryItem> convertToWatchHistoryItems() {
    return _mediaItems.map((item) => item.toWatchHistoryItem()).toList();
  }
  
  // 将Emby电影项转换为WatchHistoryItem
  List<WatchHistoryItem> convertMoviesToWatchHistoryItems() {
    return _movieItems.map((item) => item.toWatchHistoryItem()).toList();
  }
  
  // 更新排序设置并重新加载媒体项
  Future<void> updateSortSettings(String sortBy, String sortOrder) async {
    print('EmbyProvider: 更新排序设置 - sortBy: $sortBy, sortOrder: $sortOrder');
    if (_currentSortBy != sortBy || _currentSortOrder != sortOrder) {
      _currentSortBy = sortBy;
      _currentSortOrder = sortOrder;
      print('EmbyProvider: 排序设置已更新，开始重新加载媒体项');
      await loadMediaItems();
    } else {
      print('EmbyProvider: 排序设置未变化，跳过重新加载');
    }
  }
  
  // 只更新排序设置，不触发媒体重新加载（用于库内容页的外部控制）
  void updateSortSettingsOnly(String sortBy, String sortOrder) {
    print('EmbyProvider: 仅更新排序设置 - sortBy: $sortBy, sortOrder: $sortOrder');
    if (_currentSortBy != sortBy || _currentSortOrder != sortOrder) {
      _currentSortBy = sortBy;
      _currentSortOrder = sortOrder;
      // 不调用 notifyListeners() 以避免触发其他组件重新加载
    } else {
      print('EmbyProvider: 排序设置未变化，跳过更新');
    }
  }
  
  // 获取流媒体URL
  String getStreamUrl(String itemId) {
    return _embyService.getStreamUrl(itemId);
  }
  
  // 获取图片URL
  String getImageUrl(String itemId, {String type = 'Primary', int? width, int? height, int? quality}) {
    return _embyService.getImageUrl(
      itemId,
      type: type,
      width: width,
      height: height,
      quality: quality,
    );
  }

  // 保存排序设置到SharedPreferences
  Future<void> _saveSortSettings() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(_librarySpecificSortSettings);
      await prefs.setString('emby_library_sort_settings', jsonString);
      print('EmbyProvider: 排序设置已保存');
    } catch (e) {
      print('EmbyProvider: 保存排序设置失败: $e');
    }
  }

  // 加载排序设置
  Future<void> _loadSortSettings() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final sortSettingsJson = prefs.getString('emby_library_sort_settings');
      if (sortSettingsJson != null) {
        final Map<String, dynamic> decoded = json.decode(sortSettingsJson);
        _librarySpecificSortSettings = decoded.map((key, value) =>
            MapEntry(key, Map<String, String>.from(value)));
        print('EmbyProvider: 加载了媒体库排序设置: $_librarySpecificSortSettings');
      }
    } catch (e) {
      print('EmbyProvider: 加载媒体库排序设置失败: $e');
      _librarySpecificSortSettings = {};
    }
  }
}

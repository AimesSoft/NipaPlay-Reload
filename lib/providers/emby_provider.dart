import 'package:flutter/foundation.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/models/watch_history_model.dart';

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

  // 初始化Emby Provider
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    print('EmbyProvider: 开始初始化...');
    
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
    
    try {
      print('EmbyProvider: 调用EmbyService.loadSavedSettings()...');
      await _embyService.loadSavedSettings();
      _isInitialized = true;
      
      print('EmbyProvider: EmbyService初始化完成，连接状态: ${_embyService.isConnected}');
      
      if (_embyService.isConnected) {
        print('EmbyProvider: Emby已连接，正在加载媒体项目...');
        await loadMediaItems();
        await loadMovieItems();
        print('EmbyProvider: 媒体项目加载完成，数量: ${_mediaItems.length}');
      } else {
        print('EmbyProvider: Emby未连接，跳过媒体项目加载');
      }
    } catch (e) {
      print('EmbyProvider: 初始化过程中发生异常: $e');
      _hasError = true;
      _errorMessage = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
      print('EmbyProvider: 初始化完成，最终连接状态: ${_embyService.isConnected}');
    }
  }
  
  // 加载Emby媒体项
  Future<void> loadMediaItems() async {
    if (!_embyService.isConnected) return;
    
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
    
    try {
      _mediaItems = await _embyService.getLatestMediaItems();
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _mediaItems = [];
    } finally {
      _isLoading = false;
      notifyListeners();
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
    }
  }
  
  // 连接到Emby服务器
  Future<bool> connectToServer(String serverUrl, String username, String password) async {
    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
    
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
      notifyListeners();
    }
  }
  
  // 断开Emby服务器连接
  Future<void> disconnectFromServer() async {
    await _embyService.disconnect();
    _mediaItems = [];
    _movieItems = [];
    _mediaDetailsCache = {};
    _movieDetailsCache = {};
    notifyListeners();
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
}

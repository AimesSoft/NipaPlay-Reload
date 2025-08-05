import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class JellyfinService {
  static final JellyfinService instance = JellyfinService._internal();
  
  JellyfinService._internal();
  
  String? _serverUrl;
  String? _username;
  String? _password;
  String? _accessToken;
  String? _userId;
  bool _isConnected = false;
  List<JellyfinLibrary> _availableLibraries = [];
  List<String> _selectedLibraryIds = [];

  // Client information cache
  String? _cachedClientInfo;

  // Get dynamic client information
  Future<String> _getClientInfo() async {
    if (_cachedClientInfo != null) {
      return _cachedClientInfo!;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final appName = packageInfo.appName.isNotEmpty ? packageInfo.appName : 'NipaPlay';
      final version = packageInfo.version.isNotEmpty ? packageInfo.version : '1.4.9';
      
      String platform = 'Flutter';
      if (!kIsWeb && !kDebugMode) {
        try {
          platform = Platform.operatingSystem;
          // Capitalize first letter
          platform = platform[0].toUpperCase() + platform.substring(1);
        } catch (e) {
          platform = 'Flutter';
        }
      }

      _cachedClientInfo = 'MediaBrowser Client="$appName", Device="$platform", DeviceId="$appName-$platform", Version="$version"';
      return _cachedClientInfo!;
    } catch (e) {
      // Fallback to static values
      _cachedClientInfo = 'MediaBrowser Client="NipaPlay", Device="Flutter", DeviceId="NipaPlay-Flutter", Version="1.4.9"';
      return _cachedClientInfo!;
    }
  }

  // Getters
  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  String? get accessToken => _accessToken;
  String? get userId => _userId;
  List<JellyfinLibrary> get availableLibraries => _availableLibraries;
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  
  Future<void> loadSavedSettings() async {
    if (kIsWeb) {
      _isConnected = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    
    _serverUrl = prefs.getString('jellyfin_server_url');
    _username = prefs.getString('jellyfin_username');
    _accessToken = prefs.getString('jellyfin_access_token');
    _userId = prefs.getString('jellyfin_user_id');
    _selectedLibraryIds = prefs.getStringList('jellyfin_selected_libraries') ?? [];
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      // 异步验证连接，不阻塞初始化流程
      _validateConnectionAsync();
    } else {
      _isConnected = false;
    }
  }
  
  /// 异步验证连接状态，不阻塞主流程
  Future<void> _validateConnectionAsync() async {
    try {
      print('Jellyfin: 开始异步验证保存的连接信息...');
      // 尝试验证保存的令牌是否仍然有效，设置5秒超时
      final response = await _makeAuthenticatedRequest('/System/Info')
          .timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      
      print('Jellyfin: 令牌验证结果 - HTTP ${response.statusCode}, 连接状态: $_isConnected');
      
      if (_isConnected) {
        print('Jellyfin: 连接验证成功，正在加载媒体库...');
        // 加载可用媒体库
        await loadAvailableLibraries();
        print('Jellyfin: 媒体库加载完成，可用库数量: ${_availableLibraries.length}');
        // 通知连接状态变化
        _notifyConnectionStateChanged();
      } else {
        print('Jellyfin: 连接验证失败 - HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Jellyfin: 连接验证过程中发生异常: $e');
      _isConnected = false;
    }
  }
  
  // 连接状态变化回调列表
  final List<Function(bool)> _connectionStateCallbacks = [];
  
  /// 添加连接状态变化监听器
  void addConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.add(callback);
  }
  
  /// 移除连接状态变化监听器
  void removeConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.remove(callback);
  }
  
  /// 通知连接状态变化
  void _notifyConnectionStateChanged() {
    for (final callback in _connectionStateCallbacks) {
      try {
        callback(_isConnected);
      } catch (e) {
        print('Jellyfin: 连接状态回调执行失败: $e');
      }
    }
  }
  
  Future<bool> connect(String serverUrl, String username, String password) async {
    // 确保URL格式正确
    if (!serverUrl.startsWith('http://') && !serverUrl.startsWith('https://')) {
      serverUrl = 'http://$serverUrl';
    }
    
    // 移除末尾的斜杠
    if (serverUrl.endsWith('/')) {
      serverUrl = serverUrl.substring(0, serverUrl.length - 1);
    }
    
    _serverUrl = serverUrl;
    _username = username;
    _password = password;
    
    try {
      // 获取客户端配置
      final configResponse = await http.get(
        Uri.parse('$_serverUrl/System/Info/Public'),
      );
      
      if (configResponse.statusCode != 200) {
        throw Exception('服务器返回错误: ${configResponse.statusCode} ${configResponse.reasonPhrase ?? ''}\n${configResponse.body}');
      }
      
      // 认证用户
      final clientInfo = await _getClientInfo();
      final authResponse = await http.post(
        Uri.parse('$_serverUrl/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization': clientInfo,
        },
        body: json.encode({
          'Username': username,
          'Pw': password,
        }),
      );
      
      if (authResponse.statusCode != 200) {
        throw Exception('服务器返回错误: ${authResponse.statusCode} ${authResponse.reasonPhrase ?? ''}\n${authResponse.body}');
      }
      
      final authData = json.decode(authResponse.body);
      _accessToken = authData['AccessToken'];
      _userId = authData['User']['Id'];
      
      // 保存设置到SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('jellyfin_server_url', _serverUrl!);
      await prefs.setString('jellyfin_username', _username!);
      await prefs.setString('jellyfin_access_token', _accessToken!);
      await prefs.setString('jellyfin_user_id', _userId!);
      
      _isConnected = true;
      
      // 获取可用的媒体库列表
      if (!kIsWeb) {
        await loadAvailableLibraries();
      }
      
      return true;
    } catch (e) {
      _isConnected = false;
      // 直接抛出异常，Provider会捕获并展示message
      throw Exception('连接Jellyfin服务器失败: $e');
    }
  }
  
  Future<void> disconnect() async {
    _isConnected = false;
    _serverUrl = null;
    _username = null;
    _password = null;
    _accessToken = null;
    _userId = null;
    _availableLibraries = [];
    _selectedLibraryIds = [];
    
    // 清除保存的设置
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jellyfin_server_url');
    await prefs.remove('jellyfin_username');
    await prefs.remove('jellyfin_access_token');
    await prefs.remove('jellyfin_user_id');
    await prefs.remove('jellyfin_selected_libraries');
  }
  
  Future<void> loadAvailableLibraries() async {
    if (kIsWeb || !_isConnected || _userId == null) return;

    try {
      final response = await _makeAuthenticatedRequest('/UserViews?userId=$_userId');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        List<JellyfinLibrary> tempLibraries = [];
        for (var item in items) {
          if (item['CollectionType'] == 'tvshows' || item['CollectionType'] == 'movies') {
            final String libraryId = item['Id'];
            final String collectionType = item['CollectionType'];
            
            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
            
            final countResponse = await _makeAuthenticatedRequest(
                '/Items?parentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&Limit=0&Fields=ParentId');
            
            int itemCount = 0;
            if (countResponse.statusCode == 200) {
              final countData = json.decode(countResponse.body);
              itemCount = countData['TotalRecordCount'] ?? 0;
            }
            
            tempLibraries.add(JellyfinLibrary(
              id: item['Id'],
              name: item['Name'],
              type: item['CollectionType'], // Assuming 'CollectionType' maps to 'type'
              imageTagsPrimary: item['ImageTags']?['Primary'], // Safely access ImageTags
              totalItems: itemCount, 
            ));
          }
        }
        _availableLibraries = tempLibraries;
      }
    } catch (e) {
      print('Error loading available libraries: $e');
    }
  }
  
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    _selectedLibraryIds = libraryIds;
    
    // 保存选择的媒体库到SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('jellyfin_selected_libraries', _selectedLibraryIds);
  }
  
  Future<List<JellyfinMediaItem>> getLatestMediaItems({
    int limit = 99999,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty) {
      return [];
    }
    
    // 默认排序参数
    final defaultSortBy = sortBy ?? 'DateCreated,SortName';
    final defaultSortOrder = sortOrder ?? 'Descending';
    
    print('JellyfinService: 获取媒体项 - sortBy: $defaultSortBy, sortOrder: $defaultSortOrder');
    
    List<JellyfinMediaItem> allItems = [];
    
    // 从每个选中的媒体库获取最新内容
    for (String libraryId in _selectedLibraryIds) {
      try {
        // 首先获取媒体库信息以确定类型
        final libraryResponse = await _makeAuthenticatedRequest(
          '/Users/$_userId/Items/$libraryId'
        );
        
        if (libraryResponse.statusCode == 200) {
          final libraryData = json.decode(libraryResponse.body);
          final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
          
          // 根据媒体库类型选择不同的IncludeItemTypes
          String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
          
          final response = await _makeAuthenticatedRequest(
            '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&userId=$_userId'
          );
          
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final List<dynamic> items = data['Items'];
            
            List<JellyfinMediaItem> libraryItems = items
                .map((item) => JellyfinMediaItem.fromJson(item))
                .toList();
            
            allItems.addAll(libraryItems);
          }
        }
      } catch (e, stackTrace) {
        // Log the error and stack trace for debugging purposes
        print('Error processing library $libraryId: $e');
        print('Stack trace: $stackTrace');
      }
    }
    
    // 如果服务器端排序失败或需要客户端排序，则进行本地排序
    // 注意：当使用自定义排序时，我们依赖服务器端的排序结果
    if (sortBy == null && sortOrder == null) {
      // 默认情况下按最近添加日期排序
      allItems.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    }
    
    // 限制总数
    if (allItems.length > limit) {
      allItems = allItems.sublist(0, limit);
    }
    
    return allItems;
  }
  
  // 获取最新电影列表
  Future<List<JellyfinMovieInfo>> getLatestMovies({int limit = 99999}) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty) {
      return [];
    }
    
    List<JellyfinMovieInfo> allMovies = [];
    
    // 从每个选中的媒体库获取最新电影
    for (String libraryId in _selectedLibraryIds) {
      try {
        final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit&userId=$_userId'
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];
          
          List<JellyfinMovieInfo> libraryMovies = items
              .map((item) => JellyfinMovieInfo.fromJson(item))
              .toList();
          
          allMovies.addAll(libraryMovies);
        }
      } catch (e) {
        // Log the error for debugging purposes
        print('Error fetching movies for library $libraryId: $e');
      }
    }
    
    // 按最近添加日期排序
    allMovies.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    
    // 限制总数
    if (allMovies.length > limit) {
      allMovies = allMovies.sublist(0, limit);
    }
    
    return allMovies;
  }
  
  // 获取电影详情
  Future<JellyfinMovieInfo?> getMovieDetails(String movieId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$movieId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return JellyfinMovieInfo.fromJson(data);
      }
    } catch (e) {
      throw Exception('无法获取电影详情: $e');
    }
    
    return null;
  }
  
  Future<JellyfinMediaItemDetail> getMediaItemDetails(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Users/$_userId/Items/$itemId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return JellyfinMediaItemDetail.fromJson(data);
    } else {
      throw Exception('无法获取媒体详情');
    }
  }
  
  Future<List<JellyfinSeasonInfo>> getSeriesSeasons(String seriesId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Shows/$seriesId/Seasons?userId=$_userId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];
      
      List<JellyfinSeasonInfo> seasons = items
          .map((item) => JellyfinSeasonInfo.fromJson(item))
          .toList();
      
      // 按季节编号排序
      seasons.sort((a, b) => a.indexNumber?.compareTo(b.indexNumber ?? 0) ?? 0);
      
      return seasons;
    } else {
      throw Exception('无法获取剧集季信息');
    }
  }
  
  Future<List<JellyfinEpisodeInfo>> getSeasonEpisodes(String seriesId, String seasonId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/Shows/$seriesId/Episodes?userId=$_userId&seasonId=$seasonId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];
      
      List<JellyfinEpisodeInfo> episodes = items
          .map((item) => JellyfinEpisodeInfo.fromJson(item))
          .toList();
      
      // 按剧集编号排序
      episodes.sort((a, b) => a.indexNumber?.compareTo(b.indexNumber ?? 0) ?? 0);
      
      return episodes;
    } else {
      throw Exception('无法获取季节剧集信息');
    }
  }
  
  // 获取单个剧集的详细信息
  Future<JellyfinEpisodeInfo?> getEpisodeDetails(String episodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$episodeId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return JellyfinEpisodeInfo.fromJson(data);
      }
    } catch (e) {
      throw Exception('无法获取剧集详情: $e');
    }
    
    return null;
  }
  
  // 获取媒体源信息（包含文件名、大小等信息）
  Future<Map<String, dynamic>> getMediaInfo(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      // 首先尝试使用File接口获取详细信息
      final response = await _makeAuthenticatedRequest(
        '/Items/$itemId/File'
      );
      
      final contentType = response.headers['content-type'];
      bool isJsonResponse = contentType != null && (contentType.contains('application/json') || contentType.contains('text/json'));
      
      if (response.statusCode == 200 && isJsonResponse) {
        final data = json.decode(response.body);
        debugPrint('媒体文件信息API响应 (JSON): $data');
        
        final fileName = data['Name'] ?? '';
        final fileSize = data['Size'] ?? 0;
        
        // 确保获取到有效数据
        if (fileName.isNotEmpty || fileSize > 0) {
          debugPrint('成功获取到媒体文件信息: 文件名=$fileName, 大小=$fileSize');
          return {
            'fileName': fileName,
            'path': data['Path'] ?? '',
            'size': fileSize,
            'dateCreated': data['DateCreated'] ?? '',
            'dateModified': data['DateModified'] ?? ''
          };
        }
      } else if (response.statusCode == 200 && !isJsonResponse) {
        debugPrint('媒体文件信息API响应 (non-JSON, status 200): Content-Type: $contentType. 将回退。');
        // 表明端点返回了文件本身，而不是元数据。
        // 无法从此获取文件名/文件大小，因此我们将继续回退。
      } else if (response.statusCode != 200) {
        debugPrint('媒体文件信息API请求失败: HTTP ${response.statusCode}. 将回退。');
      }
      // 如果File接口无法获取有效信息，尝试使用普通的Items接口
      final itemResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$itemId'
      );
      
      if (itemResponse.statusCode == 200) {
        final itemData = json.decode(itemResponse.body);
        debugPrint('媒体项目API响应获取到部分信息');
        
        String fileName = '';
        if (itemData['Name'] != null) {
          fileName = itemData['Name'];
          // 添加合适的文件扩展名
          if (!fileName.toLowerCase().endsWith('.mp4') && 
              !fileName.toLowerCase().endsWith('.mkv') &&
              !fileName.toLowerCase().endsWith('.avi')) {
            fileName += '.mp4';
          }
        }
        
        // 尝试从MediaSource获取文件大小
        int fileSize = 0;
        if (itemData['MediaSources'] != null && 
            itemData['MediaSources'] is List && 
            itemData['MediaSources'].isNotEmpty) {
          final mediaSource = itemData['MediaSources'][0];
          fileSize = mediaSource['Size'] ?? 0;
        }
        
        debugPrint('通过备选方法获取到媒体信息: 文件名=$fileName, 大小=$fileSize');
        return {
          'fileName': fileName,
          'path': itemData['Path'] ?? '',
          'size': fileSize,
          'dateCreated': itemData['DateCreated'] ?? '',
          'dateModified': itemData['DateModified'] ?? ''
        };
      }
      
      debugPrint('获取媒体信息失败: HTTP ${response.statusCode}');
      return {};
    } catch (e) {
      debugPrint('获取媒体信息错误: $e');
      return {};
    }
  }
  
  /// 获取相邻剧集（使用Jellyfin的adjacentTo参数作为简单的上下集导航）
  /// 返回当前剧集前后各一集的剧集列表，不依赖弹幕映射
  Future<List<JellyfinEpisodeInfo>> getAdjacentEpisodes(String currentEpisodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    try {
      // 使用adjacentTo参数获取相邻剧集，限制3个结果（上一集、当前集、下一集）
      final response = await _makeAuthenticatedRequest(
        '/Items?adjacentTo=$currentEpisodeId&limit=3&fields=Overview,MediaSources'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];
        
        final episodes = items
            .map((item) => JellyfinEpisodeInfo.fromJson(item))
            .toList();
        
        // 按集数排序确保顺序正确
        episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
        
        debugPrint('[JellyfinService] 获取到${episodes.length}个相邻剧集');
        return episodes;
      } else {
        debugPrint('[JellyfinService] 获取相邻剧集失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[JellyfinService] 获取相邻剧集出错: $e');
      return [];
    }
  }
  
  /// 简单获取下一集（不依赖弹幕映射）
  Future<JellyfinEpisodeInfo?> getNextEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex != -1 && currentIndex < adjacentEpisodes.length - 1) {
      final nextEpisode = adjacentEpisodes[currentIndex + 1];
      debugPrint('[JellyfinService] 找到下一集: ${nextEpisode.name}');
      return nextEpisode;
    }
    
    debugPrint('[JellyfinService] 没有找到下一集');
    return null;
  }
  
  /// 简单获取上一集（不依赖弹幕映射）
  Future<JellyfinEpisodeInfo?> getPreviousEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex > 0) {
      final previousEpisode = adjacentEpisodes[currentIndex - 1];
      debugPrint('[JellyfinService] 找到上一集: ${previousEpisode.name}');
      return previousEpisode;
    }
    
    debugPrint('[JellyfinService] 没有找到上一集');
    return null;
  }

  // 获取流媒体URL
  String getStreamUrl(String itemId) {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    return '$_serverUrl/Videos/$itemId/stream?static=true&MediaSourceId=$itemId&api_key=$_accessToken';
  }

  /// 获取Jellyfin视频的字幕轨道信息
  /// 包括内嵌字幕和外挂字幕
  Future<List<Map<String, dynamic>>> getSubtitleTracks(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 获取播放信息，包含媒体源和字幕轨道
      final response = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId'
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mediaSources = data['MediaSources'] as List?;
        
        if (mediaSources == null || mediaSources.isEmpty) {
          debugPrint('JellyfinService: 未找到媒体源信息');
          return [];
        }

        final mediaSource = mediaSources[0];
        final mediaStreams = mediaSource['MediaStreams'] as List?;
        
        if (mediaStreams == null) {
          debugPrint('JellyfinService: 未找到媒体流信息');
          return [];
        }

        List<Map<String, dynamic>> subtitleTracks = [];
        
        for (int i = 0; i < mediaStreams.length; i++) {
          final stream = mediaStreams[i];
          final streamType = stream['Type'];
          
          if (streamType == 'Subtitle') {
            final isExternal = stream['IsExternal'] ?? false;
            final deliveryMethod = stream['DeliveryMethod'];
            final language = stream['Language'] ?? '';
            final title = stream['Title'] ?? '';
            final codec = stream['Codec'] ?? '';
            final isDefault = stream['IsDefault'] ?? false;
            final isForced = stream['IsForced'] ?? false;
            final isHearingImpaired = stream['IsHearingImpaired'] ?? false;
            
            // 构建字幕轨道信息
            Map<String, dynamic> trackInfo = {
              'index': i,
              'type': isExternal ? 'external' : 'embedded',
              'language': language,
              'title': title.isNotEmpty ? title : (language.isNotEmpty ? language : 'Unknown'),
              'codec': codec,
              'isDefault': isDefault,
              'isForced': isForced,
              'isHearingImpaired': isHearingImpaired,
              'deliveryMethod': deliveryMethod,
            };

            // 如果是外挂字幕，添加下载URL
            if (isExternal) {
              final mediaSourceId = mediaSource['Id'];
              final subtitleUrl = '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$i/Stream.$codec?api_key=$_accessToken';
              trackInfo['downloadUrl'] = subtitleUrl;
            }

            subtitleTracks.add(trackInfo);
            debugPrint('JellyfinService: 找到字幕轨道 $i: ${trackInfo['title']} (${trackInfo['type']})');
          }
        }

        debugPrint('JellyfinService: 总共找到 ${subtitleTracks.length} 个字幕轨道');
        return subtitleTracks;
      } else {
        debugPrint('JellyfinService: 获取播放信息失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('JellyfinService: 获取字幕轨道信息失败: $e');
      return [];
    }
  }

  /// 下载外挂字幕文件
  Future<String?> downloadSubtitleFile(String itemId, int subtitleIndex, String format) async {
    if (kIsWeb) return null;
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 获取媒体源ID
      final playbackInfoResponse = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId'
      );

      if (playbackInfoResponse.statusCode != 200) {
        debugPrint('JellyfinService: 获取播放信息失败，无法下载字幕');
        return null;
      }

      final playbackData = json.decode(playbackInfoResponse.body);
      final mediaSources = playbackData['MediaSources'] as List?;
      
      if (mediaSources == null || mediaSources.isEmpty) {
        debugPrint('JellyfinService: 未找到媒体源信息');
        return null;
      }

      final mediaSourceId = mediaSources[0]['Id'];
      
      // 构建字幕下载URL
      final subtitleUrl = '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format?api_key=$_accessToken';
      
      debugPrint('JellyfinService: 下载字幕文件: $subtitleUrl');
      
      // 下载字幕文件
      final subtitleResponse = await http.get(Uri.parse(subtitleUrl));
      
      if (subtitleResponse.statusCode == 200) {
        // 保存到临时文件
        final tempDir = await getTemporaryDirectory();
        final fileName = 'jellyfin_subtitle_${itemId}_$subtitleIndex.$format';
        final filePath = '${tempDir.path}/$fileName';
        
        final file = File(filePath);
        await file.writeAsBytes(subtitleResponse.bodyBytes);
        
        debugPrint('JellyfinService: 字幕文件已保存到: $filePath');
        return filePath;
      } else {
        debugPrint('JellyfinService: 下载字幕文件失败: HTTP ${subtitleResponse.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('JellyfinService: 下载字幕文件时出错: $e');
      return null;
    }
  }
  
  // 获取图片URL
  String getImageUrl(String itemId, {String type = 'Primary', int? width, int? height, int? quality}) {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    String url = '$_serverUrl/Items/$itemId/Images/$type';
    List<String> params = [];
    
    if (width != null) params.add('width=$width');
    if (height != null) params.add('height=$height');
    if (quality != null) params.add('quality=$quality');
    
    if (params.isNotEmpty) {
      url += '?${params.join('&')}';
    }
    
    return url;
  }
  
  // 辅助方法：发送经过身份验证的HTTP请求
  Future<http.Response> _makeAuthenticatedRequest(String endpoint, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_serverUrl == null || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final Uri uri = Uri.parse('$_serverUrl$endpoint');
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final Map<String, String> headers = {
      'X-Emby-Authorization': authHeader,
    };
    
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    
    // 设置默认超时时间为10秒
    final requestTimeout = timeout ?? const Duration(seconds: 10);
    
    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await http.get(uri, headers: headers).timeout(requestTimeout);
          break;
        case 'POST':
          response = await http.post(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers, body: body != null ? json.encode(body) : null).timeout(requestTimeout);
          break;
        case 'DELETE':
          response = await http.delete(uri, headers: headers).timeout(requestTimeout);
          break;
        default:
          throw Exception('不支持的HTTP方法: $method');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('请求Jellyfin服务器超时: ${e.message}');
      }
      throw Exception('请求Jellyfin服务器失败: $e');
    }
    if (response.statusCode >= 400) {
      // 详细抛出服务器错误，包括403/401/500等
      throw Exception('服务器返回错误: ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    }
    return response;
  }
}

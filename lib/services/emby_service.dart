import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';

class EmbyService {
  static final EmbyService instance = EmbyService._internal();
  
  EmbyService._internal();
  
  String? _serverUrl;
  String? _username;
  String? _password;
  String? _accessToken;
  String? _userId;
  bool _isConnected = false;
  List<EmbyLibrary> _availableLibraries = [];
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
  List<EmbyLibrary> get availableLibraries => _availableLibraries;
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  
  Future<void> loadSavedSettings() async {
    if (kIsWeb) {
      _isConnected = false;
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    
    _serverUrl = prefs.getString('emby_server_url');
    _username = prefs.getString('emby_username');
    _accessToken = prefs.getString('emby_access_token');
    _userId = prefs.getString('emby_user_id');
    _selectedLibraryIds = prefs.getStringList('emby_selected_libraries') ?? [];
    
    print('Emby loadSavedSettings: serverUrl=$_serverUrl, username=$_username, hasToken=${_accessToken != null}, userId=$_userId');
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      // 异步验证连接，不阻塞初始化流程
      _validateConnectionAsync();
    } else {
      print('Emby: 缺少必要的连接信息，跳过自动连接');
      _isConnected = false;
    }
  }
  
  /// 异步验证连接状态，不阻塞主流程
  Future<void> _validateConnectionAsync() async {
    try {
      print('Emby: 开始异步验证保存的连接信息...');
      // 尝试验证保存的令牌是否仍然有效，设置5秒超时
      final response = await _makeAuthenticatedRequest('/emby/System/Info')
          .timeout(const Duration(seconds: 5));
      _isConnected = response.statusCode == 200;
      
      print('Emby: 令牌验证结果 - HTTP ${response.statusCode}, 连接状态: $_isConnected');
      
      if (_isConnected) {
        print('Emby: 连接验证成功，正在加载媒体库...');
        // 加载可用媒体库
        await loadAvailableLibraries();
        print('Emby: 媒体库加载完成，可用库数量: ${_availableLibraries.length}');
        // 通知连接状态变化
        _notifyConnectionStateChanged();
      } else {
        print('Emby: 连接验证失败 - HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Emby: 连接验证过程中发生异常: $e');
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
        print('Emby: 连接状态回调执行失败: $e');
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
        Uri.parse('$_serverUrl/emby/System/Info/Public'),
      );
      
      if (configResponse.statusCode != 200) {
        throw Exception('服务器返回错误: ${configResponse.statusCode} ${configResponse.reasonPhrase ?? ''}\n${configResponse.body}');
      }
      
      // 认证用户
      final clientInfo = await _getClientInfo();
      final authResponse = await http.post(
        Uri.parse('$_serverUrl/emby/Users/AuthenticateByName'),
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
      
      _isConnected = true;
      
      // 保存连接信息
      await _saveConnectionInfo();
      print('Emby: 连接信息已保存到SharedPreferences');
      
      // 加载可用媒体库
      await loadAvailableLibraries();
      
      return true;
    } catch (e) {
      print('Emby 连接失败: $e');
      _isConnected = false;
      throw Exception('连接Emby服务器失败: $e');
    }
  }
  
  Future<void> _saveConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('emby_server_url', _serverUrl!);
    await prefs.setString('emby_username', _username!);
    await prefs.setString('emby_access_token', _accessToken!);
    await prefs.setString('emby_user_id', _userId!);
    
    print('Emby: 连接信息已保存 - URL: $_serverUrl, 用户: $_username, Token: ${_accessToken?.substring(0, 8)}..., UserID: $_userId');
  }
  
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('emby_server_url');
    await prefs.remove('emby_username');
    await prefs.remove('emby_access_token');
    await prefs.remove('emby_user_id');
    await prefs.remove('emby_selected_libraries');
    
    _serverUrl = null;
    _username = null;
    _password = null;
    _accessToken = null;
    _userId = null;
    _isConnected = false;
    _availableLibraries = [];
    _selectedLibraryIds = [];
  }
  
  Future<http.Response> _makeAuthenticatedRequest(String path, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    final uri = Uri.parse('$_serverUrl$path');
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': authHeader,
    };
    
    // 设置默认超时时间为10秒
    final requestTimeout = timeout ?? const Duration(seconds: 10);
    
    http.Response response;
    try {
      switch (method.toUpperCase()) {
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
          throw Exception('不支持的 HTTP 方法: $method');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('请求Emby服务器超时: ${e.message}');
      }
      throw Exception('请求Emby服务器失败: $e');
    }
    if (response.statusCode >= 400) {
      throw Exception('服务器返回错误: ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    }
    return response;
  }
  
  // 专门用于需要验证连接状态的请求方法
  Future<http.Response> _makeVerifiedAuthenticatedRequest(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    return _makeAuthenticatedRequest(path, method: method, body: body);
  }
  
  Future<void> loadAvailableLibraries() async {
    if (kIsWeb || !_isConnected || _userId == null) return;
    
    try {
      final response = await _makeAuthenticatedRequest('/emby/Library/MediaFolders');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] as List;
        final List<EmbyLibrary> tempLibraries = [];
        
        for (var item in items) {
          // 处理电视剧和电影媒体库
          if (item['CollectionType'] == 'tvshows' || item['CollectionType'] == 'movies') {
            final String libraryId = item['Id'];
            final String collectionType = item['CollectionType'];
            
            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
            
            // 获取该库的项目数量
            final countResponse = await _makeAuthenticatedRequest(
                '/emby/Users/$_userId/Items?parentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&Limit=0&Fields=ParentId');
            
            int itemCount = 0;
            if (countResponse.statusCode == 200) {
              final countData = json.decode(countResponse.body);
              itemCount = countData['TotalRecordCount'] ?? 0;
            }
            
            tempLibraries.add(EmbyLibrary(
              id: item['Id'],
              name: item['Name'],
              type: item['CollectionType'],
              imageTagsPrimary: item['ImageTags']?['Primary'],
              totalItems: itemCount, 
            ));
          }
        }
        _availableLibraries = tempLibraries;
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
      }
    } catch (e, stackTrace) {
      print('Error loading available libraries: $e');
      print('Stack trace: $stackTrace');
    }
  }
  
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    _selectedLibraryIds = libraryIds;
    
    // 保存选择的媒体库到SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emby_selected_libraries', libraryIds);
  }
  
  // 按特定媒体库获取最新内容
  Future<List<EmbyMediaItem>> getLatestMediaItemsByLibrary(
    String libraryId, {
    int limit = 20,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected) {
      return [];
    }
    
    try {
      // 默认排序参数
      final defaultSortBy = sortBy ?? 'DateCreated,SortName';
      final defaultSortOrder = sortOrder ?? 'Descending';
      
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
      
      final response = await _makeAuthenticatedRequest(
        '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];
        
        return items
            .map((item) => EmbyMediaItem.fromJson(item))
            .toList();
      }
    } catch (e) {
      print('Error fetching media items for library $libraryId: $e');
    }
    
    return [];
  }
  
  // 按特定媒体库获取随机内容
  Future<List<EmbyMediaItem>> getRandomMediaItemsByLibrary(
    String libraryId, {
    int limit = 20,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected) {
      return [];
    }
    
    try {
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
        '/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
      
      // 使用Emby的随机排序获取随机内容
      final response = await _makeAuthenticatedRequest(
        '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=Random&Limit=$limit'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];
        
        return items
            .map((item) => EmbyMediaItem.fromJson(item))
            .toList();
      }
    } catch (e) {
      print('Error fetching random media items for library $libraryId: $e');
    }
    
    return [];
  }
  
  Future<List<EmbyMediaItem>> getLatestMediaItems({
    int limitPerLibrary = 99999, 
    int totalLimit = 99999,
    String? sortBy,
    String? sortOrder,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty || _userId == null) {
      return [];
    }

    List<EmbyMediaItem> allItems = [];
    
    // 默认排序参数
    final defaultSortBy = sortBy ?? 'DateCreated';
    final defaultSortOrder = sortOrder ?? 'Descending';
    
    print('EmbyService: 获取媒体项 - sortBy: $defaultSortBy, sortOrder: $defaultSortOrder');
    
    try {
      for (final libraryId in _selectedLibraryIds) {
        try {
          // 首先获取媒体库信息以确定类型
          final libraryResponse = await _makeAuthenticatedRequest(
            '/emby/Users/$_userId/Items/$libraryId'
          );
          
          if (libraryResponse.statusCode == 200) {
            final libraryData = json.decode(libraryResponse.body);
            final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
            
            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';
            
        final String path = '/emby/Users/$_userId/Items';
        final Map<String, String> queryParameters = {
          'ParentId': libraryId,
              'IncludeItemTypes': includeItemTypes,
          'Recursive': 'true',
          'Limit': limitPerLibrary.toString(),
              'Fields': 'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear',
          'SortBy': defaultSortBy,
          'SortOrder': defaultSortOrder,
        };

        final queryString = Uri(queryParameters: queryParameters).query;
        final fullPath = '$path?$queryString';

        final response = await _makeAuthenticatedRequest(fullPath);

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['Items'] != null) {
            final items = data['Items'] as List;
            allItems.addAll(items.map((item) => EmbyMediaItem.fromJson(item)).toList());
          }
        } else {
          print('Error fetching Emby items for library $libraryId: ${response.statusCode} - ${response.body}');
            }
          }
        } catch (e, stackTrace) {
          print('Error fetching Emby items for library $libraryId: $e');
          print('Stack trace: $stackTrace');
        }
      }

      // 如果服务器端排序失败或需要客户端排序，则进行本地排序
      // 注意：当使用自定义排序时，我们依赖服务器端的排序结果
      if (sortBy == null && sortOrder == null) {
        // 默认情况下按添加日期降序排序所有收集的项目
        allItems.sort((a, b) {
          // 使用 EmbyMediaItem 中的 dateAdded 字段进行排序
          return b.dateAdded.compareTo(a.dateAdded);
        });
      }

      // 应用总数限制
      if (allItems.length > totalLimit) {
        allItems = allItems.sublist(0, totalLimit);
      }
      
      return allItems;

    } catch (e, stackTrace) {
      print('Error getting latest media items from Emby: $e');
      print('Stack trace: $stackTrace');
    }
    return [];
  }
  
  // 获取最新电影列表
  Future<List<EmbyMovieInfo>> getLatestMovies({int limit = 99999}) async {
    if (kIsWeb) return [];
    if (!_isConnected || _selectedLibraryIds.isEmpty || _userId == null) {
      return [];
    }
    
    List<EmbyMovieInfo> allMovies = [];
    
    // 从每个选中的媒体库获取最新电影
    for (String libraryId in _selectedLibraryIds) {
      try {
        final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?ParentId=$libraryId&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit'
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];
          
          List<EmbyMovieInfo> libraryMovies = items
              .map((item) => EmbyMovieInfo.fromJson(item))
              .toList();
          
          allMovies.addAll(libraryMovies);
        }
      } catch (e, stackTrace) {
        print('Error fetching movies for library $libraryId: $e');
        print('Stack trace: $stackTrace');
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
  Future<EmbyMovieInfo?> getMovieDetails(String movieId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
        '/emby/Users/$_userId/Items/$movieId'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EmbyMovieInfo.fromJson(data);
      }
    } catch (e, stackTrace) {
      print('Error getting movie details: $e');
      print('Stack trace: $stackTrace');
      throw Exception('无法获取电影详情: $e');
    }
    
    return null;
  }
  
  Future<EmbyMediaItemDetail> getMediaItemDetails(String itemId) async {
    if (!_isConnected || _userId == null) {
      throw Exception('未连接到Emby服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items/$itemId?Fields=Overview,Genres,People,Studios,ProviderIds');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EmbyMediaItemDetail.fromJson(data);
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('HTTP ${response.statusCode}: 无法获取媒体详情');
      }
    } catch (e, stackTrace) {
      print('Error getting media item details: $e');
      print('Stack trace: $stackTrace');
      throw Exception('无法获取媒体详情: $e');
    }
  }
  
  Future<List<EmbySeasonInfo>> getSeasons(String seriesId) async {
    if (!_isConnected || _userId == null) {
      throw Exception('未连接到Emby服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?parentId=$seriesId&IncludeItemTypes=Season&Recursive=false&Fields=Overview');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] as List;
        
        return items.map((item) => EmbySeasonInfo.fromJson(item)).toList();
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('HTTP ${response.statusCode}: 无法获取季节信息');
      }
    } catch (e, stackTrace) {
      print('Error getting seasons: $e');
      print('Stack trace: $stackTrace');
      throw Exception('无法获取季节信息: $e');
    }
  }
  
  Future<List<EmbyEpisodeInfo>> getEpisodes(String seasonId) async {
    if (!_isConnected || _userId == null) {
      throw Exception('未连接到Emby服务器');
    }
    
    try {
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?parentId=$seasonId&IncludeItemTypes=Episode&Recursive=false&Fields=Overview');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] as List;
        
        return items.map((item) => EmbyEpisodeInfo.fromJson(item)).toList();
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
        throw Exception('HTTP ${response.statusCode}: 无法获取剧集信息');
      }
    } catch (e, stackTrace) {
      print('Error getting episodes: $e');
      print('Stack trace: $stackTrace');
      throw Exception('无法获取剧集信息: $e');
    }
  }

  Future<List<EmbyEpisodeInfo>> getSeasonEpisodes(String seriesId, String seasonId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }
    
    final response = await _makeAuthenticatedRequest(
      '/emby/Shows/$seriesId/Episodes?userId=$_userId&seasonId=$seasonId'
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];
      
      List<EmbyEpisodeInfo> episodes = items
          .map((item) => EmbyEpisodeInfo.fromJson(item))
          .toList();
      
      // 按剧集编号排序
      episodes.sort((a, b) => a.indexNumber?.compareTo(b.indexNumber ?? 0) ?? 0);
      
      return episodes;
    } else {
      throw Exception('无法获取季节剧集信息');
    }
  }
  
  Future<EmbyEpisodeInfo?> getEpisodeDetails(String episodeId) async {
    try {
      debugPrint('[EmbyService] 开始获取剧集详情: episodeId=$episodeId');
      debugPrint('[EmbyService] 服务器URL: $_serverUrl');
      debugPrint('[EmbyService] 用户ID: $_userId');
      debugPrint('[EmbyService] 访问令牌: ${_accessToken != null ? "已设置" : "未设置"}');
      
      // 使用用户特定的API路径，与detail页面保持一致
      final response = await _makeAuthenticatedRequest('/emby/Users/$_userId/Items/$episodeId');
      
      debugPrint('[EmbyService] API响应状态码: ${response.statusCode}');
      debugPrint('[EmbyService] API响应内容长度: ${response.body.length}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('[EmbyService] 解析到的数据键: ${data.keys.toList()}');
        return EmbyEpisodeInfo.fromJson(data);
      } else {
        debugPrint('[EmbyService] ❌ API请求失败: HTTP ${response.statusCode}');
        debugPrint('[EmbyService] 错误响应内容: ${response.body}');
      }
    } catch (e, stackTrace) {
      debugPrint('[EmbyService] ❌ 获取剧集详情时出错: $e');
      print('Stack trace: $stackTrace');
    }
    
    debugPrint('[EmbyService] 返回null，无法获取剧集详情');
    return null;
  }
  
  /// 获取相邻剧集（使用Emby的AdjacentTo参数作为简单的上下集导航）
  /// 返回当前剧集前后各一集的剧集列表，不依赖弹幕映射
  Future<List<EmbyEpisodeInfo>> getAdjacentEpisodes(String currentEpisodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }
    
    try {
      // 使用AdjacentTo参数获取相邻剧集，限制3个结果（上一集、当前集、下一集）
      final response = await _makeAuthenticatedRequest(
        '/emby/Users/$_userId/Items?AdjacentTo=$currentEpisodeId&Limit=3&Fields=Overview,MediaSources'
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];
        
        final episodes = items
            .map((item) => EmbyEpisodeInfo.fromJson(item))
            .toList();
        
        // 按集数排序确保顺序正确
        episodes.sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));
        
        debugPrint('[EmbyService] 获取到${episodes.length}个相邻剧集');
        return episodes;
      } else {
        debugPrint('[EmbyService] 获取相邻剧集失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[EmbyService] 获取相邻剧集出错: $e');
      return [];
    }
  }
  
  /// 简单获取下一集（不依赖弹幕映射）
  Future<EmbyEpisodeInfo?> getNextEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex != -1 && currentIndex < adjacentEpisodes.length - 1) {
      final nextEpisode = adjacentEpisodes[currentIndex + 1];
      debugPrint('[EmbyService] 找到下一集: ${nextEpisode.name}');
      return nextEpisode;
    }
    
    debugPrint('[EmbyService] 没有找到下一集');
    return null;
  }
  
  /// 简单获取上一集（不依赖弹幕映射）
  Future<EmbyEpisodeInfo?> getPreviousEpisode(String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);
    
    if (adjacentEpisodes.isEmpty) return null;
    
    // 找到当前剧集的位置
    final currentIndex = adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);
    
    if (currentIndex > 0) {
      final previousEpisode = adjacentEpisodes[currentIndex - 1];
      debugPrint('[EmbyService] 找到上一集: ${previousEpisode.name}');
      return previousEpisode;
    }
    
    debugPrint('[EmbyService] 没有找到上一集');
    return null;
  }
  
  String getStreamUrl(String itemId) {
    if (!_isConnected || _accessToken == null) {
      return '';
    }
    
    return '$_serverUrl/emby/Videos/$itemId/stream?api_key=$_accessToken&Static=true';
  }
  
  String getImageUrl(String itemId, {String type = 'Primary', int? width, int? height, int? quality, String? tag}) {
    if (!_isConnected) {
      return '';
    }
    
    final queryParams = <String, String>{};
    
    if (width != null) queryParams['maxWidth'] = width.toString(); // Emby 使用 maxWidth/maxHeight
    if (height != null) queryParams['maxHeight'] = height.toString();
    if (quality != null) queryParams['quality'] = quality.toString();
    if (tag != null) queryParams['tag'] = tag; // 添加 tag 参数

    String imagePathSegment = type;
    // 为了兼容旧的调用，如果type是PrimaryPerson，我们特殊处理一下，实际上Emby API中没有这个Type
    // 对于人物图片，itemId 应该是人物的 ID，type 应该是 Primary，tag 应该是 ImageTags.Primary 的值
    // 但由于我们从 People 列表获取的 actor.id 并非全局人物 ItemID，而是与当前媒体关联的 ID
    // 而 actor.imagePrimaryTag 才是关键
    // Emby API 获取人物图片通常是 /Items/{PersonItemId}/Images/Primary?tag={tag}
    // 或者如果服务器配置了，可以直接用 /Items/{PersonItemId}/Images/Primary
    // 这里的 itemId 应该是 Person 的 ItemId，而不是当前媒体的 Id
    // 我们需要一种方式从 actor.id (可能是引用ID) 和 actor.imagePrimaryTag 得到正确的URL
    // 暂时假设 actor.id 就是 PersonItemID，这在某些情况下可能成立，或者 imagePrimaryTag 配合主媒体 itemId 也能工作

    // 一个更可靠的获取人物图片的方式可能是直接使用 /Items/{itemId}/Images/Primary?tag={tag_from_person_object}
    // 这里的 itemId 是 Person 的 Item ID，tag 是 Person.ImageTags.Primary
    // 如果 EmbyPerson.id 是全局人物 ID，并且 EmbyPerson.imagePrimaryTag 是该人物主图的 tag
    // 那么可以这样构建：
    // path = '/emby/Items/$itemId/Images/Primary' (itemId 是 Person.id, tag 是 Person.imagePrimaryTag)

    // 根据 Emby API 文档，更通用的图片URL格式是：
    // /Items/{ItemId}/Images/{ImageType}
    // /Items/{ItemId}/Images/{ImageType}/{ImageIndex}
    // 可选参数: MaxWidth, MaxHeight, Width, Height, Quality, FillWidth, FillHeight, Tag, Format, AddPlayedIndicator, PercentPlayed, UnplayedCount, CropWhitespace, BackgroundColor, ForegroundLayer, Blur, TrimBorder
    // 对于人物，通常 Type 是 Primary，ItemId 是人物的全局 ID。

    // 鉴于 EmbyPerson.id 可能是引用ID，而 imagePrimaryTag 是实际的图片标签
    // 我们尝试使用主媒体的ID (mediaDetail.id) 和 人物的 imagePrimaryTag 来获取图片
    // 这依赖于服务器如何处理这种情况，但值得一试
    // 如果失败，说明需要更复杂的逻辑来获取人物的全局 ItemID

    // 修正：EmbyService 里的 getImageUrl 的 itemId 参数，对于演职人员，应该传入演职人员自己的 ItemId (actor.id)
    // 而不是媒体的 itemId。EmbyPerson.imagePrimaryTag 是这个图片的具体标签。
    // 所以调用时应该是 getImageUrl(actor.id, type: 'Primary', tag: actor.imagePrimaryTag)
    // 而 getImageUrl 内部应该构建 /Items/{actor.id}/Images/Primary?tag={actor.imagePrimaryTag}

    final queryString = queryParams.isNotEmpty ? '?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}' : '';
    
    return '$_serverUrl/emby/Items/$itemId/Images/$imagePathSegment$queryString';
  }
  
  // 获取媒体文件信息（用于哈希计算）
  Future<Map<String, dynamic>?> getMediaFileInfo(String itemId) async {
    try {
      // 首先尝试获取媒体源信息
      final response = await _makeAuthenticatedRequest('/emby/Items/$itemId/PlaybackInfo?UserId=$_userId');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mediaSources = data['MediaSources'] as List?;
        
        if (mediaSources != null && mediaSources.isNotEmpty) {
          final source = mediaSources[0];
          final String? fileName = source['Name'];
          final int? fileSize = source['Size'];
          
          debugPrint('获取到Emby媒体文件信息: 文件名=$fileName, 大小=$fileSize');
          
          return {
            'fileName': fileName,
            'fileSize': fileSize,
          };
        }
      } else {
        debugPrint('媒体文件信息API请求失败: HTTP ${response.statusCode}');
      }
      
      // 如果File接口无法获取有效信息，尝试使用普通的Items接口
      final itemResponse = await _makeAuthenticatedRequest('/emby/Items/$itemId');
      
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
        
        return {
          'fileName': fileName,
          'fileSize': 0, // 无法获取确切大小时使用0
        };
      }
    } catch (e, stackTrace) {
      debugPrint('获取Emby媒体文件信息时出错: $e');
      print('Stack trace: $stackTrace');
    }
    
    return null;
  }

  /// 获取Emby视频的字幕轨道信息，包括内嵌字幕和外挂字幕
  Future<List<Map<String, dynamic>>> getSubtitleTracks(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }
    try {
      // 获取播放信息，包含媒体源和字幕轨道
      final response = await _makeAuthenticatedRequest(
        '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId'
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final mediaSources = data['MediaSources'] as List?;
        if (mediaSources == null || mediaSources.isEmpty) {
          debugPrint('EmbyService: 未找到媒体源信息');
          return [];
        }
        final mediaSource = mediaSources[0];
        final mediaStreams = mediaSource['MediaStreams'] as List?;
        if (mediaStreams == null) {
          debugPrint('EmbyService: 未找到媒体流信息');
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
              final subtitleUrl = '$_serverUrl/emby/Videos/$itemId/$mediaSourceId/Subtitles/$i/Stream.$codec?api_key=$_accessToken';
              trackInfo['downloadUrl'] = subtitleUrl;
            }
            subtitleTracks.add(trackInfo);
            debugPrint('EmbyService: 找到字幕轨道 $i: ${trackInfo['title']} (${trackInfo['type']})');
          }
        }
        debugPrint('EmbyService: 总共找到 ${subtitleTracks.length} 个字幕轨道');
        return subtitleTracks;
      } else {
        debugPrint('EmbyService: 获取播放信息失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e, stackTrace) {
      debugPrint('EmbyService: 获取字幕轨道信息失败: $e');
      print('Stack trace: $stackTrace');
      return [];
    }
  }

  /// 下载Emby外挂字幕文件
  Future<String?> downloadSubtitleFile(String itemId, int subtitleIndex, String format) async {
    if (kIsWeb) return null;
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Emby服务器');
    }
    try {
      // 获取媒体源ID
      final playbackInfoResponse = await _makeAuthenticatedRequest(
        '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId'
      );
      if (playbackInfoResponse.statusCode != 200) {
        debugPrint('EmbyService: 获取播放信息失败，无法下载字幕');
        return null;
      }
      final playbackData = json.decode(playbackInfoResponse.body);
      final mediaSources = playbackData['MediaSources'] as List?;
      if (mediaSources == null || mediaSources.isEmpty) {
        debugPrint('EmbyService: 未找到媒体源信息');
        return null;
      }
      final mediaSourceId = mediaSources[0]['Id'];
      // 构建字幕下载URL
      final subtitleUrl = '$_serverUrl/emby/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format?api_key=$_accessToken';
      debugPrint('EmbyService: 下载字幕文件: $subtitleUrl');
      // 下载字幕文件
      final subtitleResponse = await http.get(Uri.parse(subtitleUrl));
      if (subtitleResponse.statusCode == 200) {
        // 保存到临时文件
        final tempDir = await getTemporaryDirectory();
        final fileName = 'emby_subtitle_${itemId}_$subtitleIndex.$format';
        final filePath = '${tempDir.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(subtitleResponse.bodyBytes);
        debugPrint('EmbyService: 字幕文件已保存到: $filePath');
        return filePath;
      } else {
        debugPrint('EmbyService: 下载字幕文件失败: HTTP ${subtitleResponse.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('EmbyService: 下载字幕文件时出错: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
}

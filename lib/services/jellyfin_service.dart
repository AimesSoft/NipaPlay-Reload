import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/jellyfin_model.dart';

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

  // Getters
  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  List<JellyfinLibrary> get availableLibraries => _availableLibraries;
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  
  Future<void> loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _serverUrl = prefs.getString('jellyfin_server_url');
    _username = prefs.getString('jellyfin_username');
    _accessToken = prefs.getString('jellyfin_access_token');
    _userId = prefs.getString('jellyfin_user_id');
    _selectedLibraryIds = prefs.getStringList('jellyfin_selected_libraries') ?? [];
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      try {
        // 尝试验证保存的令牌是否仍然有效
        final response = await _makeAuthenticatedRequest('/System/Info');
        _isConnected = response.statusCode == 200;
        
        if (_isConnected) {
          // 加载可用媒体库
          await loadAvailableLibraries();
        }
      } catch (e) {
        _isConnected = false;
      }
    } else {
      _isConnected = false;
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
        _isConnected = false;
        return false;
      }
      
      // 认证用户
      final authResponse = await http.post(
        Uri.parse('$_serverUrl/Users/AuthenticateByName'),
        headers: {
          'Content-Type': 'application/json',
          'X-Emby-Authorization': 'MediaBrowser Client="NipaPlay", Device="Flutter", DeviceId="NipaPlay-Flutter", Version="1.0.0"',
        },
        body: json.encode({
          'Username': username,
          'Pw': password,
        }),
      );
      
      if (authResponse.statusCode != 200) {
        _isConnected = false;
        return false;
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
      await loadAvailableLibraries();
      
      return true;
    } catch (e) {
      _isConnected = false;
      return false;
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
    if (!_isConnected || _userId == null) return;

    try {
      final response = await _makeAuthenticatedRequest('/UserViews?userId=$_userId');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        List<JellyfinLibrary> tempLibraries = [];
        for (var item in items) {
          if (item['CollectionType'] == 'tvshows') {
            final String libraryId = item['Id'];
            final countResponse = await _makeAuthenticatedRequest(
                '/Items?parentId=$libraryId&IncludeItemTypes=Series&Recursive=true&Limit=0&Fields=ParentId');
            
            int seriesCount = 0;
            if (countResponse.statusCode == 200) {
              final countData = json.decode(countResponse.body);
              seriesCount = countData['TotalRecordCount'] ?? 0;
            }
            
            tempLibraries.add(JellyfinLibrary(
              id: item['Id'],
              name: item['Name'],
              type: item['CollectionType'], // Assuming 'CollectionType' maps to 'type'
              imageTagsPrimary: item['ImageTags']?['Primary'], // Safely access ImageTags
              totalItems: seriesCount, 
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
  
  Future<List<JellyfinMediaItem>> getLatestMediaItems({int limit = 50}) async {
    if (!_isConnected || _selectedLibraryIds.isEmpty) {
      return [];
    }
    
    List<JellyfinMediaItem> allItems = [];
    
    // 从每个选中的媒体库获取最新内容
    for (String libraryId in _selectedLibraryIds) {
      try {
        final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=Series&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit&userId=$_userId'
        );
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];
          
          List<JellyfinMediaItem> libraryItems = items
              .map((item) => JellyfinMediaItem.fromJson(item))
              .toList();
          
          allItems.addAll(libraryItems);
        }
      } catch (e) {
        // 处理错误
      }
    }
    
    // 按最近添加日期排序
    allItems.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
    
    // 限制总数
    if (allItems.length > limit) {
      allItems = allItems.sublist(0, limit);
    }
    
    return allItems;
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
  
  // 获取流媒体URL
  String getStreamUrl(String itemId) {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    return '$_serverUrl/Videos/$itemId/stream?static=true&MediaSourceId=$itemId&api_key=$_accessToken';
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
      url += '?' + params.join('&');
    }
    
    return url;
  }
  
  // 辅助方法：发送经过身份验证的HTTP请求
  Future<http.Response> _makeAuthenticatedRequest(String endpoint, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (_serverUrl == null || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }
    
    final Uri uri = Uri.parse('$_serverUrl$endpoint');
    final Map<String, String> headers = {
      'X-Emby-Authorization': 'MediaBrowser Client="NipaPlay", Device="Flutter", DeviceId="NipaPlay-Flutter", Version="1.0.0", Token="$_accessToken"',
    };
    
    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }
    
    switch (method) {
      case 'GET':
        return http.get(uri, headers: headers);
      case 'POST':
        return http.post(uri, headers: headers, body: body != null ? json.encode(body) : null);
      case 'PUT':
        return http.put(uri, headers: headers, body: body != null ? json.encode(body) : null);
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        throw Exception('不支持的HTTP方法: $method');
    }
  }
}

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/emby_model.dart';

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

  // Getters
  bool get isConnected => _isConnected;
  String? get serverUrl => _serverUrl;
  String? get username => _username;
  List<EmbyLibrary> get availableLibraries => _availableLibraries;
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  
  Future<void> loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    _serverUrl = prefs.getString('emby_server_url');
    _username = prefs.getString('emby_username');
    _accessToken = prefs.getString('emby_access_token');
    _userId = prefs.getString('emby_user_id');
    _selectedLibraryIds = prefs.getStringList('emby_selected_libraries') ?? [];
    
    print('Emby loadSavedSettings: serverUrl=$_serverUrl, username=$_username, hasToken=${_accessToken != null}, userId=$_userId');
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      try {
        print('Emby: 尝试验证保存的连接信息...');
        // 尝试验证保存的令牌是否仍然有效
        final response = await _makeAuthenticatedRequest('/emby/System/Info');
        _isConnected = response.statusCode == 200;
        
        print('Emby: 令牌验证结果 - HTTP ${response.statusCode}, 连接状态: $_isConnected');
        
        if (_isConnected) {
          print('Emby: 连接验证成功，正在加载媒体库...');
          // 加载可用媒体库
          await loadAvailableLibraries();
          print('Emby: 媒体库加载完成，可用库数量: ${_availableLibraries.length}');
        } else {
          print('Emby: 连接验证失败 - HTTP ${response.statusCode}');
        }
      } catch (e) {
        print('Emby: 连接验证过程中发生异常: $e');
        _isConnected = false;
      }
    } else {
      print('Emby: 缺少必要的连接信息，跳过自动连接');
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
        Uri.parse('$_serverUrl/emby/System/Info/Public'),
      );
      
      if (configResponse.statusCode != 200) {
        _isConnected = false;
        return false;
      }
      
      // 认证用户
      final authResponse = await http.post(
        Uri.parse('$_serverUrl/emby/Users/AuthenticateByName'),
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
      return false;
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
  
  Future<http.Response> _makeAuthenticatedRequest(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (_accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    final uri = Uri.parse('$_serverUrl$path');
    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': 'MediaBrowser Client="NipaPlay", Device="Flutter", DeviceId="NipaPlay-Flutter", Version="1.0.0", Token="$_accessToken"',
    };
    
    switch (method.toUpperCase()) {
      case 'GET':
        return await http.get(uri, headers: headers);
      case 'POST':
        return await http.post(uri, headers: headers, body: body != null ? json.encode(body) : null);
      case 'PUT':
        return await http.put(uri, headers: headers, body: body != null ? json.encode(body) : null);
      case 'DELETE':
        return await http.delete(uri, headers: headers);
      default:
        throw Exception('不支持的 HTTP 方法: $method');
    }
  }
  
  // 专门用于需要验证连接状态的请求方法
  Future<http.Response> _makeVerifiedAuthenticatedRequest(String path, {String method = 'GET', Map<String, dynamic>? body}) async {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    return _makeAuthenticatedRequest(path, method: method, body: body);
  }
  
  Future<void> loadAvailableLibraries() async {
    if (!_isConnected || _userId == null) return;
    
    try {
      final response = await _makeAuthenticatedRequest('/emby/Library/MediaFolders');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] as List;
        final List<EmbyLibrary> tempLibraries = [];
        
        for (var item in items) {
          // 只处理电视剧媒体库
          if (item['CollectionType'] == 'tvshows') {
            // 获取该库的项目数量
            final countResponse = await _makeAuthenticatedRequest(
                '/emby/Users/$_userId/Items?parentId=${item['Id']}&IncludeItemTypes=Series&Recursive=true&Limit=0&Fields=ParentId');
            
            int seriesCount = 0;
            if (countResponse.statusCode == 200) {
              final countData = json.decode(countResponse.body);
              seriesCount = countData['TotalRecordCount'] ?? 0;
            }
            
            tempLibraries.add(EmbyLibrary(
              id: item['Id'],
              name: item['Name'],
              type: item['CollectionType'],
              imageTagsPrimary: item['ImageTags']?['Primary'],
              totalItems: seriesCount, 
            ));
          }
        }
        _availableLibraries = tempLibraries;
      } else {
        print('Error response: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error loading available libraries: $e');
    }
  }
  
  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    _selectedLibraryIds = libraryIds;
    
    // 保存选择的媒体库到SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('emby_selected_libraries', libraryIds);
  }
  
  Future<List<EmbyMediaItem>> getLatestMediaItems({int limitPerLibrary = 99999, int totalLimit = 99999}) async {
    if (!_isConnected || _selectedLibraryIds.isEmpty || _userId == null) {
      return [];
    }

    List<EmbyMediaItem> allItems = [];
    try {
      for (final libraryId in _selectedLibraryIds) {
        final String path = '/emby/Users/$_userId/Items';
        final Map<String, String> queryParameters = {
          'ParentId': libraryId,
          'IncludeItemTypes': 'Series',
          'Recursive': 'true',
          'Limit': limitPerLibrary.toString(),
          'Fields': 'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear', //确保DateCreated在请求中
          'SortBy': 'DateCreated',
          'SortOrder': 'Descending',
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

      // 按添加日期降序排序所有收集的项目
      allItems.sort((a, b) {
        // 使用 EmbyMediaItem 中的 dateAdded 字段进行排序
        return b.dateAdded.compareTo(a.dateAdded);
      });

      // 应用总数限制
      if (allItems.length > totalLimit) {
        allItems = allItems.sublist(0, totalLimit);
      }
      
      return allItems;

    } catch (e) {
      print('Error getting latest media items from Emby: $e');
    }
    return [];
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
    } catch (e) {
      print('Error getting media item details: $e');
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
    } catch (e) {
      print('Error getting seasons: $e');
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
    } catch (e) {
      print('Error getting episodes: $e');
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
      final response = await _makeAuthenticatedRequest('/emby/Items/$episodeId');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return EmbyEpisodeInfo.fromJson(data);
      }
    } catch (e) {
      print('Error getting episode details: $e');
    }
    
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
    } catch (e) {
      debugPrint('获取Emby媒体文件信息时出错: $e');
    }
    
    return null;
  }
}

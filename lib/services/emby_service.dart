import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'debug_log_service.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/services/emby_transcode_manager.dart';
import 'package:nipaplay/services/media_server_playback_client.dart';
import 'media_server_service_base.dart';

class EmbyService extends MediaServerServiceBase
    implements MediaServerPlaybackClient {
  static final EmbyService instance = EmbyService._internal();

  EmbyService._internal();

  String? _serverUrl;
  String? _username;
  String? _password;
  String? _accessToken;
  String? _userId;
  bool _isConnected = false;
  bool _isReady = false;
  List<EmbyLibrary> _availableLibraries = [];
  List<String> _selectedLibraryIds = [];
  ServerProfile? _currentProfile;
  String? _currentAddressId;

  @override
  String get serviceName => 'Emby';

  @override
  String get serviceType => 'emby';

  @override
  String get prefsKeyPrefix => 'emby';

  @override
  String get serverNameFallback => 'Emby服务器';

  @override
  bool get alwaysIncludeContentType => true;

  @override
  String get notConnectedMessage => '未连接到 Emby 服务器';

  bool get isTranscodeEnabled => transcodeEnabledCache;

  @override
  String normalizeRequestPath(String path) => _normalizeEmbyPath(path);

  @override
  Future<bool> testConnection(String url, String username, String password) =>
      _testEmbyConnection(url, username, password);

  @override
  Future<void> performAuthentication(
          String serverUrl, String username, String password) =>
      _performAuthentication(serverUrl, username, password);

  @override
  Future<String> getServerId(String url) => _getEmbyServerId(url);

  @override
  Future<String?> getServerName(String url) => _getServerName(url);

  @override
  Future<void> loadTranscodeSettings() async {
    try {
      final transMgr = EmbyTranscodeManager.instance;
      await transMgr.initialize();
      final enabled = await transMgr.isTranscodingEnabled();
      final quality = await transMgr.getDefaultVideoQuality();
      final settings = await transMgr.getSettings();
      updateTranscodeCache(
        enabled: enabled,
        defaultQuality: quality,
        settings: settings,
      );
      DebugLogService().addLog(
          'Emby: 已加载转码偏好 缓存 enabled=$enabled, quality=$quality');
    } catch (e) {
      DebugLogService().addLog('Emby: 加载转码偏好失败，使用默认值: $e');
      updateTranscodeCache(
        enabled: false,
        defaultQuality: JellyfinVideoQuality.bandwidth5m,
        settings: const JellyfinTranscodeSettings(),
      );
    }
  }

  @override
  void clearServiceData() {
    _availableLibraries = [];
  }

  /// 获取服务器端的媒体技术元数据（容器/编解码器/Profile/Level/HDR/声道/码率等）
  /// 结构与 Jellyfin 保持一致，字段命名相同，便于 UI 统一展示。
  Future<Map<String, dynamic>> getServerMediaTechnicalInfo(
      String itemId) async {
    if (!_isConnected || _userId == null) {
      return {};
    }

    final Map<String, dynamic> result = {
      'container': null,
      'video': <String, dynamic>{},
      'audio': <String, dynamic>{},
    };

    try {
      // 1) 优先 PlaybackInfo
      final playbackResp = await _makeAuthenticatedRequest(
        '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId',
      );
      Map<String, dynamic>? firstSource;
      Map<String, dynamic>? videoStream;
      Map<String, dynamic>? audioStream;

      if (playbackResp.statusCode == 200) {
        final pbData = json.decode(playbackResp.body);
        final mediaSources = pbData['MediaSources'];
        if (mediaSources is List && mediaSources.isNotEmpty) {
          firstSource = Map<String, dynamic>.from(mediaSources.first);
          result['container'] = firstSource['Container'];
          final streams = firstSource['MediaStreams'];
          if (streams is List) {
            for (final s in streams) {
              if (s is Map && s['Type'] == 'Video' && videoStream == null) {
                videoStream = Map<String, dynamic>.from(s);
              } else if (s is Map &&
                  s['Type'] == 'Audio' &&
                  audioStream == null) {
                audioStream = Map<String, dynamic>.from(s);
              }
            }
          }
        }
      }

      // 2) 补充 Items 详情
      Map<String, dynamic>? itemDetail;
      try {
        final itemResp = await _makeAuthenticatedRequest(
            '/emby/Users/$_userId/Items/$itemId');
        if (itemResp.statusCode == 200) {
          itemDetail = Map<String, dynamic>.from(json.decode(itemResp.body));
        }
      } catch (_) {}

      final video = <String, dynamic>{
        'codec': videoStream?['Codec'] ?? firstSource?['VideoCodec'],
        'profile': videoStream?['Profile'],
        'level': videoStream?['Level']?.toString(),
        'bitDepth': videoStream?['BitDepth'],
        'width': videoStream?['Width'] ?? firstSource?['Width'],
        'height': videoStream?['Height'] ?? firstSource?['Height'],
        'frameRate':
            videoStream?['RealFrameRate'] ?? videoStream?['AverageFrameRate'],
        'bitRate': videoStream?['BitRate'] ?? firstSource?['Bitrate'],
        'pixelFormat': videoStream?['PixelFormat'],
        'colorSpace': videoStream?['ColorSpace'],
        'colorTransfer': videoStream?['ColorTransfer'],
        'colorPrimaries': videoStream?['ColorPrimaries'],
        'dynamicRange': videoStream?['VideoRange'] ?? itemDetail?['VideoRange'],
      };

      final audio = <String, dynamic>{
        'codec': audioStream?['Codec'] ?? firstSource?['AudioCodec'],
        'channels': audioStream?['Channels'],
        'channelLayout': audioStream?['ChannelLayout'],
        'sampleRate': audioStream?['SampleRate'],
        'bitRate': audioStream?['BitRate'] ?? firstSource?['AudioBitrate'],
        'language': audioStream?['Language'],
      };

      result['video'] = video;
      result['audio'] = audio;
      return result;
    } catch (e) {
      DebugLogService().addLog('EmbyService: 获取媒体技术元数据失败: $e');
      return {};
    }
  }

  // Getters
  @override
  bool get isConnected => _isConnected;
  @override
  set isConnected(bool value) => _isConnected = value;
  @override
  bool get isReady => _isReady;
  @override
  set isReady(bool value) => _isReady = value;
  @override
  String? get serverUrl => _serverUrl;
  @override
  set serverUrl(String? value) => _serverUrl = value;
  @override
  String? get username => _username;
  @override
  set username(String? value) => _username = value;
  @override
  String? get password => _password;
  @override
  set password(String? value) => _password = value;
  @override
  String? get accessToken => _accessToken;
  @override
  set accessToken(String? value) => _accessToken = value;
  @override
  String? get userId => _userId;
  @override
  set userId(String? value) => _userId = value;
  List<EmbyLibrary> get availableLibraries => _availableLibraries;
  @override
  List<String> get selectedLibraryIds => _selectedLibraryIds;
  @override
  set selectedLibraryIds(List<String> value) => _selectedLibraryIds = value;
  @override
  ServerProfile? get currentProfile => _currentProfile;
  @override
  set currentProfile(ServerProfile? value) => _currentProfile = value;
  @override
  String? get currentAddressId => _currentAddressId;
  @override
  set currentAddressId(String? value) => _currentAddressId = value;

  /// 测试Emby连接
  Future<bool> _testEmbyConnection(
      String url, String username, String password) async {
    try {
      // 获取服务器信息
      final configResponse = await http
          .get(
            Uri.parse('$url/emby/System/Info/Public'),
          )
          .timeout(const Duration(seconds: 5));

      return configResponse.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// 执行完整的认证流程
  Future<void> _performAuthentication(
      String serverUrl, String username, String password) async {
    final clientInfo = await getClientInfo();
    final authResponse = await http.post(
      Uri.parse('$serverUrl/emby/Users/AuthenticateByName'),
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
      throw Exception('认证失败: ${authResponse.statusCode}');
    }

    final authData = json.decode(authResponse.body);
    _accessToken = authData['AccessToken'];
    _userId = authData['User']['Id'];
  }

  /// 获取Emby服务器ID
  /// 如果无法获取，将抛出异常
  Future<String> _getEmbyServerId(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/emby/System/Info/Public'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Id'] ?? data['ServerId'];
      }
      // 在HTTP状态码不为200时抛出详细错误
      throw Exception(
          '获取Emby服务器ID失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    } catch (e) {
      DebugLogService().addLog('获取Emby服务器ID失败: $e');
      // 重新抛出异常，以便 identifyServer 捕获并返回详细错误
      rethrow;
    }
  }

  /// 获取服务器名称
  Future<String?> _getServerName(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/emby/System/Info/Public'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ServerName'];
      }
    } catch (e) {
      DebugLogService().addLog('获取Emby服务器名称失败: $e');
    }
    return null;
  }

  /// 确保所有Emby API请求都包含/emby前缀，兼容反向代理子路径
  String _normalizeEmbyPath(String path) {
    if (path.isEmpty) return '/emby';
    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }

    String normalized = trimmed.startsWith('/') ? trimmed : '/$trimmed';
    if (!normalized.toLowerCase().startsWith('/emby')) {
      normalized = '/emby$normalized';
    }

    // 避免出现双斜杆导致的404
    while (normalized.contains('//')) {
      normalized = normalized.replaceAll('//', '/');
    }

    return normalized;
  }

  Future<http.Response> _makeAuthenticatedRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    return makeAuthenticatedRequest(path,
        method: method, body: body, timeout: timeout);
  }

  @override
  Future<void> loadAvailableLibraries() async {
    if (kIsWeb || !_isConnected || _userId == null) return;

    try {
      final response =
          await _makeAuthenticatedRequest('/emby/Library/MediaFolders');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['Items'] as List;
        final List<EmbyLibrary> tempLibraries = [];

        for (var item in items) {
          final String collectionType =
              _resolveCollectionType(item['CollectionType']);
          // 处理电视剧、电影与混合媒体库
          if (collectionType == 'tvshows' ||
              collectionType == 'movies' ||
              collectionType == 'mixed') {
            final String libraryId = item['Id'];

            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes;
            if (collectionType == 'tvshows') {
              includeItemTypes = 'Series';
            } else if (collectionType == 'movies') {
              includeItemTypes = 'Movie';
            } else {
              includeItemTypes = 'Movie,Episode,Video';
            }

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
              type: collectionType,
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

  // 获取媒体库或文件夹下的子项（用于混合类型文件夹导航）
  Future<List<EmbyMediaItem>> getFolderItems(
    String parentId, {
    int limit = 99999,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || _userId == null) {
      return [];
    }

    try {
      final queryParams = <String, String>{
        'ParentId': parentId,
        'Recursive': 'false',
        'SortBy': 'SortName',
        'SortOrder': 'Ascending',
        'Limit': limit.toString(),
        'IncludeItemTypes': 'Folder,Series,Season,Episode,Movie,Video',
        'Fields': 'Overview,DateCreated,ImageTags,IsFolder,ParentId',
      };

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final results = items
            .map((item) => EmbyMediaItem.fromJson(item))
            .toList();

        results.sort((a, b) {
          if (a.isFolder != b.isFolder) {
            return a.isFolder ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });

        return results;
      }
    } catch (e) {
      debugPrint('Error fetching folder items for parent $parentId: $e');
    }

    return [];
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
      final libraryResponse =
          await _makeAuthenticatedRequest('/Users/$_userId/Items/$libraryId');

      if (libraryResponse.statusCode != 200) {
        return [];
      }

      final libraryData = json.decode(libraryResponse.body);
      final String collectionType =
          _resolveCollectionType(libraryData['CollectionType']);

      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes;
      if (collectionType == 'tvshows') {
        includeItemTypes = 'Series';
      } else if (collectionType == 'movies') {
        includeItemTypes = 'Movie';
      } else {
        includeItemTypes = 'Movie,Episode,Video';
      }

      final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&Fields=Overview,CommunityRating');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        return items.map((item) => EmbyMediaItem.fromJson(item)).toList();
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
      final libraryResponse =
          await _makeAuthenticatedRequest('/Users/$_userId/Items/$libraryId');

      if (libraryResponse.statusCode != 200) {
        return [];
      }

      final libraryData = json.decode(libraryResponse.body);
      final String collectionType =
          _resolveCollectionType(libraryData['CollectionType']);

      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes;
      if (collectionType == 'tvshows') {
        includeItemTypes = 'Series';
      } else if (collectionType == 'movies') {
        includeItemTypes = 'Movie';
      } else {
        includeItemTypes = 'Movie,Episode,Video';
      }

      // 使用Emby的随机排序获取随机内容，并请求Overview字段
      final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=Random&Limit=$limit&Fields=Overview,CommunityRating');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        return items.map((item) => EmbyMediaItem.fromJson(item)).toList();
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

    print(
        'EmbyService: 获取媒体项 - sortBy: $defaultSortBy, sortOrder: $defaultSortOrder');

    try {
      for (final libraryId in _selectedLibraryIds) {
        try {
          // 首先获取媒体库信息以确定类型
          final libraryResponse = await _makeAuthenticatedRequest(
              '/emby/Users/$_userId/Items/$libraryId');

          if (libraryResponse.statusCode == 200) {
            final libraryData = json.decode(libraryResponse.body);
            final String collectionType =
                _resolveCollectionType(libraryData['CollectionType']);

            // 根据媒体库类型选择不同的IncludeItemTypes
            String includeItemTypes;
            if (collectionType == 'tvshows') {
              includeItemTypes = 'Series';
            } else if (collectionType == 'movies') {
              includeItemTypes = 'Movie';
            } else {
              includeItemTypes = 'Movie,Episode,Video';
            }

            final String path = '/emby/Users/$_userId/Items';
            final Map<String, String> queryParameters = {
              'ParentId': libraryId,
              'IncludeItemTypes': includeItemTypes,
              'Recursive': 'true',
              'Limit': limitPerLibrary.toString(),
              'Fields':
                  'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear',
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
                allItems.addAll(
                    items.map((item) => EmbyMediaItem.fromJson(item)).toList());
              }
            } else {
              print(
                  'Error fetching Emby items for library $libraryId: ${response.statusCode} - ${response.body}');
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
            '/emby/Users/$_userId/Items?ParentId=$libraryId&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];

          List<EmbyMovieInfo> libraryMovies =
              items.map((item) => EmbyMovieInfo.fromJson(item)).toList();

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

  /// 获取 Resume 列表用于同步播放记录
  Future<List<Map<String, dynamic>>> fetchResumeItems({int limit = 5}) async {
    if (kIsWeb) return [];
    if (!_isConnected || _userId == null) {
      debugPrint('EmbyService.fetchResumeItems -> skip, connected=$_isConnected userId=$_userId');
      return [];
    }

    final buffer =
        StringBuffer('/emby/Users/$_userId/Items/Resume?userId=$_userId');
    buffer
      ..write('&IncludeItemTypes=Episode,Movie')
      ..write('&Limit=$limit')
      ..write('&EnableUserData=true')
      ..write(
        '&Fields=RunTimeTicks,SeriesName,SeasonName,IndexNumber,ParentId,ImageTags',
      );

    try {
      debugPrint('EmbyService.fetchResumeItems -> GET ${buffer.toString()}');
      final response = await _makeAuthenticatedRequest(buffer.toString());
      if (response.statusCode != 200) {
        DebugLogService().addLog(
          'EmbyService: 获取 resume 列表失败，HTTP ${response.statusCode}',
        );
        return [];
      }

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final items = decoded['Items'];
      debugPrint(
          'EmbyService.fetchResumeItems -> HTTP ${response.statusCode}, items=${items is List ? items.length : 'N/A'}');
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList(growable: false);
      }
    } catch (e, stack) {
      DebugLogService().addLog('EmbyService: 获取 resume 列表异常: $e\n$stack');
      debugPrint('EmbyService.fetchResumeItems -> exception $e');
    }

    return [];
  }

  // 获取电影详情
  Future<EmbyMovieInfo?> getMovieDetails(String movieId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }

    try {
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items/$movieId');

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

  Future<List<EmbyEpisodeInfo>> getSeasonEpisodes(
      String seriesId, String seasonId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }

    final response = await _makeAuthenticatedRequest(
        '/emby/Shows/$seriesId/Episodes?userId=$_userId&seasonId=$seasonId');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];

      List<EmbyEpisodeInfo> episodes =
          items.map((item) => EmbyEpisodeInfo.fromJson(item)).toList();

      // 按剧集编号排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0)
            ? 999999
            : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0)
            ? 999999
            : b.indexNumber!;
        return aIndex.compareTo(bIndex);
      });

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
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items/$episodeId');

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
  Future<List<EmbyEpisodeInfo>> getAdjacentEpisodes(
      String currentEpisodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }

    try {
      // 使用AdjacentTo参数获取相邻剧集，限制3个结果（上一集、当前集、下一集）
      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?AdjacentTo=$currentEpisodeId&Limit=3&Fields=Overview,MediaSources');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final episodes =
            items.map((item) => EmbyEpisodeInfo.fromJson(item)).toList();

        // 按集数排序确保顺序正确
        episodes
            .sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

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
    final currentIndex =
        adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);

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
    final currentIndex =
        adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);

    if (currentIndex > 0) {
      final previousEpisode = adjacentEpisodes[currentIndex - 1];
      debugPrint('[EmbyService] 找到上一集: ${previousEpisode.name}');
      return previousEpisode;
    }

    debugPrint('[EmbyService] 没有找到上一集');
    return null;
  }

  // 获取流媒体URL（异步，确保含 MediaSourceId/PlaySessionId）
  Future<String> getStreamUrl(String itemId) async {
    if (!_isConnected || _accessToken == null) {
      return '';
    }
    // 使用缓存的转码设置决定默认质量
    final effectiveQuality = transcodeEnabledCache
        ? defaultQualityCache
        : JellyfinVideoQuality.original;

    // 原画或未启用转码 -> 直连
    if (effectiveQuality == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    // 其余情况 -> 通过 PlaybackInfo 构建带会话的 HLS URL
    return await buildHlsUrlWithOptions(
      itemId,
      quality: effectiveQuality,
    );
  }

  /// 获取流媒体URL（同步），与 Jellyfin 保持一致的调用方式
  /// 若 quality 为 original 或强制直连，则返回直连 Static 流；否则返回带转码参数的 HLS master.m3u8。
  String getStreamUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    bool forceDirectPlay = false,
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
  }) {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Emby服务器');
    }

    // 强制直连
    if (forceDirectPlay) {
      return _buildDirectPlayUrl(itemId);
    }

    // 计算实际清晰度
    final effective = quality ??
        (transcodeEnabledCache
            ? defaultQualityCache
            : JellyfinVideoQuality.original);

    // 构建直连或转码 URL
    return _buildTranscodeUrlSync(
      itemId,
      effective,
      subtitleStreamIndex: subtitleStreamIndex,
      burnInSubtitle: burnInSubtitle,
    );
  }

  @override
  Future<PlaybackSession> createPlaybackSession({
    required String itemId,
    JellyfinVideoQuality? quality,
    int? startPositionMs,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool burnInSubtitle = false,
    String? playSessionId,
    String? mediaSourceId,
  }) async {
    if (!_isConnected || _accessToken == null || _userId == null) {
      throw Exception('未连接到Emby服务器');
    }

    final effectiveQuality = quality ??
        (transcodeEnabledCache
            ? defaultQualityCache
            : JellyfinVideoQuality.original);

    if (!transcodeEnabledCache) {
      final resolvedPlaySessionId = playSessionId?.isNotEmpty == true
          ? playSessionId
          : _generateLocalPlaySessionId(itemId);
      final resolvedMediaSourceId =
          (mediaSourceId?.isNotEmpty ?? false) ? mediaSourceId! : itemId;
      final directUrl = _buildDirectPlayUrl(
        itemId,
        mediaSourceId: resolvedMediaSourceId,
        playSessionId: resolvedPlaySessionId,
      );
      return PlaybackSession(
        itemId: itemId,
        mediaSourceId: resolvedMediaSourceId,
        playSessionId: resolvedPlaySessionId,
        streamUrl: directUrl,
        isTranscoding: false,
      );
    }

    final enableTranscoding = transcodeEnabledCache &&
      effectiveQuality != JellyfinVideoQuality.original;
    final maxStreamingBitrate =
      enableTranscoding ? effectiveQuality.bitrate : null;
    final resolvedPlaySessionId = playSessionId;

    final deviceProfile = PlaybackDeviceProfileBuilder.build(
      deviceName: 'NipaPlay',
      settings: transcodeSettingsCache,
    );

    final request = <String, dynamic>{
      'DeviceProfile': deviceProfile.toJson(),
      'UserId': _userId,
      'EnableDirectPlay': true,
      'EnableDirectStream': true,
      'EnableTranscoding': enableTranscoding,
    };
    if (maxStreamingBitrate != null) {
      request['MaxStreamingBitrate'] = maxStreamingBitrate * 1000;
    }
    if (startPositionMs != null && startPositionMs > 0) {
      request['StartTimeTicks'] = (startPositionMs * 10000).round();
    }
    if (audioStreamIndex != null) {
      request['AudioStreamIndex'] = audioStreamIndex;
    }
    if (enableTranscoding) {
      if (subtitleStreamIndex != null) {
        request['SubtitleStreamIndex'] = subtitleStreamIndex;
      }
      final subtitleMethod = _resolveSubtitleMethod(
        enableTranscoding: enableTranscoding,
        subtitleStreamIndex: subtitleStreamIndex,
        burnInSubtitle: burnInSubtitle,
      );
      if (subtitleMethod != null && subtitleMethod.isNotEmpty) {
        request['SubtitleMethod'] = subtitleMethod;
      }
    }
    if (resolvedPlaySessionId != null && resolvedPlaySessionId.isNotEmpty) {
      request['PlaySessionId'] = resolvedPlaySessionId;
    }
    if (mediaSourceId != null && mediaSourceId.isNotEmpty) {
      request['MediaSourceId'] = mediaSourceId;
    }

    final response = await _makeAuthenticatedRequest(
      '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId',
      method: 'POST',
      body: request,
    );

    final data = json.decode(response.body) as Map<String, dynamic>;
    return _buildPlaybackSessionFromResponse(
      itemId: itemId,
      data: data,
      preferTranscoding: enableTranscoding,
      forceDirectPlay: false,
      forcedPlaySessionId: resolvedPlaySessionId,
      requestedMediaSourceId: mediaSourceId,
    );
  }

  @override
  Future<PlaybackSession> refreshPlaybackSession(
    PlaybackSession session, {
    JellyfinVideoQuality? quality,
    int? startPositionMs,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool burnInSubtitle = false,
  }) {
    return createPlaybackSession(
      itemId: session.itemId,
      quality: quality,
      startPositionMs: startPositionMs,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      burnInSubtitle: burnInSubtitle,
      playSessionId: session.playSessionId,
      mediaSourceId: session.mediaSourceId,
    );
  }

  PlaybackSession _buildPlaybackSessionFromResponse({
    required String itemId,
    required Map<String, dynamic> data,
    required bool preferTranscoding,
    required bool forceDirectPlay,
    String? forcedPlaySessionId,
    String? requestedMediaSourceId,
  }) {
    final playSessionId =
      forcedPlaySessionId ?? data['PlaySessionId']?.toString();
    final rawSources = data['MediaSources'];
    final sources = <PlaybackMediaSource>[];
    if (rawSources is List) {
      for (final source in rawSources) {
        if (source is Map) {
          sources.add(
            PlaybackMediaSource.fromJson(Map<String, dynamic>.from(source)),
          );
        }
      }
    }

    PlaybackMediaSource? selected;
    if (requestedMediaSourceId != null && requestedMediaSourceId.isNotEmpty) {
      for (final source in sources) {
        if (source.id == requestedMediaSourceId) {
          selected = source;
          break;
        }
      }
    }
    selected ??= sources.isNotEmpty ? sources.first : null;

    final directStreamUrl = selected?.directStreamUrl;
    final transcodingUrl = selected?.transcodingUrl;

    bool useTranscoding = false;
    String? chosenUrl;
    if (!forceDirectPlay && transcodingUrl != null && transcodingUrl.isNotEmpty) {
      if (preferTranscoding ||
          directStreamUrl == null ||
          directStreamUrl.isEmpty) {
        useTranscoding = true;
        chosenUrl = transcodingUrl;
      }
    }
    chosenUrl ??= directStreamUrl;

    final resolvedUrl = (chosenUrl != null && chosenUrl.isNotEmpty)
        ? _resolvePlaybackUrl(chosenUrl)
        : _buildDirectPlayUrl(
            itemId,
            mediaSourceId: selected?.id,
            playSessionId: playSessionId,
          );

    if (chosenUrl == null || chosenUrl.isEmpty) {
      useTranscoding = false;
    }

    return PlaybackSession(
      itemId: itemId,
      mediaSourceId: selected?.id,
      playSessionId: playSessionId,
      streamUrl: resolvedUrl,
      isTranscoding: useTranscoding,
      transcodingProtocol: selected?.transcodingSubProtocol,
      transcodingContainer: selected?.transcodingContainer,
      mediaSources: sources,
      selectedSource: selected,
    );
  }

  String _generateLocalPlaySessionId(String itemId) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'nipaplay_${timestamp}_$itemId';
  }

  String _resolvePlaybackUrl(String url) {
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return url;
    }
    final normalized = url.startsWith('/') ? url : '/$url';
    return '$_serverUrl$normalized';
  }

  String? _resolveSubtitleMethod({
    required bool enableTranscoding,
    int? subtitleStreamIndex,
    bool burnInSubtitle = false,
  }) {
    if (!enableTranscoding) {
      return null;
    }
    if (subtitleStreamIndex != null) {
      return burnInSubtitle ? 'Encode' : 'Embed';
    }

    if (!transcodeSettingsCache.subtitle.enableTranscoding) {
      return null;
    }
    final delivery = transcodeSettingsCache.subtitle.deliveryMethod;
    if (delivery == JellyfinSubtitleDeliveryMethod.external ||
        delivery == JellyfinSubtitleDeliveryMethod.drop) {
      return null;
    }
    return delivery.apiValue;
  }

  /// 构建直连URL（不转码）
  String _buildDirectPlayUrl(
    String itemId, {
    String? mediaSourceId,
    String? playSessionId,
  }) {
    final params = <String, String>{
      'Static': 'true',
      if (mediaSourceId != null && mediaSourceId.isNotEmpty)
        'MediaSourceId': mediaSourceId,
      if (playSessionId != null && playSessionId.isNotEmpty)
        'PlaySessionId': playSessionId,
      if (_accessToken != null) 'api_key': _accessToken!,
    };
    final uri = Uri.parse('$_serverUrl/emby/Videos/$itemId/stream')
        .replace(queryParameters: params);
    return uri.toString();
  }

  /// 构建转码URL（HLS 使用 master.m3u8，尽量同步生成，必要参数使用约定填充）
  /// 说明：为保持同步调用，此处不请求 PlaybackInfo；在多数 Emby 环境下可以正常工作。
  /// 若遇到个别服务器需要 MediaSourceId/PlaySessionId，可通过 UI 切换质量时的异步 buildHlsUrlWithOptions 获得更稳妥的 URL。
  String _buildTranscodeUrlSync(
    String itemId,
    JellyfinVideoQuality? quality, {
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
  }) {
    // original 或未指定 -> 直连
    if (quality == null || quality == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      // HLS 分片容器
      'Container': 'ts',
      // 尝试传递 MediaSourceId 为 itemId（大多数情况下等同）以避免服务器端 mediaSource 为空
      'MediaSourceId': itemId,
    };

    // 添加常规转码参数（码率/分辨率/编解码器/音频限制/字幕处理）
    _addTranscodeParameters(
      params,
      quality,
      subtitleStreamIndex: subtitleStreamIndex,
      burnInSubtitle: burnInSubtitle,
    );

    final uri = Uri.parse('$_serverUrl/emby/Videos/$itemId/master.m3u8')
        .replace(queryParameters: params);
    debugPrint('[Emby HLS(sync)] 构建URL: ${uri.toString()}');
    return uri.toString();
  }

  /// 构建 Emby HLS URL（带可选的服务器端字幕选择与烧录开关）
  /// 说明：与 Jellyfin 复用同一枚举 JellyfinVideoQuality，便于 UI 统一。
  Future<String> buildHlsUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    int? subtitleStreamIndex,
    bool alwaysBurnInSubtitleWhenTranscoding = false,
  }) async {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Emby服务器');
    }

    final effectiveQuality = quality ?? JellyfinVideoQuality.bandwidth5m;

    // original => 直连
    if (effectiveQuality == JellyfinVideoQuality.original) {
      return getStreamUrl(itemId);
    }

    // 先获取 PlaybackInfo，拿到 MediaSourceId & PlaySessionId
    String? mediaSourceId;
    String? playSessionId;
    try {
      final playbackInfoResp = await _makeAuthenticatedRequest(
        '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId',
      );
      if (playbackInfoResp.statusCode == 200) {
        final pb = json.decode(playbackInfoResp.body) as Map<String, dynamic>;
        final srcs = (pb['MediaSources'] as List?) ?? const [];
        if (srcs.isNotEmpty) {
          final first = srcs.first as Map<String, dynamic>;
          mediaSourceId = first['Id']?.toString();
        }
        playSessionId = pb['PlaySessionId']?.toString();
      }
    } catch (e) {
      DebugLogService().addLog('Emby HLS: 获取PlaybackInfo失败: $e');
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      // Emby 对 master.m3u8 接口的典型参数
      'Container': 'ts', // HLS 分片容器
      if (mediaSourceId != null && mediaSourceId.isNotEmpty)
        'MediaSourceId': mediaSourceId,
      if (playSessionId != null && playSessionId.isNotEmpty)
        'PlaySessionId': playSessionId,
    };

    _addTranscodeParameters(params, effectiveQuality);

    // 字幕参数
    if (subtitleStreamIndex != null) {
      params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
      if (alwaysBurnInSubtitleWhenTranscoding) {
        params['SubtitleMethod'] = 'Encode'; // 烧录
        params['EnableAutoStreamCopy'] = 'false';
      } else {
        params['SubtitleMethod'] = 'Embed'; // 内嵌为独立轨
      }
    }

    final uri = Uri.parse('$_serverUrl/emby/Videos/$itemId/master.m3u8')
        .replace(queryParameters: params);
    debugPrint('[Emby HLS] 构建URL: ${uri.toString()}');
    return uri.toString();
  }

  /// 为 Emby 添加转码参数（注意参数名大小写与 Jellyfin 不同）
  void _addTranscodeParameters(
      Map<String, String> params, JellyfinVideoQuality quality,
      {int? subtitleStreamIndex, bool? burnInSubtitle}) {
    final bitrate = quality.bitrate;
    final resolution = quality.maxResolution;

    if (bitrate != null) {
      params['MaxStreamingBitrate'] = (bitrate * 1000).toString();
      params['VideoBitRate'] = (bitrate * 1000).toString();
    }

    if (resolution != null) {
      params['MaxWidth'] = resolution.width.toString();
      params['MaxHeight'] = resolution.height.toString();
    }

    // 从本地设置缓存读取编解码偏好，若未配置使用合理默认
    final videoCodecs = transcodeSettingsCache.video.preferredCodecs.isNotEmpty
        ? transcodeSettingsCache.video.preferredCodecs.join(',')
        : 'h264,hevc,av1';
    final audioCodecs = transcodeSettingsCache.audio.preferredCodecs.isNotEmpty
        ? transcodeSettingsCache.audio.preferredCodecs.join(',')
        : 'aac,mp3,opus';
    params['VideoCodec'] = videoCodecs;
    params['AudioCodec'] = audioCodecs;

    // 音频限制
    if (transcodeSettingsCache.audio.maxAudioChannels > 0) {
      params['MaxAudioChannels'] =
          transcodeSettingsCache.audio.maxAudioChannels.toString();
    }
    if (transcodeSettingsCache.audio.audioBitRate != null &&
        transcodeSettingsCache.audio.audioBitRate! > 0) {
      params['AudioBitRate'] =
          (transcodeSettingsCache.audio.audioBitRate! * 1000).toString();
    }
    if (transcodeSettingsCache.audio.audioSampleRate != null &&
        transcodeSettingsCache.audio.audioSampleRate! > 0) {
      params['AudioSampleRate'] =
          transcodeSettingsCache.audio.audioSampleRate!.toString();
    }

    // 字幕处理：如果设置允许服务端处理并非 external/drop，则添加相应参数
    if (transcodeSettingsCache.subtitle.enableTranscoding &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.external &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.drop) {
      params['SubtitleMethod'] =
          transcodeSettingsCache.subtitle.deliveryMethod.apiValue;
      if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
        params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
      }
      final shouldBurn = burnInSubtitle ??
          (transcodeSettingsCache.subtitle.deliveryMethod ==
              JellyfinSubtitleDeliveryMethod.encode);
      if (shouldBurn) {
        params['AlwaysBurnInSubtitleWhenTranscoding'] = 'true';
      }
    }

    // 保证参数整洁
    try {
      if (params['MaxStreamingBitrate']?.isEmpty == true)
        params.remove('MaxStreamingBitrate');
      if (params['MaxWidth'] == '0' || params['MaxHeight'] == '0') {
        params.remove('MaxWidth');
        params.remove('MaxHeight');
      }
    } catch (e) {
      debugPrint('添加 Emby 转码参数时出错: $e');
      params.removeWhere(
          (key, value) => key.startsWith('Max') || key.contains('BitRate'));
    }
  }

  String getImageUrl(String itemId,
      {String type = 'Primary',
      int? width,
      int? height,
      int? quality,
      String? tag}) {
    if (!_isConnected) {
      return '';
    }

    final queryParams = <String, String>{};

    if (width != null)
      queryParams['maxWidth'] = width.toString(); // Emby 使用 maxWidth/maxHeight
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

    final queryString = queryParams.isNotEmpty
        ? '?${queryParams.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    return '$_serverUrl/emby/Items/$itemId/Images/$imagePathSegment$queryString';
  }

  /// 下载指定 Emby 媒体的图片，供本地缩略图缓存使用。
  Future<List<int>?> downloadItemImage(
    String itemId, {
    String type = 'Primary',
    int? width,
    int? height,
    int? quality,
    String? tag,
  }) async {
    if (kIsWeb || !_isConnected || _accessToken == null) {
      return null;
    }

    final params = <String, String>{};
    if (width != null) params['maxWidth'] = width.toString();
    if (height != null) params['maxHeight'] = height.toString();
    if (quality != null) params['quality'] = quality.toString();
    if (tag != null && tag.isNotEmpty) params['tag'] = tag;
    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';

    try {
      final response = await _makeAuthenticatedRequest(
        '/emby/Items/$itemId/Images/$type$query',
        timeout: const Duration(seconds: 20),
      );
      return response.bodyBytes;
    } catch (e) {
      DebugLogService().addLog('EmbyService: 下载图片失败 ($itemId): $e');
      return null;
    }
  }

  // 获取媒体文件信息（用于哈希计算）
  Future<Map<String, dynamic>?> getMediaFileInfo(String itemId) async {
    try {
      // 首先尝试获取媒体源信息
      final response = await _makeAuthenticatedRequest(
          '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId');

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
      final itemResponse =
          await _makeAuthenticatedRequest('/emby/Items/$itemId');

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

  /// 搜索媒体库中的内容
  /// [searchTerm] 搜索关键词
  /// [includeItemTypes] 包含的项目类型 (Series, Movie, Episode等)
  /// [limit] 结果数量限制
  /// [parentId] 父级媒体库ID (可选，用于限制在特定媒体库中搜索)
  Future<List<EmbyMediaItem>> searchMediaItems(
    String searchTerm, {
    List<String>? includeItemTypes,
    int limit = 50,
    String? parentId,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty || _userId == null) {
      return [];
    }

    try {
      // 构建查询参数
      final queryParams = <String, String>{
        'SearchTerm': searchTerm.trim(),
        'IncludeItemTypes': (includeItemTypes ?? ['Series', 'Movie']).join(','),
        'Recursive': 'true',
        'Limit': limit.toString(),
        'Fields':
            'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear',
      };

      // 如果指定了父级媒体库，则只在该媒体库中搜索
      if (parentId != null) {
        queryParams['ParentId'] = parentId;
      } else {
        // 如果没有指定，则在所有选中的媒体库中搜索
        if (_selectedLibraryIds.isNotEmpty) {
          queryParams['ParentId'] = _selectedLibraryIds.join(',');
        }
      }

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final results =
            items.map((item) => EmbyMediaItem.fromJson(item)).toList();

        debugPrint('[EmbyService] 搜索 "$searchTerm" 找到 ${results.length} 个结果');
        return results;
      } else {
        debugPrint('[EmbyService] 搜索失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[EmbyService] 搜索出错: $e');
      return [];
    }
  }

  /// 在特定媒体库中搜索
  Future<List<EmbyMediaItem>> searchInLibrary(
    String libraryId,
    String searchTerm, {
    int limit = 50,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty || _userId == null) {
      return [];
    }

    try {
      // 首先获取媒体库信息以确定类型
      final libraryResponse = await _makeAuthenticatedRequest(
          '/emby/Users/$_userId/Items/$libraryId');

      if (libraryResponse.statusCode != 200) {
        return [];
      }

      final libraryData = json.decode(libraryResponse.body);
      final String collectionType =
          _resolveCollectionType(libraryData['CollectionType']);

      // 根据媒体库类型选择不同的IncludeItemTypes
      List<String> includeItemTypes;
      if (collectionType == 'tvshows') {
        includeItemTypes = ['Series'];
      } else if (collectionType == 'movies') {
        includeItemTypes = ['Movie'];
      } else if (collectionType == 'mixed') {
        includeItemTypes = ['Folder', 'Series', 'Season', 'Episode', 'Movie', 'Video'];
      } else {
        includeItemTypes = ['Folder', 'Series', 'Season', 'Episode', 'Movie', 'Video'];
      }

      return await searchMediaItems(
        searchTerm,
        includeItemTypes: includeItemTypes,
        limit: limit,
        parentId: libraryId,
      );
    } catch (e) {
      debugPrint('[EmbyService] 在媒体库 $libraryId 中搜索出错: $e');
      return [];
    }
  }

  /// 获取Emby视频的字幕轨道信息，包括内嵌字幕和外挂字幕
  Future<List<Map<String, dynamic>>> getSubtitleTracks(String itemId) async {
    if (!_isConnected) {
      throw Exception('未连接到Emby服务器');
    }
    try {
      // 获取播放信息，包含媒体源和字幕轨道
      final response = await _makeAuthenticatedRequest(
          '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId');
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
            final realIndex = stream['Index'] ?? i;
            final displayParts = <String>[];
            if ((title as String).isNotEmpty) {
              displayParts.add(title);
            } else if ((language as String).isNotEmpty) {
              displayParts.add(language);
            } else {
              displayParts.add('字幕');
            }
            if ((codec as String).isNotEmpty)
              displayParts.add(codec.toString().toUpperCase());
            if (isExternal) displayParts.add('外挂');
            if (isForced) displayParts.add('强制');
            if (isDefault) displayParts.add('默认');
            Map<String, dynamic> trackInfo = {
              'index': realIndex,
              'type': isExternal ? 'external' : 'embedded',
              'language': language,
              'title': title.isNotEmpty
                  ? title
                  : (language.isNotEmpty ? language : 'Unknown'),
              'codec': codec,
              'isDefault': isDefault,
              'isForced': isForced,
              'isHearingImpaired': isHearingImpaired,
              'deliveryMethod': deliveryMethod,
              'display': displayParts.join(' · '),
            };
            // 如果是外挂字幕，添加下载URL
            if (isExternal) {
              final mediaSourceId = mediaSource['Id'];
              final subtitleUrl =
                  '$_serverUrl/emby/Videos/$itemId/$mediaSourceId/Subtitles/$realIndex/Stream.$codec?api_key=$_accessToken';
              trackInfo['downloadUrl'] = subtitleUrl;
            }
            subtitleTracks.add(trackInfo);
            debugPrint(
                'EmbyService: 找到字幕轨道 $i: ${trackInfo['title']} (${trackInfo['type']})');
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

  String _resolveCollectionType(dynamic rawType) {
    final value = rawType?.toString().trim();
    if (value == null || value.isEmpty) {
      return 'mixed';
    }
    return value.toLowerCase();
  }

  /// 下载Emby外挂字幕文件
  Future<String?> downloadSubtitleFile(
      String itemId, int subtitleIndex, String format) async {
    if (kIsWeb) return null;
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Emby服务器');
    }
    try {
      // 获取媒体源ID
      final playbackInfoResponse = await _makeAuthenticatedRequest(
          '/emby/Items/$itemId/PlaybackInfo?UserId=$_userId');
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
      final subtitleUrl =
          '$_serverUrl/emby/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format?api_key=$_accessToken';
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
        debugPrint(
            'EmbyService: 下载字幕文件失败: HTTP ${subtitleResponse.statusCode}');
        return null;
      }
    } catch (e, stackTrace) {
      debugPrint('EmbyService: 下载字幕文件时出错: $e');
      print('Stack trace: $stackTrace');
      return null;
    }
  }
}

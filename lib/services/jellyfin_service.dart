import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/jellyfin_model.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:path_provider/path_provider.dart'
    if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'debug_log_service.dart';
import '../models/jellyfin_transcode_settings.dart';
import 'jellyfin_transcode_manager.dart';
import 'media_server_service_base.dart';

class JellyfinService extends MediaServerServiceBase {
  static final JellyfinService instance = JellyfinService._internal();

  JellyfinService._internal();

  String? _serverUrl;
  String? _username;
  String? _password;
  String? _accessToken;
  String? _userId;
  bool _isConnected = false;
  bool _isReady = false;
  List<JellyfinLibrary> _availableLibraries = [];
  List<String> _selectedLibraryIds = [];
  ServerProfile? _currentProfile;
  String? _currentAddressId;

  @override
  String get serviceName => 'Jellyfin';

  @override
  String get serviceType => 'jellyfin';

  @override
  String get prefsKeyPrefix => 'jellyfin';

  @override
  String get serverNameFallback => 'Jellyfin服务器';

  @override
  String get notConnectedMessage => '未连接到Jellyfin服务器';

  @override
  String normalizeRequestPath(String path) {
    if (path.isEmpty) return '';
    final trimmed = path.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  @override
  Future<bool> testConnection(String url, String username, String password) =>
      _testJellyfinConnection(url, username, password);

  @override
  Future<void> performAuthentication(
          String serverUrl, String username, String password) =>
      _performAuthentication(serverUrl, username, password);

  @override
  Future<String> getServerId(String url) => _getJellyfinServerId(url);

  @override
  Future<String?> getServerName(String url) => _getServerName(url);

  @override
  Future<void> loadTranscodeSettings() async {
    try {
      final transMgr = JellyfinTranscodeManager.instance;
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
          'Jellyfin: 已加载转码偏好 缓存 enabled=$enabled, quality=$quality');
    } catch (e) {
      DebugLogService().addLog('Jellyfin: 加载转码偏好失败，使用默认值: $e');
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
  /// 返回统一结构：
  /// {
  ///   'container': String?,
  ///   'video': {
  ///      'codec': String?, 'profile': String?, 'level': String?, 'bitDepth': int?,
  ///      'width': int?, 'height': int?, 'frameRate': num?, 'bitRate': int?,
  ///      'pixelFormat': String?, 'colorSpace': String?, 'colorTransfer': String?, 'colorPrimaries': String?,
  ///      'dynamicRange': String?
  ///   },
  ///   'audio': {
  ///      'codec': String?, 'channels': int?, 'channelLayout': String?,
  ///      'sampleRate': int?, 'bitRate': int?, 'language': String?
  ///   }
  /// }
  Future<Map<String, dynamic>> getServerMediaTechnicalInfo(
      String itemId) async {
    if (!_isConnected) {
      return {};
    }

    final Map<String, dynamic> result = {
      'container': null,
      'video': <String, dynamic>{},
      'audio': <String, dynamic>{},
    };

    try {
      // 1) 优先获取 PlaybackInfo，包含 MediaSources 与 MediaStreams（技术细节更全）
      final playbackResp = await _makeAuthenticatedRequest(
        '/Items/$itemId/PlaybackInfo?userId=$_userId',
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

      // 2) 补充 Items 详情（可能带有 VideoRange 等目录级字段）
      Map<String, dynamic>? itemDetail;
      try {
        final itemResp =
            await _makeAuthenticatedRequest('/Users/$_userId/Items/$itemId');
        if (itemResp.statusCode == 200) {
          itemDetail = Map<String, dynamic>.from(json.decode(itemResp.body));
        }
      } catch (_) {}

      // 组装 video 信息
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

      // 组装 audio 信息
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
      DebugLogService().addLog('JellyfinService: 获取媒体技术元数据失败: $e');
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
  List<JellyfinLibrary> get availableLibraries => _availableLibraries;
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

  /// 测试Jellyfin连接
  Future<bool> _testJellyfinConnection(
      String url, String username, String password) async {
    try {
      // 获取服务器信息
      final configResponse = await http
          .get(
            Uri.parse('$url/System/Info/Public'),
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
      Uri.parse('$serverUrl/Users/AuthenticateByName'),
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

  /// 获取Jellyfin服务器ID，如果无法获取将抛出异常
  Future<String> _getJellyfinServerId(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/System/Info/Public'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Id'] ?? data['ServerId'];
      }
      // 在HTTP状态码不为200时抛出详细错误
      throw Exception(
          '获取Jellyfin服务器ID失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    } catch (e) {
      DebugLogService().addLog('获取Jellyfin服务器ID失败: $e');
      // 重新抛出异常，以便 identifyServer 捕获并返回详细错误
      rethrow;
    }
  }

  /// 获取服务器名称
  Future<String?> _getServerName(String url) async {
    try {
      final response = await http
          .get(
            Uri.parse('$url/System/Info/Public'),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ServerName'];
      }
    } catch (e) {
      DebugLogService().addLog('获取Jellyfin服务器名称失败: $e');
    }
    return null;
  }

  @override
  Future<void> loadAvailableLibraries() async {
    if (kIsWeb || !_isConnected || _userId == null) return;

    try {
      final response =
          await _makeAuthenticatedRequest('/UserViews?userId=$_userId');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        List<JellyfinLibrary> tempLibraries = [];
        for (var item in items) {
          final String collectionType =
              _resolveCollectionType(item['CollectionType']);
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
              type: collectionType,
              imageTagsPrimary: item['ImageTags']
                  ?['Primary'], // Safely access ImageTags
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

  // 获取媒体库或文件夹下的子项（用于混合类型文件夹导航）
  Future<List<JellyfinMediaItem>> getFolderItems(
    String parentId, {
    int limit = 99999,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected) {
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
        'userId': _userId ?? '',
      };

      final queryString = queryParams.entries
          .map((e) => '${e.key}=${Uri.encodeComponent(e.value)}')
          .join('&');

      final response = await _makeAuthenticatedRequest('/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final results = items
            .map((item) => JellyfinMediaItem.fromJson(item))
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
  Future<List<JellyfinMediaItem>> getLatestMediaItemsByLibrary(
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
          '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&userId=$_userId&Fields=Overview,CommunityRating');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        return items.map((item) => JellyfinMediaItem.fromJson(item)).toList();
      }
    } catch (e) {
      debugPrint('Error fetching media items for library $libraryId: $e');
    }

    return [];
  }

  // 按特定媒体库获取随机内容
  Future<List<JellyfinMediaItem>> getRandomMediaItemsByLibrary(
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

      // 使用Jellyfin的随机排序获取随机内容，并请求Overview字段
      final response = await _makeAuthenticatedRequest(
          '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=Random&Limit=$limit&userId=$_userId&Fields=Overview,CommunityRating');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'];

        return items.map((item) => JellyfinMediaItem.fromJson(item)).toList();
      }
    } catch (e) {
      print('Error fetching random media items for library $libraryId: $e');
    }

    return [];
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

    print(
        'JellyfinService: 获取媒体项 - sortBy: $defaultSortBy, sortOrder: $defaultSortOrder');

    List<JellyfinMediaItem> allItems = [];

    // 从每个选中的媒体库获取最新内容
    for (String libraryId in _selectedLibraryIds) {
      try {
        // 首先获取媒体库信息以确定类型
        final libraryResponse =
            await _makeAuthenticatedRequest('/Users/$_userId/Items/$libraryId');

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

          final response = await _makeAuthenticatedRequest(
              '/Items?ParentId=$libraryId&IncludeItemTypes=$includeItemTypes&Recursive=true&SortBy=$defaultSortBy&SortOrder=$defaultSortOrder&Limit=$limit&userId=$_userId');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final List<dynamic> items = data['Items'];

            List<JellyfinMediaItem> libraryItems =
                items.map((item) => JellyfinMediaItem.fromJson(item)).toList();

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
            '/Items?ParentId=$libraryId&IncludeItemTypes=Movie&Recursive=true&SortBy=DateCreated,SortName&SortOrder=Descending&Limit=$limit&userId=$_userId');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final List<dynamic> items = data['Items'];

          List<JellyfinMovieInfo> libraryMovies =
              items.map((item) => JellyfinMovieInfo.fromJson(item)).toList();

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

  /// 获取服务器 resume 列表，用于同步播放进度。
  Future<List<Map<String, dynamic>>> fetchResumeItems({int limit = 5}) async {
    if (kIsWeb) return [];
    if (!_isConnected || _userId == null) {
      return [];
    }

    final buffer = StringBuffer('/Users/$_userId/Items/Resume?userId=$_userId');
    buffer.write('&IncludeItemTypes=Episode,Movie');
    buffer.write('&Limit=$limit');
    buffer.write(
      '&Fields=RunTimeTicks,SeriesName,SeasonName,IndexNumber,ParentId,ImageTags',
    );

    try {
      final response = await _makeAuthenticatedRequest(buffer.toString());
      if (response.statusCode != 200) {
        DebugLogService().addLog(
          'JellyfinService: 获取 resume 列表失败，HTTP ${response.statusCode}',
        );
        return [];
      }

      final decoded = json.decode(response.body) as Map<String, dynamic>;
      final items = decoded['Items'];
      if (items is List) {
        return items.whereType<Map<String, dynamic>>().toList(growable: false);
      }
    } catch (e, stack) {
      DebugLogService().addLog('JellyfinService: 获取 resume 列表异常: $e\n$stack');
    }

    return [];
  }

  // 获取电影详情
  Future<JellyfinMovieInfo?> getMovieDetails(String movieId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      final response =
          await _makeAuthenticatedRequest('/Users/$_userId/Items/$movieId');

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

    final response =
        await _makeAuthenticatedRequest('/Users/$_userId/Items/$itemId');

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
        '/Shows/$seriesId/Seasons?userId=$_userId');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];

      List<JellyfinSeasonInfo> seasons =
          items.map((item) => JellyfinSeasonInfo.fromJson(item)).toList();

      // 按季节编号排序
      seasons.sort((a, b) => a.indexNumber?.compareTo(b.indexNumber ?? 0) ?? 0);

      return seasons;
    } else {
      throw Exception('无法获取剧集季信息');
    }
  }

  Future<List<JellyfinEpisodeInfo>> getSeasonEpisodes(
      String seriesId, String seasonId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    final response = await _makeAuthenticatedRequest(
        '/Shows/$seriesId/Episodes?userId=$_userId&seasonId=$seasonId');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> items = data['Items'];

      List<JellyfinEpisodeInfo> episodes =
          items.map((item) => JellyfinEpisodeInfo.fromJson(item)).toList();

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

  // 获取单个剧集的详细信息
  Future<JellyfinEpisodeInfo?> getEpisodeDetails(String episodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      final response =
          await _makeAuthenticatedRequest('/Users/$_userId/Items/$episodeId');

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
      final response = await _makeAuthenticatedRequest('/Items/$itemId/File');

      final contentType = response.headers['content-type'];
      bool isJsonResponse = contentType != null &&
          (contentType.contains('application/json') ||
              contentType.contains('text/json'));

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
        debugPrint(
            '媒体文件信息API响应 (non-JSON, status 200): Content-Type: $contentType. 将回退。');
        // 表明端点返回了文件本身，而不是元数据。
        // 无法从此获取文件名/文件大小，因此我们将继续回退。
      } else if (response.statusCode != 200) {
        debugPrint('媒体文件信息API请求失败: HTTP ${response.statusCode}. 将回退。');
      }
      // 如果File接口无法获取有效信息，尝试使用普通的Items接口
      final itemResponse =
          await _makeAuthenticatedRequest('/Users/$_userId/Items/$itemId');

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
  Future<List<JellyfinEpisodeInfo>> getAdjacentEpisodes(
      String currentEpisodeId) async {
    if (!_isConnected) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 使用adjacentTo参数获取相邻剧集，限制3个结果（上一集、当前集、下一集）
      final response = await _makeAuthenticatedRequest(
          '/Items?adjacentTo=$currentEpisodeId&limit=3&fields=Overview,MediaSources');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final episodes =
            items.map((item) => JellyfinEpisodeInfo.fromJson(item)).toList();

        // 按集数排序确保顺序正确
        episodes
            .sort((a, b) => (a.indexNumber ?? 0).compareTo(b.indexNumber ?? 0));

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
    final currentIndex =
        adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);

    if (currentIndex != -1 && currentIndex < adjacentEpisodes.length - 1) {
      final nextEpisode = adjacentEpisodes[currentIndex + 1];
      debugPrint('[JellyfinService] 找到下一集: ${nextEpisode.name}');
      return nextEpisode;
    }

    debugPrint('[JellyfinService] 没有找到下一集');
    return null;
  }

  /// 简单获取上一集（不依赖弹幕映射）
  Future<JellyfinEpisodeInfo?> getPreviousEpisode(
      String currentEpisodeId) async {
    final adjacentEpisodes = await getAdjacentEpisodes(currentEpisodeId);

    if (adjacentEpisodes.isEmpty) return null;

    // 找到当前剧集的位置
    final currentIndex =
        adjacentEpisodes.indexWhere((ep) => ep.id == currentEpisodeId);

    if (currentIndex > 0) {
      final previousEpisode = adjacentEpisodes[currentIndex - 1];
      debugPrint('[JellyfinService] 找到上一集: ${previousEpisode.name}');
      return previousEpisode;
    }

    debugPrint('[JellyfinService] 没有找到上一集');
    return null;
  }

  // 获取流媒体URL（向后兼容的方法）
  String getStreamUrl(String itemId) {
    // 使用缓存的转码设置决定默认质量
    final effectiveQuality = transcodeEnabledCache
        ? defaultQualityCache
        : JellyfinVideoQuality.original;
    return getStreamUrlWithOptions(itemId, quality: effectiveQuality);
  }

  /// 获取流媒体URL，支持转码选项
  /// [itemId] 媒体项目ID
  /// [quality] 指定的视频质量，为null时使用用户默认设置
  /// [forceDirectPlay] 是否强制直播（不转码）
  String getStreamUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    bool forceDirectPlay = false,
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
  }) {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    // 如果强制直播，返回直播URL
    if (forceDirectPlay) {
      return _buildDirectPlayUrl(itemId);
    }

    // 若未显式传入quality，则使用缓存设置
    final effective = quality ??
        (transcodeEnabledCache
            ? defaultQualityCache
            : JellyfinVideoQuality.original);

    // 构建转码/直连URL
    return _buildTranscodeUrl(itemId, effective,
        subtitleStreamIndex: subtitleStreamIndex,
        burnInSubtitle: burnInSubtitle);
  }

  /// 构建直播URL（不转码）
  String _buildDirectPlayUrl(String itemId) {
    return '$_serverUrl/Videos/$itemId/stream?static=true&MediaSourceId=$itemId&api_key=$_accessToken';
  }

  /// 构建转码URL（HLS 使用 master.m3u8）
  String _buildTranscodeUrl(String itemId, JellyfinVideoQuality? quality,
      {int? subtitleStreamIndex, bool? burnInSubtitle}) {
    // 如果质量为 original 或未指定，使用直连
    if (quality == null || quality == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      // HLS master.m3u8 需要 MediaSourceId（大多数情况下与 itemId 相同）
      'MediaSourceId': itemId,
      // 指定分片容器，Jellyfin 默认 HLS TS 更通用
      'segmentContainer': 'ts',
    };

    // 添加转码参数（码率/分辨率/编解码器等）
    _addTranscodeParameters(params, quality,
        subtitleStreamIndex: subtitleStreamIndex,
        burnInSubtitle: burnInSubtitle);

    // 使用 HLS master.m3u8 入口
    final uri = Uri.parse('$_serverUrl/Videos/$itemId/master.m3u8')
        .replace(queryParameters: params);
    debugPrint('Jellyfin HLS 转码URL: $uri');
    return uri.toString();
  }

  /// 构建 HLS URL（带可选的服务器端字幕选择与烧录开关）
  /// 注意：不影响外挂字幕下载/加载逻辑，仅在服务端转码时让服务器选定字幕轨道或进行烧录。
  Future<String> buildHlsUrlWithOptions(
    String itemId, {
    JellyfinVideoQuality? quality,
    int? subtitleStreamIndex,
    bool alwaysBurnInSubtitleWhenTranscoding = false,
  }) async {
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    // original => 直连
    if ((quality ?? defaultQualityCache) == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    final params = <String, String>{
      'api_key': _accessToken!,
      'mediaSourceId': itemId, // 修正参数名
      'segmentContainer': 'ts',
    };

    // 画质/编解码参数
    _addTranscodeParameters(params, quality ?? defaultQualityCache);

    // 字幕参数：如果用户明确选择了服务器字幕，则强制添加字幕参数
    if (subtitleStreamIndex != null) {
      params['subtitleStreamIndex'] = subtitleStreamIndex.toString();
      // 根据用户选择决定字幕处理方式
      if (alwaysBurnInSubtitleWhenTranscoding) {
        params['subtitleMethod'] = 'Encode'; // 烧录字幕到视频中
        params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
        // 强制转码以确保字幕烧录
        params['allowVideoStreamCopy'] = 'false'; // 禁止视频流直传
      } else {
        params['subtitleMethod'] = 'Embed'; // 嵌入字幕作为独立轨道
      }
      // 不设置subtitleCodec，让服务器自动处理
      // PGSSUB等图形字幕需要服务器自动选择合适的输出格式
    } else {
      // 用户未选择特定字幕，使用默认设置
      final delivery = transcodeSettingsCache.subtitle.deliveryMethod;
      if (transcodeSettingsCache.subtitle.enableTranscoding &&
          delivery != JellyfinSubtitleDeliveryMethod.external &&
          delivery != JellyfinSubtitleDeliveryMethod.drop) {
        params['subtitleMethod'] = delivery.apiValue;
        if (alwaysBurnInSubtitleWhenTranscoding) {
          params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
        }
      }
    }

    final uri = Uri.parse('$_serverUrl/Videos/$itemId/master.m3u8')
        .replace(queryParameters: params);

    debugPrint('[Jellyfin HLS] 构建URL: ${uri.toString()}');
    debugPrint(
        '[Jellyfin HLS] 字幕参数 - streamIndex: $subtitleStreamIndex, burnIn: $alwaysBurnInSubtitleWhenTranscoding');

    return uri.toString();
  }

  /// 添加转码参数到URL参数中
  void _addTranscodeParameters(
      Map<String, String> params, JellyfinVideoQuality quality,
      {int? subtitleStreamIndex, bool? burnInSubtitle}) {
    // 基础转码参数
    final bitrate = quality.bitrate;
    final resolution = quality.maxResolution;

    if (bitrate != null) {
      params['maxStreamingBitrate'] = (bitrate * 1000).toString(); // 修正参数名
      params['videoBitRate'] = (bitrate * 1000).toString(); // 修正参数名
    }

    if (resolution != null) {
      params['maxWidth'] = resolution.width.toString(); // 修正参数名
      params['maxHeight'] = resolution.height.toString(); // 修正参数名
    }

    // 默认/偏好转码设置
    final videoCodecs = transcodeSettingsCache.video.preferredCodecs.isNotEmpty
        ? transcodeSettingsCache.video.preferredCodecs.join(',')
        : 'h264,hevc,av1';
    final audioCodecs = transcodeSettingsCache.audio.preferredCodecs.isNotEmpty
        ? transcodeSettingsCache.audio.preferredCodecs.join(',')
        : 'aac,mp3,opus';
    params['videoCodec'] = videoCodecs; // 修正参数名
    params['audioCodec'] = audioCodecs; // 修正参数名

    // 音频相关限制（可选）
    if (transcodeSettingsCache.audio.maxAudioChannels > 0) {
      params['maxAudioChannels'] =
          transcodeSettingsCache.audio.maxAudioChannels.toString();
    }
    if (transcodeSettingsCache.audio.audioBitRate != null &&
        transcodeSettingsCache.audio.audioBitRate! > 0) {
      params['audioBitRate'] =
          (transcodeSettingsCache.audio.audioBitRate! * 1000).toString();
    }
    if (transcodeSettingsCache.audio.audioSampleRate != null &&
        transcodeSettingsCache.audio.audioSampleRate! > 0) {
      params['audioSampleRate'] =
          transcodeSettingsCache.audio.audioSampleRate!.toString();
    }

    // 字幕交付方式（仅当需要由服务器处理时）
    if (transcodeSettingsCache.subtitle.enableTranscoding &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.external &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.drop) {
      params['subtitleMethod'] =
          transcodeSettingsCache.subtitle.deliveryMethod.apiValue;
      // 指定字幕流索引（如果提供）
      if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
        params['subtitleStreamIndex'] = subtitleStreamIndex.toString();
      }
      // 烧录字幕标志（如果选择烧录或显式传入）
      final shouldBurn = burnInSubtitle ??
          (transcodeSettingsCache.subtitle.deliveryMethod ==
              JellyfinSubtitleDeliveryMethod.encode);
      if (shouldBurn) {
        params['alwaysBurnInSubtitleWhenTranscoding'] = 'true';
      }
    }
    // HLS 使用 master.m3u8，不需要设置 Container/TranscodingContainer/TranscodingProtocol

    // 边界情况：确保参数有效
    try {
      // 验证参数有效性
      if (params['MaxStreamingBitrate']?.isEmpty == true) {
        params.remove('MaxStreamingBitrate');
      }
      if (params['MaxWidth'] == '0' || params['MaxHeight'] == '0') {
        params.remove('MaxWidth');
        params.remove('MaxHeight');
      }
    } catch (e) {
      debugPrint('添加转码参数时出错: $e');
      // 发生错误时移除可能有问题的参数
      params.removeWhere(
          (key, value) => key.startsWith('Max') || key.contains('BitRate'));
    }
  }

  /// 构建支持自动选择字幕的 HLS URL（异步）。
  /// 当未提供 [subtitleStreamIndex] 且字幕交付方式为 Encode/Embed/Hls 时：
  /// - 优先选择简体/繁体中文或标记为默认的字幕轨道
  Future<String> buildHlsUrlWithAutoSubtitle(
    String itemId, {
    JellyfinVideoQuality? quality,
    int? subtitleStreamIndex,
    bool? burnInSubtitle,
    String? preferredLanguage, // e.g. 'chi','zho','zh'
  }) async {
    final effective = quality ??
        (transcodeEnabledCache
            ? defaultQualityCache
            : JellyfinVideoQuality.original);

    // 若 direct play，直接返回直链
    if (effective == JellyfinVideoQuality.original) {
      return _buildDirectPlayUrl(itemId);
    }

    int? resolvedIndex = subtitleStreamIndex;
    final needsServerSubtitle = transcodeSettingsCache.subtitle.enableTranscoding &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.external &&
        transcodeSettingsCache.subtitle.deliveryMethod !=
            JellyfinSubtitleDeliveryMethod.drop;

    if (resolvedIndex == null && needsServerSubtitle) {
      try {
        final tracks = await getSubtitleTracks(itemId);
        if (tracks.isNotEmpty) {
          // 先中文（简/繁/语言码）
          final zh = tracks.firstWhere(
            (t) {
              final title = (t['title'] ?? '').toString().toLowerCase();
              final language = (t['language'] ?? '').toString().toLowerCase();
              return language.contains('chi') ||
                  language.contains('zho') ||
                  language == 'zh' ||
                  title.contains('简体') ||
                  title.contains('繁体') ||
                  title.contains('中文') ||
                  title.contains('chs') ||
                  title.contains('cht') ||
                  title.startsWith('scjp') ||
                  title.startsWith('tcjp');
            },
            orElse: () => tracks.firstWhere(
              (t) => (t['isDefault'] ?? false) == true,
              orElse: () => tracks.first,
            ),
          );
          resolvedIndex = (zh['index'] as int?);
        }
      } catch (e) {
        debugPrint('JellyfinService: 自动选择字幕轨道失败，忽略: $e');
      }
    }

    return _buildTranscodeUrl(itemId, effective,
        subtitleStreamIndex: resolvedIndex, burnInSubtitle: burnInSubtitle);
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
          '/Items/$itemId/PlaybackInfo?userId=$_userId');

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
            // 使用流的真实索引，而不是循环索引
            final realIndex = stream['Index'] ?? i;

            debugPrint(
                'JellyfinService: 找到字幕轨道 $realIndex: $language ($codec, ${isExternal ? 'external' : 'embedded'})');

            // 构建字幕轨道信息
            Map<String, dynamic> trackInfo = {
              'index': realIndex, // 使用真实索引
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
              // 供 UI 快速显示
              'display': _buildSubtitleDisplay(
                  language, title, codec, isExternal, isForced, isDefault),
            };

            // 如果是外挂字幕，添加下载URL
            if (isExternal) {
              final mediaSourceId = mediaSource['Id'];
              final subtitleUrl =
                  '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$realIndex/Stream.$codec?api_key=$_accessToken';
              trackInfo['downloadUrl'] = subtitleUrl;
            }

            subtitleTracks.add(trackInfo);
            // 注意：这里使用realIndex而不是循环的i
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
  Future<String?> downloadSubtitleFile(
      String itemId, int subtitleIndex, String format) async {
    if (kIsWeb) return null;
    if (!_isConnected || _accessToken == null) {
      throw Exception('未连接到Jellyfin服务器');
    }

    try {
      // 获取媒体源ID
      final playbackInfoResponse = await _makeAuthenticatedRequest(
          '/Items/$itemId/PlaybackInfo?userId=$_userId');

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
      final subtitleUrl =
          '$_serverUrl/Videos/$itemId/$mediaSourceId/Subtitles/$subtitleIndex/Stream.$format?api_key=$_accessToken';

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
        debugPrint(
            'JellyfinService: 下载字幕文件失败: HTTP ${subtitleResponse.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('JellyfinService: 下载字幕文件时出错: $e');
      return null;
    }
  }

  /// 构造字幕显示名称（供设置面板展示）
  String _buildSubtitleDisplay(
    String language,
    String title,
    String codec,
    bool isExternal,
    bool isForced,
    bool isDefault,
  ) {
    final List<String> parts = [];
    if (title.isNotEmpty) {
      parts.add(title);
    } else if (language.isNotEmpty) {
      parts.add(language);
    } else {
      parts.add('字幕');
    }
    if (codec.isNotEmpty) parts.add(codec.toUpperCase());
    if (isExternal) parts.add('外挂');
    if (isForced) parts.add('强制');
    if (isDefault) parts.add('默认');
    return parts.join(' · ');
  }

  /// 搜索媒体库中的内容
  /// [searchTerm] 搜索关键词
  /// [includeItemTypes] 包含的项目类型 (Series, Movie, Episode等)
  /// [limit] 结果数量限制
  /// [parentId] 父级媒体库ID (可选，用于限制在特定媒体库中搜索)
  Future<List<JellyfinMediaItem>> searchMediaItems(
    String searchTerm, {
    List<String>? includeItemTypes,
    int limit = 50,
    String? parentId,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty) {
      return [];
    }

    try {
      // 构建查询参数
      final queryParams = <String, String>{
        'searchTerm': searchTerm.trim(),
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

      final response = await _makeAuthenticatedRequest('/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];

        final results =
            items.map((item) => JellyfinMediaItem.fromJson(item)).toList();

        debugPrint(
            '[JellyfinService] 搜索 "$searchTerm" 找到 ${results.length} 个结果');
        return results;
      } else {
        debugPrint('[JellyfinService] 搜索失败: HTTP ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('[JellyfinService] 搜索出错: $e');
      return [];
    }
  }

  /// 在特定媒体库中搜索
  Future<List<JellyfinMediaItem>> searchInLibrary(
    String libraryId,
    String searchTerm, {
    int limit = 50,
  }) async {
    if (kIsWeb) return [];
    if (!_isConnected || searchTerm.trim().isEmpty) {
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
      debugPrint('[JellyfinService] 在媒体库 $libraryId 中搜索出错: $e');
      return [];
    }
  }

  // 获取图片URL
  String getImageUrl(String itemId,
      {String type = 'Primary', int? width, int? height, int? quality}) {
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

  String _resolveCollectionType(dynamic rawType) {
    final value = rawType?.toString().trim();
    if (value == null || value.isEmpty) {
      return 'mixed';
    }
    return value.toLowerCase();
  }

  /// 下载指定媒体的图片并返回二进制数据（用于离线缩略图缓存）。
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

    final params = <String>[];
    if (width != null) params.add('width=$width');
    if (height != null) params.add('height=$height');
    if (quality != null) params.add('quality=$quality');
    if (tag != null && tag.isNotEmpty) params.add('tag=$tag');
    final query = params.isNotEmpty ? '?${params.join('&')}' : '';

    try {
      final response = await _makeAuthenticatedRequest(
        '/Items/$itemId/Images/$type$query',
        timeout: const Duration(seconds: 20),
      );
      return response.bodyBytes;
    } catch (e) {
      DebugLogService().addLog('JellyfinService: 下载图片失败 ($itemId): $e');
      return null;
    }
  }

  // 辅助方法：发送经过身份验证的HTTP请求
  Future<http.Response> _makeAuthenticatedRequest(String endpoint,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    return makeAuthenticatedRequest(endpoint,
        method: method, body: body, timeout: timeout);
  }

}

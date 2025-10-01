import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/models/emby_model.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:path_provider/path_provider.dart' if (dart.library.html) 'package:nipaplay/utils/mock_path_provider.dart';
import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'debug_log_service.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/services/emby_transcode_manager.dart';

import 'package:nipaplay/utils/url_name_generator.dart';

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
  
  // 后端就绪标志与回调
  bool _isReady = false;
  bool get isReady => _isReady;
  final List<VoidCallback> _readyCallbacks = [];
  
  void addReadyListener(VoidCallback callback) {
    _readyCallbacks.add(callback);
  }
  
  void removeReadyListener(VoidCallback callback) {
    _readyCallbacks.remove(callback);
  }
  
  void _notifyReady() {
    for (final cb in _readyCallbacks) {
      try {
        cb();
      } catch (e) {
        DebugLogService().addLog('Emby: ready 回调执行失败: $e');
      }
    }
  }
  
  // 多地址支持
  ServerProfile? _currentProfile;
  String? _currentAddressId;
  final MultiAddressServerService _multiAddressService = MultiAddressServerService.instance;

  // 转码偏好缓存（内存）——让 Provider 能在运行时同步设置，避免 async IO
  bool _transcodeEnabledCache = false;
  JellyfinVideoQuality _defaultQualityCache = JellyfinVideoQuality.bandwidth5m;
  JellyfinTranscodeSettings _settingsCache = const JellyfinTranscodeSettings();

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

  /// 获取服务器端的媒体技术元数据（容器/编解码器/Profile/Level/HDR/声道/码率等）
  /// 结构与 Jellyfin 保持一致，字段命名相同，便于 UI 统一展示。
  Future<Map<String, dynamic>> getServerMediaTechnicalInfo(String itemId) async {
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
              } else if (s is Map && s['Type'] == 'Audio' && audioStream == null) {
                audioStream = Map<String, dynamic>.from(s);
              }
            }
          }
        }
      }

      // 2) 补充 Items 详情
      Map<String, dynamic>? itemDetail;
      try {
        final itemResp = await _makeAuthenticatedRequest('/emby/Users/$_userId/Items/$itemId');
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
        'frameRate': videoStream?['RealFrameRate'] ?? videoStream?['AverageFrameRate'],
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
  _isReady = false;
      return;
    }
    
    // 初始化多地址服务
    await _multiAddressService.initialize();
    
    final prefs = await SharedPreferences.getInstance();
    
    // 尝试加载当前配置
    final profileId = prefs.getString('emby_current_profile_id');
    if (profileId != null) {
      try {
        _currentProfile = _multiAddressService.getProfileById(profileId);
        if (_currentProfile != null) {
          _username = _currentProfile!.username;
          _accessToken = _currentProfile!.accessToken;
          _userId = _currentProfile!.userId;
          
          // 使用当前地址
          final currentAddress = _currentProfile!.currentAddress;
          if (currentAddress != null) {
            _serverUrl = currentAddress.normalizedUrl;
            _currentAddressId = currentAddress.id;
          }
        }
      } catch (e) {
        DebugLogService().addLog('Emby: 加载配置失败: $e');
      }
    }
    
    // 兼容旧版本存储
    if (_currentProfile == null) {
      _serverUrl = prefs.getString('emby_server_url');
      _username = prefs.getString('emby_username');
      _accessToken = prefs.getString('emby_access_token');
      _userId = prefs.getString('emby_user_id');
    }
    
    _selectedLibraryIds = prefs.getStringList('emby_selected_libraries') ?? [];
    
    print('Emby loadSavedSettings: serverUrl=$_serverUrl, username=$_username, hasToken=${_accessToken != null}, userId=$_userId');
    
    if (_serverUrl != null && _accessToken != null && _userId != null) {
      // 异步验证连接，不阻塞初始化流程
      _validateConnectionAsync();
    } else {
      print('Emby: 缺少必要的连接信息，跳过自动连接');
      _isConnected = false;
  _isReady = false;
    }

    // 预加载转码设置到本地缓存，避免在 getStreamUrl 中做异步操作（与 Jellyfin 行为一致）
    try {
      final transMgr = EmbyTranscodeManager.instance;
      await transMgr.initialize();
      _transcodeEnabledCache = await transMgr.isTranscodingEnabled();
      _defaultQualityCache = await transMgr.getDefaultVideoQuality();
      _settingsCache = await transMgr.getSettings();
      DebugLogService().addLog('Emby: 已加载转码偏好 缓存 enabled=' + _transcodeEnabledCache.toString() + ', quality=' + _defaultQualityCache.toString());
    } catch (e) {
      DebugLogService().addLog('Emby: 加载转码偏好失败，使用默认值: $e');
      _transcodeEnabledCache = false;
      _defaultQualityCache = JellyfinVideoQuality.bandwidth5m;
      _settingsCache = const JellyfinTranscodeSettings();
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
        // 设置后端就绪并发出信号（使用 microtask，确保在前面的通知处理完成后触发）
        scheduleMicrotask(() {
          _isReady = true;
          _notifyReady();
        });
      } else {
        print('Emby: 连接验证失败 - HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('Emby: 连接验证过程中发生异常: $e');
      _isConnected = false;
      _isReady = false;
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
  
  Future<bool> connect(String serverUrl, String username, String password, {String? addressName}) async {
    // 初始化多地址服务
    await _multiAddressService.initialize();
    
    // 规范化URL
    final normalizedUrl = _normalizeUrl(serverUrl);
    
    try {
      // 先识别服务器
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: 'emby',
        getServerId: _getEmbyServerId,
      );
      
      ServerProfile? profile;
      
      if (identifyResult.success && identifyResult.existingProfile != null) {
        // 服务器已存在，添加新地址或使用现有地址
        profile = identifyResult.existingProfile!;
        
        // 检查是否需要添加新地址
        final hasAddress = profile.addresses.any(
          (addr) => addr.normalizedUrl == normalizedUrl,
        );
        
        if (!hasAddress) {
          profile = await _multiAddressService.addAddressToProfile(
            profileId: profile.id,
            url: normalizedUrl,
            name: UrlNameGenerator.generateAddressName(normalizedUrl, customName: addressName),
          );
        } else {
          print('EmbyService: 地址已存在，使用现有配置');
        }
      } else if (identifyResult.isConflict) {
        // 检测到冲突：URL相同但serverId不同
        print('EmbyService: 检测到冲突，抛出异常: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      } else if (identifyResult.success) {
        // 服务器识别成功但没有现有配置，创建新配置
        print('EmbyService: 创建新的服务器配置');
        profile = await _multiAddressService.addProfile(
          serverName: await _getServerName(normalizedUrl) ?? 'Emby服务器',
          serverType: 'emby',
          url: normalizedUrl,
          username: username,
          serverId: identifyResult.serverId,
          addressName: UrlNameGenerator.generateAddressName(normalizedUrl, customName: addressName),
        );
      } else {
        // 服务器识别失败
        print('EmbyService: 服务器识别失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法识别Emby服务器');
      }
      
      if (profile == null) {
        throw Exception('无法创建服务器配置');
      }
      
      // 使用多地址尝试连接
      final connectionResult = await _multiAddressService.tryConnect(
        profile: profile,
        testConnection: (url) => _testEmbyConnection(url, username, password),
      );
      
      if (connectionResult.success && connectionResult.profile != null) {
        _currentProfile = connectionResult.profile;
        _serverUrl = connectionResult.successfulUrl;
        _currentAddressId = connectionResult.successfulAddressId;
        _username = username;
        _password = password;
        
        // 执行完整的认证流程
        await _performAuthentication(_serverUrl!, username, password);
        
        // 只有在认证成功后才设置连接状态为true
        _isConnected = true;
        
        // 更新配置中的认证信息
        _currentProfile = _currentProfile!.copyWith(
          accessToken: _accessToken,
          userId: _userId,
        );
        await _multiAddressService.updateProfile(_currentProfile!);
        
        // 保存连接信息
        await _saveConnectionInfo();
        print('Emby: 连接信息已保存到SharedPreferences');
        
        // 加载可用媒体库
        await loadAvailableLibraries();
        // 连接流程结束，先通知连接状态变化，再通过 microtask 触发 ready，保证 ready 最后到达
        _notifyConnectionStateChanged();
        scheduleMicrotask(() {
          _isReady = true;
          _notifyReady();
        });
        
        return true;
      } else {
        throw Exception(connectionResult.error ?? '连接失败');
      }
    } catch (e) {
      print('EmbyService: 连接过程中发生异常: $e');
      _isConnected = false;
      
      // 如果是服务器冲突错误，直接传递原始错误信息
      if (e.toString().contains('已被另一个') || e.toString().contains('已被占用')) {
        throw Exception(e.toString());
      }
      
      throw Exception('连接Emby服务器失败: $e');
    }
  }
  
  /// 测试Emby连接
  Future<bool> _testEmbyConnection(String url, String username, String password) async {
    try {
      // 获取服务器信息
      final configResponse = await http.get(
        Uri.parse('$url/emby/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      return configResponse.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// 执行完整的认证流程
  Future<void> _performAuthentication(String serverUrl, String username, String password) async {
    final clientInfo = await _getClientInfo();
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
      final response = await http.get(
        Uri.parse('$url/emby/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['Id'] ?? data['ServerId'];
      }
      // 在HTTP状态码不为200时抛出详细错误
      throw Exception('获取Emby服务器ID失败: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    } catch (e) {
      DebugLogService().addLog('获取Emby服务器ID失败: $e');
      // 重新抛出异常，以便 identifyServer 捕获并返回详细错误
      rethrow;
    }
  }
  
  /// 获取服务器名称
  Future<String?> _getServerName(String url) async {
    try {
      final response = await http.get(
        Uri.parse('$url/emby/System/Info/Public'),
      ).timeout(const Duration(seconds: 5));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['ServerName'];
      }
    } catch (e) {
      DebugLogService().addLog('获取Emby服务器名称失败: $e');
    }
    return null;
  }
  

  
  /// 规范化URL
  String _normalizeUrl(String url) {
    String normalized = url.trim();
    if (!normalized.startsWith('http://') && !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }
  
  Future<void> _saveConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();
    
    // 保存当前配置ID
    if (_currentProfile != null) {
      await prefs.setString('emby_current_profile_id', _currentProfile!.id);
    }
    
    // 兼容旧版本，同时保存单地址信息
    await prefs.setString('emby_server_url', _serverUrl!);
    await prefs.setString('emby_username', _username!);
    await prefs.setString('emby_access_token', _accessToken!);
    await prefs.setString('emby_user_id', _userId!);
    
    print('Emby: 连接信息已保存 - URL: $_serverUrl, 用户: $_username, Token: ${_accessToken?.substring(0, 8)}..., UserID: $_userId');
  }
  
  Future<void> disconnect() async {
    // 保存当前配置文件ID，用于删除
    final currentProfileId = _currentProfile?.id;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('emby_current_profile_id');
    await prefs.remove('emby_server_url');
    await prefs.remove('emby_username');
    await prefs.remove('emby_access_token');
    await prefs.remove('emby_user_id');
    await prefs.remove('emby_selected_libraries');
    
    _currentProfile = null;
    _currentAddressId = null;
    _serverUrl = null;
    _username = null;
    _password = null;
    _accessToken = null;
    _userId = null;
    _isConnected = false;
    _availableLibraries = [];
    _selectedLibraryIds = [];
  _isReady = false;
    
    // 删除多地址配置文件
    if (currentProfileId != null) {
      try {
        await _multiAddressService.deleteProfile(currentProfileId);
        DebugLogService().addLog('EmbyService: 已删除服务器配置文件 $currentProfileId');
      } catch (e) {
        DebugLogService().addLog('EmbyService: 删除服务器配置文件失败: $e');
      }
    }
    

    
    // TODO: 清除播放同步服务中的数据（待实现）
    // 当前 EmbyPlaybackSyncService 没有清除所有数据的方法
    // 可能需要在后续版本中添加相关方法
  }
  
  Future<http.Response> _makeAuthenticatedRequest(String path, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    // 如果有多地址配置，尝试使用多地址重试机制
    if (_currentProfile != null) {
      return await _makeAuthenticatedRequestWithRetry(path, method: method, body: body, timeout: timeout);
    }
    
    // 单地址模式（兼容旧版本）
    final uri = Uri.parse('$_serverUrl$path');
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': authHeader,
    };
    
    // 设置默认超时时间为30秒
    final requestTimeout = timeout ?? const Duration(seconds: 30);
    
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
  
  /// 带重试的认证请求（多地址支持）
  Future<http.Response> _makeAuthenticatedRequestWithRetry(String path, {String method = 'GET', Map<String, dynamic>? body, Duration? timeout}) async {
    if (_currentProfile == null || _accessToken == null) {
      throw Exception('未连接到 Emby 服务器');
    }
    
    final addresses = _currentProfile!.enabledAddresses;
    if (addresses.isEmpty) {
      throw Exception('没有可用的服务器地址');
    }
    
    final clientInfo = await _getClientInfo();
    final authHeader = clientInfo + ', Token="$_accessToken"';
    final headers = {
      'Content-Type': 'application/json',
      'X-Emby-Authorization': authHeader,
    };
    
  final requestTimeout = timeout ?? const Duration(seconds: 30);
    
    Exception? lastError;
    
    // 尝试每个地址
    for (final address in addresses) {
      if (!address.shouldRetry()) continue;
      
      final uri = Uri.parse('${address.normalizedUrl}$path');
      
      try {
        http.Response response;
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
        
        if (response.statusCode < 400) {
          // 成功，更新当前使用的地址
          if (_currentAddressId != address.id) {
            _serverUrl = address.normalizedUrl;
            _currentAddressId = address.id;
            _currentProfile = _currentProfile!.markAddressSuccess(address.id);
            await _multiAddressService.updateProfile(_currentProfile!);
          }
          return response;
        } else {
          // 提供更详细的错误信息
          String errorMessage;
          if (response.statusCode == 401) {
            errorMessage = '认证失败: 访问令牌无效或已过期 (HTTP 401)';
          } else if (response.statusCode == 403) {
            errorMessage = '访问被拒绝: 用户权限不足 (HTTP 403)';
          } else if (response.statusCode == 404) {
            errorMessage = '请求的资源未找到 (HTTP 404)';
          } else if (response.statusCode >= 500) {
            errorMessage = 'Emby服务器内部错误 (HTTP ${response.statusCode})';
          } else {
            errorMessage = '服务器返回错误: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}';
          }
          lastError = Exception(errorMessage);
          DebugLogService().addLog('EmbyService: 请求失败 ${address.normalizedUrl}: $errorMessage');
        }
      } on TimeoutException catch (e) {
        lastError = Exception('请求超时: ${e.message}');
        _currentProfile = _currentProfile!.markAddressFailed(address.id);
      } catch (e) {
        lastError = Exception('请求失败: $e');
        _currentProfile = _currentProfile!.markAddressFailed(address.id);
      }
    }
    
    // 更新失败信息
    await _multiAddressService.updateProfile(_currentProfile!);
    
    throw lastError ?? Exception('所有地址连接失败');
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
      
      // 按剧集编号排序，将特别篇（indexNumber 为 null 或 0）排在最后
      episodes.sort((a, b) {
        final aIndex = (a.indexNumber == null || a.indexNumber == 0) ? 999999 : a.indexNumber!;
        final bIndex = (b.indexNumber == null || b.indexNumber == 0) ? 999999 : b.indexNumber!;
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
  
  // 获取流媒体URL（异步，确保含 MediaSourceId/PlaySessionId）
  Future<String> getStreamUrl(String itemId) async {
    if (!_isConnected || _accessToken == null) {
      return '';
    }
    // 使用缓存的转码设置决定默认质量
    final effectiveQuality = _transcodeEnabledCache
        ? _defaultQualityCache
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
    final effective = quality ?? (_transcodeEnabledCache
        ? _defaultQualityCache
        : JellyfinVideoQuality.original);

    // 构建直连或转码 URL
    return _buildTranscodeUrlSync(
      itemId,
      effective,
      subtitleStreamIndex: subtitleStreamIndex,
      burnInSubtitle: burnInSubtitle,
    );
  }

  /// 构建直连URL（不转码）
  String _buildDirectPlayUrl(String itemId) {
    return '$_serverUrl/emby/Videos/$itemId/stream?Static=true&api_key=$_accessToken';
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
  if (mediaSourceId != null && mediaSourceId.isNotEmpty) 'MediaSourceId': mediaSourceId,
  if (playSessionId != null && playSessionId.isNotEmpty) 'PlaySessionId': playSessionId,
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
  void _addTranscodeParameters(Map<String, String> params, JellyfinVideoQuality quality, {int? subtitleStreamIndex, bool? burnInSubtitle}) {
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
    final videoCodecs = _settingsCache.video.preferredCodecs.isNotEmpty
        ? _settingsCache.video.preferredCodecs.join(',')
        : 'h264,hevc,av1';
    final audioCodecs = _settingsCache.audio.preferredCodecs.isNotEmpty
        ? _settingsCache.audio.preferredCodecs.join(',')
        : 'aac,mp3,opus';
    params['VideoCodec'] = videoCodecs;
    params['AudioCodec'] = audioCodecs;

    // 音频限制
    if (_settingsCache.audio.maxAudioChannels > 0) {
      params['MaxAudioChannels'] = _settingsCache.audio.maxAudioChannels.toString();
    }
    if (_settingsCache.audio.audioBitRate != null && _settingsCache.audio.audioBitRate! > 0) {
      params['AudioBitRate'] = (_settingsCache.audio.audioBitRate! * 1000).toString();
    }
    if (_settingsCache.audio.audioSampleRate != null && _settingsCache.audio.audioSampleRate! > 0) {
      params['AudioSampleRate'] = _settingsCache.audio.audioSampleRate!.toString();
    }

    // 字幕处理：如果设置允许服务端处理并非 external/drop，则添加相应参数
    if (_settingsCache.subtitle.enableTranscoding &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.external &&
        _settingsCache.subtitle.deliveryMethod != JellyfinSubtitleDeliveryMethod.drop) {
      params['SubtitleMethod'] = _settingsCache.subtitle.deliveryMethod.apiValue;
      if (subtitleStreamIndex != null && subtitleStreamIndex >= 0) {
        params['SubtitleStreamIndex'] = subtitleStreamIndex.toString();
      }
      final shouldBurn = burnInSubtitle ?? (_settingsCache.subtitle.deliveryMethod == JellyfinSubtitleDeliveryMethod.encode);
      if (shouldBurn) {
        params['AlwaysBurnInSubtitleWhenTranscoding'] = 'true';
      }
    }

    // 保证参数整洁
    try {
      if (params['MaxStreamingBitrate']?.isEmpty == true) params.remove('MaxStreamingBitrate');
      if (params['MaxWidth'] == '0' || params['MaxHeight'] == '0') {
        params.remove('MaxWidth');
        params.remove('MaxHeight');
      }
    } catch (e) {
      debugPrint('添加 Emby 转码参数时出错: $e');
      params.removeWhere((key, value) => key.startsWith('Max') || key.contains('BitRate'));
    }
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
        'Fields': 'Overview,Genres,People,Studios,ProviderIds,DateCreated,PremiereDate,CommunityRating,ProductionYear',
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

      final response = await _makeAuthenticatedRequest('/emby/Users/$_userId/Items?$queryString');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> items = data['Items'] ?? [];
        
        final results = items
            .map((item) => EmbyMediaItem.fromJson(item))
            .toList();

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
        '/emby/Users/$_userId/Items/$libraryId'
      );
      
      if (libraryResponse.statusCode != 200) {
        return [];
      }
      
      final libraryData = json.decode(libraryResponse.body);
      final String collectionType = libraryData['CollectionType'] ?? 'tvshows';
      
      // 根据媒体库类型选择不同的IncludeItemTypes
      String includeItemTypes = collectionType == 'tvshows' ? 'Series' : 'Movie';

      return await searchMediaItems(
        searchTerm,
        includeItemTypes: [includeItemTypes],
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
            final realIndex = stream['Index'] ?? i;
            final displayParts = <String>[];
            if ((title as String).isNotEmpty) {
              displayParts.add(title);
            } else if ((language as String).isNotEmpty) {
              displayParts.add(language);
            } else {
              displayParts.add('字幕');
            }
            if ((codec as String).isNotEmpty) displayParts.add(codec.toString().toUpperCase());
            if (isExternal) displayParts.add('外挂');
            if (isForced) displayParts.add('强制');
            if (isDefault) displayParts.add('默认');
            Map<String, dynamic> trackInfo = {
              'index': realIndex,
              'type': isExternal ? 'external' : 'embedded',
              'language': language,
              'title': title.isNotEmpty ? title : (language.isNotEmpty ? language : 'Unknown'),
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
              final subtitleUrl = '$_serverUrl/emby/Videos/$itemId/$mediaSourceId/Subtitles/$realIndex/Stream.$codec?api_key=$_accessToken';
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

  /// 获取当前服务器的所有地址
  List<ServerAddress> getServerAddresses() {
    if (_currentProfile != null) {
      return _currentProfile!.addresses;
    }
    return [];
  }

  /// 由 Provider 调用：在运行时更新本地转码缓存（避免在 getStreamUrl 中做异步 IO）
  void setTranscodePreferences({bool? enabled, JellyfinVideoQuality? defaultQuality}) {
    if (enabled != null) _transcodeEnabledCache = enabled;
    if (defaultQuality != null) _defaultQualityCache = defaultQuality;
    DebugLogService().addLog('Emby: 更新转码偏好 缓存 enabled=${enabled ?? _transcodeEnabledCache}, quality=${defaultQuality ?? _defaultQualityCache}');
  }

  /// 由 Provider 调用：更新完整转码设置缓存（用于音频/字幕等参数）
  void setFullTranscodeSettings(JellyfinTranscodeSettings settings) {
    _settingsCache = settings;
    DebugLogService().addLog('Emby: 更新完整转码设置缓存 (video/audio/subtitle/adaptive)');
  }
  
  /// 添加新地址到当前服务器
  Future<bool> addServerAddress(String url, String name) async {
    if (_currentProfile == null) return false;
    
    final normalizedUrl = _normalizeUrl(url);
    
    try {
      // 先验证这是否为同一台服务器
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: 'emby',
        getServerId: _getEmbyServerId,
      );
      
      if (!identifyResult.success) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法验证服务器身份');
      }
      
      if (identifyResult.isConflict) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      }
      
      // 验证serverId是否匹配
      if (identifyResult.serverId != _currentProfile!.serverId) {
        throw Exception('该地址属于不同的Emby服务器（服务器ID: ${identifyResult.serverId}），无法添加到当前配置');
      }
      
      final updatedProfile = await _multiAddressService.addAddressToProfile(
        profileId: _currentProfile!.id,
        url: normalizedUrl,
        name: UrlNameGenerator.generateAddressName(normalizedUrl, customName: name),
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        DebugLogService().addLog('成功添加新地址: $normalizedUrl');
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('添加服务器地址失败: $e');
      rethrow; // 重新抛出异常以便UI处理
    }
    return false;
  }
  
  /// 删除服务器地址
  Future<bool> removeServerAddress(String addressId) async {
    if (_currentProfile == null) return false;
    
    try {
      final updatedProfile = await _multiAddressService.deleteAddressFromProfile(
        profileId: _currentProfile!.id,
        addressId: addressId,
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('删除服务器地址失败: $e');
    }
    return false;
  }
  
  /// 切换服务器地址
  Future<bool> switchToAddress(String addressId) async {
    if (_currentProfile == null) return false;
    
    final address = _currentProfile!.addresses.firstWhere(
      (addr) => addr.id == addressId,
      orElse: () => throw Exception('地址不存在'),
    );
    
    // 测试连接
    final success = await _testEmbyConnection(
      address.normalizedUrl,
      _username ?? '',
      _password ?? '',
    );
    
    if (success) {
      // 验证当前用户token在新地址上的有效性
      try {
        final originalUrl = _serverUrl;
        _serverUrl = address.normalizedUrl;
        
        // 进行轻量级认证验证
        final authResponse = await _makeAuthenticatedRequest('/emby/System/Info')
            .timeout(const Duration(seconds: 5));
        
        if (authResponse.statusCode == 200) {
          _currentAddressId = address.id;
          _currentProfile = _currentProfile!.markAddressSuccess(address.id);
          await _multiAddressService.updateProfile(_currentProfile!);
          DebugLogService().addLog('EmbyService: 成功切换到地址: ${address.normalizedUrl}');
          return true;
        } else {
          // 认证失败，恢复原地址
          _serverUrl = originalUrl;
          DebugLogService().addLog('EmbyService: 地址切换失败，token在新地址上无效: HTTP ${authResponse.statusCode}');
          return false;
        }
      } catch (e) {
        // 认证失败，恢复原地址
        _serverUrl = _currentProfile!.currentAddress?.normalizedUrl;
        DebugLogService().addLog('EmbyService: 地址切换失败，认证验证异常: $e');
        return false;
      }
    }
    
    return false;
  }

  /// 更新服务器地址优先级
  Future<bool> updateServerPriority(String addressId, int priority) async {
    if (_currentProfile == null) return false;
    
    try {
      final updatedProfile = await _multiAddressService.updateAddressPriority(
        profileId: _currentProfile!.id,
        addressId: addressId,
        priority: priority,
      );
      
      if (updatedProfile != null) {
        _currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('EmbyService: 更新地址优先级失败: $e');
    }
    
    return false;
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

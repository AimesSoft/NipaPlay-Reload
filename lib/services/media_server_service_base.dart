import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/services/multi_address_server_service.dart';
import 'package:nipaplay/utils/url_name_generator.dart';
import 'debug_log_service.dart';
import 'media_server_device_id_service.dart';
import 'dart:io' if (dart.library.io) 'dart:io';

abstract class MediaServerServiceBase {
  final MultiAddressServerService _multiAddressService =
      MultiAddressServerService.instance;

  final List<VoidCallback> _readyCallbacks = [];
  final List<Function(bool)> _connectionStateCallbacks = [];

  String? _cachedClientAppName;
  String? _cachedClientVersion;
  String? _cachedClientPlatform;

  bool _transcodeEnabledCache = false;
  JellyfinVideoQuality _defaultQualityCache = JellyfinVideoQuality.bandwidth5m;
  JellyfinTranscodeSettings _settingsCache = const JellyfinTranscodeSettings();

  String get serviceName;
  String get serviceNameService => '${serviceName}Service';
  String get serviceType;
  String get prefsKeyPrefix;
  String get serverNameFallback;
  String get systemInfoPath => '/System/Info';
  bool get alwaysIncludeContentType => false;
  String get notConnectedMessage;

  String? get serverUrl;
  set serverUrl(String? value);
  String? get username;
  set username(String? value);
  String? get password;
  set password(String? value);
  String? get accessToken;
  set accessToken(String? value);
  String? get userId;
  set userId(String? value);
  bool get isConnected;
  set isConnected(bool value);
  bool get isReady;
  set isReady(bool value);
  List<String> get selectedLibraryIds;
  set selectedLibraryIds(List<String> value);
  ServerProfile? get currentProfile;
  set currentProfile(ServerProfile? value);
  String? get currentAddressId;
  set currentAddressId(String? value);

  @protected
  MultiAddressServerService get multiAddressService => _multiAddressService;

  @protected
  bool get transcodeEnabledCache => _transcodeEnabledCache;
  @protected
  JellyfinVideoQuality get defaultQualityCache => _defaultQualityCache;
  @protected
  JellyfinTranscodeSettings get transcodeSettingsCache => _settingsCache;

  @protected
  void updateTranscodeCache({
    required bool enabled,
    required JellyfinVideoQuality defaultQuality,
    required JellyfinTranscodeSettings settings,
  }) {
    _transcodeEnabledCache = enabled;
    _defaultQualityCache = defaultQuality;
    _settingsCache = settings;
  }

  @protected
  String normalizeRequestPath(String path);

  @protected
  Future<bool> testConnection(String url, String username, String password);

  @protected
  Future<void> performAuthentication(
      String serverUrl, String username, String password);

  @protected
  Future<String> getServerId(String url);

  @protected
  Future<String?> getServerName(String url);

  @protected
  Future<void> loadAvailableLibraries();

  @protected
  Future<void> loadTranscodeSettings();

  @protected
  void clearServiceData();

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
        DebugLogService().addLog('$serviceName: ready 回调执行失败: $e');
      }
    }
  }

  void addConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.add(callback);
  }

  void removeConnectionStateListener(Function(bool) callback) {
    _connectionStateCallbacks.remove(callback);
  }

  void _notifyConnectionStateChanged() {
    for (final callback in _connectionStateCallbacks) {
      try {
        callback(isConnected);
      } catch (e) {
        print('$serviceName: 连接状态回调执行失败: $e');
      }
    }
  }

  @protected
  Future<String> getClientInfo() async {
    String appName;
    String version;
    String platform;

    try {
      if (_cachedClientAppName == null ||
          _cachedClientVersion == null ||
          _cachedClientPlatform == null) {
        final packageInfo = await PackageInfo.fromPlatform();
        appName =
            packageInfo.appName.isNotEmpty ? packageInfo.appName : 'NipaPlay';
        version = packageInfo.version.isNotEmpty ? packageInfo.version : '1.4.9';

        platform = 'Flutter';
        if (!kIsWeb && !kDebugMode) {
          try {
            platform = Platform.operatingSystem;
            platform = platform[0].toUpperCase() + platform.substring(1);
          } catch (_) {
            platform = 'Flutter';
          }
        }

        _cachedClientAppName = appName;
        _cachedClientVersion = version;
        _cachedClientPlatform = platform;
      } else {
        appName = _cachedClientAppName!;
        version = _cachedClientVersion!;
        platform = _cachedClientPlatform!;
      }
    } catch (_) {
      appName = 'NipaPlay';
      version = '1.4.9';
      platform = 'Flutter';
    }

    String deviceId;
    try {
      deviceId = await MediaServerDeviceIdService.instance.getEffectiveDeviceId(
        appName: appName,
        platform: platform,
      );
    } catch (_) {
      deviceId = '$appName-$platform';
    }

    return 'MediaBrowser Client="$appName", Device="$platform", DeviceId="$deviceId", Version="$version"';
  }

  String normalizeUrl(String url) {
    String normalized = url.trim();
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'http://$normalized';
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  Future<void> loadSavedSettings() async {
    if (kIsWeb) {
      isConnected = false;
      isReady = false;
      return;
    }

    await _multiAddressService.initialize();

    final prefs = await SharedPreferences.getInstance();

    final profileId = prefs.getString('${prefsKeyPrefix}_current_profile_id');
    if (profileId != null) {
      try {
        currentProfile = _multiAddressService.getProfileById(profileId);
        if (currentProfile != null) {
          username = currentProfile!.username;
          accessToken = currentProfile!.accessToken;
          userId = currentProfile!.userId;

          final currentAddress = currentProfile!.currentAddress;
          if (currentAddress != null) {
            serverUrl = currentAddress.normalizedUrl;
            currentAddressId = currentAddress.id;
          }
        }
      } catch (e) {
        DebugLogService().addLog('$serviceName: 加载配置失败: $e');
      }
    }

    if (currentProfile == null) {
      serverUrl = prefs.getString('${prefsKeyPrefix}_server_url');
      username = prefs.getString('${prefsKeyPrefix}_username');
      accessToken = prefs.getString('${prefsKeyPrefix}_access_token');
      userId = prefs.getString('${prefsKeyPrefix}_user_id');
    }

    selectedLibraryIds =
        prefs.getStringList('${prefsKeyPrefix}_selected_libraries') ?? [];

    if (serverUrl != null && accessToken != null && userId != null) {
      _validateConnectionAsync();
    } else {
      isConnected = false;
      isReady = false;
    }

    await _loadTranscodeSettingsSafe();
  }

  Future<void> _loadTranscodeSettingsSafe() async {
    try {
      await loadTranscodeSettings();
    } catch (e) {
      DebugLogService().addLog('$serviceName: 加载转码偏好失败，使用默认值: $e');
      updateTranscodeCache(
        enabled: false,
        defaultQuality: JellyfinVideoQuality.bandwidth5m,
        settings: const JellyfinTranscodeSettings(),
      );
    }
  }

  Future<void> _validateConnectionAsync() async {
    try {
      print('$serviceName: 开始异步验证保存的连接信息...');
      final response = await makeAuthenticatedRequest(systemInfoPath)
          .timeout(const Duration(seconds: 5));
      isConnected = response.statusCode == 200;

      print(
          '$serviceName: 令牌验证结果 - HTTP ${response.statusCode}, 连接状态: $isConnected');

      if (isConnected) {
        print('$serviceName: 连接验证成功，正在加载媒体库...');
        await loadAvailableLibraries();
        print('$serviceName: 媒体库加载完成');
        _notifyConnectionStateChanged();
        scheduleMicrotask(() {
          isReady = true;
          _notifyReady();
        });
      } else {
        print('$serviceName: 连接验证失败 - HTTP ${response.statusCode}');
      }
    } catch (e) {
      print('$serviceName: 连接验证过程中发生异常: $e');
      isConnected = false;
      isReady = false;
    }
  }

  Future<bool> connect(String serverUrl, String username, String password,
      {String? addressName}) async {
    await _multiAddressService.initialize();

    final normalizedUrl = normalizeUrl(serverUrl);

    try {
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: serviceType,
        getServerId: getServerId,
      );

      ServerProfile? profile;

      if (identifyResult.success && identifyResult.existingProfile != null) {
        profile = identifyResult.existingProfile!;

        final hasAddress = profile.addresses.any(
          (addr) => addr.normalizedUrl == normalizedUrl,
        );

        if (!hasAddress) {
          profile = await _multiAddressService.addAddressToProfile(
            profileId: profile.id,
            url: normalizedUrl,
            name: UrlNameGenerator.generateAddressName(normalizedUrl,
                customName: addressName),
          );
        } else {
          print('$serviceNameService: 地址已存在，使用现有配置');
        }
      } else if (identifyResult.isConflict) {
        print('$serviceNameService: 检测到冲突，抛出异常: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      } else if (identifyResult.success) {
        print('$serviceNameService: 创建新的服务器配置');
        profile = await _multiAddressService.addProfile(
          serverName: await getServerName(normalizedUrl) ?? serverNameFallback,
          serverType: serviceType,
          url: normalizedUrl,
          username: username,
          serverId: identifyResult.serverId,
          addressName: UrlNameGenerator.generateAddressName(normalizedUrl,
              customName: addressName),
        );
      } else {
        print('$serviceNameService: 服务器识别失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法识别服务器');
      }

      if (profile == null) {
        throw Exception('无法创建服务器配置');
      }

      final connectionResult = await _multiAddressService.tryConnect(
        profile: profile,
        testConnection: (url) => testConnection(url, username, password),
      );

      if (connectionResult.success && connectionResult.profile != null) {
        currentProfile = connectionResult.profile;
        this.serverUrl = connectionResult.successfulUrl;
        currentAddressId = connectionResult.successfulAddressId;
        this.username = username;
        this.password = password;

        await performAuthentication(this.serverUrl!, username, password);

        isConnected = true;

        currentProfile = currentProfile!.copyWith(
          accessToken: accessToken,
          userId: userId,
        );
        await _multiAddressService.updateProfile(currentProfile!);

        await _saveConnectionInfo();

        await loadAvailableLibraries();
        _notifyConnectionStateChanged();
        scheduleMicrotask(() {
          isReady = true;
          _notifyReady();
        });

        return true;
      } else {
        throw Exception(connectionResult.error ?? '连接失败');
      }
    } catch (e) {
      print('$serviceNameService: 连接过程中发生异常: $e');
      isConnected = false;

      if (e.toString().contains('已被另一个') || e.toString().contains('已被占用')) {
        throw Exception(e.toString());
      }

      throw Exception('连接$serviceName服务器失败: $e');
    }
  }

  Future<void> _saveConnectionInfo() async {
    final prefs = await SharedPreferences.getInstance();

    if (currentProfile != null) {
      await prefs.setString(
          '${prefsKeyPrefix}_current_profile_id', currentProfile!.id);
    }

    await prefs.setString('${prefsKeyPrefix}_server_url', serverUrl!);
    await prefs.setString('${prefsKeyPrefix}_username', username!);
    await prefs.setString('${prefsKeyPrefix}_access_token', accessToken!);
    await prefs.setString('${prefsKeyPrefix}_user_id', userId!);
  }

  Future<void> disconnect() async {
    final currentProfileId = currentProfile?.id;

    isConnected = false;
    currentProfile = null;
    currentAddressId = null;
    serverUrl = null;
    username = null;
    password = null;
    accessToken = null;
    userId = null;
    selectedLibraryIds = [];
    isReady = false;

    clearServiceData();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${prefsKeyPrefix}_current_profile_id');
    await prefs.remove('${prefsKeyPrefix}_server_url');
    await prefs.remove('${prefsKeyPrefix}_username');
    await prefs.remove('${prefsKeyPrefix}_access_token');
    await prefs.remove('${prefsKeyPrefix}_user_id');
    await prefs.remove('${prefsKeyPrefix}_selected_libraries');

    if (currentProfileId != null) {
      try {
        await _multiAddressService.deleteProfile(currentProfileId);
        DebugLogService()
            .addLog('$serviceNameService: 已删除服务器配置文件 $currentProfileId');
      } catch (e) {
        DebugLogService()
            .addLog('$serviceNameService: 删除服务器配置文件失败: $e');
      }
    }
  }

  @protected
  Future<http.Response> makeAuthenticatedRequest(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    if (accessToken == null) {
      throw Exception(notConnectedMessage);
    }

    if (currentProfile != null) {
      return await _makeAuthenticatedRequestWithRetry(path,
          method: method, body: body, timeout: timeout);
    }

    if (serverUrl == null) {
      throw Exception(notConnectedMessage);
    }

    final uri = _buildRequestUri(path, baseUrl: serverUrl);
    final headers = await _buildAuthHeaders(body != null);

    final requestTimeout = timeout ?? const Duration(seconds: 30);

    http.Response response;
    try {
      switch (method.toUpperCase()) {
        case 'GET':
          response =
              await http.get(uri, headers: headers).timeout(requestTimeout);
          break;
        case 'POST':
          response = await http
              .post(uri,
                  headers: headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(requestTimeout);
          break;
        case 'PUT':
          response = await http
              .put(uri,
                  headers: headers,
                  body: body != null ? json.encode(body) : null)
              .timeout(requestTimeout);
          break;
        case 'DELETE':
          response =
              await http.delete(uri, headers: headers).timeout(requestTimeout);
          break;
        default:
          throw Exception('不支持的 HTTP 方法: $method');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('请求$serviceName服务器超时: ${e.message}');
      }
      throw Exception('请求$serviceName服务器失败: $e');
    }
    if (response.statusCode >= 400) {
      throw Exception(
          '服务器返回错误: ${response.statusCode} ${response.reasonPhrase ?? ''}\n${response.body}');
    }
    return response;
  }

  Future<http.Response> _makeAuthenticatedRequestWithRetry(String path,
      {String method = 'GET',
      Map<String, dynamic>? body,
      Duration? timeout}) async {
    if (currentProfile == null || accessToken == null) {
      throw Exception(notConnectedMessage);
    }

    final addresses = currentProfile!.enabledAddresses;
    if (addresses.isEmpty) {
      throw Exception('没有可用的服务器地址');
    }

    final headers = await _buildAuthHeaders(body != null);
    final requestTimeout = timeout ?? const Duration(seconds: 30);

    Exception? lastError;

    for (final address in addresses) {
      if (!address.shouldRetry()) continue;

      final uri = _buildRequestUri(path, baseUrl: address.normalizedUrl);

      try {
        http.Response response;
        switch (method.toUpperCase()) {
          case 'GET':
            response =
                await http.get(uri, headers: headers).timeout(requestTimeout);
            break;
          case 'POST':
            response = await http
                .post(uri,
                    headers: headers,
                    body: body != null ? json.encode(body) : null)
                .timeout(requestTimeout);
            break;
          case 'PUT':
            response = await http
                .put(uri,
                    headers: headers,
                    body: body != null ? json.encode(body) : null)
                .timeout(requestTimeout);
            break;
          case 'DELETE':
            response = await http
                .delete(uri, headers: headers)
                .timeout(requestTimeout);
            break;
          default:
            throw Exception('不支持的 HTTP 方法: $method');
        }

        if (response.statusCode < 400) {
          if (currentAddressId != address.id) {
            serverUrl = address.normalizedUrl;
            currentAddressId = address.id;
            currentProfile = currentProfile!.markAddressSuccess(address.id);
            await _multiAddressService.updateProfile(currentProfile!);
          }
          return response;
        } else {
          String errorMessage;
          if (response.statusCode == 401) {
            errorMessage = '认证失败: 访问令牌无效或已过期 (HTTP 401)';
          } else if (response.statusCode == 403) {
            errorMessage = '访问被拒绝: 用户权限不足 (HTTP 403)';
          } else if (response.statusCode == 404) {
            errorMessage = '请求的资源未找到 (HTTP 404)';
          } else if (response.statusCode >= 500) {
            errorMessage = '$serviceName服务器内部错误 (HTTP ${response.statusCode})';
          } else {
            errorMessage =
                '服务器返回错误: HTTP ${response.statusCode} ${response.reasonPhrase ?? ''}';
          }
          lastError = Exception(errorMessage);
          DebugLogService().addLog(
              '$serviceNameService: 请求失败 ${address.normalizedUrl}: $errorMessage');
        }
      } on TimeoutException catch (e) {
        lastError = Exception('请求超时: ${e.message}');
        currentProfile = currentProfile!.markAddressFailed(address.id);
      } catch (e) {
        lastError = Exception('请求失败: $e');
        currentProfile = currentProfile!.markAddressFailed(address.id);
      }
    }

    await _multiAddressService.updateProfile(currentProfile!);

    throw lastError ?? Exception('所有地址连接失败');
  }

  Uri _buildRequestUri(String path, {String? baseUrl}) {
    final normalizedPath = normalizeRequestPath(path);
    if (normalizedPath.startsWith('http://') ||
        normalizedPath.startsWith('https://')) {
      return Uri.parse(normalizedPath);
    }

    final resolvedBase = baseUrl ?? serverUrl;
    if (resolvedBase == null || resolvedBase.isEmpty) {
      throw Exception(notConnectedMessage);
    }

    return Uri.parse('$resolvedBase$normalizedPath');
  }

  Future<Map<String, String>> _buildAuthHeaders(bool hasBody) async {
    final clientInfo = await getClientInfo();
    final authHeader = '$clientInfo, Token=\"$accessToken\"';
    final headers = <String, String>{
      'X-Emby-Authorization': authHeader,
    };

    if (alwaysIncludeContentType || hasBody) {
      headers['Content-Type'] = 'application/json';
    }

    return headers;
  }

  List<ServerAddress> getServerAddresses() {
    if (currentProfile != null) {
      return currentProfile!.addresses;
    }
    return [];
  }

  Future<bool> addServerAddress(String url, String name) async {
    if (currentProfile == null) return false;

    final normalizedUrl = normalizeUrl(url);

    try {
      final identifyResult = await _multiAddressService.identifyServer(
        url: normalizedUrl,
        serverType: serviceType,
        getServerId: getServerId,
      );

      if (!identifyResult.success) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '无法验证服务器身份');
      }

      if (identifyResult.isConflict) {
        DebugLogService().addLog('添加地址失败: ${identifyResult.error}');
        throw Exception(identifyResult.error ?? '服务器冲突');
      }

      if (identifyResult.serverId != currentProfile!.serverId) {
        throw Exception(
            '该地址属于不同的$serviceName服务器（服务器ID: ${identifyResult.serverId}），无法添加到当前配置');
      }

      final updatedProfile = await _multiAddressService.addAddressToProfile(
        profileId: currentProfile!.id,
        url: normalizedUrl,
        name: UrlNameGenerator.generateAddressName(normalizedUrl,
            customName: name),
      );

      if (updatedProfile != null) {
        currentProfile = updatedProfile;
        DebugLogService().addLog('成功添加新地址: $normalizedUrl');
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('添加服务器地址失败: $e');
      rethrow;
    }
    return false;
  }

  Future<bool> removeServerAddress(String addressId) async {
    if (currentProfile == null) return false;

    try {
      final updatedProfile =
          await _multiAddressService.deleteAddressFromProfile(
        profileId: currentProfile!.id,
        addressId: addressId,
      );

      if (updatedProfile != null) {
        currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('删除服务器地址失败: $e');
    }
    return false;
  }

  Future<bool> switchToAddress(String addressId) async {
    if (currentProfile == null) return false;

    final address = currentProfile!.addresses.firstWhere(
      (addr) => addr.id == addressId,
      orElse: () => throw Exception('地址不存在'),
    );

    final success = await testConnection(
      address.normalizedUrl,
      username ?? '',
      password ?? '',
    );

    if (success) {
      try {
        final originalUrl = serverUrl;
        serverUrl = address.normalizedUrl;

        final authResponse =
            await makeAuthenticatedRequest(systemInfoPath)
                .timeout(const Duration(seconds: 5));

        if (authResponse.statusCode == 200) {
          currentAddressId = address.id;
          currentProfile = currentProfile!.markAddressSuccess(address.id);
          await _multiAddressService.updateProfile(currentProfile!);
          DebugLogService()
              .addLog('$serviceNameService: 成功切换到地址: ${address.normalizedUrl}');
          return true;
        } else {
          serverUrl = originalUrl;
          DebugLogService().addLog(
              '$serviceNameService: 地址切换失败，token在新地址上无效: HTTP ${authResponse.statusCode}');
          return false;
        }
      } catch (e) {
        serverUrl = currentProfile!.currentAddress?.normalizedUrl;
        DebugLogService().addLog('$serviceNameService: 地址切换失败，认证验证异常: $e');
        return false;
      }
    }

    return false;
  }

  Future<bool> updateServerPriority(String addressId, int priority) async {
    if (currentProfile == null) return false;

    try {
      final updatedProfile = await _multiAddressService.updateAddressPriority(
        profileId: currentProfile!.id,
        addressId: addressId,
        priority: priority,
      );

      if (updatedProfile != null) {
        currentProfile = updatedProfile;
        return true;
      }
    } catch (e) {
      DebugLogService().addLog('$serviceNameService: 更新地址优先级失败: $e');
    }

    return false;
  }

  Future<void> updateSelectedLibraries(List<String> libraryIds) async {
    selectedLibraryIds = libraryIds;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('${prefsKeyPrefix}_selected_libraries', libraryIds);
  }

  void setTranscodePreferences(
      {bool? enabled, JellyfinVideoQuality? defaultQuality}) {
    if (enabled != null) _transcodeEnabledCache = enabled;
    if (defaultQuality != null) _defaultQualityCache = defaultQuality;
    DebugLogService().addLog(
        '$serviceName: 更新转码偏好 缓存 enabled=${enabled ?? _transcodeEnabledCache}, quality=${defaultQuality ?? _defaultQualityCache}');
  }

  void setFullTranscodeSettings(JellyfinTranscodeSettings settings) {
    _settingsCache = settings;
    DebugLogService()
        .addLog('$serviceName: 更新完整转码设置缓存 (video/audio/subtitle/adaptive)');
  }
}

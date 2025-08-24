import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../models/server_profile_model.dart';
import 'debug_log_service.dart';

/// 多地址服务器管理服务
class MultiAddressServerService {
  static const String _profilesKey = 'server_profiles';
  static const Duration _connectionTimeout = Duration(seconds: 5);
  
  // 服务器配置列表
  List<ServerProfile> _profiles = [];
  
  // 单例模式
  static final MultiAddressServerService _instance = MultiAddressServerService._internal();
  factory MultiAddressServerService() => _instance;
  MultiAddressServerService._internal();
  
  static MultiAddressServerService get instance => _instance;
  
  List<ServerProfile> get profiles => List.unmodifiable(_profiles);
  
  /// 初始化服务，加载保存的配置
  Future<void> initialize() async {
    await loadProfiles();
  }
  
  /// 从存储加载服务器配置
  Future<void> loadProfiles() async {
    if (kIsWeb) {
      _profiles = [];
      return;
    }
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = prefs.getString(_profilesKey);
      
      if (profilesJson != null) {
        final List<dynamic> profilesList = json.decode(profilesJson);
        _profiles = profilesList
            .map((p) => ServerProfile.fromJson(p as Map<String, dynamic>))
            .toList();
        
        DebugLogService().addLog('MultiAddressServer: 加载了 ${_profiles.length} 个服务器配置');
      }
    } catch (e) {
      DebugLogService().addLog('MultiAddressServer: 加载配置失败: $e');
      _profiles = [];
    }
  }
  
  /// 保存服务器配置到存储
  Future<void> saveProfiles() async {
    if (kIsWeb) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final profilesJson = json.encode(_profiles.map((p) => p.toJson()).toList());
      await prefs.setString(_profilesKey, profilesJson);
      
      DebugLogService().addLog('MultiAddressServer: 保存了 ${_profiles.length} 个服务器配置');
    } catch (e) {
      DebugLogService().addLog('MultiAddressServer: 保存配置失败: $e');
    }
  }
  
  /// 添加新的服务器配置
  Future<ServerProfile?> addProfile({
    required String serverName,
    required String serverType,
    required String url,
    required String username,
    String? serverId,
    String? addressName,
  }) async {
    // 规范化URL
    final normalizedUrl = _normalizeUrl(url);
    
    // 创建新地址 (第一个地址优先级为0)
    final address = ServerAddress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: normalizedUrl,
      name: addressName ?? '默认地址',
      priority: 0,
    );
    
    // 创建新配置
    final profile = ServerProfile(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      serverName: serverName,
      serverType: serverType,
      addresses: [address],
      username: username,
      serverId: serverId,
    );
    
    _profiles.add(profile);
    await saveProfiles();
    
    return profile;
  }
  
  /// 通过服务器ID获取配置
  ServerProfile? getProfileById(String id) {
    return _profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('未找到服务器配置'),
    );
  }
  
  /// 通过远程服务器ID获取配置
  ServerProfile? getProfileByServerId(String serverId, String serverType) {
    try {
      return _profiles.firstWhere(
        (p) => p.serverId == serverId && p.serverType == serverType,
      );
    } catch (e) {
      return null;
    }
  }
  
  /// 通过服务器类型和用户名查找配置
  ServerProfile? findProfile({
    required String serverType,
    required String username,
    String? serverUrl,
  }) {
    for (final profile in _profiles) {
      if (profile.serverType == serverType && profile.username == username) {
        // 如果提供了URL，检查是否有匹配的地址
        if (serverUrl != null) {
          final normalizedUrl = _normalizeUrl(serverUrl);
          final hasMatchingAddress = profile.addresses.any(
            (addr) => addr.normalizedUrl == normalizedUrl,
          );
          if (hasMatchingAddress) return profile;
        } else {
          return profile;
        }
      }
    }
    return null;
  }
  
  /// 向现有配置添加新地址
  Future<ServerProfile?> addAddressToProfile({
    required String profileId,
    required String url,
    required String name,
    int? priority,
  }) async {
    final profileIndex = _profiles.indexWhere((p) => p.id == profileId);
    if (profileIndex == -1) return null;
    
    final profile = _profiles[profileIndex];
    final normalizedUrl = _normalizeUrl(url);
    
    // 检查地址是否已存在
    final existingAddress = profile.addresses.firstWhere(
      (addr) => addr.normalizedUrl == normalizedUrl,
      orElse: () => ServerAddress(id: '', url: '', name: ''),
    );
    
    if (existingAddress.id.isNotEmpty) {
      DebugLogService().addLog('MultiAddressServer: 地址已存在: $normalizedUrl');
      return profile;
    }
    
    // 如果没有指定优先级，设置为比现有最大优先级+1
    int finalPriority = priority ?? 0;
    if (priority == null && profile.addresses.isNotEmpty) {
      final maxPriority = profile.addresses.map((a) => a.priority).reduce((a, b) => a > b ? a : b);
      finalPriority = maxPriority + 1;
    }
    
    // 添加新地址
    final newAddress = ServerAddress(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      url: normalizedUrl,
      name: name,
      priority: finalPriority,
    );
    
    final updatedProfile = profile.copyWith(
      addresses: [...profile.addresses, newAddress],
    );
    
    _profiles[profileIndex] = updatedProfile;
    await saveProfiles();
    
    return updatedProfile;
  }
  
  /// 更新服务器配置
  Future<void> updateProfile(ServerProfile profile) async {
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index != -1) {
      _profiles[index] = profile;
      await saveProfiles();
    }
  }
  
  /// 删除服务器配置
  Future<void> deleteProfile(String profileId) async {
    _profiles.removeWhere((p) => p.id == profileId);
    await saveProfiles();
  }
  
  /// 删除配置中的某个地址
  Future<ServerProfile?> deleteAddressFromProfile({
    required String profileId,
    required String addressId,
  }) async {
    final profileIndex = _profiles.indexWhere((p) => p.id == profileId);
    if (profileIndex == -1) return null;
    
    final profile = _profiles[profileIndex];
    
    // 不能删除最后一个地址
    if (profile.addresses.length <= 1) {
      throw Exception('不能删除最后一个地址');
    }
    
    final updatedAddresses = profile.addresses
        .where((addr) => addr.id != addressId)
        .toList();
    
    final updatedProfile = profile.copyWith(addresses: updatedAddresses);
    _profiles[profileIndex] = updatedProfile;
    await saveProfiles();
    
    return updatedProfile;
  }
  
  /// 更新地址的启用状态
  Future<ServerProfile?> toggleAddressEnabled({
    required String profileId,
    required String addressId,
    required bool enabled,
  }) async {
    final profileIndex = _profiles.indexWhere((p) => p.id == profileId);
    if (profileIndex == -1) return null;
    
    final profile = _profiles[profileIndex];
    final updatedAddresses = profile.addresses.map((addr) {
      if (addr.id == addressId) {
        return addr.copyWith(isEnabled: enabled);
      }
      return addr;
    }).toList();
    
    final updatedProfile = profile.copyWith(addresses: updatedAddresses);
    _profiles[profileIndex] = updatedProfile;
    await saveProfiles();
    
    return updatedProfile;
  }

  /// 更新地址的优先级
  Future<ServerProfile?> updateAddressPriority({
    required String profileId,
    required String addressId,
    required int priority,
  }) async {
    final profileIndex = _profiles.indexWhere((p) => p.id == profileId);
    if (profileIndex == -1) return null;
    
    final profile = _profiles[profileIndex];
    final updatedAddresses = profile.addresses.map((addr) {
      if (addr.id == addressId) {
        return addr.copyWith(priority: priority);
      }
      return addr;
    }).toList();
    
    final updatedProfile = profile.copyWith(addresses: updatedAddresses);
    _profiles[profileIndex] = updatedProfile;
    await saveProfiles();
    
    return updatedProfile;
  }
  
  /// 尝试连接到服务器（使用多个地址）
  Future<ConnectionResult> tryConnect({
    required ServerProfile profile,
    required Future<bool> Function(String url) testConnection,
  }) async {
    final addresses = profile.enabledAddresses;
    
    if (addresses.isEmpty) {
      return ConnectionResult(
        success: false,
        error: '没有可用的服务器地址',
      );
    }
    
    String? lastError;
    ServerProfile updatedProfile = profile;
    
    // 按优先级尝试每个地址
    for (final address in addresses) {
      if (!address.shouldRetry()) {
        DebugLogService().addLog(
          'MultiAddressServer: 跳过地址 ${address.name} (${address.url}) - 失败次数过多'
        );
        continue;
      }
      
      DebugLogService().addLog(
        'MultiAddressServer: 尝试连接 ${address.name} (${address.url})'
      );
      
      try {
        final success = await testConnection(address.normalizedUrl)
            .timeout(_connectionTimeout);
        
        if (success) {
          // 标记成功
          updatedProfile = updatedProfile.markAddressSuccess(address.id);
          await updateProfile(updatedProfile);
          
          DebugLogService().addLog(
            'MultiAddressServer: 成功连接到 ${address.name} (${address.url})'
          );
          
          return ConnectionResult(
            success: true,
            successfulUrl: address.normalizedUrl,
            successfulAddressId: address.id,
            profile: updatedProfile,
          );
        } else {
          lastError = '服务器验证失败';
          updatedProfile = updatedProfile.markAddressFailed(address.id);
        }
      } on TimeoutException {
        lastError = '连接超时';
        updatedProfile = updatedProfile.markAddressFailed(address.id);
        DebugLogService().addLog(
          'MultiAddressServer: 地址 ${address.name} 连接超时'
        );
      } catch (e) {
        lastError = e.toString();
        updatedProfile = updatedProfile.markAddressFailed(address.id);
        DebugLogService().addLog(
          'MultiAddressServer: 地址 ${address.name} 连接失败: $e'
        );
      }
    }
    
    // 更新失败信息
    await updateProfile(updatedProfile);
    
    return ConnectionResult(
      success: false,
      error: lastError ?? '所有地址连接失败',
    );
  }
  
  /// 检查服务器是否可达（通过服务器ID和特定URL识别）
  Future<ServerIdentifyResult> identifyServer({
    required String url,
    required String serverType,
    required Future<String?> Function(String url) getServerId,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    
    DebugLogService().addLog('MultiAddressServer: 开始识别服务器 - URL: $normalizedUrl, Type: $serverType');
    
    try {
      final serverId = await getServerId(normalizedUrl)
          .timeout(_connectionTimeout);
      
      DebugLogService().addLog('MultiAddressServer: 获取到服务器ID - $serverId');
      
      if (serverId == null) {
        DebugLogService().addLog('MultiAddressServer: 无法获取服务器ID，无法进行冲突验证');
        
        // 检查URL是否已被占用
        for (final profile in _profiles) {
          if (profile.serverType == serverType) {
            for (final addr in profile.addresses) {
              if (addr.normalizedUrl == normalizedUrl) {
                DebugLogService().addLog('MultiAddressServer: 发现URL冲突（无法获取新服务器ID）- 现有配置: ${profile.id}');
                return ServerIdentifyResult(
                  success: false,
                  error: '该URL已被占用，且无法获取新服务器的ID进行验证。请检查服务器连接或使用不同的URL',
                  isConflict: true,
                  existingProfile: profile,
                );
              }
            }
          }
        }
        
        // 即使没有URL冲突，也要拒绝添加，因为无法验证服务器身份
        return ServerIdentifyResult(
          success: false,
          error: '无法获取${serverType}服务器ID，无法验证服务器身份。请检查服务器连接和URL格式',
        );
      }
      
      // 查找是否有相同serverId的服务器配置
      ServerProfile? existingProfile;
      DebugLogService().addLog('MultiAddressServer: 搜索现有配置，总数: ${_profiles.length}');
      
      for (final profile in _profiles) {
        DebugLogService().addLog('MultiAddressServer: 检查配置 - Type: ${profile.serverType}, ServerId: ${profile.serverId}, Username: ${profile.username}');
        if (profile.serverType == serverType && profile.serverId == serverId) {
          // 通过serverId匹配找到相同的服务器
          DebugLogService().addLog('MultiAddressServer: 通过serverId找到现有配置: ${profile.id}');
          existingProfile = profile;
          break;
        }
      }
      
      // 如果没有通过serverId找到，检查是否存在URL冲突
      if (existingProfile == null) {
        DebugLogService().addLog('MultiAddressServer: 没有通过serverId找到配置，检查URL冲突');
        for (final profile in _profiles) {
          if (profile.serverType == serverType) {
            for (final addr in profile.addresses) {
              DebugLogService().addLog('MultiAddressServer: 检查地址 - URL: ${addr.normalizedUrl}, 目标URL: $normalizedUrl');
              if (addr.normalizedUrl == normalizedUrl) {
                DebugLogService().addLog('MultiAddressServer: 找到相同URL的配置 - ProfileServerId: ${profile.serverId}, 当前ServerId: $serverId');
                // 找到相同URL的配置
                          if (profile.serverId != null && profile.serverId != serverId) {
            // URL相同但serverId不同，这是冲突情况
            DebugLogService().addLog('MultiAddressServer: 检测到冲突！URL相同但serverId不同');
            return ServerIdentifyResult(
              success: false,
              error: '该URL已被另一个${serverType}服务器占用 (服务器ID: ${profile.serverId})',
              isConflict: true,
              existingProfile: profile,
            );
          } else if (profile.serverId == null) {
            // 现有配置没有serverId，但URL已被占用 - 这也是冲突情况
            DebugLogService().addLog('MultiAddressServer: URL已被占用，且现有配置缺少serverId验证信息');
            return ServerIdentifyResult(
              success: false,
              error: '该URL已被占用，现有配置缺少服务器ID验证信息，请手动处理冲突',
              isConflict: true,
              existingProfile: profile,
            );
          } else if (profile.serverId == serverId) {
            // URL和serverId都相同，这是同一台服务器
            DebugLogService().addLog('MultiAddressServer: 找到相同URL和serverId的现有配置');
            existingProfile = profile;
          }
                break;
              }
            }
            if (existingProfile != null) break;
          }
        }
      }
      
      DebugLogService().addLog('MultiAddressServer: 识别成功 - ServerId: $serverId, 现有配置: ${existingProfile?.id}');
      return ServerIdentifyResult(
        success: true,
        serverId: serverId,
        existingProfile: existingProfile,
        url: normalizedUrl,
      );
    } on TimeoutException {
      DebugLogService().addLog('MultiAddressServer: 识别失败 - 连接超时');
      return ServerIdentifyResult(
        success: false,
        error: '连接超时',
      );
    } catch (e) {
      DebugLogService().addLog('MultiAddressServer: 识别失败 - 异常: $e');
      return ServerIdentifyResult(
        success: false,
        error: e.toString(),
      );
    }
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
}

/// 连接结果
class ConnectionResult {
  final bool success;
  final String? successfulUrl;
  final String? successfulAddressId;
  final String? error;
  final ServerProfile? profile;
  
  ConnectionResult({
    required this.success,
    this.successfulUrl,
    this.successfulAddressId,
    this.error,
    this.profile,
  });
}

/// 服务器识别结果
class ServerIdentifyResult {
  final bool success;
  final String? serverId;
  final String? url;
  final ServerProfile? existingProfile;
  final String? error;
  final bool isConflict; // 是否存在URL冲突（相同URL但不同serverId）
  
  ServerIdentifyResult({
    required this.success,
    this.serverId,
    this.url,
    this.existingProfile,
    this.error,
    this.isConflict = false,
  });
}

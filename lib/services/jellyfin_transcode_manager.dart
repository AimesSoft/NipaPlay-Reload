import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/jellyfin_transcode_settings.dart';

/// Jellyfin 转码设置管理器
/// 职责：管理转码相关的设置持久化和获取
class JellyfinTranscodeManager {
  static final JellyfinTranscodeManager instance = JellyfinTranscodeManager._internal();
  
  JellyfinTranscodeManager._internal();
  
  // 设置键名常量
  static const String _keyTranscodeSettings = 'jellyfin_transcode_settings';
  static const String _keyDefaultQuality = 'jellyfin_default_quality';
  static const String _keyEnableTranscoding = 'jellyfin_enable_transcoding';
  
  // 内存缓存
  JellyfinTranscodeSettings? _cachedSettings;
  bool _isInitialized = false;
  
  /// 初始化管理器
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      await _loadSettings();
      _isInitialized = true;
    } catch (e) {
      debugPrint('JellyfinTranscodeManager 初始化失败: $e');
      // 使用默认设置
      _cachedSettings = const JellyfinTranscodeSettings();
      _isInitialized = true;
    }
  }
  
  /// 获取当前的转码设置
  Future<JellyfinTranscodeSettings> getSettings() async {
    if (!_isInitialized) {
      await initialize();
    }
    
    return _cachedSettings ?? const JellyfinTranscodeSettings();
  }
  
  /// 保存转码设置
  Future<void> saveSettings(JellyfinTranscodeSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(settings.toJson());
      
      await prefs.setString(_keyTranscodeSettings, jsonString);
      
      // 更新内存缓存
      _cachedSettings = settings;
      
      debugPrint('Jellyfin转码设置已保存');
    } catch (e) {
      debugPrint('保存转码设置失败: $e');
      rethrow;
    }
  }
  
  /// 获取默认视频质量
  Future<JellyfinVideoQuality> getDefaultVideoQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final qualityString = prefs.getString(_keyDefaultQuality);
      
      if (qualityString != null) {
        final qualityIndex = int.tryParse(qualityString);
        if (qualityIndex != null && qualityIndex < JellyfinVideoQuality.values.length) {
          return JellyfinVideoQuality.values[qualityIndex];
        }
      }
      
      // 默认值：5Mbps高清
      return JellyfinVideoQuality.bandwidth5m;
    } catch (e) {
      debugPrint('获取默认视频质量失败: $e');
      return JellyfinVideoQuality.bandwidth5m;
    }
  }
  
  /// 保存默认视频质量
  Future<void> saveDefaultVideoQuality(JellyfinVideoQuality quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultQuality, quality.index.toString());
      
      debugPrint('默认视频质量已保存: ${quality.displayName}');
    } catch (e) {
      debugPrint('保存默认视频质量失败: $e');
      rethrow;
    }
  }
  
  /// 获取是否启用转码
  Future<bool> isTranscodingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabledString = prefs.getString(_keyEnableTranscoding);
      
      if (enabledString != null) {
        return enabledString.toLowerCase() == 'true';
      }
      
      // 默认关闭转码，保持原有直连体验
      return false;
    } catch (e) {
      debugPrint('获取转码启用状态失败: $e');
      return false;
    }
  }
  
  /// 设置是否启用转码
  Future<void> setTranscodingEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnableTranscoding, enabled.toString());
      
      debugPrint('转码启用状态已保存: $enabled');
    } catch (e) {
      debugPrint('保存转码启用状态失败: $e');
      rethrow;
    }
  }
  
  /// 重置所有设置为默认值
  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTranscodeSettings);
      await prefs.remove(_keyDefaultQuality);
      await prefs.remove(_keyEnableTranscoding);
      
      // 清除内存缓存
      _cachedSettings = null;
      
      debugPrint('Jellyfin转码设置已重置为默认值');
    } catch (e) {
      debugPrint('重置转码设置失败: $e');
      rethrow;
    }
  }
  
  /// 从SharedPreferences加载设置
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsString = prefs.getString(_keyTranscodeSettings);
      
      if (settingsString != null && settingsString.isNotEmpty) {
        final jsonData = json.decode(settingsString) as Map<String, dynamic>;
        _cachedSettings = JellyfinTranscodeSettings.fromJson(jsonData);
      } else {
        // 使用默认设置
        _cachedSettings = const JellyfinTranscodeSettings();
      }
    } catch (e) {
      debugPrint('加载转码设置失败: $e');
      _cachedSettings = const JellyfinTranscodeSettings();
    }
  }
  
  /// 获取基于网络状况的推荐质量
  /// [networkSpeedMbps] 网络速度（Mbps）
  JellyfinVideoQuality getRecommendedQuality(double networkSpeedMbps) {
    // 边界情况处理
    if (networkSpeedMbps <= 0) {
      return JellyfinVideoQuality.bandwidth1m;
    }
    
    // 留一定余量，避免缓冲
    final effectiveSpeed = networkSpeedMbps * 0.8;
    
    if (effectiveSpeed >= 35) {
      return JellyfinVideoQuality.bandwidth40m;  // 4K
    } else if (effectiveSpeed >= 16) {
      return JellyfinVideoQuality.bandwidth20m;  // 1080p超清
    } else if (effectiveSpeed >= 8) {
      return JellyfinVideoQuality.bandwidth10m;  // 1080p
    } else if (effectiveSpeed >= 4) {
      return JellyfinVideoQuality.bandwidth5m;   // 720p
    } else if (effectiveSpeed >= 1.5) {
      return JellyfinVideoQuality.bandwidth2m;   // 480p
    } else {
      return JellyfinVideoQuality.bandwidth1m;   // 360p
    }
  }
}

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/jellyfin_transcode_settings.dart';

/// Emby 转码设置管理器（与 Jellyfin 分离存储）
class EmbyTranscodeManager {
  static final EmbyTranscodeManager instance = EmbyTranscodeManager._internal();

  EmbyTranscodeManager._internal();

  static const String _keyTranscodeSettings = 'emby_transcode_settings';
  static const String _keyDefaultQuality = 'emby_default_quality';
  static const String _keyEnableTranscoding = 'emby_enable_transcoding';

  JellyfinTranscodeSettings? _cachedSettings;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _loadSettings();
      _isInitialized = true;
    } catch (e) {
      debugPrint('EmbyTranscodeManager 初始化失败: $e');
      _cachedSettings = const JellyfinTranscodeSettings();
      _isInitialized = true;
    }
  }

  Future<JellyfinTranscodeSettings> getSettings() async {
    if (!_isInitialized) await initialize();
    return _cachedSettings ?? const JellyfinTranscodeSettings();
  }

  Future<void> saveSettings(JellyfinTranscodeSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(settings.toJson());
      await prefs.setString(_keyTranscodeSettings, jsonString);
      _cachedSettings = settings;
      debugPrint('Emby 转码设置已保存');
    } catch (e) {
      debugPrint('保存 Emby 转码设置失败: $e');
      rethrow;
    }
  }

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
      return JellyfinVideoQuality.bandwidth5m;
    } catch (e) {
      debugPrint('获取 Emby 默认视频质量失败: $e');
      return JellyfinVideoQuality.bandwidth5m;
    }
  }

  Future<void> saveDefaultVideoQuality(JellyfinVideoQuality quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyDefaultQuality, quality.index.toString());
      debugPrint('Emby 默认视频质量已保存: ${quality.displayName}');
    } catch (e) {
      debugPrint('保存 Emby 默认视频质量失败: $e');
      rethrow;
    }
  }

  Future<bool> isTranscodingEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabledString = prefs.getString(_keyEnableTranscoding);
      if (enabledString != null) return enabledString.toLowerCase() == 'true';
      // 默认关闭转码，保持原有直连体验
      return false;
    } catch (e) {
      debugPrint('获取 Emby 转码启用状态失败: $e');
      return false;
    }
  }

  Future<void> setTranscodingEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnableTranscoding, enabled.toString());
      debugPrint('Emby 转码启用状态已保存: $enabled');
    } catch (e) {
      debugPrint('保存 Emby 转码启用状态失败: $e');
      rethrow;
    }
  }

  Future<void> resetToDefaults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyTranscodeSettings);
      await prefs.remove(_keyDefaultQuality);
      await prefs.remove(_keyEnableTranscoding);
      _cachedSettings = null;
      debugPrint('Emby 转码设置已重置');
    } catch (e) {
      debugPrint('重置 Emby 转码设置失败: $e');
      rethrow;
    }
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final settingsString = prefs.getString(_keyTranscodeSettings);
      if (settingsString != null && settingsString.isNotEmpty) {
        final jsonData = json.decode(settingsString) as Map<String, dynamic>;
        _cachedSettings = JellyfinTranscodeSettings.fromJson(jsonData);
      } else {
        _cachedSettings = const JellyfinTranscodeSettings();
      }
    } catch (e) {
      debugPrint('加载 Emby 转码设置失败: $e');
      _cachedSettings = const JellyfinTranscodeSettings();
    }
  }

  JellyfinVideoQuality getRecommendedQuality(double networkSpeedMbps) {
    if (networkSpeedMbps <= 0) return JellyfinVideoQuality.bandwidth1m;
    final effectiveSpeed = networkSpeedMbps * 0.8;
    if (effectiveSpeed >= 35) return JellyfinVideoQuality.bandwidth40m;
    if (effectiveSpeed >= 16) return JellyfinVideoQuality.bandwidth20m;
    if (effectiveSpeed >= 8) return JellyfinVideoQuality.bandwidth10m;
    if (effectiveSpeed >= 4) return JellyfinVideoQuality.bandwidth5m;
    if (effectiveSpeed >= 1.5) return JellyfinVideoQuality.bandwidth2m;
    return JellyfinVideoQuality.bandwidth1m;
  }
}

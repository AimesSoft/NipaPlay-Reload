import 'package:flutter/material.dart';
import 'package:nipaplay/services/emby_transcode_manager.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/services/emby_service.dart';

class EmbyTranscodeProvider extends ChangeNotifier {
  static final EmbyTranscodeProvider _instance = EmbyTranscodeProvider._internal();
  factory EmbyTranscodeProvider() => _instance;
  EmbyTranscodeProvider._internal();

  final EmbyTranscodeManager _transcodeManager = EmbyTranscodeManager.instance;

  JellyfinTranscodeSettings _settings = const JellyfinTranscodeSettings();
  bool _transcodeEnabled = true;
  bool _isInitialized = false;

  JellyfinTranscodeSettings get settings => _settings;
  bool get transcodeEnabled => _transcodeEnabled;
  JellyfinVideoQuality get currentVideoQuality => _settings.video.quality;
  bool get isInitialized => _isInitialized;

  Future<void> initialize() async {
    if (_isInitialized) return;
    try {
      await _transcodeManager.initialize();
      await _loadSettings();
      _isInitialized = true;
    } catch (e) {
      debugPrint('EmbyTranscodeProvider 初始化失败: $e');
      _isInitialized = true;
    }
  }

  Future<void> _loadSettings() async {
    try {
      _settings = await _transcodeManager.getSettings();
      _transcodeEnabled = await _transcodeManager.isTranscodingEnabled();
      notifyListeners();
    } catch (e) {
      debugPrint('加载 Emby 转码设置失败: $e');
    }
  }

  Future<bool> setTranscodeEnabled(bool enabled) async {
    try {
      await _transcodeManager.setTranscodingEnabled(enabled);
      _transcodeEnabled = enabled;
      try {
        EmbyService.instance.setTranscodePreferences(enabled: enabled);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新 Emby 转码启用状态失败: $e');
      return false;
    }
  }

  Future<bool> setDefaultVideoQuality(JellyfinVideoQuality quality) async {
    try {
      await _transcodeManager.saveDefaultVideoQuality(quality);
      _settings = _settings.copyWith(video: _settings.video.copyWith(quality: quality));
      await _transcodeManager.saveSettings(_settings);
      try {
        EmbyService.instance.setTranscodePreferences(defaultQuality: quality);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新 Emby 默认视频质量失败: $e');
      return false;
    }
  }

  Future<bool> updateSettings(JellyfinTranscodeSettings settings) async {
    try {
      await _transcodeManager.saveSettings(settings);
      _settings = settings;
      try {
        EmbyService.instance.setFullTranscodeSettings(settings);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新 Emby 转码设置失败: $e');
      return false;
    }
  }

  Future<void> refresh() async {
    if (!_isInitialized) {
      await initialize();
      return;
    }
    await _loadSettings();
  }

  JellyfinVideoQuality getRecommendedQuality(double networkSpeedMbps) {
    return _transcodeManager.getRecommendedQuality(networkSpeedMbps);
  }

  Future<bool> resetToDefaults() async {
    try {
      await _transcodeManager.resetToDefaults();
      await _loadSettings();
      return true;
    } catch (e) {
      debugPrint('Emby 重置转码设置失败: $e');
      return false;
    }
  }
}

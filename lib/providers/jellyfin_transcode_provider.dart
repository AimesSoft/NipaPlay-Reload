import 'package:flutter/material.dart';
import 'package:nipaplay/services/jellyfin_transcode_manager.dart';
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/services/jellyfin_service.dart';

/// Jellyfin转码设置Provider
/// 负责管理全局转码设置状态和同步
class JellyfinTranscodeProvider extends ChangeNotifier {
  static final JellyfinTranscodeProvider _instance = JellyfinTranscodeProvider._internal();
  factory JellyfinTranscodeProvider() => _instance;
  JellyfinTranscodeProvider._internal();

  final JellyfinTranscodeManager _transcodeManager = JellyfinTranscodeManager.instance;
  
  JellyfinTranscodeSettings _settings = const JellyfinTranscodeSettings();
  bool _transcodeEnabled = true;
  bool _isInitialized = false;

  /// 当前转码设置
  JellyfinTranscodeSettings get settings => _settings;
  
  /// 是否启用转码
  bool get transcodeEnabled => _transcodeEnabled;
  
  /// 当前默认视频质量
  JellyfinVideoQuality get currentVideoQuality => _settings.video.quality;
  
  /// 是否已初始化
  bool get isInitialized => _isInitialized;

  /// 初始化Provider
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _transcodeManager.initialize();
      await _loadSettings();
      _isInitialized = true;
    } catch (e) {
      debugPrint('JellyfinTranscodeProvider初始化失败: $e');
      _isInitialized = true; // 即使失败也标记为已初始化，避免重复尝试
    }
  }

  /// 加载转码设置
  Future<void> _loadSettings() async {
    try {
      _settings = await _transcodeManager.getSettings();
      _transcodeEnabled = await _transcodeManager.isTranscodingEnabled();
      notifyListeners();
    } catch (e) {
      debugPrint('加载转码设置失败: $e');
    }
  }

  /// 更新转码启用状态
  Future<bool> setTranscodeEnabled(bool enabled) async {
    try {
      await _transcodeManager.setTranscodingEnabled(enabled);
      _transcodeEnabled = enabled;
      
      // 如果关闭转码，自动将质量重置为原画
      if (!enabled) {
        await _transcodeManager.saveDefaultVideoQuality(JellyfinVideoQuality.original);
        _settings = _settings.copyWith(
          video: _settings.video.copyWith(quality: JellyfinVideoQuality.original)
        );
      }
      
      // 同步到 JellyfinService 的转码偏好缓存
      try {
        JellyfinService.instance.setTranscodePreferences(
          enabled: enabled,
          defaultQuality: !enabled ? JellyfinVideoQuality.original : null,
        );
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新转码启用状态失败: $e');
      return false;
    }
  }

  /// 更新默认视频质量
  Future<bool> setDefaultVideoQuality(JellyfinVideoQuality quality) async {
    try {
      await _transcodeManager.saveDefaultVideoQuality(quality);
      
      // 更新本地设置
      _settings = _settings.copyWith(
        video: _settings.video.copyWith(quality: quality),
      );
      
      // 同时保存完整设置
      await _transcodeManager.saveSettings(_settings);
      // 同步到 JellyfinService 的转码偏好缓存
      try {
        JellyfinService.instance.setTranscodePreferences(defaultQuality: quality);
      } catch (_) {}
      
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新默认视频质量失败: $e');
      return false;
    }
  }

  /// 更新完整转码设置
  Future<bool> updateSettings(JellyfinTranscodeSettings settings) async {
    try {
      await _transcodeManager.saveSettings(settings);
      _settings = settings;
      // 同步到 JellyfinService 的完整设置缓存
      try {
        JellyfinService.instance.setFullTranscodeSettings(settings);
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('更新转码设置失败: $e');
      return false;
    }
  }

  /// 重新加载设置（用于外部修改后同步）
  Future<void> refresh() async {
    if (!_isInitialized) {
      await initialize();
      return;
    }
    await _loadSettings();
  }

  /// 获取基于网络状况的推荐质量
  JellyfinVideoQuality getRecommendedQuality(double networkSpeedMbps) {
    return _transcodeManager.getRecommendedQuality(networkSpeedMbps);
  }

  /// 重置为默认设置
  Future<bool> resetToDefaults() async {
    try {
      await _transcodeManager.resetToDefaults();
      await _loadSettings();
      return true;
    } catch (e) {
      debugPrint('重置转码设置失败: $e');
      return false;
    }
  }
}

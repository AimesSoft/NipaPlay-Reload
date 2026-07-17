import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../player_abstraction/player_abstraction.dart';
import '../services/remote_subtitle_service.dart';
import 'media_source_utils.dart';

/// 外部音频轨道管理器
/// 负责自动检测同名MKA文件并加载为外部音频轨道
class AudioTrackManager {
  Player _player;
  String? _currentVideoPath;
  String? _externalAudioPath;

  static const String _prefsKey = 'external_audio_mappings';

  AudioTrackManager({required Player player}) : _player = player;

  /// 更新播放器引用（内核热切换时调用）
  void updatePlayer(Player newPlayer) {
    _player = newPlayer;
  }

  /// 设置当前视频路径
  void setCurrentVideoPath(String? path) {
    _currentVideoPath = path;
    if (path == null) {
      _externalAudioPath = null;
    }
  }

  /// 当前加载的外部音频路径
  String? get externalAudioPath => _externalAudioPath;

  /// 检测同名.mka文件路径（不加载，仅返回路径）
  /// 用于在主媒体打开前获取MKA路径
  /// 支持本地文件和共享远程媒体库
  Future<String?> detectExternalAudioPath(String videoPath) async {
    if (kIsWeb) return null;
    if (MediaSourceUtils.isContentUri(videoPath)) return null;
    if (kDebugMode) debugPrint('[MKA_DEBUG] detectExternalAudioPath: videoPath=$videoPath');

    // 检查是否来自共享远程媒体库
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      return _detectRemoteExternalAudioPath(videoPath);
    }

    // 非本地文件协议不支持
    if (videoPath.startsWith('jellyfin://') ||
        videoPath.startsWith('emby://')) {
      return null;
    }

    try {
      final videoFile = File(videoPath);
      if (!videoFile.existsSync()) return null;

      final videoDir = videoFile.parent.path;
      final videoName = p.basenameWithoutExtension(videoPath);
      final mkaPath = p.join(videoDir, '$videoName.mka');

      final mkaFile = File(mkaPath);
      if (!mkaFile.existsSync()) {
        debugPrint('AudioTrackManager: 未找到同名MKA文件: $mkaPath');
        return null;
      }

      debugPrint('AudioTrackManager: 找到同名MKA文件: $mkaPath');
      return mkaPath;
    } catch (e) {
      debugPrint('AudioTrackManager: 检测外部音频失败: $e');
      return null;
    }
  }

  /// 检测远程共享媒体库的外挂音轨，下载到缓存后返回本地路径
  Future<String?> _detectRemoteExternalAudioPath(String videoPath) async {
    try {
      if (!RemoteSubtitleService.instance.isPotentialRemoteVideoPath(videoPath)) {
        if (kDebugMode) debugPrint('[MKA_DEBUG] _detectRemoteExternalAudioPath: 不是远程视频路径');
        return null;
      }

      if (kDebugMode) debugPrint('[MKA_DEBUG] _detectRemoteExternalAudioPath: 调用 listExternalAudioForVideo...');
      final candidates = await RemoteSubtitleService.instance
          .listExternalAudioForVideo(videoPath);
      if (kDebugMode) debugPrint('[MKA_DEBUG] listExternalAudioForVideo 返回 ${candidates.length} 个候选');
      for (int i = 0; i < candidates.length; i++) {
        final c = candidates[i];
        if (kDebugMode) debugPrint('[MKA_DEBUG] 音轨候选[$i]: name=${c.name}, ext=${c.extension}, isLikelyMatch=${c.isLikelyMatch}, uri=${c.audioUri}');
      }
      if (candidates.isEmpty) {
        if (kDebugMode) debugPrint('[MKA_DEBUG] 远程媒体库未找到外挂音轨');
        return null;
      }

      // 优先选择 isLikelyMatch 的候选（同名 MKA）
      // 无匹配候选时返回 null，避免加载不相关音频（如 OP/ED 或其他集数音轨）
      RemoteAudioCandidate? best;
      for (final c in candidates) {
        if (c.isLikelyMatch) {
          best = c;
          break;
        }
      }
      if (best == null) {
        if (kDebugMode) debugPrint('[MKA_DEBUG] 无 isLikelyMatch 候选，跳过不相关音轨');
        return null;
      }

      if (kDebugMode) debugPrint('[MKA_DEBUG] 选中音轨: ${best.name}, 正在下载到缓存...');
      final cachedPath = await RemoteSubtitleService.instance
          .ensureAudioCached(best);
      if (kDebugMode) debugPrint('[MKA_DEBUG] 远程外挂音轨已缓存: $cachedPath');
      return cachedPath;
    } catch (e) {
      if (kDebugMode) debugPrint('[MKA_DEBUG] 检测远程外挂音轨失败: $e');
      return null;
    }
  }

  /// 为MediaKit内核预加载外部音频（必须在主媒体打开前调用）
  /// 通过setMedia(audio)将路径暂存到_pendingExternalAudioFile，
  /// MediaKit适配器会在主媒体加载后通过audio-add命令将外部音频添加为轨道
  void preloadExternalAudioForMediaKit(String mkaPath) {
    try {
      _player.setMedia(mkaPath, MediaType.audio);
      _externalAudioPath = mkaPath;
      debugPrint('AudioTrackManager: MediaKit预加载外部音频: $mkaPath');
    } catch (e) {
      debugPrint('AudioTrackManager: MediaKit预加载外部音频失败: $e');
    }
  }

  /// 为MDK内核加载外部音频（必须在主媒体prepare成功后调用）
  void loadExternalAudioForMdk(String mkaPath) {
    try {
      _player.setMedia(mkaPath, MediaType.audio);
      _externalAudioPath = mkaPath;
      debugPrint('AudioTrackManager: MDK加载外部音频: $mkaPath');
    } catch (e) {
      debugPrint('AudioTrackManager: MDK加载外部音频失败: $e');
    }
  }

  /// 自动检测并加载外部音频（兼容两种内核）
  /// MediaKit: 需在主媒体打开前调用detectExternalAudioPath + preloadExternalAudioForMediaKit
  /// MDK: 需在主媒体prepare成功后调用此方法
  Future<void> autoDetectAndLoadExternalAudio(String videoPath) async {
    final mkaPath = await detectExternalAudioPath(videoPath);
    if (mkaPath == null) return;

    final kernelName = _player.getPlayerKernelName();
    if (kernelName == 'MDK') {
      loadExternalAudioForMdk(mkaPath);
    }
    // MediaKit内核应使用 preloadExternalAudioForMediaKit 在主媒体打开前设置
  }

  /// 清除外部音频
  /// 对于MediaKit: 清除待加载的外挂音频路径（已加载的外部轨道会在下次打开新视频时自动清除）
  /// 对于MDK: 通过setMedia空路径卸载
  void clearExternalAudio() {
    if (_externalAudioPath != null) {
      try {
        final kernelName = _player.getPlayerKernelName();
        if (kernelName == 'Media Kit') {
          // 清除待加载路径，阻止延迟加载
          _player.setMedia('', MediaType.audio);
          // 注意：已加载的外部音频轨道会在下次_player.open(新Media)时被mpv自动清除
        } else if (kernelName == 'MDK') {
          _player.setMedia('', MediaType.audio);
        }
      } catch (e) {
        debugPrint('AudioTrackManager: 清除外部音频失败: $e');
      }
      _externalAudioPath = null;
    }
  }

  /// 保存视频→外部音频的映射
  Future<void> saveVideoAudioMapping(String videoPath, String audioPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getMappingKey(videoPath);
      await prefs.setString(key, audioPath);
    } catch (e) {
      debugPrint('AudioTrackManager: 保存映射失败: $e');
    }
  }

  /// 获取视频对应的外部音频路径
  Future<String?> getVideoAudioPath(String videoPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _getMappingKey(videoPath);
      return prefs.getString(key);
    } catch (e) {
      debugPrint('AudioTrackManager: 读取映射失败: $e');
      return null;
    }
  }

  String _getMappingKey(String videoPath) {
    final hash = videoPath.hashCode.toUnsigned(32).toString();
    return '${_prefsKey}_$hash';
  }
}

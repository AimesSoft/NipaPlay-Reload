import './abstract_player.dart';
import './mdk_player_adapter.dart';
import './video_player_adapter.dart'; // 导入新的适配器
import './media_kit_player_adapter.dart'; // 导入新的MediaKit适配器
import './erika_player_adapter.dart';
import './player_data_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart'; // 用于 debugPrint
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/utils/system_resource_monitor.dart'; // 导入系统资源监控器
import 'dart:async'; // 导入dart:async库

// Define available player types if you plan to support more than one.
// For now, it defaults to MDK or could take a parameter.
enum PlayerKernelType {
  mdk,
  videoPlayer, // 添加 video_player 内核类型
  mediaKit, // 添加 media_kit 内核类型
  erika,
  // otherPlayer,
}

class PlayerFactory {
  static const String _playerKernelTypeKey = 'player_kernel_type';
  static const String _precacheBufferSizeKey = 'player_precache_buffer_size_mb';
  static const String _macOSNativeVideoEnabledKey =
      'macos_native_video_enabled';
  static const String _androidAudioOutputKey = 'android_audio_output';
  static const String _erikaAndroidOutputModeKey = 'erika_android_output_mode';
  static const int defaultPrecacheBufferSizeMb = 32;
  static const int minPrecacheBufferSizeMb = 4;
  static const int maxPrecacheBufferSizeMb = 512;
  static PlayerKernelType? _cachedKernelType;
  static int _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
  static bool _cachedMacOSNativeVideoEnabled = false;
  static String _cachedAndroidAudioOutput = 'opensles';
  static PlayerErikaAndroidOutputMode _cachedErikaAndroidOutputMode =
      PlayerErikaAndroidOutputMode.sdr;
  static String _cachedCustomPlayerUA = ''; // 自定义播放器 UA，空=用内核默认
  static String? _oneTimeUA; // 一次性 UA（仅下一次播放有效，不持久化，用后即清）
  static bool _hasLoadedSettings = false;

  // 添加一个StreamController来广播内核切换事件
  static final StreamController<PlayerKernelType> _kernelChangeController =
      StreamController<PlayerKernelType>.broadcast();
  static Stream<PlayerKernelType> get onKernelChanged =>
      _kernelChangeController.stream;

  static bool get isErikaKernelSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.android;
  }

  // 初始化方法，在应用启动时调用
  static Future<void> initialize() async {
    if (kIsWeb) {
      _cachedKernelType = PlayerKernelType.videoPlayer;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _hasLoadedSettings = true;
      debugPrint('[PlayerFactory] Web平台，强制使用 Video Player 内核');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
      final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);
      final macOSNativeVideoEnabled =
          prefs.getBool(_macOSNativeVideoEnabledKey) ?? false;
      final androidAudioOutput =
          prefs.getString(_androidAudioOutputKey) ?? 'opensles';
      final erikaAndroidOutputModeIndex =
          prefs.getInt(_erikaAndroidOutputModeKey);

      if (kernelTypeIndex != null &&
          kernelTypeIndex < PlayerKernelType.values.length) {
        _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
      } else {
        _cachedKernelType = PlayerKernelType.mdk;
        debugPrint('[PlayerFactory] 无内核设置，使用默认: MDK');
      }

      _cachedPrecacheBufferSizeMb = _clampPrecacheBufferSizeMb(
        bufferSizeMb ?? defaultPrecacheBufferSizeMb,
      );
      _cachedMacOSNativeVideoEnabled = macOSNativeVideoEnabled;
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(
        _cachedMacOSNativeVideoEnabled,
      );
      _cachedAndroidAudioOutput = androidAudioOutput;
      _cachedErikaAndroidOutputMode =
          _decodeErikaAndroidOutputMode(erikaAndroidOutputModeIndex);
      _cachedCustomPlayerUA =
          prefs.getString(SettingsKeys.customPlayerUA) ?? '';

      _hasLoadedSettings = true;
    } catch (e) {
      debugPrint('[PlayerFactory] 初始化读取设置出错: $e');
      _cachedKernelType = PlayerKernelType.mdk;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _cachedMacOSNativeVideoEnabled = false;
      _cachedAndroidAudioOutput = 'opensles';
      _cachedErikaAndroidOutputMode = PlayerErikaAndroidOutputMode.sdr;
      _cachedCustomPlayerUA = '';
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(false);
      _hasLoadedSettings = true;
    }
  }

  // 同步加载设置
  static void _loadSettingsSync() {
    try {
      // 这里没有真正同步，仅使用默认值，确保后续异步加载会更新缓存值
      _cachedKernelType = PlayerKernelType.mdk;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _cachedMacOSNativeVideoEnabled = false;
      _cachedAndroidAudioOutput = 'opensles';
      _cachedErikaAndroidOutputMode = PlayerErikaAndroidOutputMode.sdr;
      _cachedCustomPlayerUA = '';
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(false);
      _hasLoadedSettings = true;

      // 异步加载正确设置并更新缓存
      SharedPreferences.getInstance().then((prefs) {
        final kernelTypeIndex = prefs.getInt(_playerKernelTypeKey);
        final bufferSizeMb = prefs.getInt(_precacheBufferSizeKey);
        final macOSNativeVideoEnabled =
            prefs.getBool(_macOSNativeVideoEnabledKey) ?? false;
        final androidAudioOutput =
            prefs.getString(_androidAudioOutputKey) ?? 'opensles';
        final erikaAndroidOutputModeIndex =
            prefs.getInt(_erikaAndroidOutputModeKey);
        if (kernelTypeIndex != null &&
            kernelTypeIndex < PlayerKernelType.values.length) {
          _cachedKernelType = PlayerKernelType.values[kernelTypeIndex];
          debugPrint(
              '[PlayerFactory] 异步更新内核设置: ${_cachedKernelType.toString()}');
        }
        if (bufferSizeMb != null) {
          _cachedPrecacheBufferSizeMb =
              _clampPrecacheBufferSizeMb(bufferSizeMb);
        }
        _cachedMacOSNativeVideoEnabled = macOSNativeVideoEnabled;
        MediaKitPlayerAdapter.setMacOSNativeVideoPreference(
          _cachedMacOSNativeVideoEnabled,
        );
        _cachedAndroidAudioOutput = androidAudioOutput;
        _cachedErikaAndroidOutputMode =
            _decodeErikaAndroidOutputMode(erikaAndroidOutputModeIndex);
        _cachedCustomPlayerUA =
            prefs.getString(SettingsKeys.customPlayerUA) ?? '';
      });

      debugPrint('[PlayerFactory] 同步设置临时默认值: MDK');
    } catch (e) {
      debugPrint('[PlayerFactory] 同步加载设置出错: $e');
      _cachedKernelType = PlayerKernelType.mdk;
      _cachedPrecacheBufferSizeMb = defaultPrecacheBufferSizeMb;
      _cachedAndroidAudioOutput = 'opensles';
      _cachedErikaAndroidOutputMode = PlayerErikaAndroidOutputMode.sdr;
    }
  }

  // 获取当前内核设置
  static PlayerKernelType getKernelType() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedKernelType ?? PlayerKernelType.mdk;
  }

  /// 获取自定义播放器 User-Agent（空字符串 = 用内核默认 UA）。
  static String getCustomPlayerUA() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedCustomPlayerUA;
  }

  /// 设置一次性 User-Agent（仅下一次打开视频时生效，不持久化，用后即清）。
  /// 优先级高于 [getCustomPlayerUA] 的持久 UA。空字符串清除一次性 UA。
  static void setOneTimeUA(String ua) {
    final resolved = ua.trim();
    _oneTimeUA = resolved.isEmpty ? null : resolved;
  }

  /// 消费一次性 UA：返回并清除。未设置返回 null（调用方回退到持久 UA）。
  static String? consumeOneTimeUA() {
    final v = _oneTimeUA;
    _oneTimeUA = null;
    return v;
  }

  /// 获取一次性 UA（不消费，供 UI 预填）。未设置返回 null。
  static String? getOneTimeUA() => _oneTimeUA;

  static int _clampPrecacheBufferSizeMb(int value) {
    return value
        .clamp(minPrecacheBufferSizeMb, maxPrecacheBufferSizeMb)
        .toInt();
  }

  static int getPrecacheBufferSizeMb() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedPrecacheBufferSizeMb;
  }

  static bool getMacOSNativeVideoEnabled() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedMacOSNativeVideoEnabled;
  }

  static int getPrecacheBufferSizeBytes() {
    return getPrecacheBufferSizeMb() * 1024 * 1024;
  }

  static Future<void> savePrecacheBufferSizeMb(int value) async {
    final resolved = _clampPrecacheBufferSizeMb(value);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_precacheBufferSizeKey, resolved);
      _cachedPrecacheBufferSizeMb = resolved;
    } catch (e) {
      debugPrint('[PlayerFactory] 保存预缓存大小设置出错: $e');
    }
  }

  static Future<void> saveMacOSNativeVideoEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_macOSNativeVideoEnabledKey, enabled);
      final previous = _cachedMacOSNativeVideoEnabled;
      _cachedMacOSNativeVideoEnabled = enabled;
      MediaKitPlayerAdapter.setMacOSNativeVideoPreference(enabled);
      if (previous != enabled &&
          (_cachedKernelType ?? getKernelType()) == PlayerKernelType.mediaKit) {
        _kernelChangeController.add(PlayerKernelType.mediaKit);
      }
    } catch (e) {
      debugPrint('[PlayerFactory] 保存 macOS 原生视频设置出错: $e');
    }
  }

  static String getAndroidAudioOutput() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedAndroidAudioOutput;
  }

  static Future<void> saveAndroidAudioOutput(String output) async {
    final resolved = (output == 'audiotrack') ? 'audiotrack' : 'opensles';
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_androidAudioOutputKey, resolved);
      _cachedAndroidAudioOutput = resolved;
    } catch (e) {
      debugPrint('[PlayerFactory] 保存 Android 音频后端设置出错: $e');
    }
  }

  static PlayerErikaAndroidOutputMode getErikaAndroidOutputMode() {
    if (!_hasLoadedSettings) {
      _loadSettingsSync();
    }
    return _cachedErikaAndroidOutputMode;
  }

  static Future<void> saveErikaAndroidOutputMode(
    PlayerErikaAndroidOutputMode mode,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_erikaAndroidOutputModeKey, mode.index);
      final previous = _cachedErikaAndroidOutputMode;
      _cachedErikaAndroidOutputMode = mode;
      if (previous != mode &&
          (_cachedKernelType ?? getKernelType()) == PlayerKernelType.erika) {
        _kernelChangeController.add(PlayerKernelType.erika);
      }
    } catch (e) {
      debugPrint(
          '[PlayerFactory] Failed to save Erika Android output mode: $e');
    }
  }

  static PlayerErikaAndroidOutputMode _decodeErikaAndroidOutputMode(
    int? index,
  ) {
    if (index != null &&
        index >= 0 &&
        index < PlayerErikaAndroidOutputMode.values.length) {
      return PlayerErikaAndroidOutputMode.values[index];
    }
    return PlayerErikaAndroidOutputMode.sdr;
  }

  /// 保存自定义播放器 User-Agent。空字符串表示用内核默认 UA。
  /// 即时生效于"下一次打开视频"（当前正在播放的视频不会重新请求）。
  static Future<void> saveCustomPlayerUA(String ua) async {
    final resolved = ua.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(SettingsKeys.customPlayerUA, resolved);
      _cachedCustomPlayerUA = resolved;
      debugPrint('[PlayerFactory] 已保存自定义播放器 UA: '
          '${resolved.isEmpty ? "(空=默认)" : resolved}');
    } catch (e) {
      debugPrint('[PlayerFactory] 保存自定义播放器 UA 出错: $e');
    }
  }

  // 创建播放器实例
  AbstractPlayer createPlayer({PlayerKernelType? kernelType}) {
    // 如果是Web平台，强制使用VideoPlayer
    if (kIsWeb) {
      debugPrint('[PlayerFactory] Web平台，强制创建 Video Player 播放器');
      return VideoPlayerAdapter();
    }

    // 如果没有指定内核类型，从缓存或设置中读取
    kernelType ??= getKernelType();

    switch (kernelType) {
      case PlayerKernelType.mdk:
        debugPrint('[PlayerFactory] 创建 MDK 播放器');
        return MdkPlayerAdapter();
      case PlayerKernelType.videoPlayer:
        debugPrint('[PlayerFactory] 创建 Video Player 播放器');
        return VideoPlayerAdapter();
      case PlayerKernelType.mediaKit:
        return MediaKitPlayerAdapter(
          bufferSize: getPrecacheBufferSizeBytes(),
          androidAudioOutput: getAndroidAudioOutput(),
        );
      case PlayerKernelType.erika:
        debugPrint('[PlayerFactory] 创建 Erika 播放器');
        return ErikaPlayerAdapter(
          androidOutputMode: getErikaAndroidOutputMode(),
        );
      // case PlayerKernelType.otherPlayer:
      //   // return OtherPlayerAdapter(ThirdPartyPlayerApi());
      //   throw UnimplementedError('Other player types not yet supported.');
    }
  }

  // 保存内核设置
  static Future<void> saveKernelType(PlayerKernelType type) async {
    if (kIsWeb) {
      debugPrint('[PlayerFactory] Web平台不支持更改播放器内核');
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_playerKernelTypeKey, type.index);
      _cachedKernelType = type;
      debugPrint('[PlayerFactory] 保存内核设置: ${type.toString()}');

      // 更新系统资源监视器的播放器内核类型
      String kernelTypeName;
      switch (type) {
        case PlayerKernelType.mdk:
          kernelTypeName = "MDK";
          break;
        case PlayerKernelType.videoPlayer:
          kernelTypeName = "Video Player";
          break;
        case PlayerKernelType.mediaKit:
          kernelTypeName = "Libmpv";
          break;
        case PlayerKernelType.erika:
          kernelTypeName = "Erika";
          break;
      }

      // 设置显示名称
      SystemResourceMonitor().setPlayerKernelType(kernelTypeName);

      // 确保完整更新监视器显示 - 调用更新方法
      SystemResourceMonitor().updatePlayerKernelType();

      // 广播内核切换事件
      _kernelChangeController.add(type);
    } catch (e) {
      debugPrint('[PlayerFactory] 保存内核设置出错: $e');
    }
  }
}

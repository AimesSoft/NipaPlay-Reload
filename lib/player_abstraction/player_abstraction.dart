// Export all necessary enums, data models, and the abstract interface
export './player_enums.dart' show PlayerPlaybackState, PlayerMediaType;
export './player_data_models.dart';
export './abstract_player.dart' show AbstractPlayer; // Export only AbstractPlayer type
export './player_factory.dart' show PlayerKernelType; // Export PlayerKernelType enum

import 'package:flutter/foundation.dart'; // For ValueListenable, used in AbstractPlayer
import './abstract_player.dart' as core_player; // Alias for the true AbstractPlayer
import './player_enums.dart' as core_enums; // Alias for our pure enums
import './player_data_models.dart';
import './player_factory.dart'; // Import PlayerFactory directly
import './mdk_player_adapter.dart'; // 导入具体适配器类
import './video_player_adapter.dart'; // 导入具体适配器类
import './media_kit_player_adapter.dart'; // 导入MediaKit适配器类

/// MDK-compatible PlaybackState. 
/// Code using the abstraction layer can use `PlaybackState.paused`.
enum PlaybackState { stopped, paused, playing }

/// MDK-compatible MediaType.
/// Code using the abstraction layer can use `MediaType.video`.
enum MediaType { unknown, video, audio, subtitle }

/// The main player class that client code (like VideoPlayerState) will interact with.
/// It instantiates to `Player()` and delegates all operations to an internal `AbstractPlayer` instance
/// obtained from the `PlayerFactory`.
class Player {
  final core_player.AbstractPlayer _delegate;

  /// Factory constructor that allows `Player()` to be called.
  /// This is what `VideoPlayerState` will use, e.g., `Player player = Player();`.
  factory Player() {
    // PlayerFactory 会自动从 SharedPreferences 读取播放器内核设置
    return Player._internal(PlayerFactory().createPlayer());
  }

  // Private internal constructor
  Player._internal(this._delegate);

  // Delegate all AbstractPlayer methods and properties to the internal _delegate instance.
  // This ensures that calls like `player.volume` work as expected.

  double get volume => _delegate.volume;
  set volume(double value) => _delegate.volume = value;

  /// Gets the current playback state using MDK-compatible [PlaybackState] enum.
  PlaybackState get state {
    switch (_delegate.state) { // _delegate.state is core_enums.PlayerPlaybackState
      case core_enums.PlayerPlaybackState.stopped: return PlaybackState.stopped;
      case core_enums.PlayerPlaybackState.paused: return PlaybackState.paused;
      case core_enums.PlayerPlaybackState.playing: return PlaybackState.playing;
    }
  }
  /// Sets the playback state using MDK-compatible [PlaybackState] enum.
  set state(PlaybackState value) { 
    switch (value) {
      case PlaybackState.stopped: _delegate.state = core_enums.PlayerPlaybackState.stopped; break;
      case PlaybackState.paused: _delegate.state = core_enums.PlayerPlaybackState.paused; break;
      case PlaybackState.playing: _delegate.state = core_enums.PlayerPlaybackState.playing; break;
    }
  }

  ValueListenable<int?> get textureId => _delegate.textureId;

  String get media => _delegate.media;
  set media(String value) => _delegate.media = value;

  PlayerMediaInfo get mediaInfo => _delegate.mediaInfo;

  List<int> get activeSubtitleTracks => _delegate.activeSubtitleTracks;
  set activeSubtitleTracks(List<int> value) => _delegate.activeSubtitleTracks = value;

  List<int> get activeAudioTracks => _delegate.activeAudioTracks;
  set activeAudioTracks(List<int> value) => _delegate.activeAudioTracks = value;

  int get position => _delegate.position;

  bool get supportsExternalSubtitles => _delegate.supportsExternalSubtitles;

  Future<int?> updateTexture() => _delegate.updateTexture();

  /// Sets the media source using MDK-compatible [MediaType] enum.
  void setMedia(String path, MediaType type) {
    core_enums.PlayerMediaType coreType;
    switch (type) {
      case MediaType.unknown: coreType = core_enums.PlayerMediaType.unknown; break;
      case MediaType.video: coreType = core_enums.PlayerMediaType.video; break;
      case MediaType.audio: coreType = core_enums.PlayerMediaType.audio; break;
      case MediaType.subtitle: coreType = core_enums.PlayerMediaType.subtitle; break;
    }
    _delegate.setMedia(path, coreType);
  }

  Future<void> prepare() => _delegate.prepare();

  void seek({required int position}) => _delegate.seek(position: position);

  void dispose() => _delegate.dispose();

  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) =>
      _delegate.snapshot(width: width, height: height);

  // Delegate new methods for DecoderManager
  void setDecoders(MediaType type, List<String> decoders) {
    core_enums.PlayerMediaType coreType;
    switch (type) {
      case MediaType.unknown: coreType = core_enums.PlayerMediaType.unknown; break;
      case MediaType.video: coreType = core_enums.PlayerMediaType.video; break;
      case MediaType.audio: coreType = core_enums.PlayerMediaType.audio; break;
      case MediaType.subtitle: coreType = core_enums.PlayerMediaType.subtitle; break;
    }
    _delegate.setDecoders(coreType, decoders);
  }

  List<String> getDecoders(MediaType type) {
    core_enums.PlayerMediaType coreType;
    switch (type) {
      case MediaType.unknown: coreType = core_enums.PlayerMediaType.unknown; break;
      case MediaType.video: coreType = core_enums.PlayerMediaType.video; break;
      case MediaType.audio: coreType = core_enums.PlayerMediaType.audio; break;
      case MediaType.subtitle: coreType = core_enums.PlayerMediaType.subtitle; break;
    }
    return _delegate.getDecoders(coreType);
  }

  String? getProperty(String key) => _delegate.getProperty(key);
  
  void setProperty(String key, String value) => _delegate.setProperty(key, value);
  
  // 直接播放控制方法
  Future<void> playDirectly() => _delegate.playDirectly();
  Future<void> pauseDirectly() => _delegate.pauseDirectly();
  
  // 获取当前使用的播放器内核类型的名称
  String getPlayerKernelName() {
    if (_delegate is MdkPlayerAdapter) {
      return "MDK";
    } else if (_delegate is VideoPlayerAdapter) {
      return "Video Player";
    } else if (_delegate is MediaKitPlayerAdapter) {
      return "Media Kit";
    } else {
      return "未知";
    }
  }
}

// Type aliases for full compatibility if VideoPlayerState uses these type names
typedef MediaInfo = PlayerMediaInfo;
typedef Frame = PlayerFrame; 
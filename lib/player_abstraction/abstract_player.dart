import 'dart:async';
import 'package:flutter/foundation.dart'; // For ValueListenable
import './player_enums.dart';
import './player_data_models.dart';

abstract class AbstractPlayer {
  // Properties
  double get volume;
  set volume(double value);

  PlayerPlaybackState get state;
  set state(PlayerPlaybackState value);

  ValueListenable<int?> get textureId;

  String get media;
  set media(String value);

  PlayerMediaInfo get mediaInfo;

  List<int> get activeSubtitleTracks;
  set activeSubtitleTracks(List<int> value);

  List<int> get activeAudioTracks;
  set activeAudioTracks(List<int> value);

  int get position; // in milliseconds

  bool get supportsExternalSubtitles;

  // Methods
  Future<int?> updateTexture();

  void setMedia(String path, PlayerMediaType type);

  Future<void> prepare();

  void seek({required int position});

  void dispose();

  Future<PlayerFrame?> snapshot({int width = 0, int height = 0});

  // NEW METHODS for DecoderManager compatibility
  void setDecoders(PlayerMediaType type, List<String> decoders);
  List<String> getDecoders(PlayerMediaType type);
  String? getProperty(String key);
  void setProperty(String key, String value);
  
  // NEW DIRECT PLAYBACK METHODS
  /// 直接开始播放，绕过状态设置
  Future<void> playDirectly();
  
  /// 直接暂停播放，绕过状态设置
  Future<void> pauseDirectly();
} 
import 'dart:async';
import 'package:flutter/foundation.dart'; // For ValueListenable
import './player_enums.dart';
import './player_data_models.dart';

abstract class AbstractPlayer {
  // Properties
  double get volume;
  set volume(double value);

  double get playbackRate;
  set playbackRate(double value);

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
  int get bufferedPosition; // in milliseconds, end of buffered data
  void setBufferRange({int minMs, int maxMs, bool drop});

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
  Future<void> setVideoSurfaceSize({int? width, int? height});

  /// 跳转到指定索引的章节（使用 mpv 原生 `chapter` 属性，keyframe 对齐）。
  /// 参考 REFERENCE/mpv/player/command.c:996 (queue_seek MPSEEK_CHAPTER)。
  /// 不支持章节的内核（mdk/erika）为空实现。
  Future<void> setChapter(int index);
  
  // NEW DIRECT PLAYBACK METHODS
  /// 直接开始播放，绕过状态设置
  Future<void> playDirectly();
  
  /// 直接暂停播放，绕过状态设置
  Future<void> pauseDirectly();

  /// 设置播放速度
  void setPlaybackRate(double rate);

  /// 逐帧前进（暂停后前进一帧）
  void stepForward();

  /// 逐帧后退（暂停后后退一帧）
  void stepBackward();
}

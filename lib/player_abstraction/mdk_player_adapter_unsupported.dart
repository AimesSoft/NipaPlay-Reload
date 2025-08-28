import 'package:flutter/foundation.dart';
import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';
import 'dart:async';

class MdkPlayerAdapter implements AbstractPlayer {
  MdkPlayerAdapter();
  
  @override
  double get volume => 1.0;
  @override
  set volume(double value) {}

  @override
  double get playbackRate => 1.0;
  @override
  set playbackRate(double value) {}

  @override
  PlayerPlaybackState get state => PlayerPlaybackState.stopped;
  @override
  set state(PlayerPlaybackState value) {}

  @override
  ValueListenable<int?> get textureId => ValueNotifier(null);

  @override
  String get media => '';
  @override
  set media(String value) {}

  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 0);

  @override
  List<int> get activeSubtitleTracks => [];
  @override
  set activeSubtitleTracks(List<int> value) {}

  @override
  List<int> get activeAudioTracks => [];
  @override
  set activeAudioTracks(List<int> value) {}

  @override
  int get position => 0;

  @override
  bool get supportsExternalSubtitles => false;

  @override
  Future<int?> updateTexture() async => null;

  @override
  void setMedia(String path, PlayerMediaType type) {}

  @override
  Future<void> prepare() async {}

  @override
  void seek({required int position}) {}

  @override
  void dispose() {}

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async => null;

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  
  @override
  List<String> getDecoders(PlayerMediaType type) => [];

  @override
  String? getProperty(String key) => null;

  @override
  void setProperty(String key, String value) {}

  @override
  Future<void> playDirectly() async {}
  
  @override
  Future<void> pauseDirectly() async {}

  @override
  void setPlaybackRate(double rate) {}

  // 详细播放技术信息（不支持MDK的平台返回空）
  Map<String, dynamic> getDetailedMediaInfo() => const <String, dynamic>{};
} 
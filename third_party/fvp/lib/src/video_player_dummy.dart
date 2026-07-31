import 'dart:typed_data';

import 'media_info_dummy.dart';

/// A dummy class for web
class MdkVideoPlayerPlatform {
  static void registerVideoPlayerPlatformsWith({dynamic options}) {}

  // for FVPController
  bool isLive(int textureId) {
    return false;
  }

  MediaInfo? getMediaInfo(int textureId) {
    return null;
  }

  void setProperty(int textureId, String name, String value) {}

  void setAudioDecoders(int textureId, List<String> value) {}

  void setVideoDecoders(int textureId, List<String> value) {}

  void record(int textureId, {String? to, String? format}) {}

  Future<Uint8List?> snapshot(int textureId, {int? width, int? height}) async {
    return null;
  }

  void setRange(int textureId, {required int from, int to = -1}) {}

  void setBufferRange(
    int textureId, {
    int min = -1,
    int max = -1,
    bool drop = false,
  }) {}

  Future<void> fastSeekTo(int textureId, Duration position) async {}

  Future<void> step(int textureId, int frames) async {}

  void setBrightness(int textureId, double value) {}

  void setContrast(int textureId, double value) {}

  void setHue(int textureId, double value) {}

  void setSaturation(int textureId, double value) {}

  void setProgram(int textureId, int programId) {}

  void setAudioTracks(int textureId, List<int> value) {}

  List<int>? getActiveAudioTracks(int textureId) {
    return null;
  }

  void setVideoTracks(int textureId, List<int> value) {}

  List<int>? getActiveVideoTracks(int textureId) {
    return null;
  }

  void setSubtitleTracks(int textureId, List<int> value) {}

  List<int>? getActiveSubtitleTracks(int textureId) {
    return null;
  }

  void setExternalAudio(int textureId, String uri) {}

  void setExternalVideo(int textureId, String uri) {}

  void setExternalSubtitle(int textureId, String uri) {}
}

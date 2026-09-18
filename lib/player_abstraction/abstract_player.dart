import 'dart:async';
import 'package:flutter/foundation.dart'; // For ValueListenable
import './player_enums.dart';
import './player_data_models.dart';

/// Maximum number of open attempts for a remote media source, including the
/// initial open. Slow or sleeping remote disks therefore get four transparent
/// retries after the first attempt.
const int networkMediaLoadMaxAttempts = 5;

/// Optional capability for backends whose native teardown must be awaited.
abstract interface class AsyncDisposablePlayer {
  Future<void> disposeAsync();
}

/// Optional capability for backends whose native seek completes
/// asynchronously across a platform bridge.
abstract interface class AsyncSeekPlayer {
  Future<void> seekAndWait({required int position});
}

/// Optional capability for backends whose external subtitle replacement is
/// completed through an asynchronous platform bridge.
abstract interface class AsyncExternalSubtitlePlayer {
  Future<void> setExternalSubtitleAsync(String path);
}

/// Optional capability for backends that can distinguish an accepted play
/// command from a media source that has actually produced usable metadata.
abstract interface class MediaLoadAwarePlayer {
  bool get isMediaReady;
  bool get hasReceivedRealPosition;
  bool get hasMediaLoadFailed;
  String? get mediaLoadError;

  Future<bool> waitUntilMediaReady({required Duration timeout});

  /// Retries the current source only when doing so is safe and useful.
  /// Returns false when the source/error is not retryable or the retry budget
  /// has been exhausted.
  Future<bool> retryCurrentMediaLoad();
}

enum GifExportQuality { normal, high }

@immutable
class GifExportRequest {
  const GifExportRequest({
    required this.inputUri,
    required this.outputPath,
    required this.start,
    required this.end,
    required this.framesPerSecond,
    required this.outputWidth,
    required this.outputHeight,
    this.quality = GifExportQuality.normal,
    this.httpHeaders = const <String, String>{},
  });

  final String inputUri;
  final String outputPath;
  final Duration start;
  final Duration end;
  final int framesPerSecond;
  final int outputWidth;
  final int outputHeight;
  final GifExportQuality quality;
  final Map<String, String> httpHeaders;
}

@immutable
class GifExportResult {
  const GifExportResult({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.frameCount,
    required this.fileSize,
  });

  final String outputPath;
  final int width;
  final int height;
  final int frameCount;
  final int fileSize;
}

abstract interface class GifExportCapablePlayer {
  bool get supportsGifExport;
  Future<GifExportResult> exportGif(GifExportRequest request);
}

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

  /// 设置 HTTP User-Agent（播放器请求视频时使用）。默认空实现，各内核按需 override。
  /// 空字符串 [ua] = 用内核默认 UA。在打开媒体前调用。
  void setUserAgent(String ua) {}
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

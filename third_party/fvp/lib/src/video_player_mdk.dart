// Copyright 2022-2025 Wang Bin. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'package:flutter/widgets.dart'; //
import 'package:flutter/services.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'fvp_platform_interface.dart';
import 'extensions.dart';
import 'media_info.dart';

import '../mdk.dart' as mdk;

final _log = Logger('fvp');

class MdkVideoPlayer extends mdk.Player {
  final streamCtl = StreamController<VideoEvent>();
  bool _initialized = false;

  @override
  void dispose() {
    onMediaStatus(null);
    onEvent(null);
    onStateChanged(null);
    streamCtl.close();
    _initialized = false;
    super.dispose();
  }

  MdkVideoPlayer() : super() {
    onMediaStatus((oldValue, newValue) {
      _log.fine(
        '$hashCode player$nativeHandle onMediaStatus: $oldValue => $newValue',
      );
      if (!oldValue.test(mdk.MediaStatus.loaded) &&
          newValue.test(mdk.MediaStatus.loaded)) {
        // initialized event must be sent only once. keep_open=1 is another solution
        //if ((textureId.value ?? -1) >= 0) {
        //  return true; // prepared callback is invoked before MediaStatus.loaded, so textureId can be a valid value here
        //}
        if (_initialized) {
          _log.fine('$hashCode player$nativeHandle already initialized');
          return true;
        }
        _initialized = true;
        textureSize.then((size) {
          if (size == null) {
            return;
          }
          streamCtl.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              duration: Duration(
                microseconds: isLive
                    // int max for live streams, duration.inMicroseconds == 9223372036854775807
                    ? double.maxFinite.toInt()
                    : mediaInfo.duration * 1000,
              ),
              size: size,
            ),
          );
        });
      } else if (!oldValue.test(mdk.MediaStatus.buffering) &&
          newValue.test(mdk.MediaStatus.buffering)) {
        streamCtl.add(VideoEvent(eventType: VideoEventType.bufferingStart));
      } else if (!oldValue.test(mdk.MediaStatus.buffered) &&
          newValue.test(mdk.MediaStatus.buffered)) {
        streamCtl.add(VideoEvent(eventType: VideoEventType.bufferingEnd));
      }
      return true;
    });

    onEvent((ev) {
      _log.fine(
        '$hashCode player$nativeHandle onEvent: ${ev.category} - ${ev.detail} - ${ev.error}',
      );
      if (ev.category == "reader.buffering") {
        final pos = position;
        final bufLen = buffered();
        streamCtl.add(
          VideoEvent(
            eventType: VideoEventType.bufferingUpdate,
            buffered: [
              DurationRange(
                Duration(microseconds: pos),
                Duration(milliseconds: pos + bufLen),
              ),
            ],
          ),
        );
      }
    });

    onStateChanged((oldValue, newValue) {
      _log.fine(
        '$hashCode player$nativeHandle onPlaybackStateChanged: $oldValue => $newValue',
      );
      if (newValue == mdk.PlaybackState.stopped) {
        // FIXME: keep_open no stopped
        streamCtl.add(VideoEvent(eventType: VideoEventType.completed));
        return;
      }
      streamCtl.add(
        VideoEvent(
          eventType: VideoEventType.isPlayingStateUpdate,
          isPlaying: newValue == mdk.PlaybackState.playing,
        ),
      );
    });
  }
}

class MdkVideoPlayerPlatform extends VideoPlayerPlatform {
  static final _players = <int, MdkVideoPlayer>{};
  static Map<String, Object>? _globalOpts;
  static Map<String, String>? _playerOpts;
  static int? _maxWidth;
  static int? _maxHeight;
  static bool? _fitMaxSize;
  static bool? _tunnel;
  static String? _subtitleFontFile;
  static int _lowLatency = 0;
  static int _seekFlags = mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache;
  static List<String>? _decoders;
  static final _mdkLog = Logger('mdk');
  // _prevImpl: required if registerWith() can be invoked multiple times by user
  static VideoPlayerPlatform? _prevImpl;

  /*
  Registers this class as the default instance of [VideoPlayerPlatform].

  [options] can be
  "video.decoders": a list of decoder names. supported decoders: https://github.com/wang-bin/mdk-sdk/wiki/Decoders
  "maxWidth", "maxHeight": texture max size. if not set, video frame size is used. a small value can reduce memory cost, but may result in lower image quality.
 */
  static void registerVideoPlayerPlatformsWith({dynamic options}) {
    _log.fine('registerVideoPlayerPlatformsWith: $options');
    if (options is Map<String, dynamic>) {
      final platforms = options['platforms'];
      if (platforms is List<String>) {
        if (!platforms.contains(Platform.operatingSystem)) {
          if (_prevImpl != null &&
              VideoPlayerPlatform.instance is MdkVideoPlayerPlatform) {
            // null if it's the 1st time to call registerWith() including current platform
            // if current is not MdkVideoPlayerPlatform, another plugin may set instance
            // if current is MdkVideoPlayerPlatform, we have to restore instance,  _prevImpl is correct and no one changed instance
            VideoPlayerPlatform.instance = _prevImpl!;
          }
          return;
        }
      }

      if ((options['fastSeek'] ?? false) as bool) {
        _seekFlags |= mdk.SeekFlag.keyFrame;
      }
      _lowLatency = (options['lowLatency'] ?? 0) as int;
      _maxWidth = options["maxWidth"];
      _maxHeight = options["maxHeight"];
      _fitMaxSize = options["fitMaxSize"];
      _tunnel = options["tunnel"];
      _playerOpts = options['player'];
      _globalOpts = options['global'];
      // TODO: _env => putenv
      _decoders = options['video.decoders'];
      _subtitleFontFile = options['subtitleFontFile'];
    }

    if (_decoders == null && !PlatformEx.isAndroidEmulator()) {
      // prefer hardware decoders
      const vdRk = ['rkmpp', 'FFmpeg', 'dav1d'];
      const vdPi = ['V4L2M2M', 'FFmpeg:hwcontext=drm', 'FFmpeg', 'dav1d'];
      final vdLinux = PlatformEx.isRockchip()
          ? vdRk
          : (PlatformEx.isRaspberryPi()
                ? vdPi
                : ['VAAPI', 'CUDA', 'VDPAU', 'hap', 'FFmpeg', 'dav1d']);
      final vd = {
        'windows': [
          'MFT:d3d=11',
          "D3D11",
          "DXVA",
          'CUDA',
          'hap',
          'FFmpeg',
          'dav1d',
        ],
        'macos': ['VT', 'hap', 'FFmpeg', 'dav1d'],
        'ios': ['VT', 'FFmpeg', 'dav1d'],
        'linux': vdLinux,
        'android': ['AMediaCodec', 'FFmpeg', 'dav1d'],
      };
      _decoders = vd[Platform.operatingSystem];
    }

    // delay: ensure log handler is set in main(), blank window if run with debugger.
    // registerWith() can be invoked by dart_plugin_registrant.dart before main. when debugging, won't enter main if posting message from native to dart(new native log message) before main?
    Future.delayed(const Duration(milliseconds: 0), () {
      _setupMdk();
    });

    _prevImpl ??= VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = MdkVideoPlayerPlatform();
  }

  static void _setupMdk() {
    mdk.setLogHandler((level, msg) {
      if (msg.endsWith('\n')) {
        msg = msg.substring(0, msg.length - 1);
      }
      switch (level) {
        case mdk.LogLevel.error:
          _mdkLog.severe(msg);
        case mdk.LogLevel.warning:
          _mdkLog.warning(msg);
        case mdk.LogLevel.info:
          _mdkLog.info(msg);
        case mdk.LogLevel.debug:
          _mdkLog.fine(msg);
        case mdk.LogLevel.all:
          _mdkLog.finest(msg);
        default:
          return;
      }
    });
    // mdk.setGlobalOptions('plugins', 'mdk-braw');
    mdk.setGlobalOption("log", "all");
    mdk.setGlobalOption('d3d11.sync.cpu', 1);
    if (_subtitleFontFile?.startsWith('http') ?? false) {
      final fileName = _subtitleFontFile!.split('/').last;
      getApplicationCacheDirectory().then((dir) {
        final fontPath = '${dir.path}/$fileName';
        _log.fine('check font path: $fontPath');
        if (File(fontPath).existsSync()) {
          mdk.setGlobalOption('subtitle.fonts.file', fontPath);
          return;
        }
        _log.fine('downloading font file: $_subtitleFontFile');
        http.get(Uri.parse(_subtitleFontFile!)).then((response) {
          if (response.statusCode == 200) {
            _log.fine('save font file: $fontPath');
            File(fontPath).writeAsBytes(response.bodyBytes).then((_) {
              mdk.setGlobalOption('subtitle.fonts.file', fontPath);
            });
          }
        });
      });
    } else {
      mdk.setGlobalOption(
        'subtitle.fonts.file',
        PlatformEx.assetUri(_subtitleFontFile ?? 'assets/subfont.ttf'),
      );
    }
    _globalOpts?.forEach((key, value) {
      mdk.setGlobalOption(key, value);
    });
  }

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int textureId) async {
    _players.remove(textureId)?.dispose();
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final uri = _toUri(dataSource);
    final player = MdkVideoPlayer();
    _log.fine('$hashCode player${player.nativeHandle} create($uri)');

    //player.setProperty("keep_open", "1");
    player.setProperty('video.decoder', 'shader_resource=0');
    player.setProperty('avformat.strict', 'experimental');
    player.setProperty('avformat.safe', '0');
    player.setProperty('avio.reconnect', '1');
    player.setProperty('avio.reconnect_delay_max', '7');
    player.setProperty('avformat.rtsp_transport', 'tcp');
    if (dataSource.sourceType != DataSourceType.network) {
      // for m3u8 local file etc.
      player.setProperty(
        'avio.protocol_whitelist',
        'file,ftp,rtmp,http,https,tls,rtp,tcp,udp,crypto,httpproxy,data,concatf,concat,subfile',
      );
    }
    _playerOpts?.forEach((key, value) {
      player.setProperty(key, value);
    });

    if (_decoders != null) {
      player.videoDecoders = _decoders!;
    }
    if (_lowLatency > 0) {
      // +nobuffer: the 1st key-frame packet is dropped. -nobuffer: high latency
      player.setProperty('avformat.fflags', '+nobuffer');
      player.setProperty('avformat.fpsprobesize', '0');
      player.setProperty('avformat.analyzeduration', '100000');
      if (_lowLatency > 1) {
        player.setBufferRange(min: 0, max: 1000, drop: true);
      } else {
        player.setBufferRange(min: 0);
      }
    }

    if (dataSource.httpHeaders.isNotEmpty) {
      String headers = '';
      dataSource.httpHeaders.forEach((key, value) {
        headers += '$key: $value\r\n';
      });
      player.setProperty('avio.headers', headers);
    }
    player.media = uri;
    int ret = await player.prepare(); // required!
    if (ret < 0) {
      // no throw, handle error in controller.addListener
      _players[-hashCode] = player;
      player.streamCtl.addError(
        PlatformException(
          code: 'media open error',
          message: 'invalid or unsupported media',
        ),
      );
      //player.dispose(); // dispose for throw
      return -hashCode;
    }
    // FIXME: pending events will be processed after texture returned, but no events before prepared
    // FIXME: set tunnel too late
    final tex = await player.updateTexture(
      width: _maxWidth,
      height: _maxHeight,
      tunnel: _tunnel,
      fit: _fitMaxSize,
    );
    if (tex < 0) {
      _players[-hashCode] = player;
      player.streamCtl.addError(
        PlatformException(
          code: 'video size error',
          message: 'invalid or unsupported media with invalid video size',
        ),
      );
      //player.dispose();
      return -hashCode;
    }
    _log.fine('$hashCode player${player.nativeHandle} textureId=$tex');
    _players[tex] = player;
    return tex;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    final player = _players[textureId];
    if (player != null) {
      player.loop = looping ? -1 : 0;
    }
  }

  @override
  Future<void> play(int textureId) async {
    _players[textureId]?.state = mdk.PlaybackState.playing;
  }

  @override
  Future<void> pause(int textureId) async {
    _players[textureId]?.state = mdk.PlaybackState.paused;
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    _players[textureId]?.volume = volume;
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    _players[textureId]?.playbackRate = speed;
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _seekToWithFlags(textureId, position, mdk.SeekFlag(_seekFlags));
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    final player = _players[textureId];
    if (player == null) {
      return Duration.zero;
    }
    final pos = player.position;
    final bufLen = player.buffered();
    final ranges = player.bufferedTimeRanges();
    player.streamCtl.add(
      VideoEvent(
        eventType: VideoEventType.bufferingUpdate,
        buffered:
            ranges +
            [
              DurationRange(
                Duration(milliseconds: pos),
                Duration(milliseconds: pos + bufLen),
              ),
            ],
      ),
    );
    return Duration(milliseconds: pos);
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    final player = _players[textureId];
    if (player != null) {
      return player.streamCtl.stream;
    }
    throw Exception('No Stream<VideoEvent> for textureId: $textureId.');
  }

  @override
  Widget buildView(int textureId) {
    return Texture(textureId: textureId);
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {
    FvpPlatform.instance.setMixWithOthers(mixWithOthers);
  }

  // more apis for fvp controller
  bool isLive(int textureId) {
    return _players[textureId]?.isLive ?? false;
  }

  MediaInfo? getMediaInfo(int textureId) {
    return _players[textureId]?.mediaInfo;
  }

  void setProperty(int textureId, String name, String value) {
    _players[textureId]?.setProperty(name, value);
  }

  void setAudioDecoders(int textureId, List<String> value) {
    _players[textureId]?.audioDecoders = value;
  }

  void setVideoDecoders(int textureId, List<String> value) {
    _players[textureId]?.videoDecoders = value;
  }

  void record(int textureId, {String? to, String? format}) {
    _players[textureId]?.record(to: to, format: format);
  }

  Future<Uint8List?> snapshot(int textureId, {int? width, int? height}) async {
    Uint8List? data;
    final player = _players[textureId];
    if (player == null) {
      return data;
    }
    return _players[textureId]?.snapshot(width: width, height: height);
  }

  void setRange(int textureId, {required int from, int to = -1}) {
    _players[textureId]?.setRange(from: from, to: to);
  }

  void setBufferRange(
    int textureId, {
    int min = -1,
    int max = -1,
    bool drop = false,
  }) {
    _players[textureId]?.setBufferRange(min: min, max: max, drop: drop);
  }

  Future<void> fastSeekTo(int textureId, Duration position) async {
    return _seekToWithFlags(
      textureId,
      position,
      mdk.SeekFlag(_seekFlags | mdk.SeekFlag.keyFrame),
    );
  }

  Future<void> step(int textureId, int frames) async {
    final player = _players[textureId];
    if (player == null) {
      return;
    }
    player.seek(
      position: frames,
      flags: const mdk.SeekFlag(mdk.SeekFlag.frame | mdk.SeekFlag.fromNow),
    );
  }

  void setBrightness(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.brightness, [value]);
  }

  void setContrast(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.contrast, [value]);
  }

  void setHue(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.hue, [value]);
  }

  void setSaturation(int textureId, double value) {
    _players[textureId]?.setVideoEffect(mdk.VideoEffect.saturation, [value]);
  }

  void setProgram(int textureId, int programId) {
    _players[textureId]?.setActiveTracks(mdk.MediaType.unknown, [programId]);
  }

  // embedded tracks, can be main data source from create(), or external media source via setExternalAudio
  void setAudioTracks(int textureId, List<int> value) {
    _players[textureId]?.activeAudioTracks = value;
  }

  List<int>? getActiveAudioTracks(int textureId) {
    return _players[textureId]?.activeAudioTracks;
  }

  void setVideoTracks(int textureId, List<int> value) {
    _players[textureId]?.activeVideoTracks = value;
  }

  List<int>? getActiveVideoTracks(int textureId) {
    return _players[textureId]?.activeVideoTracks;
  }

  void setSubtitleTracks(int textureId, List<int> value) {
    _players[textureId]?.activeSubtitleTracks = value;
  }

  List<int>? getActiveSubtitleTracks(int textureId) {
    return _players[textureId]?.activeSubtitleTracks;
  }

  // external track. can select external tracks via setAudioTracks()
  void setExternalAudio(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.audio);
  }

  void setExternalVideo(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.video);
  }

  void setExternalSubtitle(int textureId, String uri) {
    _players[textureId]?.setMedia(uri, mdk.MediaType.subtitle);
  }

  Future<void> _seekToWithFlags(
    int textureId,
    Duration position,
    mdk.SeekFlag flags,
  ) async {
    final player = _players[textureId];
    if (player == null) {
      return;
    }
    if (player.isLive) {
      final bufMax = player.buffered();
      final pos = player.position;
      if (position.inMilliseconds <= pos ||
          position.inMilliseconds > pos + bufMax) {
        _log.fine(
          '_seekToWithFlags: $position out of live stream buffered range [$pos, ${pos + bufMax}]',
        );
        return;
      }
    }
    player.seek(position: position.inMilliseconds, flags: flags);
  }

  String _toUri(DataSource dataSource) {
    switch (dataSource.sourceType) {
      case DataSourceType.asset:
        return PlatformEx.assetUri(
          dataSource.asset!,
          package: dataSource.package,
        );
      case DataSourceType.network:
        return dataSource.uri!;
      case DataSourceType.file:
        return Uri.decodeComponent(dataSource.uri!);
      case DataSourceType.contentUri:
        return dataSource.uri!;
    }
  }
}

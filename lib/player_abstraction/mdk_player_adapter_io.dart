import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter/foundation.dart';
// Required for Uint8List
import 'package:nipaplay_core/player_abstraction/abstract_player.dart';
import 'package:nipaplay_core/player_abstraction/player_enums.dart';
import 'package:nipaplay_core/player_abstraction/player_data_models.dart';
import 'dart:async';
import 'package:nipaplay/utils/subtitle_font_loader.dart';

@visibleForTesting
void applyMdkUserAgentProperties(
  void Function(String key, String value) setter,
  String userAgent,
) {
  setter('avformat.user_agent', userAgent);
  setter('avio.user_agent', userAgent);
}

@visibleForTesting
void applyMdkHttpProxyProperties(
  void Function(String key, String value) setter,
  String httpProxy,
) {
  if (httpProxy.isEmpty) return;
  setter('avformat.http_proxy', httpProxy);
  setter('avio.http_proxy', httpProxy);
}

// Enum Converters
PlayerPlaybackState _toPlayerPlaybackState(mdk.PlaybackState state) {
  if (state == mdk.PlaybackState.stopped) return PlayerPlaybackState.stopped;
  if (state == mdk.PlaybackState.paused) return PlayerPlaybackState.paused;
  if (state == mdk.PlaybackState.playing) return PlayerPlaybackState.playing;
  return PlayerPlaybackState.stopped;
}

mdk.PlaybackState _fromPlayerPlaybackState(PlayerPlaybackState state) {
  switch (state) {
    case PlayerPlaybackState.stopped:
      return mdk.PlaybackState.stopped;
    case PlayerPlaybackState.paused:
      return mdk.PlaybackState.paused;
    case PlayerPlaybackState.playing:
      return mdk.PlaybackState.playing;
  }
}

PlayerMediaType _toPlayerMediaType(mdk.MediaType type) {
  switch (type) {
    case mdk.MediaType.unknown:
      return PlayerMediaType.unknown;
    case mdk.MediaType.video:
      return PlayerMediaType.video;
    case mdk.MediaType.audio:
      return PlayerMediaType.audio;
    case mdk.MediaType.subtitle:
      return PlayerMediaType.subtitle;
    default:
      throw ArgumentError('Unknown MDK MediaType: $type');
  }
}

mdk.MediaType _fromPlayerMediaType(PlayerMediaType type) {
  switch (type) {
    case PlayerMediaType.unknown:
      return mdk.MediaType.unknown;
    case PlayerMediaType.video:
      return mdk.MediaType.video;
    case PlayerMediaType.audio:
      return mdk.MediaType.audio;
    case PlayerMediaType.subtitle:
      return mdk.MediaType.subtitle;
    default:
      throw ArgumentError('Unknown PlayerMediaType: $type');
  }
}

PlayerMediaInfo _toPlayerMediaInfo(mdk.MediaInfo mdkInfo,
    {int internalAudioTrackCount = 0}) {
  return PlayerMediaInfo(
    duration: mdkInfo.duration,
    video: mdkInfo.video?.map((v) {
      String? codecNameValue;
      try {
        try {
          dynamic trackCodecName = (v as dynamic).codecName;
          if (trackCodecName is String && trackCodecName.isNotEmpty) {
            codecNameValue = trackCodecName;
          }
        } catch (_) {}

        if (codecNameValue == null) {
          codecNameValue = v.codec.toString();
          if (codecNameValue.startsWith('Instance of')) {
            codecNameValue = 'Unknown Codec';
          }
        }
      } catch (e) {
        codecNameValue = 'Error Retrieving Codec';
      }
      return PlayerVideoStreamInfo(
        codec: PlayerVideoCodecParams(
            width: v.codec.width ?? 0,
            height: v.codec.height ?? 0,
            name: codecNameValue),
        codecName: codecNameValue,
      );
    }).toList(),
    subtitle: mdkInfo.subtitle?.map((sMdk) {
      return PlayerSubtitleStreamInfo(
        title: sMdk.metadata['title'] ??
            'Subtitle track ${mdkInfo.subtitle!.indexOf(sMdk)}',
        language: sMdk.metadata['language'] ?? 'unknown',
        metadata: sMdk.metadata,
        rawRepresentation: sMdk.toString(),
      );
    }).toList(),
    audio: mdkInfo.audio?.map<PlayerAudioStreamInfo>((aMdk) {
      String? codecNameValue;
      int? bitRate;
      int? channels;
      int? sampleRate;
      String? title;
      String? language;
      Map<String, String> metadata = {};
      String rawRepresentation = 'Unknown Audio Track';

      try {
        rawRepresentation = aMdk.toString();
        dynamic mdkAudioCodec = (aMdk as dynamic)?.codec;

        if (mdkAudioCodec != null) {
          try {
            dynamic codecNameProp = (mdkAudioCodec as dynamic)?.name;
            if (codecNameProp is String && codecNameProp.isNotEmpty) {
              codecNameValue = codecNameProp;
            } else {
              codecNameValue = mdkAudioCodec.toString();
              if (codecNameValue.startsWith('Instance of')) {
                codecNameValue = 'Unknown Codec';
              }
            }
          } catch (e) {
            codecNameValue = mdkAudioCodec.toString();
            if (codecNameValue.startsWith('Instance of')) {
              codecNameValue = 'Unknown Codec';
            }
          }

          try {
            bitRate = (mdkAudioCodec as dynamic)?.bit_rate as int?;
          } catch (e) {}
          try {
            channels = (mdkAudioCodec as dynamic)?.channels as int?;
          } catch (e) {}
          try {
            sampleRate = (mdkAudioCodec as dynamic)?.sample_rate as int?;
          } catch (e) {}
        }

        try {
          dynamic mdkMetadata = (aMdk as dynamic)?.metadata;
          if (mdkMetadata is Map) {
            metadata = mdkMetadata.map(
                (key, value) => MapEntry(key.toString(), value.toString()));
            title = metadata['title'];
            language = metadata['language'];
          }
        } catch (e) {}
      } catch (e) {}

      final trackIndex = mdkInfo.audio!.indexOf(aMdk);
      return PlayerAudioStreamInfo(
        codec: PlayerAudioCodecParams(
          name: codecNameValue,
          bitRate: bitRate,
          channels: channels,
          sampleRate: sampleRate,
        ),
        title: title ?? 'Audio track $trackIndex',
        language: language ?? 'unknown',
        metadata: metadata,
        rawRepresentation: rawRepresentation,
        isExternal: internalAudioTrackCount > 0 &&
            trackIndex >= internalAudioTrackCount,
      );
    }).toList(),
  );
}

class MdkPlayerAdapter implements AbstractPlayer {
  late mdk.Player _mdkPlayer;
  double _playbackRate = 1.0;
  List<String> _videoDecoders = const [];
  List<String> _audioDecoders = const [];
  final Map<String, String> _stickyProperties = {};
  String? _activeVideoDecoder;
  String? _activeAudioDecoder;
  int _internalAudioTrackCount = 0; // 内部音频轨道数，用于区分外挂MKA轨道
  final String _httpProxy;

  // 内嵌字幕轨切换后的停滞看门狗（见 _armSubtitleStallWatchdog）。
  Timer? _subtitleStallWatchTimer;
  int _subtitleStallWatchToken = 0;
  // 最近一次请求的内嵌字幕轨选择：停滞恢复重建原生 player 后需要重放。
  List<int> _lastRequestedSubtitleTracks = const [];

  MdkPlayerAdapter({String? httpProxy})
      : _httpProxy = (httpProxy ?? '').trim() {
    _mdkPlayer = mdk.Player();
    _attachMdkEventListeners();
    _applyInitialSettings();
  }

  void _attachMdkEventListeners() {
    try {
      void handleEvent(mdk.MediaEvent e) {
        switch (e.category) {
          case 'decoder.video':
            _activeVideoDecoder = e.detail;
            break;
          case 'decoder.audio':
            _activeAudioDecoder = e.detail;
            break;
        }
      }

      // FVP 0.33 exposes onEvent as a callback registrar, while 0.37 exposes
      // it as a Stream. Keep both forms working so the shared dependency graph
      // can stay on the mainline version and HarmonyOS can use its newer fork.
      final dynamic eventSource = _mdkPlayer.onEvent;
      if (eventSource is Stream<mdk.MediaEvent>) {
        eventSource.listen(handleEvent);
      } else {
        (eventSource as void Function(void Function(mdk.MediaEvent)))
            .call(handleEvent);
      }
    } catch (e) {
      debugPrint('MDK: 注册事件监听失败: $e');
    }
  }

  void _setStickyProperty(String key, String value) {
    _stickyProperties[key] = value;
    _mdkPlayer.setProperty(key, value);
  }

  void _reapplyStickyProperties() {
    for (final entry in _stickyProperties.entries) {
      try {
        _mdkPlayer.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  void _applyInitialSettings() {
    try {
      applyMdkHttpProxyProperties(_setStickyProperty, _httpProxy);
      _setStickyProperty('auto_load', '0');
      _setStickyProperty('subtitle', '1');
      // 重新应用播放速度设置
      if (_playbackRate != 1.0) {
        _mdkPlayer.playbackRate = _playbackRate;
        debugPrint('MDK: 初始化时应用播放速度: ${_playbackRate}x');
      }
    } catch (e) {
      debugPrint('MDK: 初始化设置失败: $e');
    }

    _configureSubtitleFonts();
  }

  void _configureSubtitleFonts() {
    if (!(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform.name == 'ohos')) {
      return;
    }

    unawaited(() async {
      try {
        final fontInfo = await ensureSubtitleFontFromAsset(
          assetPath: 'assets/subfont.ttf',
          fileName: 'subfont.ttf',
        );

        if (fontInfo == null) {
          debugPrint('MDK: 字幕字体准备失败，使用系统默认字体');
          return;
        }

        final fontsDir = fontInfo['directory'];
        final fontFile = fontInfo['filePath'];
        if (fontsDir == null || fontFile == null) {
          debugPrint('MDK: 字幕字体路径信息不完整');
          return;
        }
        const fontName = 'Droid Sans Fallback';

        try {
          _mdkPlayer.setProperty('subtitle.font', fontName);
          _mdkPlayer.setProperty('subtitle.fonts.dir', fontsDir);
          _mdkPlayer.setProperty('subtitle.fonts.file', fontFile);
        } catch (e) {
          debugPrint('MDK: 设置播放器字幕字体失败: $e');
        }

        try {
          mdk.setGlobalOption('subtitle.font', fontName);
          mdk.setGlobalOption('subtitle.fonts.dir', fontsDir);
          mdk.setGlobalOption('subtitle.fonts.file', fontFile);
        } catch (e) {
          debugPrint('MDK: 设置全局字幕字体失败: $e');
        }

        debugPrint('MDK: 字幕字体已配置，目录: $fontsDir');
      } catch (e) {
        debugPrint('MDK: 配置字幕字体过程中出错: $e');
      }
    }());
  }

  @override
  double get volume => _mdkPlayer.volume;
  @override
  set volume(double value) => _mdkPlayer.volume = value;

  @override
  double get playbackRate => _playbackRate;
  @override
  set playbackRate(double value) {
    _playbackRate = value;
    try {
      _mdkPlayer.playbackRate = value;
      debugPrint('MDK: 设置播放速度: ${value}x');
    } catch (e) {
      debugPrint('MDK: 设置播放速度失败: $e');
    }
  }

  @override
  PlayerPlaybackState get state => _toPlayerPlaybackState(_mdkPlayer.state);
  @override
  set state(PlayerPlaybackState value) =>
      _mdkPlayer.state = _fromPlayerPlaybackState(value);

  @override
  ValueListenable<int?> get textureId => _mdkPlayer.textureId;

  @override
  String get media => _mdkPlayer.media;
  @override
  set media(String value) {
    // 换主媒体后旧的字幕停滞观察作废
    _subtitleStallWatchTimer?.cancel();
    if (value.isNotEmpty && _mdkPlayer.media != value) {
      _activeVideoDecoder = null;
      _activeAudioDecoder = null;
      _internalAudioTrackCount = 0; // 重置：新主媒体尚未加载外挂音频
      final videoDecoders = _videoDecoders.isNotEmpty
          ? List<String>.from(_videoDecoders)
          : List<String>.from(_mdkPlayer.videoDecoders);
      final audioDecoders = _audioDecoders.isNotEmpty
          ? List<String>.from(_audioDecoders)
          : List<String>.from(_mdkPlayer.audioDecoders);

      try {
        _mdkPlayer.dispose();
      } catch (e) {}

      _mdkPlayer = mdk.Player();
      _attachMdkEventListeners();
      _applyInitialSettings();

      try {
        _reapplyStickyProperties();
        if (videoDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.video, videoDecoders);
        }
        if (audioDecoders.isNotEmpty) {
          setDecoders(PlayerMediaType.audio, audioDecoders);
        }
      } catch (e) {}
    } else if (value.isEmpty && _mdkPlayer.media.isNotEmpty) {
      _mdkPlayer.state = mdk.PlaybackState.stopped;
      _mdkPlayer.setMedia("", mdk.MediaType.video);
    }

    _mdkPlayer.media = value;
  }

  @override
  PlayerMediaInfo get mediaInfo => _toPlayerMediaInfo(_mdkPlayer.mediaInfo,
      internalAudioTrackCount: _internalAudioTrackCount);

  @override
  List<int> get activeSubtitleTracks => _mdkPlayer.activeSubtitleTracks;
  @override
  set activeSubtitleTracks(List<int> value) {
    if (value.isEmpty) {
      _subtitleStallWatchTimer?.cancel();
      _lastRequestedSubtitleTracks = const [];
      try {
        _mdkPlayer.activeSubtitleTracks = const [];
      } catch (e) {
        debugPrint('MDK: 关闭字幕轨失败: $e');
      }
      return;
    }

    // 与 MediaKit 适配器的 CRITICAL CHECK 对齐：没有任何字幕轨时不要把
    // 切换请求透传给 native（错误/越界索引属未定义行为，实测可让原生
    // 管线停死在 iOS 上）。
    int trackCount = 0;
    try {
      trackCount = _mdkPlayer.mediaInfo.subtitle?.length ?? 0;
    } catch (_) {}
    if (trackCount <= 0) {
      debugPrint('MDK: 忽略字幕轨切换，当前媒体没有可用字幕轨: $value');
      return;
    }
    final filtered = value.where((i) => i >= 0 && i < trackCount).toList();
    if (filtered.isEmpty) {
      debugPrint('MDK: 字幕轨索引全部越界，忽略切换: $value (共$trackCount轨)');
      return;
    }
    if (filtered.length != value.length) {
      debugPrint('MDK: 字幕轨索引越界已裁剪: $value -> $filtered (共$trackCount轨)');
    }

    final previous = List<int>.of(_mdkPlayer.activeSubtitleTracks);
    try {
      _mdkPlayer.activeSubtitleTracks = filtered;
    } catch (e) {
      debugPrint('MDK: 设置字幕轨失败: $e');
      return;
    }
    _lastRequestedSubtitleTracks = filtered;
    final actuallyChanged = filtered.length != previous.length ||
        filtered.asMap().entries.any((entry) => entry.value != previous[entry.key]);
    if (actuallyChanged) {
      _armSubtitleStallWatchdog();
    }
  }

  /// 内嵌字幕轨切换后的停滞看门狗。
  ///
  /// iOS 实测（WebDAV + MDK 内核）：在没有字幕事件的时间段切换内嵌字幕轨
  /// 后，原生管线会在几秒内停住——state 仍是 playing 但 position 不再前进，
  /// seek 无法恢复，只能重播（即重建原生 player）。这里在切换后采样两次
  /// position；确认停滞后用一个全新的原生 player 重建同一媒体并恢复
  /// 位置/倍速/音量/字幕选择。
  ///
  /// 卡住的旧实例**不调用 dispose**：其原生层可能正持有阻塞中的 demuxer
  /// 锁，同步 dispose 有把主 isolate 一并冻住的风险（比视频停死更糟），
  /// 交给进程退出回收。
  void _armSubtitleStallWatchdog() {
    _subtitleStallWatchTimer?.cancel();
    final token = ++_subtitleStallWatchToken;
    var firstSample = -1;

    void sample() {
      if (token != _subtitleStallWatchToken) return;
      int positionMs;
      try {
        positionMs = _mdkPlayer.position;
      } catch (_) {
        return;
      }
      final playing = _mdkPlayer.state == mdk.PlaybackState.playing;
      // 暂停中或尚未起播都不构成停滞证据；给观察窗口重置一次机会。
      if (!playing || positionMs <= 0) {
        firstSample = -1;
        return;
      }
      if (firstSample < 0) {
        firstSample = positionMs;
        return;
      }
      if (positionMs == firstSample) {
        _subtitleStallWatchTimer?.cancel();
        debugPrint(
            'MDK: 字幕轨切换后播放停滞(position=$positionMs)，重建原生播放器恢复');
        _recoverFromSubtitleStall(token);
      }
    }

    _subtitleStallWatchTimer =
        Timer(const Duration(milliseconds: 1200), () {
      sample();
      _subtitleStallWatchTimer?.cancel();
      _subtitleStallWatchTimer =
          Timer(const Duration(milliseconds: 1800), sample);
    });
  }

  void _recoverFromSubtitleStall(int token) {
    if (token != _subtitleStallWatchToken) return;
    final String mediaUrl;
    final int positionMs;
    final bool wasPlaying;
    final double volumeBefore;
    try {
      mediaUrl = _mdkPlayer.media;
      positionMs = _mdkPlayer.position;
      wasPlaying = _mdkPlayer.state == mdk.PlaybackState.playing;
      volumeBefore = _mdkPlayer.volume;
    } catch (e) {
      debugPrint('MDK: 停滞恢复失败（读取旧实例状态）: $e');
      return;
    }
    if (mediaUrl.isEmpty) return;

    final videoDecoders = _videoDecoders.isNotEmpty
        ? List<String>.from(_videoDecoders)
        : List<String>.from(_mdkPlayer.videoDecoders);
    final audioDecoders = _audioDecoders.isNotEmpty
        ? List<String>.from(_audioDecoders)
        : List<String>.from(_mdkPlayer.audioDecoders);
    final subtitleSelection = List<int>.of(_lastRequestedSubtitleTracks);

    // 有意不 dispose 卡住的旧实例：见 _armSubtitleStallWatchdog 注释。
    _mdkPlayer = mdk.Player();
    _internalAudioTrackCount = 0; // 重建后外挂音轨状态清零（主媒体之外的
    // setMedia(audio) 附加轨会丢失，属本恢复路径的已知限制）
    _attachMdkEventListeners();
    _applyInitialSettings();
    try {
      _reapplyStickyProperties();
      if (videoDecoders.isNotEmpty) {
        setDecoders(PlayerMediaType.video, videoDecoders);
      }
      if (audioDecoders.isNotEmpty) {
        setDecoders(PlayerMediaType.audio, audioDecoders);
      }
      _mdkPlayer.volume = volumeBefore;
      _mdkPlayer.media = mediaUrl;
      if (positionMs > 0) {
        _mdkPlayer.seek(position: positionMs);
      }
      _mdkPlayer.playbackRate = _playbackRate;
      if (wasPlaying) {
        _mdkPlayer.state = mdk.PlaybackState.playing;
      }
    } catch (e) {
      debugPrint('MDK: 停滞恢复重建失败: $e');
      return;
    }

    // 字幕轨要等新媒体加载出轨道列表后再重放（现在设置会因无轨被守卫拦截）。
    if (subtitleSelection.isNotEmpty) {
      unawaited(() async {
        for (var attempt = 0; attempt < 10; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          int count = 0;
          try {
            count = _mdkPlayer.mediaInfo.subtitle?.length ?? 0;
          } catch (_) {}
          if (count <= 0) continue;
          final applied = subtitleSelection
              .where((index) => index >= 0 && index < count)
              .toList();
          if (applied.isEmpty) return;
          try {
            _mdkPlayer.activeSubtitleTracks = applied;
            debugPrint('MDK: 停滞恢复后已重放字幕轨选择: $applied');
          } catch (e) {
            debugPrint('MDK: 停滞恢复后重放字幕轨失败: $e');
          }
          return;
        }
      }());
    }
  }

  @override
  List<int> get activeAudioTracks => _mdkPlayer.activeAudioTracks;
  @override
  set activeAudioTracks(List<int> value) =>
      _mdkPlayer.activeAudioTracks = value;

  @override
  int get position => _mdkPlayer.position;

  @override
  int get bufferedPosition {
    try {
      final bufferedDuration = _mdkPlayer.buffered();
      if (bufferedDuration <= 0) {
        return 0;
      }
      final endPosition = _mdkPlayer.position + bufferedDuration;
      final duration = _mdkPlayer.mediaInfo.duration;
      if (duration > 0) {
        return endPosition.clamp(0, duration).toInt();
      }
      return endPosition;
    } catch (_) {
      return 0;
    }
  }

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {
    try {
      _mdkPlayer.setBufferRange(min: minMs, max: maxMs, drop: drop);
    } catch (e) {
      debugPrint('MDK: 设置缓冲范围失败: $e');
    }
  }

  @override
  bool get supportsExternalSubtitles => true;

  @override
  Future<int?> updateTexture() {
    try {
      final originalFuture = _mdkPlayer.updateTexture();
      return originalFuture.timeout(const Duration(seconds: 10), onTimeout: () {
        throw TimeoutException(
            'Texture update timed out for ${_mdkPlayer.media}');
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  void setMedia(String path, PlayerMediaType type) {
    if (type == PlayerMediaType.audio) {
      if (path.isNotEmpty) {
        // 记录当前内部音频轨道数，用于区分外挂MKA轨道
        try {
          _internalAudioTrackCount = _mdkPlayer.mediaInfo.audio?.length ?? 0;
        } catch (_) {
          _internalAudioTrackCount = 0;
        }
      } else {
        _internalAudioTrackCount = 0;
      }
    }
    _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));
  }

  @override
  Future<void> prepare() async {
    try {
      _mdkPlayer.prepare();
      // prepare后重新应用播放速度，确保设置生效
      if (_playbackRate != 1.0) {
        _mdkPlayer.playbackRate = _playbackRate;
        debugPrint('MDK: prepare后应用播放速度: ${_playbackRate}x');
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  void seek({required int position}) {
    _mdkPlayer.seek(position: position);
  }

  @override
  void dispose() {
    _subtitleStallWatchTimer?.cancel();
    // MDK 的原生 dispose 是同步 FFI 调用，网络流（WebDAV/http）关闭时
    // 可能会在原生层等网络读取数秒——内核热切换链直接 await 这一下会把
    // 整个主 isolate 冻住（iOS「从 WebDAV 播放切内核导致 app 卡死」的
    // 主要嫌疑）。与 MediaKit 适配器同款处理：先让出事件循环让热切换继续
    // 创建新播放器，原生释放在下一拍执行并吞掉异常。
    final mdkPlayer = _mdkPlayer;
    unawaited(Future<void>.delayed(const Duration(milliseconds: 16), () {
      try {
        mdkPlayer.dispose();
      } catch (e) {
        debugPrint('MDK: 释放原生播放器失败: $e');
      }
    }));
  }

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    final Uint8List? frameBytes =
        await _mdkPlayer.snapshot(width: width, height: height);
    if (frameBytes == null) {
      if (width <= 0) width = 128;
      if (height <= 0) height = 72;
      final int numBytes = width * height * 4;
      final Uint8List blackBytes = Uint8List(numBytes);
      for (int i = 3; i < numBytes; i += 4) {
        blackBytes[i] = 255;
      }
      return PlayerFrame(width: width, height: height, bytes: blackBytes);
    }
    return PlayerFrame(
      width: width,
      height: height,
      bytes: frameBytes,
    );
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    switch (type) {
      case PlayerMediaType.video:
        _videoDecoders = List<String>.from(decoders);
        break;
      case PlayerMediaType.audio:
        _audioDecoders = List<String>.from(decoders);
        break;
      default:
        break;
    }
    _mdkPlayer.setDecoders(_fromPlayerMediaType(type), decoders);
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    switch (type) {
      case PlayerMediaType.video:
        if (_videoDecoders.isNotEmpty) return List<String>.from(_videoDecoders);
        return List<String>.from(_mdkPlayer.videoDecoders);
      case PlayerMediaType.audio:
        if (_audioDecoders.isNotEmpty) return List<String>.from(_audioDecoders);
        return List<String>.from(_mdkPlayer.audioDecoders);
      default:
        return const [];
    }
  }

  @override
  String? getProperty(String key) {
    switch (key) {
      case 'decoder.video':
        return _activeVideoDecoder;
      case 'decoder.audio':
        return _activeAudioDecoder;
    }
    return _mdkPlayer.getProperty(key);
  }

  @override
  void setUserAgent(String ua) {
    applyMdkUserAgentProperties(setProperty, ua);
    debugPrint('MDK: 已设置 user-agent: ${ua.isEmpty ? "(默认)" : ua}');
  }

  @override
  void setProperty(String key, String value) {
    try {
      _setStickyProperty(key, value);
    } catch (e) {
      debugPrint('MDK: 设置属性失败: $e');
    }
  }

  @override
  void stepForward() {
    // MDK: 使用 seek 模拟逐帧前进（约 1/24 秒 = ~42ms）
    final fps = mediaInfo.video?.isNotEmpty == true
        ? (mediaInfo.video!.first.codec.width > 0 ? 24 : 24) // 默认24fps
        : 24;
    final frameDuration = 1000 ~/ fps;
    final currentPos = position;
    seek(position: currentPos + frameDuration);
    state = PlayerPlaybackState.paused;
  }

  @override
  void stepBackward() {
    final fps = 24; // 默认24fps
    final frameDuration = 1000 ~/ fps;
    final currentPos = position;
    seek(position: (currentPos - frameDuration).clamp(0, currentPos));
    state = PlayerPlaybackState.paused;
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {
    // MDK 内核由自身窗口管理渲染尺寸，这里保持空实现。
  }

  @override
  Future<void> setChapter(int index) async {
    // MDK 内核暂未暴露章节跳转（MediaInfo.ChapterInfo 存在但适配器未接入）。
  }

  @override
  Future<void> playDirectly() async {
    try {
      _mdkPlayer.state = mdk.PlaybackState.playing;
    } catch (e) {}
  }

  @override
  Future<void> pauseDirectly() async {
    try {
      _mdkPlayer.state = mdk.PlaybackState.paused;
    } catch (e) {}
  }

  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate;
  }

  // 提供详细播放技术信息（MDK）
  Map<String, dynamic> getDetailedMediaInfo() {
    final info = _mdkPlayer.mediaInfo;
    final Map<String, dynamic> ret = {
      'kernel': 'MDK',
      'video': <dynamic>[],
      'audio': <dynamic>[],
      'duration': info.duration,
    };

    try {
      ret['video'] = (info.video ?? []).map((v) {
        final codec = v.codec;
        String codecName = 'unknown';
        try {
          final dynamic name = (v as dynamic).codecName;
          if (name is String && name.isNotEmpty) codecName = name;
        } catch (_) {
          codecName = codec.toString();
        }
        return {
          'codecName': codecName,
          'width': codec.width,
          'height': codec.height,
          'raw': v.toString(),
        };
      }).toList();
    } catch (_) {}

    try {
      ret['audio'] = (info.audio ?? []).map((a) {
        final dynamic c = (a as dynamic).codec;
        String? name;
        int? bitRate;
        int? channels;
        int? sampleRate;
        try {
          name = c?.name as String?;
        } catch (_) {}
        try {
          bitRate = c?.bit_rate as int?;
        } catch (_) {}
        try {
          channels = c?.channels as int?;
        } catch (_) {}
        try {
          sampleRate = c?.sample_rate as int?;
        } catch (_) {}
        return {
          'codecName': name,
          'bitRate': bitRate,
          'channels': channels,
          'sampleRate': sampleRate,
          'raw': a.toString(),
        };
      }).toList();
    } catch (_) {}

    return ret;
  }

  // MDK 的异步接口：直接返回同步结果（MDK 获取多为同步）
  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async {
    return getDetailedMediaInfo();
  }
}

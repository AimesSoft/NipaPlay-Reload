import 'package:fvp/mdk.dart' as mdk;
import 'package:flutter/foundation.dart';
// Required for Uint8List
import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';
import 'dart:async';
import 'dart:io' show Platform;
import 'package:nipaplay/utils/player_kernel_manager.dart';
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

class MdkPlayerAdapter implements AbstractPlayer, AsyncDisposablePlayer {
  late mdk.Player _mdkPlayer;
  double _playbackRate = 1.0;
  List<String> _videoDecoders = const [];
  List<String> _audioDecoders = const [];
  final Map<String, String> _stickyProperties = {};
  String? _activeVideoDecoder;
  String? _activeAudioDecoder;
  int _internalAudioTrackCount = 0; // 内部音频轨道数，用于区分外挂MKA轨道
  final String _httpProxy;
  // 幂等守卫：热切换主路径（步骤 3.1）与 finally 兜底会先后调用
  // disposeAsync，必须合并为同一次 teardown，杜绝 double mdkPlayerAPI_delete。
  bool _isDisposed = false;
  Future<void>? _disposeAsyncFuture;
  // iOS 上播放过媒体则跳过原生销毁（泄露兜底）：mdkPlayerAPI_delete 的
  // join 解码/渲染线程在 iPad 15.1 实测会永久阻塞主 isolate。空闲切换
  // （从未加载媒体）仍走正常销毁（已验证安全）。
  bool _hadLoadedMedia = false;

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
    if (value.isNotEmpty) {
      // 主视频是通过 media setter 打开的(video_player_state_player_setup:
      // player.media = playUrl)，不是 setMedia()——这里必须同步标记，
      // 否则热切换 dispose 的“跳过原生销毁”兜底永不触发(iPad 实测仍卡死)。
      _hadLoadedMedia = true;
    }
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

      // 换媒体会重建内核实例：若旧实例已加载媒体，iOS/Windows 上的
      // mdkPlayerAPI_delete 同样会 join 解码/渲染线程永久阻塞
      // (与热切换卡死同根因，切集时也会触发)。先卸载媒体管线，
      // 再跳过原生销毁(泄露旧实例壳，占内存换不冻结)，然后新建。
      if ((Platform.isIOS || Platform.isWindows) && _hadLoadedMedia) {
        try {
          if (_mdkPlayer.media.isNotEmpty) {
            _mdkPlayer.setMedia('', mdk.MediaType.video);
          }
        } catch (e) {}
        PlayerKernelManager.traceHotSwapStage(
            'mdk media-swap: iOS/Windows 跳过旧实例原生销毁(泄露兜底)');
      } else {
        try {
          _mdkPlayer.dispose();
        } catch (e) {}
      }

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
  set activeSubtitleTracks(List<int> value) =>
      _mdkPlayer.activeSubtitleTracks = value;

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
    if (path.isNotEmpty) {
      _hadLoadedMedia = true;
    }
    _mdkPlayer.setMedia(path, _fromPlayerMediaType(type));
  }

  @override
  Future<void> prepare() async {
    try {
      _mdkPlayer.prepare();
      if (_mdkPlayer.media.isNotEmpty) {
        _hadLoadedMedia = true;
      }
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
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    // iOS/Windows 播放过媒体后，mdkPlayerAPI_delete 会 join 解码/渲染线程并
    // 永久阻塞主 isolate（iPad 15.1 实测 freeze 于 native delete；先 state=
    // stopped + setMedia("") 卸载媒体也不解决，Windows 同样卡死但难触发）。
    // 卸载后管线已停：跳过原生销毁，仅泄露一个已停止的 Player 壳
    // （内存滞留换切换不冻结）。空闲态（从未加载媒体）仍正常销毁。
    if ((Platform.isIOS || Platform.isWindows) && _hadLoadedMedia) {
      PlayerKernelManager.traceHotSwapStage(
          'mdk dispose: iOS/Windows 跳过原生销毁（泄露兜底，避免 mdkPlayerAPI_delete 冻结）');
      debugPrint('MDK: iOS/Windows 播放过媒体，跳过原生销毁（泄露兜底）');
      return;
    }
    _mdkPlayer.dispose();
  }

  /// 异步释放：fvp 的 Player.dispose() 是 `async void`——内部先
  /// `await updateTexture(width:-1)`（releaseTexture 平台通道往返 +
  /// 等待 videoSize Completer），最后才执行 mdkPlayerAPI_delete，
  /// 调用方无法等待其完成。旧实现调用后立即返回，导致：
  /// 1) 播放中热切换时，旧原生实例（解码线程/GL 上下文/音频输出）在
  ///    新内核创建并起播时仍未销毁（await 挂起或异步链未走完），
  ///    新旧实例在平台线程并存 → 死锁卡死（iPadOS 实测：空闲切换必现
  ///    不卡、播放中切换卡死，正源于此）；
  /// 2) finally 兜底与主路径并发触发 double mdkPlayerAPI_delete。
  /// 现策略：并发调用合并（_disposeAsyncFuture）+ 幂等；并主动用带超时的
  /// updateTexture(width:-1) 提前收敛纹理与 Completer，使 dispose() 内部
  /// 的同调用变成快速 no-op，原生删除在新建内核初始化前到达。
  @override
  Future<void> disposeAsync() {
    return _disposeAsyncFuture ??= _disposeAsyncInternal();
  }

  Future<void> _disposeAsyncInternal() async {
    PlayerKernelManager.traceHotSwapStage('mdk teardown: set stopped begin');
    try {
      if (state != PlayerPlaybackState.stopped) {
        state = PlayerPlaybackState.stopped;
      }
    } catch (e) {
      debugPrint('MDK: dispose 前置停止失败: $e');
    }
    // ← 历史卡死点 1：fvp dispose 内部的 updateTexture 等待 videoSize
    PlayerKernelManager.traceHotSwapStage('mdk teardown: releaseTexture begin');
    try {
      await _mdkPlayer
          .updateTexture(width: -1)
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('MDK: dispose 前释放纹理未完成（继续销毁）: $e');
    }
    PlayerKernelManager.traceHotSwapStage('mdk teardown: releaseTexture done');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    // ← 卡死点（iPad 实测 freeze 于 native delete）：fvp dispose() 只做
    // state=stopped（停播放循环），并不卸载媒体——VT 硬解/解复用线程仍
    // 活跃，mdkPlayerAPI_delete 需要 join 这些线程而永久阻塞主 isolate。
    // 先 setMedia("") 卸载媒体，让解码管线先行收敛拆除，delete 时无线程
    // 可 join 即可快速返回。
    PlayerKernelManager.traceHotSwapStage('mdk teardown: unload media begin');
    try {
      if (_mdkPlayer.media.isNotEmpty) {
        _mdkPlayer.setMedia('', mdk.MediaType.video);
      }
    } catch (e) {
      debugPrint('MDK: dispose 前卸载媒体失败: $e');
    }
    await Future<void>.delayed(const Duration(milliseconds: 150));
    PlayerKernelManager.traceHotSwapStage('mdk teardown: unload media done');
    // ← 历史卡死点 2：mdkPlayerAPI_delete（同步 FFI）
    PlayerKernelManager.traceHotSwapStage('mdk teardown: native delete begin');
    dispose();
    // fvp dispose 为 async void：上面的 updateTexture 已提前收敛，
    // 此处短暂让出，确保 mdkPlayerAPI_delete 在新内核初始化前执行。
    await Future<void>.delayed(const Duration(milliseconds: 150));
    PlayerKernelManager.traceHotSwapStage('mdk teardown: done');
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

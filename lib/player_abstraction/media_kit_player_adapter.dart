import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/scheduler.dart'; // 导入TickerProvider
import 'package:nipaplay/utils/subtitle_font_loader.dart';
import 'package:nipaplay/utils/subtitle_file_utils.dart';
import 'package:nipaplay/utils/platform_utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import './abstract_player.dart';
import './player_enums.dart';
import './player_data_models.dart';

/// MediaKit播放器适配器
class MediaKitPlayerAdapter implements AbstractPlayer, TickerProvider {
  static bool _disableMpvLogs = false;
  static int? _cachedMacosMajor;
  static const int _defaultBufferSize = 32 * 1024 * 1024;
  static const String _hdrValidationFlag = 'NIPAPLAY_MACOS_HDR_VALIDATE';

  static void setMpvLogLevelNone() {
    _disableMpvLogs = true;
  }

  static bool shouldUseDefaultQuietMpvLogs() {
    return !_shouldEnableMpvDiagnostics();
  }

  static bool _envFlagEnabled(String name) {
    final value = Platform.environment[name];
    if (value == null) {
      return false;
    }
    switch (value.trim().toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
      case 'on':
        return true;
      default:
        return false;
    }
  }

  static String? _envString(String name) {
    final value = Platform.environment[name]?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  static bool _shouldEnableMpvDiagnostics() {
    return _envFlagEnabled('NIPAPLAY_ENABLE_MPV_LOGS') ||
        _envFlagEnabled(_hdrValidationFlag) ||
        _envString('NIPAPLAY_MPV_LOG_FILE') != null ||
        _envString('NIPAPLAY_MPV_MSG_LEVEL') != null ||
        _envString('NIPAPLAY_MPV_LOG_LEVEL') != null;
  }

  static MPVLogLevel _resolveMpvLogLevel() {
    switch (_envString('NIPAPLAY_MPV_LOG_LEVEL')?.toLowerCase()) {
      case 'trace':
        return MPVLogLevel.trace;
      case 'debug':
        return MPVLogLevel.debug;
      case 'v':
      case 'verbose':
        return MPVLogLevel.v;
      case 'info':
        return MPVLogLevel.info;
      case 'warn':
      case 'warning':
        return MPVLogLevel.warn;
      case 'error':
        return MPVLogLevel.error;
      default:
        return _shouldEnableMpvDiagnostics()
            ? MPVLogLevel.debug
            : MPVLogLevel.debug;
    }
  }

  static String? _resolveHardwareDecodingOverride() {
    final env = _envString('NIPAPLAY_MPV_HWDEC');
    if (env != null) {
      return env;
    }
    if (Platform.isMacOS && _envFlagEnabled(_hdrValidationFlag)) {
      return 'videotoolbox,auto';
    }
    return null;
  }

  static int? _resolveMacosMajorVersion() {
    if (_cachedMacosMajor != null) {
      return _cachedMacosMajor;
    }
    if (!Platform.isMacOS) {
      return null;
    }
    final version = Platform.operatingSystemVersion;
    final versionMatch = RegExp(r'Version\s+(\d+)').firstMatch(version) ??
        RegExp(r'macOS\s+(\d+)').firstMatch(version);
    if (versionMatch != null) {
      _cachedMacosMajor = int.tryParse(versionMatch.group(1)!);
      return _cachedMacosMajor;
    }
    final firstNumber = RegExp(r'(\d+)').firstMatch(version);
    if (firstNumber == null) {
      return null;
    }
    final major = int.tryParse(firstNumber.group(1)!);
    if (major == null) {
      return null;
    }
    if (major >= 20 && major <= 30) {
      // Darwin 20 -> macOS 11, Darwin 23 -> macOS 14
      _cachedMacosMajor = major - 9;
      return _cachedMacosMajor;
    }
    _cachedMacosMajor = major;
    return _cachedMacosMajor;
  }

  static bool _shouldDisableHardwareAcceleration() {
    if (!Platform.isMacOS) {
      return false;
    }
    final env = Platform.environment['NIPAPLAY_DISABLE_HWACCEL'];
    if (env != null) {
      final normalized = env.toLowerCase();
      if (normalized == '1' || normalized == 'true' || normalized == 'yes') {
        return true;
      }
    }
    final major = _resolveMacosMajorVersion();
    if (major != null && major < 14) {
      return true;
    }
    return false;
  }

  static bool _shouldUseMacOSNativeVideoSurface() {
    if (!Platform.isMacOS) {
      return false;
    }
    final env = Platform.environment['NIPAPLAY_ENABLE_MACOS_NATIVE_VIDEO'];
    if (env == null) {
      return false;
    }
    switch (env.toLowerCase()) {
      case '1':
      case 'true':
      case 'yes':
        return true;
      default:
        return false;
    }
  }

  static String _resolveMacOSNativeVideoVO() {
    final env = Platform.environment['NIPAPLAY_MACOS_NATIVE_VIDEO_VO'];
    if (env == null || env.trim().isEmpty) {
      return 'gpu-next';
    }
    return env.trim();
  }

  static String _resolveMacOSNativeVideoWidTarget() {
    final env = Platform.environment['NIPAPLAY_MACOS_NATIVE_VIDEO_WID_TARGET'];
    switch (env?.trim().toLowerCase()) {
      case 'window':
        return 'window';
      default:
        return 'view';
    }
  }

  final Player _player;
  VideoController? _controller;
  final ValueNotifier<int?> _textureIdNotifier = ValueNotifier<int?>(null);
  final GlobalKey _repaintBoundaryKey = GlobalKey();
  bool _textureIdListenerAttached = false;

  String _currentMedia = '';
  PlayerMediaInfo _mediaInfo = PlayerMediaInfo(duration: 0);
  PlayerPlaybackState _state = PlayerPlaybackState.stopped;
  List<int> _activeSubtitleTracks = [];
  List<int> _activeAudioTracks = [];

  String? _lastKnownActiveSubtitleId;
  StreamSubscription<Track>? _trackSubscription;
  bool _isDisposed = false;

  // Jellyfin流媒体重试
  int _jellyfinRetryCount = 0;
  static const int _maxJellyfinRetries = 3;
  Timer? _jellyfinRetryTimer;
  String? _lastJellyfinMediaPath;

  // 时间插值器相关字段
  Ticker? _ticker;
  Duration _interpolatedPosition = Duration.zero;
  Duration _lastActualPosition = Duration.zero;
  int _lastPositionTimestamp = 0;

  final Map<PlayerMediaType, List<String>> _decoders = {
    PlayerMediaType.video: [],
    PlayerMediaType.audio: [],
    PlayerMediaType.subtitle: [],
    PlayerMediaType.unknown: [],
  };
  final Map<String, String> _properties = {};

  // 添加播放速度状态变量
  double _playbackRate = 1.0;
  final bool _mpvDiagnosticsEnabled;
  final bool _enableHardwareAcceleration;
  final bool _prefersPlatformVideoSurface;
  int? _attachedPlatformViewHandle;
  int? _attachedPlatformWindowHandle;

  MediaKitPlayerAdapter({int? bufferSize})
      : _mpvDiagnosticsEnabled = _shouldEnableMpvDiagnostics(),
        _enableHardwareAcceleration = !_shouldDisableHardwareAcceleration(),
        _prefersPlatformVideoSurface = _shouldUseMacOSNativeVideoSurface(),
        _player = Player(
          configuration: PlayerConfiguration(
            libass: true,
            libassAndroidFont: defaultTargetPlatform == TargetPlatform.android
                ? 'assets/subfont.ttf'
                : null,
            libassAndroidFontName:
                defaultTargetPlatform == TargetPlatform.android
                    ? 'Droid Sans Fallback'
                    : null,
            bufferSize: bufferSize ?? _defaultBufferSize,
            logLevel:
                _disableMpvLogs ? MPVLogLevel.error : _resolveMpvLogLevel(),
          ),
        ) {
    _applyMpvLogLevelOverride();
    _applyMpvDiagnosticOptions();
    if (!_prefersPlatformVideoSurface) {
      _controller = VideoController(
        _player,
        configuration: VideoControllerConfiguration(
          enableHardwareAcceleration: _enableHardwareAcceleration,
        ),
      );
    }
    _initializeHardwareDecoding();
    _initializeCodecs();
    unawaited(_setupSubtitleFonts());
    _controller?.waitUntilFirstFrameRendered.then((_) {
      _updateTextureIdFromController();
    });
    _addEventListeners();
    _setupDefaultTrackSelectionBehavior();
    _initializeTicker();
  }

  void _applyMpvLogLevelOverride() {
    if (!_disableMpvLogs) {
      return;
    }
    try {
      unawaited(
        (_player.platform as dynamic).setProperty('msg-level', 'all=no'),
      );
    } catch (e) {
      debugPrint('MediaKit: 设置MPV日志级别为none失败: $e');
    }
  }

  void _applyMpvDiagnosticOptions() {
    if (!_mpvDiagnosticsEnabled) {
      return;
    }

    final defaultMsgLevel = _envFlagEnabled(_hdrValidationFlag)
        ? 'all=warn,cplayer=debug,vd=debug,vf=v,vo=debug,vo/gpu-next=v,gpu=v,mac=v,cocoacb=v,ffmpeg=warn,ffmpeg/demuxer=warn,lavf=warn,demux=warn,file=warn,playlist=warn'
        : 'all=debug';

    final options = <String, String>{
      if (_envString('NIPAPLAY_MPV_LOG_FILE') case final logFile?)
        'log-file': logFile,
      'msg-level': _envString('NIPAPLAY_MPV_MSG_LEVEL') ?? defaultMsgLevel,
      if (Platform.isMacOS && _envFlagEnabled(_hdrValidationFlag)) ...{
        'gpu-api': _envString('NIPAPLAY_MPV_GPU_API') ?? 'vulkan',
        'gpu-context': _envString('NIPAPLAY_MPV_GPU_CONTEXT') ?? 'macvk',
        'target-colorspace-hint':
            _envString('NIPAPLAY_MPV_TARGET_COLORSPACE_HINT') ?? 'yes',
        'target-colorspace-hint-mode':
            _envString('NIPAPLAY_MPV_TARGET_COLORSPACE_HINT_MODE') ?? 'source',
        'hdr-compute-peak':
            _envString('NIPAPLAY_MPV_HDR_COMPUTE_PEAK') ?? 'auto',
      },
    };

    for (final entry in options.entries) {
      _setMpvPropertyForDiagnostics(entry.key, entry.value);
    }
  }

  void _setMpvPropertyForDiagnostics(String name, String value) {
    _properties[name] = value;
    try {
      final dynamic platform = _player.platform;
      platform?.setProperty?.call(name, value);
      debugPrint('MediaKit HDR诊断: mpv $name=$value');
    } catch (e) {
      debugPrint('MediaKit HDR诊断: 设置 mpv $name 失败: $e');
    }
  }

  void _initializeHardwareDecoding() {
    try {
      final hwdecOverride = _resolveHardwareDecodingOverride();
      if (hwdecOverride != null) {
        (_player.platform as dynamic)?.setProperty('hwdec', hwdecOverride);
        _properties['hwdec'] = hwdecOverride;
        debugPrint('MediaKit HDR诊断: mpv hwdec=$hwdecOverride');
        return;
      }
      if (!_enableHardwareAcceleration) {
        (_player.platform as dynamic)?.setProperty('hwdec', 'no');
        debugPrint('MediaKit: macOS < 14 或被禁用，硬件加速已关闭');
        return;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        (_player.platform as dynamic)?.setProperty('hwdec', 'mediacodec-copy');
      } else {
        // 对于其他平台，'auto-copy' 仍然是一个好的通用选择
        (_player.platform as dynamic)?.setProperty('hwdec', 'auto-copy');
      }
    } catch (e) {
      debugPrint('MediaKit: 设置硬件解码模式失败: $e');
    }
  }

  void _initializeCodecs() {
    try {
      final videoDecoders = ['auto'];
      setDecoders(PlayerMediaType.video, videoDecoders);
    } catch (e) {
      debugPrint('设置解码器失败: $e');
    }
  }

  Future<void> _setupSubtitleFonts() async {
    try {
      final dynamic platform = _player.platform;
      if (platform == null) {
        debugPrint('MediaKit: 无法设置字体回退和字幕选项，platform实例为null');
        return;
      }

      platform.setProperty?.call("embeddedfonts", "yes");
      platform.setProperty?.call("sub-ass-force-style", "");
      platform.setProperty?.call("sub-ass-override", "no");

      if (defaultTargetPlatform == TargetPlatform.android) {
        platform.setProperty?.call("sub-font", "Droid Sans Fallback");
        // PlayerConfiguration 已配置 libassAndroidFont，对应的目录无需在此覆盖。
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        platform.setProperty?.call("sub-font", "Droid Sans Fallback");
        final fontInfo = await ensureSubtitleFontFromAsset(
          assetPath: 'assets/subfont.ttf',
          fileName: 'subfont.ttf',
        );
        if (fontInfo != null) {
          final fontsDir = fontInfo['directory'];
          platform.setProperty?.call("sub-fonts-dir", fontsDir);
          platform.setProperty?.call("sub-file-paths", fontsDir);
          debugPrint('MediaKit: iOS 字幕字体目录: $fontsDir');
        } else {
          debugPrint('MediaKit: iOS 字幕字体准备失败，使用系统字体回退');
        }
      } else {
        platform.setProperty?.call("sub-font", "subfont");
        platform.setProperty?.call("sub-fonts-dir", "assets");
      }

      platform.setProperty?.call(
        "sub-fallback-fonts",
        "Droid Sans Fallback,Source Han Sans SC,subfont,思源黑体,微软雅黑,Microsoft YaHei,Noto Sans CJK SC,华文黑体,STHeiti",
      );
      platform.setProperty?.call("sub-codepage", "auto");
      platform.setProperty?.call("sub-auto", "fuzzy");
      platform.setProperty?.call("sub-ass-vsfilter-aspect-compat", "yes");
      platform.setProperty?.call("sub-ass-vsfilter-blur-compat", "yes");
    } catch (e) {
      debugPrint('设置字体回退和字幕选项失败: $e');
    }
  }

  void _updateTextureIdFromController() {
    final controller = _controller;
    if (controller == null) {
      return;
    }
    try {
      final currentId = controller.id.value;
      if (_textureIdNotifier.value != currentId) {
        _textureIdNotifier.value = currentId;
        debugPrint('MediaKit: 纹理ID已更新: $currentId');
      } else {
        debugPrint('MediaKit: 成功获取纹理ID从VideoController: $currentId');
      }

      if (!_textureIdListenerAttached) {
        _textureIdListenerAttached = true;
        controller.id.addListener(_handleTextureIdChange);
      }
    } catch (e) {
      debugPrint('获取纹理ID失败: $e');
    }
  }

  void _handleTextureIdChange() {
    if (_isDisposed) return;
    final newId = _controller?.id.value;
    if (newId != null && _textureIdNotifier.value != newId) {
      _textureIdNotifier.value = newId;
      debugPrint('MediaKit: 纹理ID已更新: $newId');
    }
  }

  void _addEventListeners() {
    _player.stream.playing.listen((playing) {
      _state = playing
          ? PlayerPlaybackState.playing
          : (_player.state.position.inMilliseconds > 0
              ? PlayerPlaybackState.paused
              : PlayerPlaybackState.stopped);
      if (playing) {
        _lastActualPosition = _player.state.position;
        _lastPositionTimestamp = DateTime.now().millisecondsSinceEpoch;
        if (_ticker != null && !_ticker!.isActive) {
          _ticker!.start();
        }
      } else {
        _ticker?.stop();
        _interpolatedPosition = _player.state.position;
        _lastActualPosition = _player.state.position;
      }
    });

    _player.stream.tracks.listen(_updateMediaInfo);

    // 添加对视频尺寸变化的监听
    //debugPrint('[MediaKit] 设置videoParams监听器');
    _player.stream.videoParams.listen((params) {
      //debugPrint('[MediaKit] 视频参数变化: dw=${params.dw}, dh=${params.dh}');
      // 当视频尺寸可用时，重新更新媒体信息
      if (params.dw != null &&
          params.dh != null &&
          params.dw! > 0 &&
          params.dh! > 0) {
        _updateMediaInfoWithVideoDimensions(params.dw!, params.dh!);
      }
    });

    // 添加对播放状态的监听，在播放时检查视频尺寸
    _player.stream.playing.listen((playing) {
      if (playing) {
        //debugPrint('[MediaKit] 视频开始播放，检查视频尺寸');
        // 延迟一点时间确保视频已经真正开始播放
        Future.delayed(const Duration(milliseconds: 500), () {
          if (_player.state.width != null &&
              _player.state.height != null &&
              _player.state.width! > 0 &&
              _player.state.height! > 0) {
            //debugPrint('[MediaKit] 播放时获取到视频尺寸: ${_player.state.width}x${_player.state.height}');
            // 强制更新媒体信息
            _updateMediaInfoWithVideoDimensions(
              _player.state.width!,
              _player.state.height!,
            );
          }
        });
      }
    });

    _trackSubscription = _player.stream.track.listen(
      (trackEvent) {
        // //debugPrint('MediaKitAdapter: Active track changed event received. Subtitle ID from event: ${trackEvent.subtitle.id}, Title: ${trackEvent.subtitle.title}');
        // The listener callback itself is not async, so we don't await _handleActiveSubtitleTrackDataChange here.
        // _handleActiveSubtitleTrackDataChange will run its async operations independently.
        _handleActiveSubtitleTrackDataChange(trackEvent.subtitle);
      },
      onError: (error) {
        //debugPrint('MediaKitAdapter: Error in player.stream.track: $error');
      },
      onDone: () {
        //debugPrint('MediaKitAdapter: player.stream.track was closed.');
      },
    );

    _player.stream.error.listen((error) {
      debugPrint('MediaKit错误: $error');
      _handleStreamingError(error);
    });

    _player.stream.duration.listen((duration) {
      if (duration.inMilliseconds > 0 &&
          _mediaInfo.duration != duration.inMilliseconds) {
        _mediaInfo = _mediaInfo.copyWith(duration: duration.inMilliseconds);
      }
    });

    _player.stream.log.listen((log) {
      if (_mpvDiagnosticsEnabled) {
        debugPrint('MediaKit MPV日志: [${log.level}/${log.prefix}] ${log.text}');
      }
    });
  }

  void _printAllTracksInfo(Tracks tracks) {
    StringBuffer sb = StringBuffer();
    sb.writeln('============ MediaKit所有轨道信息 ============');
    final realVideoTracks = _filterRealTracks<VideoTrack>(tracks.video);
    final realAudioTracks = _filterRealTracks<AudioTrack>(tracks.audio);
    final realSubtitleTracks = _filterRealTracks<SubtitleTrack>(
      tracks.subtitle,
    );
    sb.writeln(
      '视频轨道数: ${tracks.video.length}, 音频轨道数: ${tracks.audio.length}, 字幕轨道数: ${tracks.subtitle.length}',
    );
    sb.writeln(
      '真实视频轨道数: ${realVideoTracks.length}, 真实音频轨道数: ${realAudioTracks.length}, 真实字幕轨道数: ${realSubtitleTracks.length}',
    );
    for (int i = 0; i < tracks.video.length; i++) {
      final track = tracks.video[i];
      int? width;
      int? height;
      try {
        width = (track as dynamic).codec?.width;
        height = (track as dynamic).codec?.height;
      } catch (_) {
        width = null;
        height = null;
      }
      sb.writeln(
        'V[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'} 编码:${track.codec ?? 'N/A'} width:$width height:$height',
      );
    }
    for (int i = 0; i < tracks.audio.length; i++) {
      final track = tracks.audio[i];
      sb.writeln(
        'A[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'} 编码:${track.codec ?? 'N/A'}',
      );
    }
    for (int i = 0; i < tracks.subtitle.length; i++) {
      final track = tracks.subtitle[i];
      sb.writeln(
        'S[$i] ID:${track.id} 标题:${track.title ?? 'N/A'} 语言:${track.language ?? 'N/A'}',
      );
    }
    sb.writeln(
      '原始API: V=${_player.state.tracks.video.length} A=${_player.state.tracks.audio.length} S=${_player.state.tracks.subtitle.length}',
    );
    sb.writeln('============================================');
    debugPrint(sb.toString());
  }

  List<T> _filterRealTracks<T>(List<T> tracks) {
    return tracks.where((track) {
      final String id = (track as dynamic).id as String;
      if (id == 'auto' || id == 'no') {
        return false;
      }
      final intId = int.tryParse(id);
      return intId != null && intId >= 0;
    }).toList();
  }

  void _updateMediaInfo(Tracks tracks) {
    //debugPrint('MediaKitAdapter: _updateMediaInfo CALLED. Received tracks: Video=${tracks.video.length}, Audio=${tracks.audio.length}, Subtitle=${tracks.subtitle.length}');
    _printAllTracksInfo(tracks);
    // 打印所有视频轨道的宽高
    final realVideoTracks = _filterRealTracks<VideoTrack>(tracks.video);
    for (var track in realVideoTracks) {
      int? width;
      int? height;
      try {
        width = (track as dynamic).codec?.width;
        height = (track as dynamic).codec?.height;
      } catch (_) {
        width = null;
        height = null;
      }
      //debugPrint('[MediaKit] 轨道: id=${track.id}, title=${track.title}, codec=${track.codec}, width=$width, height=$height');
    }

    final realAudioTracks = _filterRealTracks<AudioTrack>(tracks.audio);
    final realIncomingSubtitleTracks = _filterRealTracks<SubtitleTrack>(
      tracks.subtitle,
    );

    // 针对Jellyfin流媒体的特殊处理
    if (_currentMedia.contains('jellyfin://') ||
        _currentMedia.contains('emby://')) {
      _handleJellyfinStreamingTracks(
        tracks,
        realVideoTracks,
        realAudioTracks,
        realIncomingSubtitleTracks,
      );
      return;
    }
    final embeddedSubtitleTracks =
        realIncomingSubtitleTracks.where((track) => !track.isExternal).toList();

    List<PlayerVideoStreamInfo>? videoStreams;
    if (realVideoTracks.isNotEmpty) {
      videoStreams = realVideoTracks.map((track) {
        // 尝试从轨道信息获取宽高
        int? width;
        int? height;
        try {
          width = (track as dynamic).codec?.width;
          height = (track as dynamic).codec?.height;
        } catch (_) {
          width = null;
          height = null;
        }

        // 如果轨道信息中没有宽高，从_player.state获取
        if ((width == null || width == 0) &&
            (_player.state.width != null && _player.state.width! > 0)) {
          width = _player.state.width;
          height = _player.state.height;
          //debugPrint('[MediaKit] 从_player.state获取视频尺寸: ${width}x$height');
        }

        return PlayerVideoStreamInfo(
          codec: PlayerVideoCodecParams(
            width: width ?? 0,
            height: height ?? 0,
            name: track.title ?? track.language ?? 'Unknown Video',
          ),
          codecName: track.codec ?? 'Unknown',
        );
      }).toList();
      // 打印videoStreams的宽高
      for (var vs in videoStreams) {
        //debugPrint('[MediaKit] videoStreams: codec.width=${vs.codec.width}, codec.height=${vs.codec.height}, codecName=${vs.codecName}');
      }
    }

    List<PlayerAudioStreamInfo>? audioStreams;
    if (realAudioTracks.isNotEmpty) {
      audioStreams = [];
      for (int i = 0; i < realAudioTracks.length; i++) {
        final track = realAudioTracks[i];
        final title = track.title ?? track.language ?? 'Audio Track ${i + 1}';
        final language = track.language ?? '';
        audioStreams.add(
          PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(
              name: title,
              channels: 0,
              sampleRate: 0,
              bitRate: null,
            ),
            title: title,
            language: language,
            metadata: {
              'id': track.id.toString(),
              'title': title,
              'language': language,
              'index': i.toString(),
            },
            rawRepresentation: 'Audio: $title (ID: ${track.id})',
          ),
        );
      }
    }

    List<PlayerSubtitleStreamInfo>? resolvedSubtitleStreams;
    if (embeddedSubtitleTracks.isNotEmpty) {
      resolvedSubtitleStreams = [];
      for (int i = 0; i < embeddedSubtitleTracks.length; i++) {
        final track =
            embeddedSubtitleTracks[i]; // This is media_kit's SubtitleTrack
        final trackIdStr = (track as dynamic).id as String;

        // Normalize here BEFORE creating PlayerSubtitleStreamInfo
        final normInfo = _normalizeSubtitleTrackInfoHelper(
          track.title,
          track.language,
          i,
        );

        resolvedSubtitleStreams.add(
          PlayerSubtitleStreamInfo(
            title: normInfo.title, // Use normalized title
            language: normInfo.language, // Use normalized language
            metadata: {
              'id': trackIdStr,
              'title': normInfo.title, // Store normalized title in metadata too
              'language': normInfo.language, // Store normalized language
              'original_mk_title':
                  track.title ?? '', // Keep original for reference
              'original_mk_language':
                  track.language ?? '', // Keep original for reference
              'index': i.toString(),
            },
            rawRepresentation:
                'Subtitle: ${normInfo.title} (ID: $trackIdStr) Language: ${normInfo.language}',
          ),
        );
      }
    } else if (_mediaInfo.subtitle != null && _mediaInfo.subtitle!.isNotEmpty) {
      // Preserve the existing list if incoming tracks are temporarily empty.
      resolvedSubtitleStreams = _mediaInfo.subtitle;
    } else {
      resolvedSubtitleStreams = null;
    }

    final currentDuration = _mediaInfo.duration > 0
        ? _mediaInfo.duration
        : _player.state.duration.inMilliseconds;

    _mediaInfo = PlayerMediaInfo(
      duration: currentDuration,
      video: videoStreams,
      audio: audioStreams,
      subtitle: resolvedSubtitleStreams, // Use the resolved list
    );

    _ensureDefaultTracksSelected();

    // If _mediaInfo was just updated (potentially preserving subtitle list),
    // it's crucial to re-sync the active subtitle track based on the *current* player state.
    // _handleActiveSubtitleTrackDataChange is better for reacting to live changes,
    // but after _mediaInfo is rebuilt, a direct sync is good.
    final currentActualPlayerSubtitleId = _player.state.track.subtitle.id;
    //debugPrint('MediaKitAdapter: _updateMediaInfo - Triggering sync with current actual player subtitle ID: $currentActualPlayerSubtitleId');
    _performSubtitleSyncLogic(currentActualPlayerSubtitleId);
  }

  /// 当视频尺寸可用时更新媒体信息
  void _updateMediaInfoWithVideoDimensions(int width, int height) {
    //debugPrint('[MediaKit] _updateMediaInfoWithVideoDimensions: width=$width, height=$height');

    // 更新现有的视频流信息
    if (_mediaInfo.video != null && _mediaInfo.video!.isNotEmpty) {
      final updatedVideoStreams = _mediaInfo.video!.map((stream) {
        // 如果当前宽高为0，则使用新的宽高
        if (stream.codec.width == 0 || stream.codec.height == 0) {
          //debugPrint('[MediaKit] 更新视频流尺寸: ${stream.codec.width}x${stream.codec.height} -> ${width}x$height');
          return PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(
              width: width,
              height: height,
              name: stream.codec.name,
            ),
            codecName: stream.codecName,
          );
        }
        return stream;
      }).toList();

      _mediaInfo = _mediaInfo.copyWith(video: updatedVideoStreams);
      //debugPrint('[MediaKit] 媒体信息已更新，视频流尺寸: ${updatedVideoStreams.first.codec.width}x${updatedVideoStreams.first.codec.height}');
    }
  }

  /// 处理Jellyfin流媒体的轨道信息
  void _handleJellyfinStreamingTracks(
    Tracks tracks,
    List<VideoTrack> realVideoTracks,
    List<AudioTrack> realAudioTracks,
    List<SubtitleTrack> realSubtitleTracks,
  ) {
    //debugPrint('MediaKitAdapter: 处理Jellyfin流媒体轨道信息');

    // 对于Jellyfin流媒体，即使轨道信息不完整，也要尝试创建基本的媒体信息
    List<PlayerVideoStreamInfo>? videoStreams;
    List<PlayerAudioStreamInfo>? audioStreams;
    List<PlayerSubtitleStreamInfo>? subtitleStreams;

    // 如果真实轨道为空，尝试从原始轨道中提取信息
    if (realVideoTracks.isEmpty && tracks.video.isNotEmpty) {
      //debugPrint('MediaKitAdapter: Jellyfin流媒体视频轨道信息不完整，尝试从原始轨道提取');
      videoStreams = [
        PlayerVideoStreamInfo(
          codec: PlayerVideoCodecParams(
            width: 1920, // 默认值
            height: 1080, // 默认值
            name: 'Jellyfin Video Stream',
          ),
          codecName: 'unknown',
        ),
      ];
    } else if (realVideoTracks.isNotEmpty) {
      videoStreams = realVideoTracks
          .map(
            (track) => PlayerVideoStreamInfo(
              codec: PlayerVideoCodecParams(
                width: 0,
                height: 0,
                name: track.title ?? track.language ?? 'Jellyfin Video',
              ),
              codecName: track.codec ?? 'Unknown',
            ),
          )
          .toList();
    }

    if (realAudioTracks.isEmpty && tracks.audio.isNotEmpty) {
      //debugPrint('MediaKitAdapter: Jellyfin流媒体音频轨道信息不完整，尝试从原始轨道提取');
      audioStreams = [
        PlayerAudioStreamInfo(
          codec: PlayerAudioCodecParams(
            name: 'Jellyfin Audio Stream',
            channels: 2, // 默认立体声
            sampleRate: 48000, // 默认采样率
            bitRate: null,
          ),
          title: 'Jellyfin Audio',
          language: 'unknown',
          metadata: {
            'id': 'auto',
            'title': 'Jellyfin Audio',
            'language': 'unknown',
            'index': '0',
          },
          rawRepresentation: 'Audio: Jellyfin Audio Stream',
        ),
      ];
    } else if (realAudioTracks.isNotEmpty) {
      audioStreams = [];
      for (int i = 0; i < realAudioTracks.length; i++) {
        final track = realAudioTracks[i];
        final title = track.title ?? track.language ?? 'Audio Track ${i + 1}';
        final language = track.language ?? '';
        audioStreams.add(
          PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(
              name: title,
              channels: 0,
              sampleRate: 0,
              bitRate: null,
            ),
            title: title,
            language: language,
            metadata: {
              'id': track.id.toString(),
              'title': title,
              'language': language,
              'index': i.toString(),
            },
            rawRepresentation: 'Audio: $title (ID: ${track.id})',
          ),
        );
      }
    }

    // 对于Jellyfin流媒体，通常没有内嵌字幕，所以subtitleStreams保持为null

    final currentDuration = _mediaInfo.duration > 0
        ? _mediaInfo.duration
        : _player.state.duration.inMilliseconds;

    _mediaInfo = PlayerMediaInfo(
      duration: currentDuration,
      video: videoStreams,
      audio: audioStreams,
      subtitle: subtitleStreams,
    );

    //debugPrint('MediaKitAdapter: Jellyfin流媒体媒体信息更新完成 - 视频轨道: ${videoStreams?.length ?? 0}, 音频轨道: ${audioStreams?.length ?? 0}');

    _ensureDefaultTracksSelected();
  }

  // Made async to handle potential future from getProperty
  Future<void> _handleActiveSubtitleTrackDataChange(
    SubtitleTrack subtitleData,
  ) async {
    String? idToProcess = subtitleData.id;
    final originalEventId =
        subtitleData.id; // Keep original event id for logging
    //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Received event with subtitle ID: "$originalEventId"');

    if (idToProcess == 'auto') {
      try {
        final dynamic platform = _player.platform;
        // Check if platform and getProperty method exist to avoid runtime errors
        if (platform != null && platform.getProperty != null) {
          // Correctly call getProperty with the string literal 'sid'
          var rawSidProperty = platform.getProperty('sid');

          dynamic resolvedSidValue;
          if (rawSidProperty is Future) {
            //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - platform.getProperty(\'sid\') returned a Future. Awaiting...');
            resolvedSidValue = await rawSidProperty;
          } else {
            //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - platform.getProperty(\'sid\') returned a direct value.');
            resolvedSidValue = rawSidProperty;
          }

          String? actualMpvSidString;
          if (resolvedSidValue != null) {
            actualMpvSidString = resolvedSidValue
                .toString(); // Convert to string, as SID can be int or string 'no'/'auto'
          }

          //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Event ID is "auto". Queried platform for actual "sid", got: "$actualMpvSidString" (raw value from getProperty: $resolvedSidValue)');

          if (actualMpvSidString != null &&
              actualMpvSidString.isNotEmpty &&
              actualMpvSidString != 'auto' &&
              actualMpvSidString != 'no') {
            // We got a valid, specific track ID from mpv
            idToProcess = actualMpvSidString;
            //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Using mpv-queried SID: "$idToProcess" instead of event ID "auto"');
          } else {
            // Query didn't yield a specific track, or it was still 'auto'/'no'/null. Stick with the event's ID.
            //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Queried SID is "$actualMpvSidString". Sticking with event ID "$originalEventId".');
          }
        } else {
          //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Player platform or getProperty method is null. Cannot query actual "sid". Processing event ID "$originalEventId" as is.');
        }
      } catch (e, s) {
        //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Error querying "sid" from platform: $e\nStack trace:\n$s. Processing event ID "$originalEventId" as is.');
      }
    }

    if (_lastKnownActiveSubtitleId != idToProcess) {
      _lastKnownActiveSubtitleId =
          idToProcess; // Update last known with the ID we decided to process
      _performSubtitleSyncLogic(idToProcess);
    } else {
      //debugPrint('MediaKitAdapter: _handleActiveSubtitleTrackDataChange - Process ID ("$idToProcess") is the same as last known ("$_lastKnownActiveSubtitleId"). No sync triggered.');
    }
  }

  void _performSubtitleSyncLogic(String? activeMpvSid) {
    //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic CALLED. Using MPV SID: "${activeMpvSid ?? "null"}"');
    try {
      // It's crucial to call _ensureDefaultTracksSelected *before* we potentially clear _activeSubtitleTracks
      // if activeMpvSid is null/no/auto, especially if _activeSubtitleTracks is currently empty.
      // This gives our logic a chance to pick a default if MPV hasn't picked one yet.
      // However, _ensureDefaultTracksSelected itself might call _player.setSubtitleTrack, which would trigger
      // _handleActiveSubtitleTrackDataChange and then _performSubtitleSyncLogic again. To avoid re-entrancy or loops,
      // _ensureDefaultTracksSelected should ideally only set a track if no track is effectively selected by MPV.
      // The check `if (_player.state.track.subtitle.id == 'auto' || _player.state.track.subtitle.id == 'no')`
      // inside _ensureDefaultTracksSelected helps with this.

      final List<PlayerSubtitleStreamInfo>? realSubtitleTracksInMediaInfo =
          _mediaInfo.subtitle;
      //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Current _mediaInfo.subtitle track count: ${realSubtitleTracksInMediaInfo?.length ?? 0}');

      List<int> newActiveTrackIndices = [];

      if (activeMpvSid != null &&
          activeMpvSid != 'no' &&
          activeMpvSid != 'auto' &&
          activeMpvSid.isNotEmpty) {
        if (realSubtitleTracksInMediaInfo != null &&
            realSubtitleTracksInMediaInfo.isNotEmpty) {
          int foundRealIndex = -1;
          for (int i = 0; i < realSubtitleTracksInMediaInfo.length; i++) {
            final mediaInfoTrackMpvId =
                realSubtitleTracksInMediaInfo[i].metadata['id'];
            //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Comparing MPV SID "$activeMpvSid" with mediaInfo track MPV ID "$mediaInfoTrackMpvId" at _mediaInfo.subtitle index $i');
            if (mediaInfoTrackMpvId == activeMpvSid) {
              foundRealIndex = i;
              //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Match found! Index in _mediaInfo.subtitle: $foundRealIndex');
              break;
            }
          }
          if (foundRealIndex != -1) {
            newActiveTrackIndices = [foundRealIndex];
          } else {
            //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - No match found for MPV SID "$activeMpvSid" in _mediaInfo.subtitle.');
          }
        } else {
          //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - No real subtitle tracks in _mediaInfo to match MPV SID "$activeMpvSid".');
        }
      } else {
        //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - MPV SID is "${activeMpvSid ?? "null"}" (null, no, auto, or empty). Clearing active tracks.');
      }

      bool hasChanged = false;
      if (newActiveTrackIndices.length != _activeSubtitleTracks.length) {
        hasChanged = true;
      } else {
        for (int i = 0; i < newActiveTrackIndices.length; i++) {
          if (newActiveTrackIndices[i] != _activeSubtitleTracks[i]) {
            hasChanged = true;
            break;
          }
        }
      }

      //debugPrint('MediaKitAdapter: _performSubtitleSyncLogic - Calculated newActiveTrackIndices: $newActiveTrackIndices, Current _activeSubtitleTracks: $_activeSubtitleTracks, HasChanged: $hasChanged');

      if (hasChanged) {
        _activeSubtitleTracks = List<int>.from(newActiveTrackIndices);
        //debugPrint('MediaKitAdapter: _activeSubtitleTracks UPDATED (by _performSubtitleSyncLogic). New state: $_activeSubtitleTracks, Based on MPV SID: $activeMpvSid');
      } else {
        //debugPrint('MediaKitAdapter: _activeSubtitleTracks UNCHANGED (by _performSubtitleSyncLogic). Current state: $_activeSubtitleTracks, Based on MPV SID: $activeMpvSid');
      }
    } catch (e, s) {
      //debugPrint('MediaKitAdapter: Error in _performSubtitleSyncLogic: $e\nStack trace:\n$s');
      if (_activeSubtitleTracks.isNotEmpty) {
        _activeSubtitleTracks = [];
        //debugPrint('MediaKitAdapter: _activeSubtitleTracks cleared due to error in _performSubtitleSyncLogic.');
      }
    }
  }

  // Helper inside MediaKitPlayerAdapter to check for Chinese subtitle
  bool _isChineseSubtitle(PlayerSubtitleStreamInfo subInfo) {
    final title = (subInfo.title ?? '').toLowerCase();
    final lang = (subInfo.language ?? '').toLowerCase();
    // Also check metadata which might have more accurate original values from media_kit tracks
    final metadataTitle = (subInfo.metadata['title'] ?? '').toLowerCase();
    final metadataLang = (subInfo.metadata['language'] ?? '').toLowerCase();

    final patterns = [
      'chi', 'chs', 'zh', '中文', '简体', '繁体', 'simplified', 'traditional',
      'zho', 'zh-hans', 'zh-cn', 'zh-sg', 'sc', 'zh-hant', 'zh-tw', 'zh-hk',
      'tc',
      'scjp', 'tcjp', // 支持字幕组常用的简体中文日语(scjp)和繁体中文日语(tcjp)格式
    ];

    for (var p in patterns) {
      if (title.contains(p) ||
          lang.contains(p) ||
          metadataTitle.contains(p) ||
          metadataLang.contains(p)) {
        return true;
      }
    }
    return false;
  }

  void _ensureDefaultTracksSelected() {
    // Audio track selection (existing logic)
    try {
      if (_mediaInfo.audio != null &&
          _mediaInfo.audio!.isNotEmpty &&
          _activeAudioTracks.isEmpty) {
        _activeAudioTracks = [0];

        final realAudioTracksInMediaInfo = _mediaInfo.audio!;
        if (realAudioTracksInMediaInfo.isNotEmpty) {
          final firstRealAudioTrackMpvId =
              realAudioTracksInMediaInfo[0].metadata['id'];
          AudioTrack? actualAudioTrackToSet;
          for (final atd in _player.state.tracks.audio) {
            if (atd.id == firstRealAudioTrackMpvId) {
              actualAudioTrackToSet = atd;
              break;
            }
          }
          if (actualAudioTrackToSet != null) {
            //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择第一个有效音频轨道: _mediaInfo index=0, ID=${actualAudioTrackToSet.id}');
            _player.setAudioTrack(actualAudioTrackToSet);
          } else {
            //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择音频轨道失败: 未在player.state.tracks.audio中找到ID为 $firstRealAudioTrackMpvId 的轨道');
          }
        }
      }
    } catch (e) {
      //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - 自动选择第一个有效音频轨道失败: $e');
    }

    // Subtitle track selection logic
    // Only attempt to set a default if MPV hasn't already picked a specific track.
    if (_player.state.track.subtitle.id == 'auto' ||
        _player.state.track.subtitle.id == 'no') {
      if (_mediaInfo.subtitle != null &&
          _mediaInfo.subtitle!.isNotEmpty &&
          _activeSubtitleTracks.isEmpty) {
        //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Attempting to select a default subtitle track as current selection is "${_player.state.track.subtitle.id}" and _activeSubtitleTracks is empty.');
        int preferredSubtitleIndex = -1;
        int firstSimplifiedChineseIndex = -1;
        int firstTraditionalChineseIndex = -1;
        int firstGenericChineseIndex = -1;

        for (int i = 0; i < _mediaInfo.subtitle!.length; i++) {
          final subInfo = _mediaInfo.subtitle![i];
          // Use original title and language from metadata for more reliable matching against keywords
          final titleLower =
              (subInfo.metadata['title'] ?? subInfo.title ?? '').toLowerCase();
          final langLower =
              (subInfo.metadata['language'] ?? subInfo.language ?? '')
                  .toLowerCase();

          bool isSimplified = titleLower.contains('simplified') ||
              titleLower.contains('简体') ||
              langLower.contains('zh-hans') ||
              langLower.contains('zh-cn') ||
              langLower.contains('sc') ||
              titleLower.contains('scjp') ||
              langLower.contains('scjp');

          bool isTraditional = titleLower.contains('traditional') ||
              titleLower.contains('繁体') ||
              langLower.contains('zh-hant') ||
              langLower.contains('zh-tw') ||
              langLower.contains('tc') ||
              titleLower.contains('tcjp') ||
              langLower.contains('tcjp');

          if (isSimplified && firstSimplifiedChineseIndex == -1) {
            firstSimplifiedChineseIndex = i;
          }
          if (isTraditional && firstTraditionalChineseIndex == -1) {
            firstTraditionalChineseIndex = i;
          }
          // Use the _isChineseSubtitle helper which checks more broadly
          if (_isChineseSubtitle(subInfo) && firstGenericChineseIndex == -1) {
            firstGenericChineseIndex = i;
          }
        }

        if (firstSimplifiedChineseIndex != -1) {
          preferredSubtitleIndex = firstSimplifiedChineseIndex;
          //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Simplified Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
        } else if (firstTraditionalChineseIndex != -1) {
          preferredSubtitleIndex = firstTraditionalChineseIndex;
          //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Traditional Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
        } else if (firstGenericChineseIndex != -1) {
          preferredSubtitleIndex = firstGenericChineseIndex;
          //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Found Preferred: Generic Chinese subtitle at _mediaInfo index: $preferredSubtitleIndex');
        }

        if (preferredSubtitleIndex != -1) {
          final selectedMediaInfoTrack =
              _mediaInfo.subtitle![preferredSubtitleIndex];
          final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];
          SubtitleTrack? actualSubtitleTrackToSet;
          // Iterate through the player's current actual subtitle tracks to find the matching SubtitleTrack object
          for (final stData in _player.state.tracks.subtitle) {
            if (stData.id == mpvTrackIdToSelect) {
              actualSubtitleTrackToSet = stData;
              break;
            }
          }

          if (actualSubtitleTrackToSet != null) {
            //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Automatically selecting subtitle: _mediaInfo index=$preferredSubtitleIndex, MPV ID=${actualSubtitleTrackToSet.id}, Title=${actualSubtitleTrackToSet.title}');
            _player.setSubtitleTrack(actualSubtitleTrackToSet);
            // Note: _activeSubtitleTracks will be updated by the event stream (_handleActiveSubtitleTrackDataChange -> _performSubtitleSyncLogic)
          } else {
            //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Could not find SubtitleTrackData in player.state.tracks.subtitle for MPV ID "$mpvTrackIdToSelect" (from _mediaInfo index $preferredSubtitleIndex). Cannot auto-select default subtitle.');
          }
        } else {
          //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - No preferred Chinese subtitle track found in _mediaInfo.subtitle. No default selected by this logic.');
        }
      } else {
        //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Conditions not met for default subtitle selection. _mediaInfo.subtitle empty/null: ${_mediaInfo.subtitle == null || _mediaInfo.subtitle!.isEmpty}, _activeSubtitleTracks not empty: ${_activeSubtitleTracks.isNotEmpty}');
      }
    } else {
      //debugPrint('MediaKitAdapter: _ensureDefaultTracksSelected - Player already has a specific subtitle track selected (ID: ${_player.state.track.subtitle.id}). Skipping default selection logic.');
    }
  }

  @override
  double get volume => _player.state.volume / 100.0;

  @override
  set volume(double value) {
    _player.setVolume(value.clamp(0.0, 1.0) * 100);
  }

  // 添加播放速度属性实现
  @override
  double get playbackRate => _playbackRate;

  @override
  set playbackRate(double value) {
    // 速率调整前重置插值基准，避免时间轴瞬移
    final currentPosition = _interpolatedPosition;
    _lastActualPosition = currentPosition;
    _interpolatedPosition = currentPosition;
    _lastPositionTimestamp = DateTime.now().millisecondsSinceEpoch;

    _playbackRate = value;
    try {
      _player.setRate(value);
      debugPrint('MediaKit: 设置播放速度: ${value}x');
    } catch (e) {
      debugPrint('MediaKit: 设置播放速度失败: $e');
    }
  }

  @override
  PlayerPlaybackState get state => _state;

  @override
  set state(PlayerPlaybackState value) {
    switch (value) {
      case PlayerPlaybackState.stopped:
        _ticker?.stop();
        _player.stop();
        break;
      case PlayerPlaybackState.paused:
        _ticker?.stop();
        _player.pause();
        break;
      case PlayerPlaybackState.playing:
        if (_ticker != null && !_ticker!.isActive) {
          _ticker!.start();
        }
        _player.play();
        break;
    }
    _state = value;
  }

  @override
  ValueListenable<int?> get textureId => _textureIdNotifier;

  @override
  String get media => _currentMedia;

  @override
  set media(String value) {
    setMedia(value, PlayerMediaType.video);
  }

  @override
  PlayerMediaInfo get mediaInfo => _mediaInfo;

  @override
  List<int> get activeSubtitleTracks => _activeSubtitleTracks;

  @override
  set activeSubtitleTracks(List<int> value) {
    try {
      //debugPrint('MediaKitAdapter: UI wants to set activeSubtitleTracks (indices in _mediaInfo.subtitle) to: $value');
      final List<PlayerSubtitleStreamInfo>? mediaInfoSubtitles =
          _mediaInfo.subtitle;

      // Log the current state of _player.state.tracks.subtitle for diagnostics
      if (_player.state.tracks.subtitle.isNotEmpty) {
        //debugPrint('MediaKitAdapter: activeSubtitleTracks setter - _player.state.tracks.subtitle (raw from player):');
        for (var track in _player.state.tracks.subtitle) {
          debugPrint('  - ID: ${track.id}, Title: ${track.title ?? 'N/A'}');
        }
      } else {
        //debugPrint('MediaKitAdapter: activeSubtitleTracks setter - _player.state.tracks.subtitle is EMPTY.');
      }

      if (value.isEmpty) {
        _player.setSubtitleTrack(SubtitleTrack.no());
        //debugPrint('MediaKitAdapter: UI set no subtitle track. Telling mpv to use "no".');
        // _activeSubtitleTracks should be updated by _performSubtitleSyncLogic via _handleActiveSubtitleTrackDataChange
        return;
      }

      final uiSelectedMediaInfoIndex = value.first;

      // CRITICAL CHECK: If _mediaInfo has been reset (subtitles are null/empty),
      // do not proceed with trying to set a track based on an outdated index.
      if (mediaInfoSubtitles == null || mediaInfoSubtitles.isEmpty) {
        //debugPrint('MediaKitAdapter: CRITICAL - UI requested track index $uiSelectedMediaInfoIndex, but _mediaInfo.subtitle is currently NULL or EMPTY. This likely means player state was reset externally (e.g., by SubtitleManager clearing tracks). IGNORING this subtitle change request to prevent player stop/crash. The UI should resync with the new player state via listeners.');
        // DO NOT call _player.setSubtitleTrack() here.
        return; // Exit early
      }

      // Proceed if _mediaInfo.subtitle is valid
      if (uiSelectedMediaInfoIndex >= 0 &&
          uiSelectedMediaInfoIndex < mediaInfoSubtitles.length) {
        final selectedMediaInfoTrack =
            mediaInfoSubtitles[uiSelectedMediaInfoIndex];
        final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];

        SubtitleTrack? actualSubtitleTrackToSet;
        for (final stData in _player.state.tracks.subtitle) {
          if (stData.id == mpvTrackIdToSelect) {
            actualSubtitleTrackToSet = stData;
            break;
          }
        }

        if (actualSubtitleTrackToSet != null) {
          //debugPrint('MediaKitAdapter: UI selected _mediaInfo index $uiSelectedMediaInfoIndex (MPV ID: $mpvTrackIdToSelect). Setting player subtitle track with SubtitleTrack(id: ${actualSubtitleTrackToSet.id}, title: ${actualSubtitleTrackToSet.title ?? 'N/A'}).');
          _player.setSubtitleTrack(actualSubtitleTrackToSet);
        } else {
          //debugPrint('MediaKitAdapter: Could not find SubtitleTrackData in player.state.tracks.subtitle for MPV ID "$mpvTrackIdToSelect" (from UI index $uiSelectedMediaInfoIndex). Setting to "no" as a fallback for this specific failure.');
          _player.setSubtitleTrack(SubtitleTrack.no());
        }
      } else {
        // This case means mediaInfoSubtitles is NOT empty, but the index is out of bounds.
        //debugPrint('MediaKitAdapter: Invalid UI track index $uiSelectedMediaInfoIndex for a NON-EMPTY _mediaInfo.subtitle list (length: ${mediaInfoSubtitles.length}). Setting to "no" because the requested index is out of bounds.');
        _player.setSubtitleTrack(SubtitleTrack.no());
      }
    } catch (e, s) {
      //debugPrint('MediaKitAdapter: Error in "set activeSubtitleTracks": $e\\nStack trace:\\n$s. Setting to "no" as a safety measure.');
      // Avoid crashing, but set to 'no' if an unexpected error occurs.
      if (!_isDisposed) {
        // Check if player is disposed before trying to set track
        try {
          _player.setSubtitleTrack(SubtitleTrack.no());
        } catch (playerError) {
          //debugPrint('MediaKitAdapter: Further error trying to set SubtitleTrack.no() in catch block: $playerError');
        }
      }
    }
  }

  @override
  List<int> get activeAudioTracks => _activeAudioTracks;

  @override
  set activeAudioTracks(List<int> value) {
    try {
      _activeAudioTracks = value;
      final List<PlayerAudioStreamInfo>? mediaInfoAudios = _mediaInfo.audio;

      if (value.isEmpty) {
        if (mediaInfoAudios != null && mediaInfoAudios.isNotEmpty) {
          final firstRealAudioTrackMpvId = mediaInfoAudios[0].metadata['id'];
          AudioTrack? actualTrackData;
          for (final atd in _player.state.tracks.audio) {
            if (atd.id == firstRealAudioTrackMpvId) {
              actualTrackData = atd;
              break;
            }
          }
          if (actualTrackData != null) {
            debugPrint('默认设置第一个音频轨道 (ID: ${actualTrackData.id})');
            _player.setAudioTrack(actualTrackData);
            _activeAudioTracks = [0];
          }
        }
        return;
      }

      final uiSelectedMediaInfoIndex = value.first;
      if (mediaInfoAudios != null &&
          uiSelectedMediaInfoIndex >= 0 &&
          uiSelectedMediaInfoIndex < mediaInfoAudios.length) {
        final selectedMediaInfoTrack =
            mediaInfoAudios[uiSelectedMediaInfoIndex];
        final mpvTrackIdToSelect = selectedMediaInfoTrack.metadata['id'];

        AudioTrack? actualTrackData;
        for (final atd in _player.state.tracks.audio) {
          if (atd.id == mpvTrackIdToSelect) {
            actualTrackData = atd;
            break;
          }
        }
        if (actualTrackData != null) {
          debugPrint(
            '设置音频轨道: _mediaInfo索引=$uiSelectedMediaInfoIndex, ID=${actualTrackData.id}',
          );
          _player.setAudioTrack(actualTrackData);
        } else {
          _player.setAudioTrack(AudioTrack.auto());
        }
      } else {
        _player.setAudioTrack(AudioTrack.auto());
      }
    } catch (e) {
      debugPrint('设置音频轨道失败: $e');
      _player.setAudioTrack(AudioTrack.auto());
    }
  }

  @override
  int get position => _interpolatedPosition.inMilliseconds;

  @override
  int get bufferedPosition {
    final bufferMs = _player.state.buffer.inMilliseconds;
    if (bufferMs <= 0) {
      return 0;
    }
    final durationMs = _player.state.duration.inMilliseconds;
    if (durationMs <= 0) {
      return bufferMs;
    }
    return bufferMs.clamp(0, durationMs).toInt();
  }

  @override
  void setBufferRange({int minMs = -1, int maxMs = -1, bool drop = false}) {
    // MediaKit 使用 bufferSize（字节）配置，不支持 MDK 的时间缓冲接口。
  }

  @override
  bool get supportsExternalSubtitles => true;

  /// 检查是否是Jellyfin流媒体且正在初始化
  bool get _isJellyfinInitializing {
    if (!_currentMedia.contains('jellyfin://') &&
        !_currentMedia.contains('emby://')) {
      return false;
    }

    final hasNoDuration = _mediaInfo.duration <= 0;
    final hasNoPosition = _player.state.position.inMilliseconds <= 0;
    final hasNoError = _mediaInfo.specificErrorMessage == null ||
        _mediaInfo.specificErrorMessage!.isEmpty;

    return hasNoDuration && hasNoPosition && hasNoError;
  }

  @override
  Future<int?> updateTexture() async {
    if (_prefersPlatformVideoSurface) {
      return null;
    }
    if (_textureIdNotifier.value == null) {
      _updateTextureIdFromController();
    }
    return _textureIdNotifier.value;
  }

  @override
  void setMedia(String path, PlayerMediaType type) {
    //debugPrint('[MediaKit] setMedia: path=$path, type=$type');
    if (type == PlayerMediaType.subtitle) {
      //debugPrint('MediaKitAdapter: setMedia called for SUBTITLE. Path: "$path"');
      if (path.isEmpty) {
        //debugPrint('MediaKitAdapter: setMedia (for subtitle) - Path is empty. Calling player.setSubtitleTrack(SubtitleTrack.no()). Main media and info remain UNCHANGED.');
        if (!_isDisposed) _player.setSubtitleTrack(SubtitleTrack.no());
      } else {
        final subtitleUri = normalizeExternalSubtitleTrackUri(path);
        // Assuming path is a valid file URI or path that media_kit can handle for subtitles
        //debugPrint('MediaKitAdapter: setMedia (for subtitle) - Path is "$path". Calling player.setSubtitleTrack(SubtitleTrack.uri(path)). Main media and info remain UNCHANGED.');
        if (!_isDisposed) {
          _player.setSubtitleTrack(SubtitleTrack.uri(subtitleUri));
        }
      }
      // Player events will handle updating _activeSubtitleTracks via _performSubtitleSyncLogic.
      return;
    }

    // --- Original logic for Main Video/Audio Media ---
    _currentMedia = path;
    _activeSubtitleTracks = [];
    _activeAudioTracks = [];
    _lastKnownActiveSubtitleId = null;
    _mediaInfo = PlayerMediaInfo(duration: 0);
    _isDisposed = false;

    final mediaOptions = <String, dynamic>{};
    _properties.forEach((key, value) {
      mediaOptions[key] = value;
    });

    final preparedMedia = _prepareNetworkMediaIfNeeded(path);

    //debugPrint('MediaKitAdapter: 打开媒体 (MAIN VIDEO/AUDIO): $path');
    if (!_isDisposed) {
      _player.open(
        Media(
          preparedMedia.url,
          extras: mediaOptions,
          httpHeaders: preparedMedia.httpHeaders,
        ),
        play: false,
      );
    }

    if (_mpvDiagnosticsEnabled &&
        Platform.isMacOS &&
        _envFlagEnabled(_hdrValidationFlag)) {
      unawaited(_dumpMacOSHdrDiagnostics('media-opened'));
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => unawaited(_dumpMacOSHdrDiagnostics('media-opened+1500ms')),
      );
      Future.delayed(
        const Duration(milliseconds: 4000),
        () => unawaited(_dumpMacOSHdrDiagnostics('media-opened+4000ms')),
      );
    }

    // 设置mpv底层video-aspect属性，确保保持原始宽高比
    Future.delayed(const Duration(milliseconds: 500), () {
      try {
        final dynamic platform = _player.platform;
        if (platform != null && platform.setProperty != null) {
          // 设置video-aspect为-1，让mpv自动保持原始宽高比
          platform.setProperty('video-aspect', '-1');
          //debugPrint('[MediaKit] 设置mpv底层video-aspect为-1（保持原始比例）');

          // 延迟检查设置是否生效
          Future.delayed(const Duration(milliseconds: 500), () async {
            try {
              var videoAspect = platform.getProperty('video-aspect');
              if (videoAspect is Future) {
                videoAspect = await videoAspect;
              }
              //debugPrint('[MediaKit] mpv底层 video-aspect 设置后: $videoAspect');
            } catch (e) {
              //debugPrint('[MediaKit] 获取mpv底层video-aspect失败: $e');
            }
          });
        }
      } catch (e) {
        //debugPrint('[MediaKit] 设置mpv底层video-aspect失败: $e');
      }
    });

    // This delayed block might still be useful for printing initial track info after the player has processed the new media.
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!_isDisposed) {
        _printAllTracksInfo(_player.state.tracks);
        //debugPrint('MediaKitAdapter: setMedia (MAIN VIDEO/AUDIO) - Delayed block executed. Initial track info printed.');
      }
    });
  }

  _PreparedNetworkMedia _prepareNetworkMediaIfNeeded(String originalPath) {
    try {
      final Uri uri = Uri.parse(originalPath);
      if (!_isHttpScheme(uri.scheme)) {
        return _PreparedNetworkMedia(url: originalPath);
      }

      final authHeader = _buildBasicAuthHeader(uri);
      if (authHeader == null) {
        return _PreparedNetworkMedia(url: originalPath);
      }

      final sanitizedUri = _stripUserInfo(uri);
      return _PreparedNetworkMedia(
        url: sanitizedUri.toString(),
        httpHeaders: {'Authorization': authHeader},
      );
    } catch (_) {
      return _PreparedNetworkMedia(url: originalPath);
    }
  }

  bool _isHttpScheme(String? scheme) {
    if (scheme == null) {
      return false;
    }
    final lower = scheme.toLowerCase();
    return lower == 'http' || lower == 'https';
  }

  String? _buildBasicAuthHeader(Uri uri) {
    if (uri.userInfo.isEmpty) {
      return null;
    }

    final separatorIndex = uri.userInfo.indexOf(':');
    String username;
    String password;
    if (separatorIndex >= 0) {
      username = uri.userInfo.substring(0, separatorIndex);
      password = uri.userInfo.substring(separatorIndex + 1);
    } else {
      username = uri.userInfo;
      password = '';
    }

    username = Uri.decodeComponent(username);
    password = Uri.decodeComponent(password);

    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  Uri _stripUserInfo(Uri uri) {
    return Uri(
      scheme: uri.scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      path: uri.path,
      query: uri.hasQuery ? uri.query : null,
      fragment: uri.fragment.isEmpty ? null : uri.fragment,
    );
  }

  @override
  Future<void> prepare() async {
    if (!_prefersPlatformVideoSurface) {
      await updateTexture();
    }
    if (!_isDisposed) {
      _printAllTracksInfo(_player.state.tracks);
    }
  }

  @override
  void seek({required int position}) {
    final seekPosition = Duration(milliseconds: position);
    _player.seek(seekPosition);
    _interpolatedPosition = seekPosition;
    _lastActualPosition = seekPosition;
    _lastPositionTimestamp = DateTime.now().millisecondsSinceEpoch;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _ticker?.dispose();
    _trackSubscription?.cancel();
    _jellyfinRetryTimer?.cancel();
    if (_textureIdListenerAttached && _controller != null) {
      _controller!.id.removeListener(_handleTextureIdChange);
    }
    unawaited(detachPlatformVideoSurface());
    _player.dispose();
    _textureIdNotifier.dispose();
  }

  GlobalKey get repaintBoundaryKey => _repaintBoundaryKey;

  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    try {
      final videoWidth = _player.state.width ?? 1920;
      final videoHeight = _player.state.height ?? 1080;
      //debugPrint('[MediaKit] snapshot: _player.state.width=$videoWidth, _player.state.height=$videoHeight');
      final actualWidth = width > 0 ? width : videoWidth;
      final actualHeight = height > 0 ? height : videoHeight;

      Uint8List? bytes = await _player.screenshot(
        format: 'image/png',
        includeLibassSubtitles: true,
      );

      if (bytes == null) {
        debugPrint('MediaKit: PNG截图失败，尝试JPEG格式');
        bytes = await _player.screenshot(
          format: 'image/jpeg',
          includeLibassSubtitles: true,
        );
      }

      if (bytes == null) {
        debugPrint('MediaKit: 所有格式截图失败，尝试原始BGRA格式');
        bytes = await _player.screenshot(
          format: null,
          includeLibassSubtitles: true,
        );
      }

      if (bytes != null) {
        // debugPrint('MediaKit: 成功获取截图，大小: ${bytes.length} 字节，尺寸: ${actualWidth}x$actualHeight');
        final String base64Image = base64Encode(bytes);
        return PlayerFrame(
          bytes: bytes,
          width: actualWidth,
          height: actualHeight,
        );
      } else {
        debugPrint('MediaKit: 所有截图方法都失败');
      }
    } catch (e) {
      debugPrint('MediaKit: 截图过程出错: $e');
    }
    return null;
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> names) {
    _decoders[type] = names;
  }

  @override
  List<String> getDecoders(PlayerMediaType type) {
    return _decoders[type] ?? [];
  }

  @override
  String? getProperty(String name) {
    try {
      final dynamic platform = _player.platform;
      if (platform != null && platform.getProperty != null) {
        final dynamic value = platform.getProperty(name);
        if (value is String) {
          return value;
        }
        if (value != null && value is! Future) {
          return value.toString();
        }
      }
    } catch (_) {
      // 忽略异常，回退到缓存值
    }
    return _properties[name];
  }

  @override
  void setProperty(String name, String value) {
    var resolvedValue = value;
    final diagnosticHwdecOverride = _mpvDiagnosticsEnabled && name == 'hwdec'
        ? _resolveHardwareDecodingOverride()
        : null;
    if (diagnosticHwdecOverride != null && value != diagnosticHwdecOverride) {
      resolvedValue = diagnosticHwdecOverride;
      debugPrint(
        'MediaKit HDR诊断: 忽略外部 hwdec=$value，保持 $diagnosticHwdecOverride',
      );
    } else if (!_enableHardwareAcceleration &&
        name == 'hwdec' &&
        value != 'no') {
      resolvedValue = 'no';
      debugPrint('MediaKit: 硬件加速已禁用，强制设置 hwdec=no');
    }
    _properties[name] = resolvedValue;
    try {
      final dynamic platform = _player.platform;
      platform?.setProperty?.call(name, resolvedValue);
    } catch (e) {
      debugPrint('MediaKit: 设置属性$name 失败: $e');
    }
  }

  Future<String?> _getMpvPropertyForDiagnostics(String name) async {
    try {
      final dynamic platform = _player.platform;
      if (platform == null || platform.getProperty == null) {
        return null;
      }
      dynamic value = platform.getProperty(name);
      if (value is Future) {
        value = await value;
      }
      if (value == null) {
        return null;
      }
      return value.toString();
    } catch (_) {
      return null;
    }
  }

  Future<void> _dumpMacOSHdrDiagnostics(String phase) async {
    if (!_mpvDiagnosticsEnabled ||
        !Platform.isMacOS ||
        !_envFlagEnabled(_hdrValidationFlag) ||
        _isDisposed) {
      return;
    }

    const properties = <String>[
      'vo-configured',
      'current-vo',
      'gpu-api',
      'gpu-context',
      'hwdec',
      'hwdec-current',
      'video-codec',
      'video-format',
      'video-params',
      'video-out-params',
      'target-colorspace-hint',
      'target-colorspace-hint-mode',
      'target-prim',
      'target-trc',
      'target-peak',
      'tone-mapping',
      'hdr-compute-peak',
    ];

    final buffer = StringBuffer('MediaKit HDR诊断[$phase]');
    for (final property in properties) {
      final value = await _getMpvPropertyForDiagnostics(property);
      if (value != null && value.isNotEmpty) {
        buffer.write('\n  $property=$value');
      }
    }
    debugPrint(buffer.toString());
  }

  @override
  Future<void> playDirectly() async {
    await _player.play();
  }

  @override
  Future<void> pauseDirectly() async {
    await _player.pause();
  }

  @override
  Future<void> setVideoSurfaceSize({int? width, int? height}) async {
    try {
      await _controller?.setSize(width: width, height: height);
    } catch (e) {
      debugPrint('MediaKit: 调整视频纹理尺寸失败: $e');
    }
  }

  bool get prefersPlatformVideoSurface => _prefersPlatformVideoSurface;

  Future<void> attachPlatformVideoSurface({
    required int viewHandle,
    int? windowHandle,
  }) async {
    if (!_prefersPlatformVideoSurface || _isDisposed) {
      return;
    }

    final widTarget = _resolveMacOSNativeVideoWidTarget();
    final resolvedHandle = widTarget == 'window'
        ? (windowHandle ?? viewHandle)
        : (viewHandle > 0 ? viewHandle : (windowHandle ?? 0));
    if (resolvedHandle <= 0) {
      throw ArgumentError('No valid macOS native video handle available.');
    }

    final isSameBinding = _attachedPlatformViewHandle == viewHandle &&
        _attachedPlatformWindowHandle == windowHandle;
    if (isSameBinding) {
      return;
    }

    _attachedPlatformViewHandle = viewHandle;
    _attachedPlatformWindowHandle = windowHandle;

    try {
      final dynamic platform = _player.platform;
      if (platform == null) {
        return;
      }

      await platform.setProperty?.call('vo', 'null');
      await platform.setProperty?.call('wid', resolvedHandle.toString());
      await platform.setProperty?.call('force-window', 'yes');
      await platform.setProperty?.call('sub-use-margins', 'no');
      await platform.setProperty?.call('sub-scale-with-window', 'yes');
      await platform.setProperty?.call('vo', _resolveMacOSNativeVideoVO());

      final currentPosition = _player.state.position;
      if (currentPosition > Duration.zero) {
        await _player.seek(currentPosition);
      }
      unawaited(_dumpMacOSHdrDiagnostics('surface-attached'));
      Future.delayed(
        const Duration(milliseconds: 1500),
        () => unawaited(_dumpMacOSHdrDiagnostics('surface-attached+1500ms')),
      );
    } catch (e) {
      debugPrint('MediaKit: 绑定 macOS 原生视频面失败: $e');
      rethrow;
    }
  }

  Future<void> detachPlatformVideoSurface() async {
    if (!_prefersPlatformVideoSurface) {
      return;
    }

    _attachedPlatformViewHandle = null;
    _attachedPlatformWindowHandle = null;

    try {
      final dynamic platform = _player.platform;
      if (platform == null) {
        return;
      }
      await platform.setProperty?.call('vo', 'null');
      await platform.setProperty?.call('wid', '0');
    } catch (e) {
      debugPrint('MediaKit: 解绑 macOS 原生视频面失败: $e');
    }
  }

  void _setupDefaultTrackSelectionBehavior() {
    try {
      final dynamic platform = _player.platform;
      if (platform != null) {
        platform.setProperty?.call("vid", "auto");
        platform.setProperty?.call("aid", "auto");
        platform.setProperty?.call("sid", "auto");

        List<String> preferredSlangs = [
          // Prioritize specific forms of Chinese
          'chi-Hans', 'chi-CN', 'chi-SG', 'zho-Hans', 'zho-CN',
          'zho-SG', // Simplified Chinese variants
          'sc', 'simplified', '简体', // Keywords for Simplified
          'chi-Hant', 'chi-TW', 'chi-HK', 'zho-Hant', 'zho-TW',
          'zho-HK', // Traditional Chinese variants
          'tc', 'traditional', '繁体', // Keywords for Traditional
          // General Chinese
          'chi', 'zho', 'chinese', '中文',
          // Other languages as fallback
          'eng', 'en', 'english',
          'jpn', 'ja', 'japanese',
        ];
        final slangString = preferredSlangs.join(',');
        platform.setProperty?.call("slang", slangString);
        //debugPrint('MediaKitAdapter: Set MPV preferred subtitle languages (slang) to: $slangString');

        _player.stream.tracks.listen((tracks) {
          // _updateMediaInfo (called by this listener) will then call _ensureDefaultTracksSelected.
        });
      }
    } catch (e) {
      //debugPrint('MediaKitAdapter: 设置默认轨道选择策略失败: $e');
    }
  }

  /// 处理流媒体特定错误
  void _handleStreamingError(dynamic error) {
    if (_currentMedia.contains('jellyfin://') ||
        _currentMedia.contains('emby://')) {
      //debugPrint('MediaKitAdapter: 检测到流媒体错误，尝试特殊处理: $error');

      // 检查是否是网络连接问题
      if (error.toString().contains('network') ||
          error.toString().contains('connection') ||
          error.toString().contains('timeout')) {
        //debugPrint('MediaKitAdapter: 流媒体网络连接错误，建议检查网络连接和服务器状态');
        _mediaInfo = _mediaInfo.copyWith(
          specificErrorMessage: '流媒体连接失败，请检查网络连接和服务器状态',
        );
        _attemptJellyfinRetry('网络连接错误');
      }
      // 检查是否是认证问题
      else if (error.toString().contains('auth') ||
          error.toString().contains('unauthorized') ||
          error.toString().contains('401') ||
          error.toString().contains('403')) {
        //debugPrint('MediaKitAdapter: 流媒体认证错误，请检查API密钥和权限');
        _mediaInfo = _mediaInfo.copyWith(
          specificErrorMessage: '流媒体认证失败，请检查API密钥和访问权限',
        );
        // 认证错误不重试，因为重试也不会成功
      }
      // 检查是否是格式不支持
      else if (error.toString().contains('format') ||
          error.toString().contains('codec') ||
          error.toString().contains('unsupported')) {
        //debugPrint('MediaKitAdapter: 流媒体格式不支持，可能需要转码');
        _mediaInfo = _mediaInfo.copyWith(
          specificErrorMessage: '当前播放内核不支持此流媒体格式，请尝试在服务器端启用转码',
        );
        // 格式不支持不重试
      }
      // 其他流媒体错误
      else {
        //debugPrint('MediaKitAdapter: 未知流媒体错误');
        _mediaInfo = _mediaInfo.copyWith(
          specificErrorMessage: '流媒体播放失败，请检查服务器配置和网络连接',
        );
        _attemptJellyfinRetry('未知错误');
      }
    }
  }

  /// 尝试Jellyfin流媒体重试
  void _attemptJellyfinRetry(String errorType) {
    if (_jellyfinRetryCount >= _maxJellyfinRetries) {
      //debugPrint('MediaKitAdapter: Jellyfin流媒体重试次数已达上限 ($_maxJellyfinRetries)，停止重试');
      return;
    }

    if (_lastJellyfinMediaPath != _currentMedia) {
      // 新的媒体路径，重置重试计数
      _jellyfinRetryCount = 0;
      _lastJellyfinMediaPath = _currentMedia;
    }

    _jellyfinRetryCount++;
    final retryDelay = Duration(
      seconds: _jellyfinRetryCount * 2,
    ); // 递增延迟：2秒、4秒、6秒

    //debugPrint('MediaKitAdapter: 准备重试Jellyfin流媒体播放 (第$_jellyfinRetryCount次，延迟${retryDelay.inSeconds}秒)');

    _jellyfinRetryTimer?.cancel();
    _jellyfinRetryTimer = Timer(retryDelay, () {
      if (!_isDisposed && _currentMedia == _lastJellyfinMediaPath) {
        //debugPrint('MediaKitAdapter: 开始重试Jellyfin流媒体播放');
        _retryJellyfinPlayback();
      }
    });
  }

  /// 重试Jellyfin播放
  void _retryJellyfinPlayback() {
    if (_currentMedia.isEmpty) return;

    try {
      //debugPrint('MediaKitAdapter: 重试播放Jellyfin流媒体: $_currentMedia');

      // 停止当前播放
      _player.stop();

      // 等待一小段时间
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_isDisposed) {
          // 重新打开媒体
          final mediaOptions = <String, dynamic>{};
          _properties.forEach((key, value) {
            mediaOptions[key] = value;
          });

          _player.open(Media(_currentMedia, extras: mediaOptions), play: false);
          //debugPrint('MediaKitAdapter: Jellyfin流媒体重试完成');
        }
      });
    } catch (e) {
      //debugPrint('MediaKitAdapter: Jellyfin流媒体重试失败: $e');
    }
  }

  // 添加setPlaybackRate方法实现
  @override
  void setPlaybackRate(double rate) {
    playbackRate = rate; // 这将调用setter
  }

  // 实现 TickerProvider 的 createTicker 方法
  @override
  Ticker createTicker(TickerCallback onTick) {
    return Ticker(onTick);
  }

  void _initializeTicker() {
    _ticker = createTicker(_onTick);
  }

  void _onTick(Duration elapsed) {
    if (_player.state.playing) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_lastPositionTimestamp == 0) {
        _lastPositionTimestamp = now;
      }
      final delta = now - _lastPositionTimestamp;
      _interpolatedPosition = _lastActualPosition +
          Duration(milliseconds: (delta * _player.state.rate).toInt());

      if (_player.state.duration > Duration.zero &&
          _interpolatedPosition > _player.state.duration) {
        _interpolatedPosition = _player.state.duration;
      }
    }
  }

  // 提供详细播放技术信息
  Map<String, dynamic> getDetailedMediaInfo() {
    final Map<String, dynamic> result = {
      'kernel': 'MediaKit',
      'mpvProperties': <String, dynamic>{},
      'videoParams': <String, dynamic>{},
      'audioParams': <String, dynamic>{},
      'tracks': <String, dynamic>{},
    };

    // 尝试获取mpv底层属性
    try {
      final dynamic platform = _player.platform;
      if (platform != null) {
        dynamic _gp(String name) {
          try {
            final v = platform.getProperty?.call(name);
            if (v is Future) {
              // 避免阻塞UI，同步接口不await，直接返回占位
              return null;
            }
            return v;
          } catch (_) {
            return null;
          }
        }

        final mpv = <String, dynamic>{
          // fps
          'container-fps': _gp('container-fps'),
          'estimated-vf-fps': _gp('estimated-vf-fps'),
          // bitrate
          'video-bitrate': _gp('video-bitrate'),
          'audio-bitrate': _gp('audio-bitrate'),
          'demuxer-bitrate': _gp('demuxer-bitrate'),
          'container-bitrate': _gp('container-bitrate'),
          'bitrate': _gp('bitrate'),
          // hwdec
          'hwdec': _gp('hwdec'),
          'hwdec-current': _gp('hwdec-current'),
          'hwdec-active': _gp('hwdec-active'),
          'current-vo': _gp('current-vo'),
          // video params
          'video-params/colormatrix': _gp('video-params/colormatrix'),
          'video-params/colorprimaries': _gp('video-params/colorprimaries'),
          'video-params/transfer': _gp('video-params/transfer'),
          'video-params/w': _gp('video-params/w'),
          'video-params/h': _gp('video-params/h'),
          'video-params/dw': _gp('video-params/dw'),
          'video-params/dh': _gp('video-params/dh'),
          // codecs
          'video-codec': _gp('video-codec'),
          'audio-codec': _gp('audio-codec'),
          'audio-codec-name': _gp('audio-codec-name'),
          // audio params
          'audio-samplerate': _gp('audio-samplerate'),
          'audio-channels': _gp('audio-channels'),
          'audio-params/channel-count': _gp('audio-params/channel-count'),
          'audio-channel-layout': _gp('audio-channel-layout'),
          'audio-params/channel-layout': _gp('audio-params/channel-layout'),
          'audio-params/format': _gp('audio-params/format'),
          // track ids
          'dwidth': _gp('dwidth'),
          'dheight': _gp('dheight'),
          'video-out-params/w': _gp('video-out-params/w'),
          'video-out-params/h': _gp('video-out-params/h'),
          'vid': _gp('vid'),
          'aid': _gp('aid'),
          'sid': _gp('sid'),
        }..removeWhere((k, v) => v == null);

        result['mpvProperties'] = mpv;
      }
    } catch (_) {}

    // 视频参数
    try {
      result['videoParams'] = <String, dynamic>{
        'width': _player.state.width,
        'height': _player.state.height,
      };
    } catch (_) {}

    // 音频参数
    try {
      result['audioParams'] = <String, dynamic>{
        'channels': _player.state.audioParams.channels,
        'sampleRate': _player.state.audioParams.sampleRate,
        'format': _player.state.audioParams.format,
      };
    } catch (_) {}

    // 轨道信息
    try {
      final tracks = _player.state.tracks;
      result['tracks'] = {
        'video': tracks.video
            .map(
              (t) => {
                'id': t.id,
                'title': t.title,
                'language': t.language,
                'codec': t.codec,
              },
            )
            .toList(),
        'audio': tracks.audio
            .map(
              (t) => {
                'id': t.id,
                'title': t.title,
                'language': t.language,
                'codec': t.codec,
              },
            )
            .toList(),
        'subtitle': tracks.subtitle
            .map((t) => {'id': t.id, 'title': t.title, 'language': t.language})
            .toList(),
      };
    } catch (_) {}

    // 估算比特率（若mpv未提供）
    // 省略基于文件大小的码率估算以保持跨平台稳定
    try {
      if (!(result['mpvProperties'] as Map).containsKey('video-bitrate')) {
        // 留空，UI可根据 mpvProperties 中的其他字段或自行估算
      }
    } catch (_) {}

    return result;
  }

  // 异步版本：等待 mpv 属性获取，填充更多字段
  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async {
    final Map<String, dynamic> result = {
      'kernel': 'MediaKit',
      'mpvProperties': <String, dynamic>{},
      'videoParams': <String, dynamic>{},
      'audioParams': <String, dynamic>{},
      'tracks': <String, dynamic>{},
    };

    // 获取 mpv 属性（await）
    try {
      final dynamic platform = _player.platform;
      if (platform != null) {
        Future<dynamic> _gp(String name) async {
          try {
            final v = platform.getProperty?.call(name);
            if (v is Future) return await v; // 等待实际值
            return v;
          } catch (_) {
            return null;
          }
        }

        final mpv = <String, dynamic>{
          'container-fps': await _gp('container-fps'),
          'estimated-vf-fps': await _gp('estimated-vf-fps'),
          'video-bitrate': await _gp('video-bitrate'),
          'audio-bitrate': await _gp('audio-bitrate'),
          'demuxer-bitrate': await _gp('demuxer-bitrate'),
          'container-bitrate': await _gp('container-bitrate'),
          'bitrate': await _gp('bitrate'),
          'hwdec': await _gp('hwdec'),
          'hwdec-current': await _gp('hwdec-current'),
          'hwdec-active': await _gp('hwdec-active'),
          'current-vo': await _gp('current-vo'),
          'video-params/colormatrix': await _gp('video-params/colormatrix'),
          'video-params/colorprimaries': await _gp(
            'video-params/colorprimaries',
          ),
          'video-params/transfer': await _gp('video-params/transfer'),
          'video-params/w': await _gp('video-params/w'),
          'video-params/h': await _gp('video-params/h'),
          'video-params/dw': await _gp('video-params/dw'),
          'video-params/dh': await _gp('video-params/dh'),
          'video-codec': await _gp('video-codec'),
          'audio-codec': await _gp('audio-codec'),
          'audio-codec-name': await _gp('audio-codec-name'),
          'audio-samplerate': await _gp('audio-samplerate'),
          'audio-channels': await _gp('audio-channels'),
          'audio-params/channel-count': await _gp('audio-params/channel-count'),
          'audio-channel-layout': await _gp('audio-channel-layout'),
          'audio-params/channel-layout': await _gp(
            'audio-params/channel-layout',
          ),
          'audio-params/format': await _gp('audio-params/format'),
          'dwidth': await _gp('dwidth'),
          'dheight': await _gp('dheight'),
          'video-out-params/w': await _gp('video-out-params/w'),
          'video-out-params/h': await _gp('video-out-params/h'),
          'vid': await _gp('vid'),
          'aid': await _gp('aid'),
          'sid': await _gp('sid'),
        }..removeWhere((k, v) => v == null);

        result['mpvProperties'] = mpv;
      }
    } catch (_) {}

    // 视频参数
    try {
      result['videoParams'] = <String, dynamic>{
        'width': _player.state.width,
        'height': _player.state.height,
      };
    } catch (_) {}

    // 音频参数
    try {
      result['audioParams'] = <String, dynamic>{
        'channels': _player.state.audioParams.channels,
        'sampleRate': _player.state.audioParams.sampleRate,
        'format': _player.state.audioParams.format,
      };
    } catch (_) {}

    // 轨道信息
    try {
      final tracks = _player.state.tracks;
      result['tracks'] = {
        'video': tracks.video
            .map(
              (t) => {
                'id': t.id,
                'title': t.title,
                'language': t.language,
                'codec': t.codec,
              },
            )
            .toList(),
        'audio': tracks.audio
            .map(
              (t) => {
                'id': t.id,
                'title': t.title,
                'language': t.language,
                'codec': t.codec,
              },
            )
            .toList(),
        'subtitle': tracks.subtitle
            .map((t) => {'id': t.id, 'title': t.title, 'language': t.language})
            .toList(),
      };
    } catch (_) {}

    return result;
  }
}

// Helper map similar to SubtitleManager's languagePatterns
const Map<String, String> _subtitleNormalizationPatterns = {
  r'simplified|简体|chs|zh-hans|zh-cn|zh-sg|sc$|scjp': '简体中文',
  r'traditional|繁体|cht|zh-hant|zh-tw|zh-hk|tc$|tcjp': '繁体中文',
  r'chi|zho|chinese|中文': '中文', // General Chinese as a fallback
  r'eng|en|英文|english': '英文',
  r'jpn|ja|日文|japanese': '日语',
  r'kor|ko|韩文|korean': '韩语',
  // Add other languages as needed
};

String _getNormalizedLanguageHelper(String input) {
  // Renamed to avoid conflict if class has a member with same name
  if (input.isEmpty) return '';
  final lowerInput = input.toLowerCase();
  for (final entry in _subtitleNormalizationPatterns.entries) {
    final pattern = RegExp(entry.key, caseSensitive: false);
    if (pattern.hasMatch(lowerInput)) {
      return entry.value; // Return "简体中文", "繁体中文", "中文", "英文", etc.
    }
  }
  return input; // Return original if no pattern matches
}

// Method to produce normalized title and language for PlayerSubtitleStreamInfo
({String title, String language}) _normalizeSubtitleTrackInfoHelper(
  String? rawTitle,
  String? rawLang,
  int trackIndexForFallback,
) {
  String originalTitle = rawTitle ?? '';
  String originalLangCode = rawLang ?? '';

  String determinedLanguage = '';

  // Priority 1: Determine language from rawLang
  if (originalLangCode.isNotEmpty) {
    determinedLanguage = _getNormalizedLanguageHelper(originalLangCode);
  }

  // Priority 2: If language from rawLang is generic ("中文") or unrecognized,
  // try to get a more specific one (简体中文/繁体中文) from rawTitle.
  if (originalTitle.isNotEmpty) {
    String langFromTitle = _getNormalizedLanguageHelper(originalTitle);
    if (langFromTitle == '简体中文' || langFromTitle == '繁体中文') {
      if (determinedLanguage != '简体中文' && determinedLanguage != '繁体中文') {
        // Title provides a more specific Chinese variant than lang code did (or lang code was not Chinese)
        determinedLanguage = langFromTitle;
      }
    } else if (determinedLanguage.isEmpty ||
        determinedLanguage == originalLangCode) {
      // If lang code didn't yield a recognized language (or was empty),
      // and title yields a recognized one (even if just "中文" or "英文"), use it.
      if (langFromTitle != originalTitle &&
          _subtitleNormalizationPatterns.containsValue(langFromTitle)) {
        determinedLanguage = langFromTitle;
      }
    }
  }

  // If still no recognized language, use originalLangCode or originalTitle if available, otherwise "未知"
  if (determinedLanguage.isEmpty ||
      (determinedLanguage == originalLangCode &&
          !_subtitleNormalizationPatterns.containsValue(determinedLanguage))) {
    // 优先使用原始语言代码，如果没有则使用原始标题，最后才是"未知"
    if (originalLangCode.isNotEmpty) {
      determinedLanguage = originalLangCode;
    } else if (originalTitle.isNotEmpty) {
      determinedLanguage = originalTitle;
    } else {
      determinedLanguage = '未知';
    }
  }

  String finalTitle;
  final String finalLanguage = determinedLanguage;

  if (originalTitle.isNotEmpty) {
    String originalTitleAsLang = _getNormalizedLanguageHelper(originalTitle);

    // Case 1: The original title string itself IS a direct representation of the final determined language.
    // Example: finalLanguage="简体中文", originalTitle="简体" or "Simplified Chinese".
    // In this scenario, the title should just be the clean, finalLanguage.
    if (originalTitleAsLang == finalLanguage) {
      // Check if originalTitle is essentially just the language or has more info.
      // If originalTitle is "简体中文 (Director's Cut)" -> originalTitleAsLang is "简体中文"
      // originalTitle is NOT simple.
      // If originalTitle is "简体" -> originalTitleAsLang is "简体中文"
      // originalTitle IS simple.
      bool titleIsSimpleRepresentation = true;
      // A simple heuristic: if stripping common language keywords from originalTitle leaves little else,
      // or if originalTitle does not contain typical annotation markers like '('.
      // This is tricky; for now, if originalTitleAsLang matches finalLanguage,
      // we assume originalTitle might be a shorter/variant form and prefer finalLanguage as the base title.
      // If originalTitle had extra info, it means originalTitleAsLang would likely NOT be finalLanguage,
      // OR originalTitle would be longer.

      if (originalTitle.length > finalLanguage.length + 3 &&
          originalTitle.contains(finalLanguage)) {
        // e.g. originalTitle = "简体中文 (Forced)", finalLanguage = "简体中文"
        finalTitle = originalTitle;
      } else if (finalLanguage.contains(originalTitle) &&
          finalLanguage.length >= originalTitle.length) {
        // e.g. originalTitle = "简体", finalLanguage = "简体中文" -> title should be "简体中文"
        finalTitle = finalLanguage;
      } else if (originalTitle == originalTitleAsLang) {
        //e.g. originalTitle = "简体中文", finalLanguage = "简体中文"
        finalTitle = finalLanguage;
      } else {
        // originalTitle might be "Simplified" and finalLanguage "简体中文".
        // Or, originalTitle is "Chinese (Commentary)" (originalTitleAsLang="中文") and finalLanguage="中文".
        // If originalTitle is more descriptive than just the language it normalizes to.
        finalTitle = originalTitle;
      }
    } else {
      // Case 2: The original title is NOT a direct representation of the final language.
      // Example: finalLanguage="简体中文", originalTitle="Commentary track".
      // Or finalLanguage="印尼语", originalTitle="Bahasa Indonesia". (Here originalTitleAsLang might be "印尼语")
      // We should combine them if originalTitle isn't already reflecting the language.
      if (finalLanguage != '未知' &&
          !originalTitle.toLowerCase().contains(
                finalLanguage.toLowerCase().substring(
                      0,
                      finalLanguage.length > 2 ? 2 : 1,
                    ),
              )) {
        // Avoids "简体中文 (简体中文 Commentary)" if originalTitle was "简体中文 Commentary"
        // Check if originalTitle already contains the language (or part of it)
        bool titleAlreadyHasLang = false;
        for (var patValue in _subtitleNormalizationPatterns.values) {
          if (patValue != "未知" && originalTitle.contains(patValue)) {
            titleAlreadyHasLang = true;
            break;
          }
        }
        if (titleAlreadyHasLang) {
          finalTitle = originalTitle;
        } else {
          finalTitle = "$finalLanguage ($originalTitle)";
        }
      } else {
        finalTitle = originalTitle;
      }
    }
  } else {
    // originalTitle is empty, so title is just the language.
    finalTitle = finalLanguage;
  }

  // Fallback if title somehow ended up empty or generic "n/a"
  if (finalTitle.isEmpty || finalTitle.toLowerCase() == 'n/a') {
    finalTitle = (finalLanguage != '未知' && finalLanguage.isNotEmpty)
        ? finalLanguage
        : "轨道 ${trackIndexForFallback + 1}";
  }
  if (finalTitle.isEmpty) finalTitle = "轨道 ${trackIndexForFallback + 1}";

  return (title: finalTitle, language: finalLanguage);
}

class _PreparedNetworkMedia {
  final String url;
  final Map<String, String>? httpHeaders;

  const _PreparedNetworkMedia({required this.url, this.httpHeaders});
}

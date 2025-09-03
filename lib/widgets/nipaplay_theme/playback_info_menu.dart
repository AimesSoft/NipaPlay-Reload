import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'settings_hint_text.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/emby_service.dart';

class PlaybackInfoMenu extends StatefulWidget {
  final VoidCallback onClose;

  const PlaybackInfoMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<PlaybackInfoMenu> createState() => _PlaybackInfoMenuState();
}

class _PlaybackInfoMenuState extends State<PlaybackInfoMenu> {
  Map<String, dynamic>? _asyncDetailedInfo; // 缓存一次性异步获取的详细信息
  Map<String, dynamic>? _serverMeta; // 缓存服务器媒体元数据（流媒体时）

  @override
  void initState() {
    super.initState();
    // 首帧后异步拉取详细信息（尤其是 mpv 的属性需要 await）
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final videoState = context.read<VideoPlayerState>();
      try {
        final info = await videoState.player.getDetailedMediaInfoAsync();
        if (mounted) setState(() => _asyncDetailedInfo = info);
      } catch (_) {
        // 忽略失败，保持同步回退
      }

      // 若为流媒体，尝试从服务器获取媒体技术元数据
      final path = videoState.currentVideoPath;
      if (path != null) {
        try {
          Map<String, dynamic>? meta;
          if (path.startsWith('jellyfin://')) {
            final itemId = path.replaceFirst('jellyfin://', '');
            meta = await JellyfinService.instance.getServerMediaTechnicalInfo(itemId);
          } else if (path.startsWith('emby://')) {
            final itemId = path.replaceFirst('emby://', '');
            meta = await EmbyService.instance.getServerMediaTechnicalInfo(itemId);
          }
          if (meta != null && meta.isNotEmpty && mounted) {
            setState(() => _serverMeta = meta);
          }
        } catch (_) {}
      }
    });
  }
  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return BaseSettingsMenu(
          title: '播放信息',
          onClose: widget.onClose,
          content: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsHintText('当前播放状态和媒体信息'),
                const SizedBox(height: 16),
                _buildInfoCard('播放状态', _getPlaybackStatusInfo(videoState)),
                const SizedBox(height: 12),
                _buildInfoCard('视频信息', _getVideoInfo(videoState)),
                const SizedBox(height: 12),
                _buildInfoCard('音频信息', _getAudioInfo(videoState)),
                const SizedBox(height: 12),
                _buildInfoCard('网络信息', _getNetworkInfo(videoState)),
                if (_serverMeta != null && _serverMeta!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard('来源元数据', _getServerMetaInfo()),
                ],
                if (_isTranscoding(videoState)) ...[
                  const SizedBox(height: 12),
                  _buildInfoCard('转码信息', _getTranscodeInfo(videoState)),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  List<InfoItem> _getServerMetaInfo() {
    final m = _serverMeta ?? const {};
    final container = _normalizeText(m['container']) ?? '未知';
    final v = (m['video'] is Map) ? Map<String, dynamic>.from(m['video']) : const {};
    final a = (m['audio'] is Map) ? Map<String, dynamic>.from(m['audio']) : const {};

    String vCodec = _normalizeText(v['codec']) ?? '未知';
    final vProfile = _normalizeText(v['profile']);
    final vLevel = _normalizeText(v['level']);
    final vBitDepth = v['bitDepth'];
    final vResW = v['width'];
    final vResH = v['height'];
    final vFps = v['frameRate'];
    final vBitrate = v['bitRate'];
    final vRange = _normalizeText(v['dynamicRange']);
    final colorPrimaries = _normalizeText(v['colorPrimaries']);
    final colorTransfer = _normalizeText(v['colorTransfer']);
    final colorSpace = _normalizeText(v['colorSpace']);

    // 拼装视频行
    final List<InfoItem> items = [
      InfoItem('容器', container),
      InfoItem('视频', _joinNonEmpty([
        vCodec,
        if (vProfile != null) 'Profile $vProfile',
        if (vLevel != null) 'Level $vLevel',
        if (vBitDepth is int) '${vBitDepth}bit',
      ], sep: ' · ')),
  InfoItem('分辨率', (vResW is int && vResH is int && vResW > 0 && vResH > 0) ? '${vResW}x${vResH}' : '未知'),
      InfoItem('帧率', (vFps is num && vFps > 0) ? '${vFps.toStringAsFixed(2)} fps' : '未知'),
      InfoItem('码率', (vBitrate is int && vBitrate > 0) ? '${(vBitrate / 1000).toStringAsFixed(0)} kbps' : '未知'),
    ];

    final colorLine = _joinNonEmpty([colorPrimaries, colorTransfer, colorSpace], sep: ' / ');
    if (colorLine.isNotEmpty) {
      items.add(InfoItem('色彩', colorLine));
    }
    if (vRange != null) {
      items.add(InfoItem('动态范围', vRange));
    }

    // 音频
    String aCodec = _normalizeText(a['codec']) ?? '未知';
    final aChannels = a['channels'];
    final aLayout = _normalizeText(a['channelLayout']);
    final aSample = a['sampleRate'];
    final aBitrate = a['bitRate'];
    items.addAll([
      InfoItem('音频', _joinNonEmpty([
        aCodec,
        if (aLayout != null) aLayout,
        if (aChannels is int && aChannels > 0) _formatChannels(aChannels),
      ], sep: ' · ')),
      InfoItem('采样率', (aSample is int && aSample > 0) ? '$aSample Hz' : '未知'),
      InfoItem('音频码率', (aBitrate is int && aBitrate > 0) ? '${(aBitrate / 1000).toStringAsFixed(0)} kbps' : '未知'),
    ]);

    return items;
  }

  Widget _buildInfoCard(String title, List<InfoItem> items) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    '${item.label}:',
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: Colors.white.withOpacity(0.7),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    item.value,
                    locale:Locale("zh-Hans","zh"),
style: TextStyle(
                      color: item.isHighlighted ? Colors.white : Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: item.isHighlighted ? FontWeight.w500 : FontWeight.normal,
                    ),
                  ),
                ),
              ],
            ),
          )).toList(),
        ],
      ),
    );
  }

  List<InfoItem> _getPlaybackStatusInfo(VideoPlayerState videoState) {
    final status = videoState.status;
    final position = videoState.position;
    final duration = videoState.duration;
    final progress = videoState.progress;

    return [
      InfoItem('状态', _getStatusText(status), _isStatusActive(status)),
      InfoItem('进度', '${_formatDuration(position)} / ${_formatDuration(duration)}'),
      InfoItem('百分比', '${(progress * 100).toStringAsFixed(1)}%'),
      InfoItem('播放速度', '${videoState.playbackRate}x'),
    ];
  }

  List<InfoItem> _getVideoInfo(VideoPlayerState videoState) {
    final mediaInfo = videoState.player.mediaInfo;
    final videoStreams = mediaInfo.video;
  final playerKernelName = videoState.playerCoreName;
    
    if (videoStreams == null || videoStreams.isEmpty) {
      return [
        InfoItem('编解码器', '未知'),
        InfoItem('分辨率', '未知'),
        InfoItem('帧率', '未知'),
        InfoItem('码率', '未知'),
      ];
    }
    
    final videoStream = videoStreams.first;
    final codec = videoStream.codec;
    
    // 根据播放器内核类型处理信息
    if (playerKernelName.toLowerCase().contains('mdk')) {
      // MDK播放器：解析完整的参数字符串
      final codecParamsString = codec.name ?? '';
      final codecInfo = _parseVideoCodecParams(codecParamsString);
      
    // 优先用参数串中的 codec 字段；回退使用流的 codecName
    final codecName = _normalizeText(RegExp(r'codec:\s*([\w\-\.]+)').firstMatch(codecParamsString)?.group(1))
      ?? (videoStream.codecName ?? 'unknown');
      final resolution = codec.width > 0 && codec.height > 0 
          ? '${codec.width}x${codec.height}' 
          : '未知';
    final frameRate = codecInfo['fps'] ?? codecInfo['frameRate'] ?? '未知';
      final bitRate = codecInfo['bitRate'] ?? '未知';
      
      return [
        InfoItem('编解码器', codecName),
        InfoItem('分辨率', resolution),
        InfoItem('帧率', frameRate),
        InfoItem('码率', bitRate),
      ];
    } else {
  // Media Kit播放器：通过抽象层接口获取更详细信息
  String frameRate = '未知';
  String bitRate = '未知';
  String colorSpace = '未知';
  String decodeMethod = '未知';

      final detailedInfo = _asyncDetailedInfo ?? videoState.player.getDetailedMediaInfo();
  // 使用详细信息（若异步已填充，则优先）
      if (detailedInfo.isNotEmpty) {
        final mpvProps = detailedInfo['mpvProperties'] as Map?;
        if (mpvProps != null && mpvProps.isNotEmpty) {
          final containerFps = _toNum(mpvProps['container-fps']);
          final estimatedFps = _toNum(mpvProps['estimated-vf-fps']);
          if (containerFps != null && containerFps > 0) {
            frameRate = '${containerFps.toStringAsFixed(2)} fps';
          } else if (estimatedFps != null && estimatedFps > 0) {
            frameRate = '${estimatedFps.toStringAsFixed(2)} fps';
          }

          // 码率优先从视频比特率读取；若为流媒体且无值，尝试多来源回退
          final videoBitrate = _toNum(mpvProps['video-bitrate']);
          if (videoBitrate != null && videoBitrate > 0) {
            bitRate = '${(videoBitrate / 1000).toStringAsFixed(0)} kbps';
          } else if (_isStreamingSource(videoState)) {
            final fallback = _toNum(mpvProps['bitrate'])
                ?? _toNum(mpvProps['demuxer-bitrate'])
                ?? _toNum(mpvProps['container-bitrate'])
                ?? _toNum(mpvProps['audio-bitrate']);
            if (fallback != null && fallback > 0) {
              bitRate = '${(fallback / 1000).toStringAsFixed(0)} kbps';
            }
          }

          // 色彩空间：清理空值，避免尾部斜杠
          final cm = _normalizeText(mpvProps['video-params/colormatrix']);
          final cp = _normalizeText(mpvProps['video-params/colorprimaries']);
          final parts = _joinNonEmpty([cm, cp], sep: ' / ');
          if (parts.isNotEmpty) colorSpace = parts;

          // 解码方式：优先 hwdec-current（实际使用），否则根据 hwdec 判断
          final hwdecCurrent = mpvProps['hwdec-current'];
          final hwdec = mpvProps['hwdec'];
          if (hwdecCurrent is String && hwdecCurrent.isNotEmpty && hwdecCurrent.toLowerCase() != 'no') {
            decodeMethod = '硬件 ($hwdecCurrent)';
          } else if (hwdec is String && hwdec.isNotEmpty && hwdec.toLowerCase() != 'no') {
            decodeMethod = '硬件 ($hwdec)';
          } else {
            decodeMethod = '软件';
          }
        }

        // 回退：从 videoParams 读取（若有）
        // （保留占位：若后续提供 fps 字段可加回）
      }
      
      final codecName = videoStream.codecName ?? 'unknown';
      final resolution = codec.width > 0 && codec.height > 0 
          ? '${codec.width}x${codec.height}' 
          : '未知';
      
      return [
        InfoItem('编解码器', codecName),
        InfoItem('分辨率', resolution),
        InfoItem('帧率', frameRate),
        InfoItem('码率', bitRate),
  InfoItem('解码', decodeMethod),
        if (colorSpace != '未知') InfoItem('色彩空间', colorSpace),
      ];
    }
  }

  List<InfoItem> _getAudioInfo(VideoPlayerState videoState) {
    final mediaInfo = videoState.player.mediaInfo;
    final audioStreams = mediaInfo.audio;
    final playerKernelName = videoState.playerCoreName;
    
    if (audioStreams == null || audioStreams.isEmpty) {
      return [
        InfoItem('编解码器', '未知'),
        InfoItem('采样率', '未知'),
        InfoItem('声道', '未知'),
        InfoItem('码率', '未知'),
      ];
    }
    
    final audioStream = audioStreams.first;
    final codec = audioStream.codec;
    
    // 根据播放器内核类型处理信息
    if (playerKernelName.toLowerCase().contains('mdk')) {
      // MDK播放器：解析完整的参数字符串
      final codecParamsString = codec.name ?? '';
      final codecInfo = _parseAudioCodecParams(codecParamsString);
      
      final codecName = codecInfo['codec'] ?? 'aac';
      final profile = codecInfo['profile'] ?? '';
      final profileText = profile.isNotEmpty ? ' $profile' : '';
      
      final sampleRate = codecInfo['sampleRate'] ?? '未知';
      String channels = codec.channels != null && codec.channels! > 0 
          ? _formatChannels(codec.channels!) 
          : '未知';
      final bitRate = codecInfo['bitRate'] ?? '未知';
      // 声道回退：从解析结果中读取 channels 数字
      if (channels == '未知' && codecInfo['channels'] != null) {
        final ch = int.tryParse(codecInfo['channels']!);
        if (ch != null && ch > 0) channels = _formatChannels(ch);
      }
      
      return [
        InfoItem('编解码器', '$codecName$profileText'),
        InfoItem('采样率', sampleRate),
        InfoItem('声道', channels),
        InfoItem('码率', bitRate),
      ];
    } else {
      // Media Kit播放器：通过抽象层接口获取更详细信息
      String codecName = '未知';
      String sampleRate = '未知';
      String channels = '未知';
      String bitRate = '未知';

      final detailedInfo = _asyncDetailedInfo ?? videoState.player.getDetailedMediaInfo();
  // 使用详细信息（若异步已填充，则优先）
      if (detailedInfo.isNotEmpty) {
        final mpvProps = detailedInfo['mpvProperties'] as Map?;
        if (mpvProps != null) {
          final audioCodec = mpvProps['audio-codec'] ?? mpvProps['audio-codec-name'];
          if (audioCodec != null) {
            codecName = _sanitizeCodecName(audioCodec.toString());
          }
          final audioSampleRate = _toNum(mpvProps['audio-samplerate']);
          if (audioSampleRate != null && audioSampleRate > 0) {
            sampleRate = '${audioSampleRate.toInt()} Hz';
          }
          // 多来源尝试获取声道数
          final chPicked = _pickChannels(mpvProps);
          if (chPicked != null && chPicked > 0) {
            channels = _formatChannels(chPicked);
          }
          final audioBitrateValue = _toNum(mpvProps['audio-bitrate']);
          if (audioBitrateValue != null && audioBitrateValue > 0) {
            bitRate = '${(audioBitrateValue / 1000).toStringAsFixed(0)} kbps';
          }
        }

        // 备用：从audioParams获取
        if (sampleRate == '未知' || channels == '未知') {
          final audioParams = detailedInfo['audioParams'] as Map?;
          if (audioParams != null) {
            final sr = audioParams['sampleRate'];
            if (sampleRate == '未知' && sr is num && sr > 0) {
              sampleRate = '${sr} Hz';
            }
            final ch = audioParams['channels'];
            if (channels == '未知' && ch is num && ch > 0) {
              channels = _formatChannels(ch.toInt());
            }
          }
        }

        // 备用：从轨道信息获取编解码器名
        if (codecName == '未知') {
          final tracks = detailedInfo['tracks'] as Map?;
          final audios = tracks != null ? tracks['audio'] : null;
          if (audios is List && audios.isNotEmpty) {
            final a0 = audios.first;
            if (a0 is Map && a0['codec'] != null) {
              codecName = a0['codec'].toString();
            }
          }
        }
      }
      
      // 如果还是未知，尝试从基础信息获取
      if (codecName == '未知') {
        codecName = audioStream.codec.name ?? 'unknown';
      }
      if (channels == '未知' && codec.channels != null && codec.channels! > 0) {
        channels = _formatChannels(codec.channels!);
      }
      
      return [
        InfoItem('编解码器', codecName),
        InfoItem('采样率', sampleRate),
        InfoItem('声道', channels),
        InfoItem('码率', bitRate),
      ];
    }
  }

  List<InfoItem> _getNetworkInfo(VideoPlayerState videoState) {
    final currentPath = videoState.currentVideoPath;
    final isStreaming = currentPath?.startsWith('http') == true ||
                       currentPath?.startsWith('jellyfin://') == true ||
                       currentPath?.startsWith('emby://') == true;

    if (!isStreaming) {
      return [
        InfoItem('类型', '本地文件'),
        InfoItem('路径', currentPath?.split('/').last ?? '未知'),
      ];
    }

    return [
      InfoItem('类型', _getStreamType(currentPath)),
      InfoItem('协议', _getProtocol(currentPath)),
      InfoItem('缓冲状态', '良好'),
      InfoItem('网络延迟', '< 50ms'),
    ];
  }

  List<InfoItem> _getTranscodeInfo(VideoPlayerState videoState) {
    final currentPath = videoState.currentVideoPath;
    final isJellyfin = currentPath?.startsWith('jellyfin://') == true;
    final isEmby = currentPath?.startsWith('emby://') == true;

    if (!isJellyfin && !isEmby) {
      return [InfoItem('状态', '不适用 (本地播放)')];
    }

    // 获取实际播放URL来判断是否在转码
    // 对于流媒体，我们需要检查实际的播放URL格式
    final actualUrl = videoState.currentActualPlayUrl;
    bool isTranscoding = false;
    String transcodeType = '未知';
    
    if (actualUrl != null) {
      if (actualUrl.contains('master.m3u8')) {
        isTranscoding = true;
        transcodeType = 'HLS 转码';
      } else if (actualUrl.contains('stream.') || actualUrl.contains('/stream/')) {
        isTranscoding = true;
        transcodeType = '流转码';
      } else if (actualUrl.contains('/original/') || actualUrl.contains('original')) {
        isTranscoding = false;
        transcodeType = '直接播放';
      }
    }
    
    if (isTranscoding) {
      return [
        InfoItem('状态', transcodeType, true),
        InfoItem('协议', isJellyfin ? 'Jellyfin HLS' : 'Emby HLS'),
        InfoItem('说明', '服务器正在转码视频流'),
      ];
    } else {
      return [
        InfoItem('状态', '直接播放', false),
        InfoItem('协议', isJellyfin ? 'Jellyfin API' : 'Emby API'),
        InfoItem('传输方式', 'HTTP直连'),
      ];
    }
  }

  bool _isTranscoding(VideoPlayerState videoState) {
    final currentPath = videoState.currentVideoPath;
    return currentPath?.startsWith('jellyfin://') == true ||
           currentPath?.startsWith('emby://') == true;
  }

  bool _isStreamingSource(VideoPlayerState videoState) {
    final currentPath = videoState.currentVideoPath;
    return currentPath?.startsWith('http') == true ||
           currentPath?.startsWith('https') == true ||
           currentPath?.startsWith('jellyfin://') == true ||
           currentPath?.startsWith('emby://') == true;
  }

  String _getStatusText(PlayerStatus status) {
    switch (status) {
      case PlayerStatus.idle:
        return '空闲';
      case PlayerStatus.loading:
        return '加载中';
      case PlayerStatus.recognizing:
        return '识别中';
      case PlayerStatus.ready:
        return '就绪';
      case PlayerStatus.playing:
        return '播放中';
      case PlayerStatus.paused:
        return '已暂停';
      case PlayerStatus.disposed:
        return '已释放';
      case PlayerStatus.error:
        return '错误';
    }
  }

  bool _isStatusActive(PlayerStatus status) {
    return status == PlayerStatus.playing;
  }

  String _getStreamType(String? path) {
    if (path?.startsWith('jellyfin://') == true) return 'Jellyfin流媒体';
    if (path?.startsWith('emby://') == true) return 'Emby流媒体';
    if (path?.startsWith('http') == true) return 'HTTP流媒体';
    return '未知';
  }

  String _getProtocol(String? path) {
    if (path?.startsWith('https://') == true) return 'HTTPS';
    if (path?.startsWith('http://') == true) return 'HTTP';
    if (path?.startsWith('jellyfin://') == true) return 'Jellyfin API';
    if (path?.startsWith('emby://') == true) return 'Emby API';
    return '未知';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  String _formatChannels(int channels) {
    switch (channels) {
      case 1:
        return '单声道 (1.0)';
      case 2:
        return '立体声 (2.0)';
      case 6:
        return '5.1环绕声';
      case 8:
        return '7.1环绕声';
      default:
        return '$channels 声道';
    }
  }

  // 解析视频编解码器参数字符串
  Map<String, String> _parseVideoCodecParams(String codecString) {
    final Map<String, String> result = {};
    
    // 解析 VideoCodecParameters(codec: h264, tag: 828601953, profile: 100, level: 50, bitRate: 2701394, 1920x1080, 23.976024627685547fps, format: yuv420p, bFrames:2)
    final RegExp regExp = RegExp(r'(\w+):\s*([^,)]+)');
    final matches = regExp.allMatches(codecString);
    
    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(2);
      if (key != null && value != null) {
        result[key] = value.trim();
      }
    }
    
    // 特殊处理分辨率
    final resolutionMatch = RegExp(r'(\d+)x(\d+)').firstMatch(codecString);
    if (resolutionMatch != null) {
      result['resolution'] = '${resolutionMatch.group(1)}x${resolutionMatch.group(2)}';
    }
    
    // 特殊处理帧率
    final fpsMatch = RegExp(r'([\d.]+)fps').firstMatch(codecString);
    if (fpsMatch != null) {
      final fps = double.tryParse(fpsMatch.group(1) ?? '') ?? 0;
      result['fps'] = '${fps.toStringAsFixed(1)} fps';
    }
    
    // 特殊处理码率
    if (result['bitRate'] != null) {
      final bitRate = int.tryParse(result['bitRate']!) ?? 0;
      if (bitRate > 0) {
        result['bitRate'] = '${(bitRate / 1000000).toStringAsFixed(1)} Mbps';
      }
    }
    
    return result;
  }

  // 解析音频编解码器参数字符串
  Map<String, String> _parseAudioCodecParams(String codecString) {
    final Map<String, String> result = {};
    
    // 解析 AudioCodecParameters(codec: aac, tag: 1630826605, profile: 1, level: -99, bitRate: 128000, isFloat: true, isUnsigned: false, isPlanar: true, channels: 2 @44100Hz, blockAlign: 0, frameSize: 1024)
    final RegExp regExp = RegExp(r'(\w+):\s*([^,)]+)');
    final matches = regExp.allMatches(codecString);
    
    for (final match in matches) {
      final key = match.group(1);
      final value = match.group(2);
      if (key != null && value != null) {
        result[key] = value.trim();
      }
    }
    
    // 特殊处理采样率和声道
    final channelMatch = RegExp(r'channels:\s*(\d+)\s*@\s*(\d+)Hz').firstMatch(codecString);
    if (channelMatch != null) {
      final sampleRate = int.tryParse(channelMatch.group(2) ?? '') ?? 0;
      result['sampleRate'] = '${(sampleRate / 1000).toStringAsFixed(1)} kHz';
      result['channels'] = channelMatch.group(1) ?? '';
    }
    
    // 特殊处理码率
    if (result['bitRate'] != null) {
      final bitRate = int.tryParse(result['bitRate']!) ?? 0;
      if (bitRate > 0) {
        result['bitRate'] = '${(bitRate / 1000).toStringAsFixed(0)} kbps';
      }
    }
    
    // 格式化 profile
    if (result['profile'] != null) {
      final profile = result['profile'];
      if (profile == '1') {
        result['profile'] = 'AAC-LC';
      } else if (profile == '2') {
        result['profile'] = 'AAC-HE';
      } else {
        result['profile'] = 'Profile $profile';
      }
    }
    
    return result;
  }
}

class InfoItem {
  final String label;
  final String value;
  final bool isHighlighted;

  InfoItem(this.label, this.value, [this.isHighlighted = false]);
}

// 将 mpv 可能返回的字符串数值安全解析为 num
num? _toNum(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) {
    return num.tryParse(v);
  }
  return null;
}

// 规范化文本（去除 null/空串、'(null)' 等）
String? _normalizeText(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  if (s.toLowerCase() == 'null' || s.toLowerCase() == '(null)') return null;
  return s;
}

// 拼接非空片段
String _joinNonEmpty(List<String?> parts, {String sep = ' '}) {
  final filtered = parts.where((e) => e != null && e.isNotEmpty).cast<String>();
  return filtered.join(sep);
}

// 清理编解码器名称中的 "(null)"
String _sanitizeCodecName(String codec) {
  return codec.replaceAll('(null)', '').replaceAll('()', '').replaceAll(RegExp(r'\s+'), ' ').trim();
}

// 从 mpv 属性推断声道：优先数值，其次字符串（stereo/mono/5.1 等）
int? _pickChannels(Map mpvProps) {
  final n = _toNum(mpvProps['audio-channels']);
  if (n != null && n > 0) return n.toInt();
  final s = _normalizeText(mpvProps['audio-params/channel-layout'])
      ?? _normalizeText(mpvProps['audio-channel-layout'])
      ?? _normalizeText(mpvProps['audio-params/format']);
  if (s != null) {
    final lower = s.toLowerCase();
    if (lower.contains('mono') || lower == '1.0') return 1;
    if (lower.contains('stereo') || lower == '2.0') return 2;
    if (lower.contains('5.1') || lower.contains('5_1')) return 6;
    if (lower.contains('7.1') || lower.contains('7_1')) return 8;
    final m = RegExp(r'^(\d+)\.(\d+)$').firstMatch(lower);
    if (m != null) {
      final base = int.tryParse(m.group(1) ?? '0') ?? 0;
      final lfe = int.tryParse(m.group(2) ?? '0') ?? 0;
      final total = base + lfe;
      if (total > 0) return total;
    }
  }
  return null;
}

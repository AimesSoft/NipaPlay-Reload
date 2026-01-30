import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/models/media_server_playback.dart';

abstract class MediaServerPlaybackClient {
  Future<PlaybackSession> createPlaybackSession({
    required String itemId,
    JellyfinVideoQuality? quality,
    int? startPositionMs,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool burnInSubtitle = false,
    String? playSessionId,
    String? mediaSourceId,
  });

  Future<PlaybackSession> refreshPlaybackSession(
    PlaybackSession session, {
    JellyfinVideoQuality? quality,
    int? startPositionMs,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    bool burnInSubtitle = false,
  }) {
    return createPlaybackSession(
      itemId: session.itemId,
      quality: quality,
      startPositionMs: startPositionMs,
      audioStreamIndex: audioStreamIndex,
      subtitleStreamIndex: subtitleStreamIndex,
      burnInSubtitle: burnInSubtitle,
      playSessionId: session.playSessionId,
      mediaSourceId: session.mediaSourceId,
    );
  }
}

class PlaybackDeviceProfileBuilder {
  static DeviceProfile build({
    required String deviceName,
    required JellyfinTranscodeSettings settings,
  }) {
    final videoCodecs = settings.video.preferredCodecs.isNotEmpty
      ? settings.video.preferredCodecs
      : const [
        'h264',
        'hevc',
        'av1',
        'vp9',
        'vp8',
        'mpeg2video',
        'mpeg4',
        'vc1',
        'wmv3',
        'theora',
        'prores',
        'mjpeg',
        ];
    final audioCodecs = settings.audio.preferredCodecs.isNotEmpty
      ? settings.audio.preferredCodecs
      : const [
        'aac',
        'mp3',
        'opus',
        'flac',
        'alac',
        'vorbis',
        'ac3',
        'eac3',
        'dts',
        'truehd',
        'pcm',
        'wma',
        ];
    final subtitleCodecs = settings.subtitle.preferredCodecs.isNotEmpty
      ? settings.subtitle.preferredCodecs
      : const ['srt', 'ass', 'ssa', 'vtt', 'sub', 'pgs', 'idx', 'sup'];

    final directPlayProfiles = <DirectPlayProfile>[
      DirectPlayProfile(
        type: 'Video',
        container:
            'mp4,mkv,webm,avi,mov,flv,ts,m2ts,m4v,mpg,mpeg,wmv,3gp,3g2,ogv',
        videoCodec: videoCodecs.join(','),
        audioCodec: audioCodecs.join(','),
      ),
      DirectPlayProfile(
        type: 'Audio',
        container: 'aac,mp3,flac,opus,ogg,wav,alac,m4a,ac3,eac3,dts,wma',
        audioCodec: audioCodecs.join(','),
      ),
    ];

    final transcodingProfiles = <TranscodingProfile>[
      TranscodingProfile(
        type: 'Video',
        container: 'ts',
        protocol: 'hls',
        videoCodec: videoCodecs.join(','),
        audioCodec: audioCodecs.join(','),
        maxAudioChannels: settings.audio.maxAudioChannels > 0
            ? settings.audio.maxAudioChannels
            : null,
        minSegments: 1,
        breakOnNonKeyFrames: true,
        copyTimestamps: false,
        enableMpegtsM2TsMode: false,
        context: 'Streaming',
      ),
    ];

    final subtitleProfiles = <SubtitleProfile>[
      for (final format in subtitleCodecs)
        SubtitleProfile(format: format, method: 'External'),
      for (final format in subtitleCodecs)
        SubtitleProfile(format: format, method: 'Embed'),
      for (final format in subtitleCodecs)
        SubtitleProfile(format: format, method: 'Encode'),
    ];

    return DeviceProfile(
      name: deviceName,
      directPlayProfiles: directPlayProfiles,
      transcodingProfiles: transcodingProfiles,
      subtitleProfiles: subtitleProfiles,
    );
  }
}

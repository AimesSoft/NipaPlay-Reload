import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/emby_media_selection.dart';
import 'package:nipaplay/models/media_server_playback.dart';

void main() {
  group('describeEmbyMediaSource', () {
    test('maps source metadata and typed tracks', () {
      final source = PlaybackMediaSource.fromJson({
        'Id': 'baha',
        'Name': 'WEB-DL.Baha',
        'Size': 1470000000,
        'Bitrate': 2200000,
        'Container': 'mkv',
        'MediaStreams': [
          {
            'Index': 0,
            'Type': 'Video',
            'Codec': 'hevc',
            'Profile': 'Main 10',
            'Level': '153',
            'Width': 1920,
            'Height': 1080,
            'RealFrameRate': 23.976,
            'BitDepth': 10,
            'VideoRange': 'HDR',
            'BitRate': 2100000,
          },
          {
            'Index': 1,
            'Type': 'Audio',
            'Language': 'jpn',
            'Title': '日语',
            'Codec': 'aac',
            'Channels': 2,
            'SampleRate': 48000,
            'BitRate': 128000,
            'IsDefault': true,
          },
          {
            'Index': 2,
            'Type': 'Subtitle',
            'Language': 'chi',
            'Title': '简体',
            'Codec': 'ass',
            'IsExternal': false,
            'IsDefault': true,
            'IsForced': false,
          },
        ],
      });

      final descriptor = describeEmbyMediaSource(source, ordinal: 0);

      expect(source.name, 'WEB-DL.Baha');
      expect(source.size, 1470000000);
      expect(source.bitRate, 2200000);
      expect(descriptor.displayName, 'WEB-DL.Baha');
      expect(descriptor.summary, '1080p · 1.37 GB · 2.2 Mbps');

      final video = descriptor.videoTracks.single;
      expect(video.index, 0);
      expect(video.codec, 'hevc');
      expect(video.profile, 'Main 10');
      expect(video.level, '153');
      expect(video.width, 1920);
      expect(video.height, 1080);
      expect(video.frameRate, 23.976);
      expect(video.bitDepth, 10);
      expect(video.hdr, 'HDR');
      expect(video.bitRate, 2100000);

      final audio = descriptor.audioTracks.single;
      expect(audio.index, 1);
      expect(audio.language, 'jpn');
      expect(audio.title, '日语');
      expect(audio.codec, 'aac');
      expect(audio.channels, 2);
      expect(audio.sampleRate, 48000);
      expect(audio.bitRate, 128000);
      expect(audio.isDefault, isTrue);
      expect(audio.fingerprint.normalizedTitle, '日语');

      final subtitle = descriptor.subtitleTracks.single;
      expect(subtitle.index, 2);
      expect(subtitle.language, 'chi');
      expect(subtitle.title, '简体');
      expect(subtitle.codec, 'ass');
      expect(subtitle.isExternal, isFalse);
      expect(subtitle.isDefault, isTrue);
      expect(subtitle.isForced, isFalse);
      expect(subtitle.fingerprint.codec, 'ass');
    });

    test('accepts numeric strings and keeps the original stream maps', () {
      final source = PlaybackMediaSource.fromJson({
        'Id': 'string-numbers',
        'Path': r'D:\Anime\Episode 01.mkv',
        'Size': '1048576',
        'Bitrate': '800000',
        'Container': 'mkv',
        'DirectStreamUrl': '/Videos/episode/stream.mkv',
        'TranscodingUrl': '/Videos/episode/master.m3u8',
        'TranscodingContainer': 'ts',
        'TranscodingSubProtocol': 'hls',
        'SupportsTranscoding': true,
        'SupportsDirectPlay': true,
        'SupportsDirectStream': true,
        'MediaStreams': [
          {
            'Index': '4',
            'Type': 'Video',
            'Height': '720',
            'Width': '1280',
            'RealFrameRate': '24',
          },
        ],
      });

      final descriptor = describeEmbyMediaSource(source, ordinal: 1);

      expect(source.size, 1048576);
      expect(source.bitRate, 800000);
      expect(source.mediaStreams.single['Index'], '4');
      expect(source.directStreamUrl, '/Videos/episode/stream.mkv');
      expect(source.transcodingUrl, '/Videos/episode/master.m3u8');
      expect(source.transcodingContainer, 'ts');
      expect(source.transcodingSubProtocol, 'hls');
      expect(source.supportsTranscoding, isTrue);
      expect(source.supportsDirectPlay, isTrue);
      expect(source.supportsDirectStream, isTrue);
      expect(descriptor.displayName, 'Episode 01.mkv');
      expect(descriptor.summary, '720p · 1 MB · 0.8 Mbps');
      expect(descriptor.videoTracks.single.index, 4);
      expect(descriptor.videoTracks.single.frameRate, 24);
    });

    test('extracts a source name from a Linux path', () {
      const source = PlaybackMediaSource(
        id: 'linux-path',
        path: '/mnt/anime/Season 01/Episode 02.mkv',
      );

      final descriptor = describeEmbyMediaSource(source, ordinal: 1);

      expect(descriptor.displayName, 'Episode 02.mkv');
    });

    test('falls back to ordinal and container for an unnamed source', () {
      const source = PlaybackMediaSource(
        id: 'fallback',
        container: 'mp4',
      );

      final descriptor = describeEmbyMediaSource(source, ordinal: 2);

      expect(descriptor.displayName, '版本 3 · MP4');
      expect(descriptor.summary, isEmpty);
      expect(descriptor.videoTracks, isEmpty);
      expect(descriptor.audioTracks, isEmpty);
      expect(descriptor.subtitleTracks, isEmpty);
    });

    test('ignores malformed metadata and unsupported stream types', () {
      final source = PlaybackMediaSource.fromJson({
        'Id': 'malformed',
        'Name': '  Custom Source  ',
        'Size': 'not-a-number',
        'Bitrate': '',
        'MediaStreams': [
          {'Index': 'bad', 'Type': 'Video', 'Height': 'bad'},
          {'Index': 7, 'Type': 'Data', 'Codec': 'bin'},
          'not-a-map',
        ],
      });

      final descriptor = describeEmbyMediaSource(source, ordinal: 0);

      expect(source.size, isNull);
      expect(source.bitRate, isNull);
      expect(descriptor.displayName, 'Custom Source');
      expect(descriptor.summary, isEmpty);
      expect(descriptor.videoTracks, isEmpty);
      expect(descriptor.audioTracks, isEmpty);
      expect(descriptor.subtitleTracks, isEmpty);
    });
  });
}

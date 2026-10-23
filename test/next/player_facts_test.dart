import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/classic/classic_playback_controls.dart';
import 'package:nipaplay/next/capabilities/playback_controls_capability.dart';
import 'package:nipaplay/next/capabilities/player_facts.dart';
import 'package:nipaplay/next/player/classic/classic_facts.dart';
import 'package:nipaplay/next/player/classic/video_player_state_port.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';
import 'test_support.dart';

/// What the Media Kit adapter's getDetailedMediaInfoAsync returns: the
/// values sit inside mpvProperties, not at the top level.
Map<String, dynamic> mediaKitDetails({String hwdec = 'videotoolbox'}) => {
      'kernel': 'MediaKit',
      'mpvProperties': <String, dynamic>{
        'container-fps': '23.976024',
        'estimated-vf-fps': '23.950000',
        'video-bitrate': '2701394',
        'audio-bitrate': '128000',
        'hwdec': 'auto-safe',
        'hwdec-current': hwdec,
        'current-vo': 'libmpv',
        'gpu-api': 'opengl',
        'video-format': 'h264',
        'video-codec': 'h264 (H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10)',
        'video-params/w': '1920',
        'video-params/h': '1080',
        'dwidth': '1920',
        'dheight': '1080',
        'video-params/colormatrix': 'bt.709',
        'video-params/colorprimaries': 'bt.709',
        'video-params/transfer': 'bt.1886',
        'audio-codec-name': 'aac',
        'audio-codec': 'aac (AAC (Advanced Audio Coding))',
        'audio-params/channel-count': '2',
        'audio-params/channel-layout': 'stereo',
        'audio-params/format': 'floatp',
        'audio-samplerate': '48000',
      },
      'videoParams': {'width': 1920, 'height': 1080},
      'audioParams': {'channels': 2, 'sampleRate': 48000, 'format': 'floatp'},
      'tracks': {'video': [], 'audio': [], 'subtitle': []},
    };

const mpvExtras = <String, String?>{
  'frame-drop-count': '3',
  'decoder-frame-drop-count': '1',
  'mistimed-frame-count': '0',
  'vo-delayed-frame-count': '2',
  'video-params/pixelformat': 'nv12',
  'video-params/hw-pixelformat': 'videotoolbox_vld',
  'speed': '1.500000',
  'file-format': 'matroska,webm',
  'demuxer-cache-duration': '12.5',
  'paused-for-cache': 'no',
  'cache-buffering-state': '100',
  'avsync': '-0.004',
};

/// Classic's Media Kit kernel as a test double: what it reports is given.
class ReportingKernel extends ClassicKernel {
  Map<String, dynamic> details = mediaKitDetails();
  Map<String, String?> extras = mpvExtras;
  final asked = <List<String>>[];
  bool failed = false;
  String? loadError;
  bool retryable = false;

  @override
  Future<Map<String, dynamic>> getDetailedMediaInfoAsync() async => details;
  @override
  Future<Map<String, String?>> readMpvProperties(List<String> names) async {
    asked.add(names);
    return {for (final name in names) name: extras[name]};
  }

  @override
  bool get isMediaReady => !failed;
  @override
  bool get hasMediaLoadFailed => failed;
  @override
  String? get mediaLoadError => loadError;
  @override
  bool get mediaLoadErrorRetryable => retryable;
}

/// Classic's state with a failure as Classic leaves it: its text and step.
class FailingState extends ClassicPlayerState {
  FailingState(ReportingKernel super.kernel);
  String? failure;
  String? stage;
  String? path = '/media/episode.mkv';
  @override
  String? get error => failure;
  @override
  String? get errorStage => stage;
  @override
  String? get currentVideoPath => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlaybackFailures.instance.clear();
  });

  group('media facts', () {
    test('Media Kit values come from mpvProperties, which the old details '
        'lookup missed', () {
      final details = mediaKitDetails();
      // diagnostics.status read these keys at the top level and found none.
      expect([
        for (final key in ['videoCodec', 'audioCodec', 'videoWidth',
          'videoHeight', 'fps', 'hwdec', 'decoder', 'buffering'])
          if (details.containsKey(key)) key
      ], isEmpty);
      final facts = playerMediaFacts(
          kernel: 'media_kit',
          info: PlayerMediaInfo(duration: 1000),
          details: details,
          mpv: mpvExtras);
      expect(facts['video'], {
        'codec': 'h264',
        'width': 1920,
        'height': 1080,
        'displayWidth': 1920,
        'displayHeight': 1080,
        'pixelFormat': 'nv12',
        'hwPixelFormat': 'videotoolbox_vld',
        'fps': 23.976024,
        'measuredFps': 23.95,
        'bitrate': 2701394,
        'colorMatrix': 'bt.709',
        'colorPrimaries': 'bt.709',
        'transfer': 'bt.1886',
      });
      expect(facts['decoder'], {
        'name': 'h264 (H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10)',
        'hardware': true,
        'method': 'videotoolbox',
        'requested': 'auto-safe',
      });
      expect(facts['frames'], {
        'dropped': 3,
        'decoderDropped': 1,
        'mistimed': 0,
        'delayed': 2,
        'decoded': null,
        'rendered': null,
      });
      expect(facts['audio'], {
        'codec': 'aac',
        'decoder': 'aac (AAC (Advanced Audio Coding))',
        'sampleRate': 48000,
        'channels': 2,
        'channelLayout': 'stereo',
        'sampleFormat': 'floatp',
        'bitrate': 128000,
      });
      expect(facts['output'], {
        'videoOutput': 'libmpv',
        'gpuApi': 'opengl',
        'gpuContext': null,
        'rate': 1.5,
        'avsyncSeconds': -0.004,
      });
      expect(facts['cache'],
          {'aheadSeconds': 12.5, 'pausedForCache': false, 'bufferingPercent': 100});
      expect(facts['container'], {'format': 'matroska,webm', 'bitrate': null});
      expect(diagnosticsPlayerDetails(facts, buffering: false), {
        'videoCodec': 'h264',
        'audioCodec': 'aac',
        'videoWidth': 1920,
        'videoHeight': 1080,
        'fps': 23.976024,
        'hwdec': 'videotoolbox',
        'decoder': 'h264 (H.264 / AVC / MPEG-4 AVC / MPEG-4 part 10)',
        'hardwareDecoding': true,
        'droppedFrames': 3,
        'buffering': false,
      });
    });

    test('software decoding is false and what mpv does not give is null', () {
      final software = playerMediaFacts(
          kernel: 'media_kit',
          info: PlayerMediaInfo(duration: 0),
          details: mediaKitDetails(hwdec: 'no'));
      expect(software['decoder'],
          containsPair('hardware', false));
      expect(diagnosticsPlayerDetails(software, buffering: true)['hwdec'], 'no');
      final empty = playerMediaFacts(
          kernel: 'media_kit',
          info: PlayerMediaInfo(duration: 0),
          details: {'kernel': 'MediaKit', 'mpvProperties': {}});
      for (final section in ['video', 'decoder', 'frames', 'audio', 'output',
        'cache', 'container']) {
        expect((empty[section] as Map).values.every((v) => v == null), isTrue,
            reason: section);
      }
    });

    test('MDK reports typed streams and the decoder it opened', () {
      JsonMap facts(String? decoder) => playerMediaFacts(
          kernel: 'mdk',
          info: PlayerMediaInfo(duration: 1000),
          details: {'kernel': 'MDK'},
          streams: {
            'format': 'matroska,webm',
            'bitRate': 3100000,
            'video': [
              {'codec': 'hevc', 'bitRate': 0, 'frameRate': 23.976,
                'formatName': 'yuv420p10le', 'width': 3840, 'height': 2160}
            ],
            'audio': [
              {'codec': 'aac', 'bitRate': 128000, 'channels': 2,
                'sampleRate': 48000},
              {'codec': 'flac', 'bitRate': 0, 'channels': 6,
                'sampleRate': 96000},
            ],
            'videoDecoders': ['VT', 'hap', 'dav1d', 'FFmpeg'],
          },
          videoDecoder: decoder,
          activeAudio: 1);
      final hardware = facts('VT');
      expect(hardware['video'], containsPair('codec', 'hevc'));
      expect(hardware['video'], containsPair('fps', 23.976));
      expect(hardware['video'], containsPair('pixelFormat', 'yuv420p10le'));
      expect(hardware['video'], containsPair('bitrate', null));
      expect(hardware['container'],
          {'format': 'matroska,webm', 'bitrate': 3100000});
      expect(hardware['decoder'], {
        'name': 'VT',
        'hardware': true,
        'method': 'VT',
        'requested': 'VT,hap,dav1d,FFmpeg'
      });
      expect(hardware['audio'], containsPair('codec', 'flac'));
      expect(hardware['audio'], containsPair('channels', 6));
      expect((hardware['frames'] as Map).values.every((v) => v == null), isTrue);
      expect((facts('FFmpeg')['decoder'] as Map)['hardware'], isFalse);
      expect((facts('MFT:d3d=11')['decoder'] as Map)['hardware'], isTrue);
      expect((facts('hap')['decoder'] as Map)['hardware'], isNull);
      expect((facts(null)['decoder'] as Map)['hardware'], isNull);
    });

    test('Erika reports its decoder backend and frame counters', () {
      final facts = playerMediaFacts(
          kernel: 'erika',
          info: PlayerMediaInfo(duration: 1000),
          details: {
            'kernel': 'Erika',
            'decoder': {'activeBackend': 'software',
              'requestedBackend': 'vaapi', 'codec': 'av1',
              'pixelFormat': 'yuv420p'},
            'presenterStats': {'decodedVideoFrames': 240,
              'renderedVideoFrames': 238},
            'videoWidth': 1280,
            'videoHeight': 720,
          },
          videoDecoder: 'FFmpeg (software)');
      expect(facts['decoder'], {
        'name': 'FFmpeg (software)',
        'hardware': false,
        'method': 'software',
        'requested': 'vaapi'
      });
      expect(facts['frames'], containsPair('decoded', 240));
      expect(facts['frames'], containsPair('rendered', 238));
      expect(facts['video'], containsPair('codec', 'av1'));
      expect(facts['video'], containsPair('width', 1280));
    });

    test('playback.info reads the kernel through Player', () async {
      final kernel = ReportingKernel();
      final state = ClassicPlayerState(kernel);
      final harness = Harness(
          [PlaybackControlsCapability(ClassicPlaybackControls(state))]);
      final info = await invokeCompleted(harness, 'playback.info', {});
      expect(kernel.asked.single, mpvDiagnosticProperties);
      expect(info['kernel'], containsPair('id', 'media_kit'));
      expect(info['kernel'], containsPair('name', 'Media Kit'));
      expect((info['video'] as Map)['codec'], 'h264');
      expect((info['frames'] as Map)['dropped'], 3);
      expect((info['decoder'] as Map)['hardware'], isTrue);
      expect(info['danmakuRenderer'], isA<Map>());
      expect(info['sessionId'], startsWith('internal:'));
      expect((info['kernelDetails'] as Map)['diagnosticProperties'],
          containsPair('frame-drop-count', '3'));
    });
  });

  group('failure categories', () {
    test('kernel and player texts map to categories, the rest is unknown', () {
      const cases = {
        'Failed to recognize file format.': 'unsupported_format',
        'No video or audio streams selected.': 'unsupported_format',
        'tcp: Connection refused': 'network',
        'HTTP error 404 Not Found': 'source_failed',
        'HTTP error 403 Forbidden': 'unauthorized',
        'Permission denied': 'permission_denied',
        'No such file or directory': 'file_not_found',
        'Texture update timed out': 'timeout',
        '视频文件可能已损坏': null,
        '': null,
      };
      for (final entry in cases.entries) {
        expect(errorTextCategory(entry.key), entry.value, reason: entry.key);
      }
    });

    test('the local file comes first, then kernel, player and step', () {
      expect(
          playbackFailureCategory(
              stage: 'file_check',
              playerMessage: '文件不存在或无法访问',
              file: {'exists': true, 'readable': false}),
          'permission_denied');
      expect(
          playbackFailureCategory(
              stage: 'media_open',
              kernelMessage: 'HTTP error 404 Not Found',
              playerMessage: '播放器打开媒体失败: Texture update timed out'),
          'source_failed');
      expect(
          playbackFailureCategory(
              stage: 'initialize',
              playerMessage: '初始化视频播放器时出错: Texture update timed out'),
          'timeout');
      expect(playbackFailureCategory(stage: 'media_ready_timeout',
          playerMessage: '播放器打开媒体失败: 媒体未返回有效轨道或时长'), 'timeout');
      expect(playbackFailureCategory(stage: 'stream_session',
          playerMessage: '无法获取播放会话'), 'source_failed');
      expect(playbackFailureCategory(stage: 'invalid_media',
          playerMessage: '视频文件 "a.mkv" 可能已损坏或无法读取'), 'unknown');
      expect(playbackFailureCategory(), 'unknown');
    });

    test('a local file is probed for existence and readability', () async {
      final directory = await Directory.systemTemp.createTemp('pf-probe-');
      addTearDown(() => directory.delete(recursive: true));
      expect(await probeLocalFile('${directory.path}/missing.mkv'),
          {'exists': false, 'readable': null});
      final file = await File('${directory.path}/a.mkv').writeAsString('x');
      expect(await probeLocalFile(file.path),
          {'exists': true, 'readable': true});
      if (!Platform.isWindows) {
        await Process.run('chmod', ['000', file.path]);
        addTearDown(() => Process.run('chmod', ['644', file.path]));
        final unreadable = await probeLocalFile(file.path);
        expect(unreadable['exists'], isTrue);
        expect(unreadable['readable'], isFalse);
      }
    });
  });

  group('playback state', () {
    test('reports the effective rate, the boost, the kernel, the danmaku '
        'layer and the end of the video', () {
      final kernel = ReportingKernel();
      final state = ClassicPlayerState(kernel);
      final port = VideoPlayerStatePort(state);
      var json = port.snapshot().toJson();
      expect(json['rate'], 1);
      expect(json['effectiveRate'], 1);
      expect(json['speedBoost'], {'active': false, 'rate': state.speedBoostRate});
      expect(json['kernel'], {'id': 'media_kit', 'name': 'Media Kit'});
      expect((json['danmakuRenderer'] as Map)['id'], isIn(['cpu', 'gpu',
        'canvas', 'nipaplay_next', 'next2', 'dfm_plus']));
      expect(json['autoNext'], {
        'endAction': 'autoNext',
        'countingDown': false,
        'remainingSeconds': null,
        'next': null,
      });
      state.startSpeedBoost();
      json = port.snapshot().toJson();
      expect(json['rate'], 1);
      expect(json['effectiveRate'], state.speedBoostRate);
      expect(json['kernelRate'], state.speedBoostRate);
      expect(json['speedBoost'], {'active': true, 'rate': state.speedBoostRate});
      state.stopSpeedBoost();
      expect(port.snapshot().toJson()['effectiveRate'], 1);
    });

    test('an error carries its step, category and the kernel\'s own words',
        () {
      final kernel = ReportingKernel()
        ..failed = true
        ..loadError = 'Failed to recognize file format.';
      final state = FailingState(kernel)
        ..failure = '播放器打开媒体失败: Failed to recognize file format.'
        ..stage = 'media_open';
      final error = VideoPlayerStatePort(state).snapshot().error!;
      expect(error, containsPair('code', 'media_load_failed'));
      expect(error, containsPair('retryable', true));
      expect(error, containsPair('recoveryAction', 'playback.retry'));
      expect(error, containsPair('stage', 'media_open'));
      expect(error, containsPair('category', 'unsupported_format'));
      expect(error, containsPair('kernel', 'media_kit'));
      expect(error, containsPair('kernelRetryable', false));
      expect(error['messages'], {
        'player': '播放器打开媒体失败: Failed to recognize file format.',
        'kernel': 'Failed to recognize file format.',
        'media': null,
      });
    });

    test('a failure is recorded with the file it could not open, redacted',
        () async {
      final directory = await Directory.systemTemp.createTemp('pf-record-');
      addTearDown(() => directory.delete(recursive: true));
      final kernel = ReportingKernel();
      final state = FailingState(kernel)
        ..path = '${directory.path}/gone.mkv'
        ..failure = '文件不存在或无法访问'
        ..stage = 'file_check';
      final sessionId = VideoPlayerStatePort(state).snapshot().sessionId!;
      final failure = await PlaybackFailures.instance
          .record(captureClassicFailure(state, sessionId));
      expect(failure['category'], 'file_not_found');
      expect(failure['file'], {'exists': false, 'readable': null});
      expect(failure['stage'], 'file_check');
      expect(failure['kernel'], 'media_kit');
      expect(failure['failureId'], startsWith('pf-'));
      expect(failure.containsKey('_localPath'), isFalse);
      final error = VideoPlayerStatePort(state).snapshot().error!;
      expect(error['failureId'], failure['failureId']);

      final remote = FailingState(ReportingKernel()
        ..failed = true
        ..loadError = 'tcp: Connection refused https://h.example/v.mkv?api_key=SECRET')
        ..path = 'https://h.example/v.mkv?api_key=SECRET'
        ..failure = '播放器打开媒体失败: tcp: Connection refused'
        ..stage = 'media_open';
      final second = await PlaybackFailures.instance.record(
          captureClassicFailure(
              remote, VideoPlayerStatePort(remote).snapshot().sessionId!));
      expect(second['category'], 'network');
      expect(second['file'], isNull);
      expect('$second', isNot(contains('SECRET')));

      final harness = Harness(
          [PlaybackControlsCapability(ClassicPlaybackControls(remote))]);
      final listed =
          await invokeCompleted(harness, 'playback.failures', {'limit': 1});
      expect(listed['total'], 2);
      expect((listed['failures'] as List).single['failureId'],
          second['failureId']);
    });

    test('cancel_auto_next reports no countdown without touching one',
        () async {
      final state = ClassicPlayerState(ReportingKernel());
      final harness = Harness(
          [PlaybackControlsCapability(ClassicPlaybackControls(state))]);
      expect(harness.lookup('playback.cancel_auto_next')!.spec.effect,
          Effect.write);
      final result =
          await invokeCompleted(harness, 'playback.cancel_auto_next', {});
      expect(result['cancelled'], isFalse);
      expect(((result['state'] as Map)['autoNext'] as Map)['countingDown'],
          isFalse);
    });
  });

}

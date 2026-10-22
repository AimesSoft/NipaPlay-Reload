

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/capabilities/kernel_control.dart';
import 'package:nipaplay/next/capabilities/kernel_facts.dart';
import 'package:nipaplay/next/capabilities/video_player_state_port.dart';
import 'package:nipaplay/player_abstraction/erika_player_adapter.dart';
import 'package:nipaplay/player_abstraction/mdk_player_adapter_io.dart';
import 'package:nipaplay/next/settings/registry.dart' show SettingsAccess;
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player_test_support.dart';
import 'test_support.dart';

PlayerMediaInfo _tracks() => PlayerMediaInfo(
      duration: 24 * 60 * 1000,
      audio: [
        PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(name: 'flac'),
            language: 'jpn',
            rawRepresentation: 'audio 0'),
        PlayerAudioStreamInfo(
            codec: PlayerAudioCodecParams(name: 'aac'),
            title: '评论音轨',
            language: 'jpn',
            rawRepresentation: 'audio 1'),
      ],
      subtitle: [
        PlayerSubtitleStreamInfo(
            title: '简体中文', language: 'chs', rawRepresentation: 'subtitle 0'),
        PlayerSubtitleStreamInfo(
            title: '繁體中文', language: 'cht', rawRepresentation: 'subtitle 1'),
      ],
    );

/// Classic's Media Kit kernel with an mpv inside: what mpv holds, what it
/// is told, and mpv's own error for a property it does not have.
class MpvKernel extends ClassicKernel {
  final mpv = <String, String>{
    'mpv-version': 'mpv v0.40.0',
    'ffmpeg-version': '7.1.1',
    'hwdec': 'auto-copy',
    'hwdec-current': 'videotoolbox',
    'deband': 'no',
    'vf': '',
    'http-proxy': '',
    'external-files': '',
    'user-agent': 'NipaPlay/1.0',
  };
  final written = <String>[];

  MpvKernel() {
    mediaInfo = _tracks();
  }

  @override
  bool get isMediaReady => true;
  @override
  bool get hasMediaLoadFailed => false;
  @override
  String? get mediaLoadError => null;
  @override
  bool get mediaLoadErrorRetryable => false;

  @override
  Future<Map<String, ({String? value, String? error})>>
      readMpvPropertiesChecked(List<String> names) async => {
            for (final name in names)
              name: mpv.containsKey(name)
                  ? (value: mpv[name], error: null)
                  : (value: null, error: 'property not found'),
          };

  @override
  Future<String?> writeMpvProperty(String name, String value) async {
    if (!mpv.containsKey(name)) return 'property not found';
    written.add('$name=$value');
    mpv[name] = value;
    return null;
  }

  final commands = <List<String>>[];
  @override
  Future<({Object? result, String? error})> runMpvCommand(List<String> args,
      {Duration timeout = const Duration(seconds: 10)}) async {
    commands.add(args);
    switch (args.first) {
      case 'set':
        mpv[args[1]] = args[2];
        return (result: null, error: null);
      case 'vf':
        final vf = mpv['vf']!;
        mpv['vf'] = vf.isEmpty ? args[2] : '$vf,${args[2]}';
        return (result: null, error: null);
      case 'expand-text':
        return (result: 'expanded ${args[1]}', error: null);
      case 'subprocess':
        return (result: {'status': 0, 'stdout': 'hi'}, error: null);
      case 'load-script' || 'loadfile':
        return (result: null, error: null);
    }
    return (result: null, error: 'invalid parameter');
  }
}

/// MDK as NipaPlay's adapter shows it: the properties set on it, its
/// decoder lists and version.
class MdkKernel extends Fake implements MdkPlayerAdapter {
  MdkKernel({List<int>? audio, List<int>? subtitle})
      : activeAudioTracks = audio ?? [0],
        activeSubtitleTracks = subtitle ?? [0];
  final props = <String, String>{'auto_load': '0', 'subtitle': '1'};
  List<String> video = ['VT', 'FFmpeg'];
  List<String> audioDecoders = ['FFmpeg'];
  @override
  final buffering = ValueNotifier<bool>(false);
  @override
  final textureId = ValueNotifier<int?>(null);
  @override
  double volume = 1;
  @override
  double playbackRate = 1;
  @override
  PlayerPlaybackState state = PlayerPlaybackState.playing;
  @override
  PlayerMediaInfo mediaInfo = _tracks();
  @override
  List<int> activeAudioTracks;
  @override
  List<int> activeSubtitleTracks;
  @override
  int get position => 0;
  @override
  int get bufferedPosition => 0;
  @override
  String? getProperty(String key) => switch (key) {
        'decoder.video' => 'VT',
        'decoder.audio' => 'FFmpeg',
        _ => props[key],
      };
  @override
  void setProperty(String key, String value) => props[key] = value;
  @override
  List<String> getDecoders(PlayerMediaType type) =>
      type == PlayerMediaType.video ? video : audioDecoders;
  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {
    if (type == PlayerMediaType.video) {
      video = decoders;
    } else {
      audioDecoders = decoders;
    }
  }

  @override
  String? get nativeVersion => '0.33.1';
  @override
  void setPlaybackRate(double rate) => playbackRate = rate;
  @override
  void dispose() {}
  @override
  Future<void> disposeAsync() async {}
}

/// Erika as NipaPlay's adapter shows it; each read of its status is two
/// seconds and 48 decoded frames after the one before.
class ErikaKernel extends Fake implements ErikaPlayerAdapter {
  @override
  final buffering = ValueNotifier<bool>(false);
  @override
  final textureId = ValueNotifier<int?>(null);
  @override
  double volume = 1;
  @override
  double playbackRate = 1;
  @override
  PlayerPlaybackState state = PlayerPlaybackState.playing;
  @override
  PlayerMediaInfo mediaInfo = _tracks();
  @override
  List<int> activeAudioTracks = [0];
  @override
  List<int> activeSubtitleTracks = [0];
  @override
  int get position => 0;
  @override
  int get bufferedPosition => 0;
  @override
  void dispose() {}
  @override
  Future<void> disposeAsync() async {}

  final decoders = <PlayerMediaType, List<String>>{};
  final props = <String, String>{};
  @override
  String? getProperty(String key) => props[key];
  @override
  void setProperty(String key, String value) => props[key] = value;
  @override
  List<String> getDecoders(PlayerMediaType type) => decoders[type] ?? const [];
  @override
  void setDecoders(PlayerMediaType type, List<String> list) =>
      decoders[type] = list;

  bool hud = false;
  PlayerUpscalerMode upscaler = PlayerUpscalerMode.off;
  int reads = 0;
  int underflow = 0;

  @override
  bool get debugHudEnabled => hud;
  @override
  Future<void> setDebugHud(bool enabled) async => hud = enabled;
  @override
  Future<void> setUpscaler(PlayerUpscalerMode mode) async => upscaler = mode;
  @override
  Future<PlayerUpscalerStatus> getUpscalerStatus() async =>
      PlayerUpscalerStatus(
          requestedMode: upscaler,
          activeBackend: PlayerUpscalerBackendStatus.off,
          fallbackCount: 0,
          upscaledFrames: 0,
          lastEncodeDuration: Duration.zero,
          lastGpuDuration: Duration.zero);

  final invoked = <String>[];
  @override
  Future<({Object? result, String? error, bool supported})> invokeNative(
      String method, Map<String, Object?> arguments) async {
    invoked.add(method);
    return switch (method) {
      'getPresenterStats' =>
        (result: {'decodedVideoFrames': 1}, error: null, supported: true),
      'setOutputHeadroom' => (result: null, error: null, supported: true),
      'listMethods' => (
          result: {
            'schema': 1,
            'methods': [
              {'name': 'listMethods', 'scope': 'global'},
              {'name': 'pause', 'scope': 'presenter'},
            ],
          },
          error: null,
          supported: true
        ),
      _ => (
          result: null,
          error: 'Erika has no method $method on this platform',
          supported: false
        ),
    };
  }

  @override
  Future<Map<String, Object?>> readKernelStatus() async {
    final n = reads++;
    return {
      'presenterStats': {
        'decodedVideoFrames': 1000 + 48 * n,
        'renderedVideoFrames': 990 + 46 * n,
        'hardwareVideoFrames': 990 + 46 * n,
        'softwareVideoFrames': 0,
        'cpuVideoFrameFallbacks': 0,
        'videoFrameBackpressureDrops': n,
        'importFailures': 0,
        'renderFailures': 0,
        'audioFailures': 0,
        'audioClockUnderflowFrames': underflow,
        'audioRecoveryCount': 0,
        'audioRecoveryFailures': 0,
        'hdrSourceFrames': 1000 + 48 * n,
        'hdr10OutputFrames': 0,
        'sdrTonemapFrames': 1000 + 48 * n,
        'hdr10OutputActive': false,
      },
      'presenterStatsAt': DateTime.utc(2026, 10, 22, 12)
          .add(Duration(seconds: 2 * n))
          .toIso8601String(),
      'outputStatus': {
        'requestedMode': 'sdr',
        'activeEncoding': 'sdrSrgb',
        'extendedLinearActive': false,
        'fallbackReason': 'display_hdr_unsupported',
      },
      'resourceStatus': {'videoFrameBytes': 4096, 'drawableCount': 3},
      'upscalerStatus': {'requestedMode': upscaler.name},
      'tracks': [
        {
          'id': 1,
          'kind': 'video',
          'selected': true,
          'codec': 'hevc',
          'frameRateNumerator': 24000,
          'frameRateDenominator': 1001,
        }
      ],
      'decoder': {
        'stage': 'open_surface_to_bytebuffer',
        'requestedBackend': 'videoToolbox',
        'previousBackend': 'software',
        'activeBackend': 'videoToolbox',
        'fallbackCount': 0,
      },
      'audioOutput': null,
      'videoParams': {'width': 3840, 'height': 2160, 'primaries': 3, 'transfer': 2},
      'debugHud': hud,
      'lastError': null,
      'errors': <String, String>{},
      'diagnostics': {
        'schema': 1,
        'decoder': {'activeBackend': 'videotoolbox', 'hardware': true},
        'timing': {
          'scheduler': {'lateDroppedFrames': 3, 'presentedFrames': 990},
          'clock': {'lastDriftMs': 1.5, 'corrections': 2},
        },
        'media': {'video': {'codec': 'hevc'}},
        'note': 'from /Users/someone/Movies/secret.mkv?token=abc',
      },
    };
  }
}

/// Classic's player state with one media open, over the kernel given.
class KernelState extends VideoPlayerState {
  KernelState(AbstractPlayer kernel)
      : super.forSettings(Player.withDelegate(kernel));
  PlayerStatus playing = PlayerStatus.playing;
  String? path = '/media/episode.mkv';
  PlayableItem? request = PlayableItem(videoPath: '/media/episode.mkv');
  Duration at = const Duration(minutes: 3);

  @override
  PlayerStatus get status => playing;
  @override
  bool get isPaused => playing == PlayerStatus.paused;
  @override
  bool get hasVideo => const {
        PlayerStatus.ready,
        PlayerStatus.playing,
        PlayerStatus.paused
      }.contains(playing);
  @override
  Duration get position => at;
  @override
  Duration get duration => const Duration(minutes: 24);
  @override
  String? get currentVideoPath => path;
  @override
  PlayableItem? get lastPlaybackRequest => request;

  /// Classic opening another media: the request first, the file once open.
  void open(String next, {bool settle = true}) {
    request = PlayableItem(videoPath: next);
    playing = PlayerStatus.loading;
    notifyListeners();
    if (settle) {
      path = next;
      playing = PlayerStatus.playing;
      notifyListeners();
    }
  }

  void notify() => notifyListeners();
}

/// Classic's kernel switch, recorded: the new player is what [make] gives.
class Switches {
  Switches(this.make);
  final AbstractPlayer Function(PlayerKernelType? kernel) make;
  final calls = <(PlayerKernelType?, String?)>[];
  Future<void> call(VideoPlayerState state, PlayerKernelType? kernel,
      PlayableItem? request) async {
    calls.add((kernel, request?.videoPath));
    state.player = Player.withDelegate(make(kernel));
  }
}

Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Classic's state once what it sets up on a new player has run.
Future<KernelState> opened(AbstractPlayer kernel) async {
  final state = KernelState(kernel);
  await settle();
  await Future<void>.delayed(const Duration(milliseconds: 20));
  return state;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ({Harness harness, KernelControl control, Switches switches, List<String> asked})
      rig(KernelState state,
          {bool approve = true,
          PlayerKernelType configured = PlayerKernelType.mediaKit,
          List<PlayerKernelType> supported = PlayerKernelType.values,
          String? harness,
          PlayerKernelType Function()? live,
          AbstractPlayer Function(PlayerKernelType?)? make}) {
    final asked = <String>[];
    final switches = Switches(make ??
        (kernel) => kernel == PlayerKernelType.mdk ? MdkKernel() : MpvKernel());
    final stored = live ?? () => configured;
    final control = KernelControl(state,
        consent: (title, message, accept, stopped) async {
          asked.add('$title\n$message\n$accept');
          return approve;
        },
        // Classic's switch builds the player with Player(), which takes what
        // it was built from off the list of saves waiting for a rebuild.
        switcher: (state, kernel, request) async {
          await switches.call(state, kernel, request);
          DeferredReloads.built(kernel ?? stored(), stored());
        },
        configured: stored,
        supported: () => supported,
        harness: () => harness);
    addTearDown(() => control.release(reopen: false));
    return (
      harness: Harness([KernelControlCapability(control)]),
      control: control,
      switches: switches,
      asked: asked
    );
  }

  String session(KernelState state) =>
      VideoPlayerStatePort(state).snapshot().sessionId!;

  group('reading', () {
    test('Media Kit: mpv and ffmpeg versions, a snapshot and the properties '
        'asked for with mpv\'s own error', () async {
      final kernel = MpvKernel();
      final r = rig(await opened(kernel));
      final read = await invokeCompleted(r.harness, 'playback.kernel', {
        'properties': ['deband', 'no-such-property']
      });
      expect(read['kernel'], {
        'id': 'media_kit',
        'name': 'Media Kit',
        'configured': 'media_kit',
        'version': {'mpv': 'mpv v0.40.0', 'ffmpeg': '7.1.1'},
      });
      final snapshot = read['snapshot'] as Map;
      expect(snapshot['hwdec'], 'auto-copy');
      expect(snapshot['hwdec-current'], 'videotoolbox');
      expect(snapshot['vf'], '', reason: 'an empty value stays empty');
      expect(snapshot['gpu-api'], isNull, reason: 'mpv gave none');
      expect(read['properties'], {
        'deband': {'value': 'no', 'error': null},
        'no-such-property': {'value': null, 'error': 'property not found'},
      });
      expect((read['controls'] as Map)['properties'],
          {'read': 'any_mpv_property', 'write': 'any_mpv_property'});
      expect((read['controls'] as Map)['reopenWith'],
          ['mdk', 'video_player', 'media_kit', 'erika']);
      expect(read['overrides'], isEmpty);
    });

    test('MDK: its version, decoder lists and the properties set on it',
        () async {
      final kernel = MdkKernel();
      final r = rig(await opened(kernel));
      final read = await invokeCompleted(r.harness, 'playback.kernel', {
        'properties': ['avformat.fflags']
      });
      expect(read['kernel'], containsPair('id', 'mdk'));
      expect((read['kernel'] as Map)['version'], {'mdk': '0.33.1'});
      expect(read['decoders'], {
        'video': kernel.video,
        'audio': ['FFmpeg'],
        'activeVideo': 'VT',
        'activeAudio': 'FFmpeg',
      });
      expect((read['snapshot'] as Map)['auto_load'], '0');
      expect((read['snapshot'] as Map)['keep_open'], isNull);
      expect(read['properties'], {
        'avformat.fflags': {'value': null, 'error': null}
      });
      expect((read['controls'] as Map)['decoders'], ['video', 'audio']);
    });

    test('Erika: decoder, frame, audio and HDR facts as reported, a window '
        'between reads, and what it does not expose', () async {
      final kernel = ErikaKernel();
      final r = rig(await opened(kernel));
      final first = (await invokeCompleted(r.harness, 'playback.kernel', {}))[
          'erika'] as Map;
      expect(first['window'], isNull);
      expect(first['windowUnavailable'], 'no_previous_read');
      expect(first['decoder'], containsPair('hardware', true));
      expect(first['decoder'], containsPair('fellBack', true));
      expect(first['decoder'], containsPair('activeBackend', 'videoToolbox'));
      expect((first['frames'] as Map)['nominalFps'], 23.976);
      expect((first['frames'] as Map)['lateDropped'], 3);
      final diagnostics = first['diagnostics'] as Map;
      expect(diagnostics['schema'], 1);
      expect(((diagnostics['timing'] as Map)['clock'] as Map)['corrections'], 2);
      expect(diagnostics['note'], isNot(contains('token=abc')));
      expect((first['hdr'] as Map)['sdrTonemapFrames'], 1000);
      expect((first['hdr'] as Map)['videoTransfer'], 2);
      expect((first['hdr'] as Map)['metadata'], isNull);
      expect(((first['hdr'] as Map)['output'] as Map)['fallbackReason'],
          'display_hdr_unsupported');
      expect(first['resources'], {'videoFrameBytes': 4096, 'drawableCount': 3});
      expect(first['debugHud'], false);
      expect(first['notReported'],
          containsAll(['network.throughput', 'hdr.metadata']));
      expect(first['notReported'],
          isNot(anyOf(contains('frames.lateDropped'), contains('sync.driftMs'))));

      kernel.underflow = 512;
      final second = (await invokeCompleted(r.harness, 'playback.kernel', {}))[
          'erika'] as Map;
      final window = second['window'] as Map;
      expect(window['source'], 'previous_read');
      expect(window['seconds'], 2.0);
      expect(window['decodedFrames'], 48);
      expect(window['decodedFps'], 24.0);
      expect(window['renderedFps'], 23.0);
      expect(window['audioUnderflowFrames'], 512);
      expect(window['backpressureDrops'], 1);
      expect(window['sdrTonemapFrames'], 48);
      expect(window['paused'], false);

      final sampled = (await invokeCompleted(
          r.harness, 'playback.kernel', {'sampleMs': 500}))['erika'] as Map;
      expect((sampled['window'] as Map)['source'], 'sampled');
      expect((sampled['window'] as Map)['decodedFrames'], 48);
    });

    test('which Erika methods only read', () {
      expect(erikaReadsOnly('listMethods', const {}), true);
      expect(erikaReadsOnly('getDiagnosticsSnapshot', const {}), true);
      expect(erikaReadsOnly('trackSelection', const {}), true);
      expect(erikaReadsOnly('pause', const {}), false);
      expect(erikaReadsOnly('invokeJson', const {'method': 'getLogs'}), true);
      expect(erikaReadsOnly('invokeJson', const {'method': 'seek'}), false);
      expect(erikaReadsOnly('invokeJson', const {'method': 'invokeJson'}),
          false);
    });

    test('a reset of Erika\'s counters gives no window', () {
      final at = DateTime.utc(2026);
      final result = erikaWindow(
          ErikaSample(at, 1, '/a', {'decodedVideoFrames': 500}),
          ErikaSample(at.add(const Duration(seconds: 3)), 1, '/a',
              {'decodedVideoFrames': 20}),
          source: 'previous_read');
      expect(result.window, isNull);
      expect(result.reason, 'counters_reset');
      expect(
          erikaWindow(ErikaSample(at, 1, '/a', const {}),
                  ErikaSample(at.add(const Duration(seconds: 3)), 2, '/a', const {}),
                  source: 'previous_read')
              .reason,
          'player_changed');
    });
  });

  group('changing for this playback', () {
    test('mpv takes the value now, later files do not inherit it, and '
        'another media puts the original back', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final options = Map.of(kernel.properties);
      final result = await invokeCompleted(r.harness,
          'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'hwdec': 'no', 'deband': 'yes', 'vf': 'hflip'},
      });
      final changes = (result['changes'] as List).cast<Map>();
      expect(changes.first, containsPair('before', 'auto-copy'));
      expect(changes.first, containsPair('requested', 'no'));
      expect(changes.first, containsPair('after', 'no'));
      expect(changes.first, containsPair('error', null));
      expect(changes.first, containsPair('restorable', true));
      expect(kernel.mpv['hwdec'], 'no');
      // Not one of the options Classic gives each file it opens.
      expect(kernel.properties, options);

      // Classic itself changes vf before the media changes.
      kernel.mpv['vf'] = 'vflip';
      state.open('/media/episode-2.mkv');
      await settle();
      expect(kernel.mpv['hwdec'], 'auto-copy');
      expect(kernel.mpv['deband'], 'no');
      expect(kernel.mpv['vf'], 'vflip', reason: 'changed since: left as is');
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      final restores = [
        for (final c in (read['changes'] as List).cast<Map>())
          if (c['action'] == 'restore') c
      ];
      expect({for (final c in restores) c['name']: c['trigger']},
          {'hwdec': 'media_changed', 'deband': 'media_changed', 'vf': 'media_changed'});
      expect(restores.firstWhere((c) => c['name'] == 'vf')['restored'], false);
      expect(restores.firstWhere((c) => c['name'] == 'vf')['reason'],
          'changed_since');
      expect(
          restores.firstWhere((c) => c['name'] == 'hwdec')['restored'], true);
      expect(r.switches.calls, isEmpty, reason: 'mpv restored in place');
    });

    test('retrying the same media keeps the changes', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'hwdec': 'no'},
      });
      state.open('/media/episode.mkv');
      await settle();
      expect(kernel.mpv['hwdec'], 'no');
      expect(
          (await invokeCompleted(r.harness, 'playback.kernel', {}))['overrides'],
          hasLength(1));
    });

    test('each change is recorded with who and when, and restore puts the '
        'original back', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final outcome = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': session(state),
            'properties': {'hwdec': 'no'},
          },
          Invocation(origin: 'conversation:main', id: 'inv-1'));
      expect(outcome, isA<Completed>());
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'hwdec': 'vaapi'},
      });
      var read = await invokeCompleted(r.harness, 'playback.kernel', {});
      final override = (read['overrides'] as List).single as Map;
      expect(override['original'], 'auto-copy');
      expect(override['current'], 'vaapi');
      expect(override['changeIds'], hasLength(2));
      final first = (read['changes'] as List).cast<Map>().last;
      expect(first['action'], 'set');
      expect(first['origin'], 'conversation:main');
      expect(first['invocationId'], 'inv-1');
      expect(first['before'], 'auto-copy');
      expect(first['after'], 'no');
      expect(first['at'], isA<String>());

      final restored = await invokeCompleted(
          r.harness, 'playback.restore_kernel_properties', {
        'names': ['hwdec', 'deband']
      });
      expect(restored['restored'], [
        containsPair('restored', true),
        {'name': 'deband', 'restored': false, 'reason': 'not_changed'},
      ]);
      expect((restored['restored'] as List).first,
          containsPair('after', 'auto-copy'));
      expect(kernel.mpv['hwdec'], 'auto-copy');
      read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      expect((read['changes'] as List).first, containsPair('action', 'restore'));
    });

    test('a setting that can send traffic elsewhere waits for the person, '
        'and a no changes nothing', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final declined = rig(state, approve: false);
      final outcome = await declined.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': session(state),
            'properties': {
              'http-proxy': 'http://user:secret@proxy.example:8080',
              'deband': 'yes'
            },
          },
          Invocation(origin: 'test'));
      expect(outcome, isA<Failed>());
      expect((outcome as Failed).failure.code, FailureCode.conflict);
      expect(outcome.failure.message, '用户没有同意这次播放使用这些网络设置');
      expect(kernel.mpv['http-proxy'], '');
      expect(kernel.mpv['deband'], 'no');
      expect(declined.asked.single, contains('http-proxy'));
      expect(declined.asked.single, isNot(contains('secret')));

      final allowed = rig(state);
      final result = await invokeCompleted(
          allowed.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'external-files': 'https://example.com/a.ass'},
      });
      expect(allowed.asked, hasLength(1));
      expect((result['changes'] as List).single,
          containsPair('consent', 'user_approved'));
      expect(kernel.mpv['external-files'], 'https://example.com/a.ass');
      expect(kernelSettingConsent('hwdec', 'no'), isNull);
      for (final name in ['user-agent', 'http-header-fields', 'cookies-file',
        'tls-verify', 'referrer', 'avio.http_proxy', 'avformat.headers']) {
        expect(kernelSettingConsent(name, 'x'), 'network', reason: name);
      }
      expect(kernelSettingConsent('stream-lavf-o', 'http_proxy=http://p:1'),
          'network');
      expect(kernelSettingConsent('stream-lavf-o', 'reconnect=1'), isNull);
      expect(kernelSettingConsent('script-opts', 'osc-visibility=never'),
          isNull);
    });

    test('MDK: decoders go back with the media; a property MDK never '
        'reported makes the next media open on a fresh player', () async {
      final kernel = MdkKernel();
      final state = await opened(kernel);
      final r = rig(state, configured: PlayerKernelType.mdk);
      final decoders = kernel.video;
      final result = await invokeCompleted(
          r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'video.avfilter': 'hflip', 'auto_load': '1'},
        'videoDecoders': ['FFmpeg', 'dav1d'],
      });
      final changes = {
        for (final c in (result['changes'] as List).cast<Map>()) c['name']: c
      };
      expect(changes['video.avfilter'], containsPair('restorable', false));
      expect(changes['auto_load'], containsPair('before', '0'));
      expect(changes['videoDecoders'], containsPair('before', decoders));
      expect(kernel.video, ['FFmpeg', 'dav1d']);
      expect(result['nextMediaOpensFreshPlayer'], true);

      state.open('/media/episode-2.mkv', settle: false);
      await settle();
      expect(kernel.video, decoders);
      expect(kernel.props['auto_load'], '0');
      expect(r.switches.calls, isEmpty, reason: 'waits for the media to open');
      state.path = '/media/episode-2.mkv';
      state.playing = PlayerStatus.ready;
      state.notify();
      await settle();
      expect(r.switches.calls, isEmpty,
          reason: 'open, but its play() has not taken yet');
      state.playing = PlayerStatus.playing;
      state.notify();
      await settle();
      expect(r.switches.calls, [(null, '/media/episode-2.mkv')]);
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      expect(read['nextMediaOpensFreshPlayer'], false);
      expect((read['changes'] as List).first,
          allOf(containsPair('action', 'revert'),
              containsPair('trigger', 'media_changed')));
    });

    test('Erika: upscaler and debug HUD for this media, others refused',
        () async {
      final kernel = ErikaKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final result = await invokeCompleted(
          r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'upscaler': 'artCnnC4F16', 'debugHud': 'true'},
      });
      expect((result['changes'] as List).cast<Map>().map((c) =>
          [c['name'], c['before'], c['after']]), [
        ['upscaler', 'off', 'artCnnC4F16'],
        ['debugHud', 'false', 'true'],
      ]);
      expect(kernel.hud, isTrue);
      final refused = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': session(state),
            'properties': {'hwdec': 'no'},
          },
          Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.invalidInput);
      expect(refused.failure.message, contains('upscaler'));
      state.open('/media/episode-2.mkv');
      await settle();
      expect(kernel.hud, isFalse);
      expect(kernel.upscaler, PlayerUpscalerMode.off);
    });

    test('a session that changed is refused', () async {
      final state = await opened(MdkKernel());
      final r = rig(state);
      final outcome = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {'sessionId': 'internal:other', 'properties': {'a': 'b'}},
          Invocation(origin: 'test'));
      expect((outcome as Failed).failure.code, FailureCode.conflict);
    });
  });

  group('reopening on another kernel', () {
    test('a paused media is reported paused once the new player has paused',
        () async {
      final state = await opened(MpvKernel())..playing = PlayerStatus.paused;
      final r = rig(state, make: (kernel) {
        // Classic's reopen plays the media, then pauses it; each takes effect
        // only once the kernel answers.
        state.playing = PlayerStatus.playing;
        Timer(const Duration(milliseconds: 150),
            () => state.playing = PlayerStatus.paused);
        return MdkKernel();
      });
      final result = await invokeCompleted(r.harness,
          'playback.reopen_with_kernel', {
        'sessionId': session(state),
        'kernel': 'mdk',
      });
      expect((result['preserved'] as Map)['paused'],
          {'before': true, 'after': true});
    });

    test('carries position, pause, tracks and reports the kernel running; '
        'the next media opens on the kernel setting', () async {
      final kernel = MpvKernel()
        ..activeAudioTracks = [1]
        ..activeSubtitleTracks = [1];
      final state = await opened(kernel);
      final mdkKernel = MdkKernel(audio: [0], subtitle: [0]);
      final r = rig(state,
          make: (type) => type == PlayerKernelType.mdk ? mdkKernel : MpvKernel());
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'hwdec': 'no'},
      });
      final result = await invokeCompleted(r.harness,
          'playback.reopen_with_kernel', {
        'sessionId': session(state),
        'kernel': 'mdk',
      });
      expect(r.switches.calls, [(PlayerKernelType.mdk, '/media/episode.mkv')]);
      expect(result['kernel'], {
        'requested': 'mdk',
        'actual': 'mdk',
        'name': 'MDK',
        'configured': 'media_kit',
      });
      expect(result['opened'], true);
      expect(result['replaced'], true);
      final preserved = result['preserved'] as Map;
      expect(preserved['positionMs'], {'before': 180000, 'after': 180000});
      expect(preserved['audioTrack'], containsPair('reapplied', true));
      expect(preserved['subtitleTrack'], containsPair('reapplied', true));
      expect(mdkKernel.activeAudioTracks, [1]);
      expect(mdkKernel.activeSubtitleTracks, [1]);
      expect(result['nextMediaOpensConfiguredKernel'], true);
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      expect(read['kernelOverride'], containsPair('kernel', 'mdk'));
      expect((read['changes'] as List).cast<Map>().map((c) => c['action']),
          containsAll(['reopen', 'ended', 'set']));

      state.open('/media/episode-2.mkv');
      await settle();
      expect(r.switches.calls.last, (null, '/media/episode-2.mkv'));
      expect(state.player.getPlayerKernelName(), 'Media Kit');
      expect((await invokeCompleted(r.harness, 'playback.kernel', {}))[
          'kernelOverride'], isNull);
    });

    test('a kernel this device cannot run is refused', () async {
      final state = await opened(MpvKernel());
      final r = rig(state,
          supported: [PlayerKernelType.mdk, PlayerKernelType.mediaKit]);
      final outcome = await r.harness.invokeJson('playback.reopen_with_kernel',
          {'sessionId': session(state), 'kernel': 'erika'},
          Invocation(origin: 'test'));
      expect((outcome as Failed).failure.code, FailureCode.unavailable);
      expect(r.switches.calls, isEmpty);
    });

    test('turning Next off puts everything back', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': session(state),
        'properties': {'hwdec': 'no'},
      });
      await r.control.release();
      expect(kernel.mpv['hwdec'], 'auto-copy');
      expect(r.switches.calls, isEmpty);

      await invokeCompleted(r.harness, 'playback.reopen_with_kernel',
          {'sessionId': session(state), 'kernel': 'mdk'});
      await r.control.release();
      expect(r.switches.calls.last.$1, isNull);
      expect(state.player.getPlayerKernelName(), 'Media Kit');
    });
  });

  group('passing through', () {
    test('an mpv command goes to mpv as given; one that changes a property '
        'holds for this media like a property change', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final vf = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': session(state),
        'command': ['vf', 'add', 'hflip'],
      });
      expect(kernel.commands.single, ['vf', 'add', 'hflip']);
      expect(vf['property'], {
        'name': 'vf',
        'before': '',
        'after': 'hflip',
        'restorable': true,
      });
      expect(vf['lasting'], 'property');
      expect(vf['error'], isNull);

      final text = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': session(state),
        'command': ['expand-text', r'${hwdec-current}'],
      });
      expect(text['result'], r'expanded ${hwdec-current}');
      expect(text['lasting'], 'none');
      expect(text['nextMediaOpensFreshPlayer'], false);

      final bogus = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': session(state),
        'command': ['no-such-command'],
      });
      expect(bogus['error'], 'invalid parameter');
      expect(bogus['nextMediaOpensFreshPlayer'], false);

      final program = await invokeCompleted(
          r.harness, 'playback.kernel_command', {
        'sessionId': session(state),
        'command': ['subprocess', 'curl', 'https://example.com'],
      });
      expect(r.asked, isEmpty, reason: 'running a program does not wait');
      expect(program['result'], {'status': 0, 'stdout': 'hi'});

      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect((read['changes'] as List).cast<Map>().map((c) => c['action']),
          everyElement('command'));
      expect((read['changes'] as List).last,
          containsPair('command', ['vf', 'add', 'hflip']));
      state.open('/media/episode-2.mkv');
      await settle();
      expect(kernel.mpv['vf'], '');
      expect(r.switches.calls, isEmpty);
    });

    test('load-script takes a script in the harness; a command whose effect '
        'may stay makes the next media open on a fresh player', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final harness = await Directory.systemTemp.createTemp('kc-harness-');
      addTearDown(() => harness.delete(recursive: true));
      final script = File('${harness.path}/scripts/probe.lua');
      await script.create(recursive: true);
      final r = rig(state, harness: harness.path);
      final outside = await r.harness.invokeJson('playback.kernel_command', {
        'sessionId': session(state),
        'command': ['load-script', '/etc/hosts'],
      }, Invocation(origin: 'test'));
      expect((outside as Failed).failure.code, FailureCode.invalidInput);
      expect(kernel.commands, isEmpty);
      final loaded = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': session(state),
        'command': ['load-script', script.path],
      });
      expect(loaded['lasting'], 'unknown');
      expect(loaded['nextMediaOpensFreshPlayer'], true);
      state.open('/media/episode-2.mkv');
      await settle();
      expect(r.switches.calls, [(null, '/media/episode-2.mkv')]);
    });

    test('a command that would send traffic elsewhere waits for the person',
        () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state, approve: false);
      final outcome = await r.harness.invokeJson('playback.kernel_command', {
        'sessionId': session(state),
        'command': ['loadfile', 'https://user:pw@example.com/v.mkv'],
      }, Invocation(origin: 'test'));
      expect((outcome as Failed).failure.message, '用户没有同意这次播放使用这些网络设置');
      expect(kernel.commands, isEmpty);
      expect(r.asked.single, isNot(contains('pw@')));
      expect(kernelCommandConsent(['set', 'http-proxy', 'http://p:1']),
          'network');
      expect(kernelCommandConsent(['no-osd', 'set', 'deband', 'yes']), isNull);
      expect(mpvCommandProperty(['no-osd', 'cycle-values', '!reverse', 'hwdec',
        'no', 'auto']), 'hwdec');
    });

    test('Erika takes a method as given, or says it has none', () async {
      final kernel = ErikaKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final read = await invokeCompleted(r.harness, 'playback.kernel_invoke', {
        'sessionId': session(state),
        'method': 'getPresenterStats',
      });
      expect(read['supported'], true);
      expect(read['result'], {'decodedVideoFrames': 1});
      expect(read['nextMediaOpensFreshPlayer'], false);
      final missing = await invokeCompleted(r.harness, 'playback.kernel_invoke', {
        'sessionId': session(state),
        'method': 'getDiagnosticsJson',
      });
      expect(missing['supported'], false);
      expect(missing['error'], contains('no method'));
      final set = await invokeCompleted(r.harness, 'playback.kernel_invoke', {
        'sessionId': session(state),
        'method': 'setOutputHeadroom',
        'arguments': {'headroom': 2.0},
      });
      expect(set['nextMediaOpensFreshPlayer'], true);
      final table = await invokeCompleted(r.harness, 'playback.kernel_invoke', {
        'sessionId': session(state),
        'method': 'listMethods',
      });
      expect(((table['result'] as Map)['methods'] as List).first,
          containsPair('name', 'listMethods'));
      expect(kernel.invoked, contains('listMethods'));
      final mpv = rig(await opened(MpvKernel()));
      final refused = await mpv.harness.invokeJson('playback.kernel_invoke', {
        'sessionId': 'x',
        'method': 'm',
      }, Invocation(origin: 'test'));
      expect(refused, isA<Failed>());
    });

    test('watching reads once, or each change over a bounded time', () async {
      final kernel = MpvKernel();
      final state = await opened(kernel);
      final r = rig(state);
      final once = await invokeCompleted(r.harness,
          'playback.watch_kernel_properties', {
        'properties': ['hwdec-current', 'nothing-here'],
      });
      expect(once['samples'], 1);
      expect(once['changes'], isEmpty);
      expect(once['endedBy'], 'duration');
      expect(once['initial'], {
        'hwdec-current': {'value': 'videotoolbox', 'error': null},
        'nothing-here': {'value': null, 'error': 'property not found'},
      });
      Timer(const Duration(milliseconds: 250),
          () => kernel.mpv['hwdec-current'] = 'no');
      final watched = await invokeCompleted(r.harness,
          'playback.watch_kernel_properties', {
        'properties': ['hwdec-current'],
        'durationMs': 700,
        'intervalMs': 100,
      });
      expect((watched['changes'] as List).single,
          allOf(containsPair('name', 'hwdec-current'),
              containsPair('value', 'no')));
      expect(watched['final'], {
        'hwdec-current': {'value': 'no', 'error': null}
      });
      expect(watched['samples'], greaterThan(3));
      final erika = rig(await opened(ErikaKernel()));
      final refused = await erika.harness.invokeJson(
          'playback.watch_kernel_properties', {
        'properties': ['x'],
      }, Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.unavailable);
    });
  });

  group('settings saved by Next', () {
    // The kernel setting is stored; the player in use runs the other one.
    Future<T> inNext<T>(Future<T> Function() body) => runZoned(body,
        zoneValues: {SettingsAccess.invocationKey: Invocation(origin: 'mcp')});

    setUp(() async {
      DeferredReloads.reset();
      await PlayerFactory.saveKernelType(PlayerKernelType.mdk);
      await PlayerFactory.saveHttpProxy('');
    });
    tearDown(() async {
      DeferredReloads.reset();
      await PlayerFactory.saveHttpProxy('');
    });

    test('with no media open the player is rebuilt on the stored values now',
        () async {
      final state = await opened(MdkKernel());
      state.path = null;
      final r = rig(state, live: PlayerFactory.getKernelType);
      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mediaKit));
      await settle();
      expect(r.switches.calls, [(null, '/media/episode.mkv')]);
      expect(state.player.getPlayerKernelName(), 'Media Kit');
      expect(DeferredReloads.pendingFor(PlayerKernelType.mediaKit), false);
      state.open('/media/next.mkv');
      await settle();
      expect(r.switches.calls, hasLength(1), reason: 'nothing is left to apply');
    });

    test('media being watched is not interrupted; the next one opens on the '
        'stored values, once', () async {
      final state = await opened(MdkKernel());
      final r = rig(state, live: PlayerFactory.getKernelType);
      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mediaKit));
      await settle();
      expect(r.switches.calls, isEmpty);
      expect(state.player.getPlayerKernelName(), 'MDK');
      expect(DeferredReloads.pendingFor(PlayerKernelType.mediaKit), true);

      state.open('/media/next.mkv');
      await settle();
      expect(r.switches.calls, [(null, '/media/next.mkv')]);
      expect(state.player.getPlayerKernelName(), 'Media Kit');
      expect(DeferredReloads.pendingFor(PlayerKernelType.mediaKit), false);
      state.open('/media/third.mkv');
      await settle();
      expect(r.switches.calls, hasLength(1));
    });

    test('opening the same file again on the same player counts as an open',
        () async {
      final state = await opened(MdkKernel());
      final r = rig(state, live: PlayerFactory.getKernelType);
      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mediaKit));
      await settle();
      state.open('/media/episode.mkv');
      await settle();
      expect(r.switches.calls, [(null, '/media/episode.mkv')]);
    });

    test('a save back to what the player was built with leaves nothing '
        'waiting', () async {
      final state = await opened(MdkKernel());
      final r = rig(state, live: PlayerFactory.getKernelType);
      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mediaKit));
      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mdk));
      state.open('/media/next.mkv');
      await settle();
      expect(r.switches.calls, isEmpty);
    });

    test('with a reopen_with_kernel override in force the next media is '
        'switched once, for both', () async {
      await PlayerFactory.saveKernelType(PlayerKernelType.mediaKit);
      final state = await opened(MpvKernel());
      final r = rig(state,
          live: PlayerFactory.getKernelType,
          make: (kernel) =>
              kernel == PlayerKernelType.mdk ? MdkKernel() : MpvKernel());
      await invokeCompleted(r.harness, 'playback.reopen_with_kernel',
          {'sessionId': session(state), 'kernel': 'mdk'});
      await inNext(() => PlayerFactory.saveHttpProxy('http://127.0.0.1:7890'));
      await settle();
      expect(r.switches.calls, [(PlayerKernelType.mdk, '/media/episode.mkv')]);

      state.open('/media/next.mkv');
      await settle();
      expect(r.switches.calls, [
        (PlayerKernelType.mdk, '/media/episode.mkv'),
        (null, '/media/next.mkv'),
      ], reason: 'one switch puts back the kernel and applies the proxy');
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['kernelOverride'], isNull);
      expect(read['nextMediaOpensFreshPlayer'], false);
    });

    test('a reopen_with_kernel after a pending save keeps its own record',
        () async {
      await PlayerFactory.saveKernelType(PlayerKernelType.mediaKit);
      final state = await opened(MpvKernel());
      final r = rig(state,
          live: PlayerFactory.getKernelType,
          make: (kernel) =>
              kernel == PlayerKernelType.mdk ? MdkKernel() : MpvKernel());
      await inNext(() => PlayerFactory.saveHttpProxy('http://127.0.0.1:7890'));
      final result = await invokeCompleted(r.harness,
          'playback.reopen_with_kernel',
          {'sessionId': session(state), 'kernel': 'mdk'});
      expect(r.switches.calls, [(PlayerKernelType.mdk, '/media/episode.mkv')],
          reason: 'the pending save did not switch the player on its own');
      expect(result['nextMediaOpensConfiguredKernel'], true);
      expect((await invokeCompleted(r.harness, 'playback.kernel', {}))[
          'kernelOverride'], containsPair('kernel', 'mdk'));

      state.open('/media/next.mkv');
      await settle();
      expect(r.switches.calls, hasLength(2));
      expect(r.switches.calls.last, (null, '/media/next.mkv'));
      state.open('/media/third.mkv');
      await settle();
      expect(r.switches.calls, hasLength(2));
    });

    test('Classic (outside a Next call) still rebuilds at once through the '
        'kernel change event', () async {
      final events = <PlayerKernelType>[];
      final subscription = PlayerFactory.onKernelChanged.listen(events.add);
      addTearDown(subscription.cancel);
      await PlayerFactory.saveKernelType(PlayerKernelType.mediaKit);
      await settle();
      expect(events, [PlayerKernelType.mediaKit]);
      expect(DeferredReloads.pendingFor(PlayerKernelType.mediaKit), false);

      await inNext(() => PlayerFactory.saveKernelType(PlayerKernelType.mdk));
      await settle();
      expect(events, [PlayerKernelType.mediaKit],
          reason: 'a Next call does not broadcast');
    });
  });

}

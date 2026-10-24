import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/kernel_control.dart';
import 'package:nipaplay/next/capabilities/kernel_facts.dart';
import 'package:nipaplay/next/capabilities/media_models.dart';
import 'package:nipaplay/next/player/core/session.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/kernel/native.dart';
import 'package:nipaplay/next/player/next_playback.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'player/fake_driver.dart';
import 'test_support.dart';

/// An mpv inside a kernel instance: what mpv holds, what it is told, and
/// mpv's own error for a property it does not have.
class FakeMpv implements MpvNative {
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
  final commands = <List<String>>[];
  final logFiles = <String>[];

  @override
  Future<Object?> version() async => null;
  @override
  Future<Map<String, NativeRead>> read(List<String> names) async => {
        for (final name in names)
          name: mpv.containsKey(name)
              ? (value: mpv[name], error: null)
              : (value: null, error: 'property not found'),
      };
  @override
  Future<String?> write(String name, String value) async {
    if (!mpv.containsKey(name)) return 'property not found';
    mpv[name] = value;
    return null;
  }

  @override
  Future<NativeReply> command(List<String> args,
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

  @override
  Future<void> logFile(String path) async => logFiles.add(path);
}

/// MDK: the properties set on it, its decoder lists.
class FakeMdk implements MdkNative {
  final props = <String, String>{'auto_load': '0', 'subtitle': '1'};
  List<String> video = ['VT', 'FFmpeg'];
  List<String> audio = ['FFmpeg'];

  @override
  Future<Object?> version() async => {'mdk': '0.33.1'};
  @override
  Future<Map<String, NativeRead>> read(List<String> names) async =>
      {for (final n in names) n: (value: props[n], error: null)};
  @override
  Future<void> write(String name, String value) async => props[name] = value;
  @override
  Future<List<String>> decoders({required bool video}) async =>
      video ? this.video : audio;
  @override
  Future<void> setDecoders(List<String> names, {required bool video}) async {
    if (video) {
      this.video = names;
    } else {
      audio = names;
    }
  }

  @override
  Future<String?> activeDecoder({required bool video}) async =>
      video ? 'VT' : 'FFmpeg';
}

/// Erika; each read of its status is two seconds and 48 decoded frames
/// after the one before.
class FakeErika implements ErikaNative {
  bool hud = false;
  PlayerUpscalerMode mode = PlayerUpscalerMode.off;
  int reads = 0;
  int underflow = 0;
  final invoked = <String>[];

  @override
  Future<Object?> version() async => null;
  @override
  Future<Map<String, NativeRead>> read(List<String> names) async => {
        for (final n in names)
          n: (value: null, error: 'Erika has no named properties.')
      };
  @override
  Future<bool> debugHud() async => hud;
  @override
  Future<void> setDebugHud(bool enabled) async => hud = enabled;
  @override
  Future<PlayerUpscalerMode> upscaler() async => mode;
  @override
  Future<void> setUpscaler(PlayerUpscalerMode mode) async => this.mode = mode;
  @override
  Future<Map<String, Object?>?> engineLog({int? sinceSeq}) async => null;

  @override
  Future<NativeInvokeReply> invoke(String method, JsonMap arguments) async {
    invoked.add(method);
    return switch (method) {
      'getPresenterStats' => (
          result: {'decodedVideoFrames': 1},
          error: null,
          supported: true
        ),
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
  Future<JsonMap> status() async {
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
      'upscalerStatus': {'requestedMode': mode.name},
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
      'videoParams': {
        'width': 3840,
        'height': 2160,
        'primaries': 3,
        'transfer': 2
      },
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
        'media': {
          'video': {'codec': 'hevc'}
        },
        'note': 'from /Users/someone/Movies/secret.mkv?token=abc',
      },
    };
  }
}

/// video_player's controller as a kernel instance's handle.
class FakeState implements StateNative {
  @override
  List<String> get names => const ['position', 'isPlaying'];
  @override
  Future<Object?> version() async => {'video_player': '2.9.5'};
  @override
  Future<Map<String, NativeRead>> read(List<String> asked) async => {
        for (final n in asked)
          n: switch (n) {
            'position' => (value: '1000', error: null),
            'isPlaying' => (value: 'true', error: null),
            _ => (value: null, error: 'no state named $n'),
          }
      };
}

/// The playback as kernel control sees it.
class FakePlayback extends Fake implements KernelHost {
  FakePlayback(this.rig);
  final FakeHost rig;
  @override
  PlaybackSnapshot snapshot() => PlaybackSnapshot(
      status: 'playing',
      hasVideo: true,
      paused: false,
      path: rig.host.current.value?.path,
      seriesTitle: null,
      episodeTitle: null,
      animeId: null,
      episodeId: null,
      positionMs: 0,
      durationMs: 0,
      rate: 1,
      canPrevious: false,
      canNext: false,
      sessionId: rig.host.current.value?.id);
  @override
  JsonMap? error(String sessionId) => null;
}

KernelNative nativeFor(KernelId kernel) => switch (kernel) {
      KernelId.mediaKit => FakeMpv(),
      KernelId.mdk => FakeMdk(),
      KernelId.erika => FakeErika(),
      KernelId.videoPlayer => const PlainNative(null),
    };

late String video;

MediaRequest request() => MediaRequest(locator: video, origin: 'test');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('kernel-control-');
    video = '${temp.path}/episode.mkv';
    await File(video).writeAsString('not a video');
  });
  tearDown(() => temp.delete(recursive: true));

  /// A session playing on [kernel] with [native] behind it, and kernel
  /// control over it. A swap makes a new instance of the kernel asked, with a
  /// native of its own ([natives] keeps them in the order made).
  Future<
          ({
            Harness harness,
            KernelControl control,
            FakeHost rig,
            PlaybackSession session,
            List<String> asked,
            List<KernelNative> natives,
            List<KernelId> supported,
          })>
      rig(KernelId kernel,
          {KernelNative? native,
          bool approve = true,
          String? harness,
          List<KernelId>? supported}) async {
    final natives = <KernelNative>[];
    final asked = <String>[];
    final kernels = supported ?? [...KernelId.values];
    // Each instance gets a native handle of its own.
    final host = FakeHost(
        kernel: kernel.id,
        driver: (kernel, lease) {
          final handle =
              natives.isEmpty && native != null ? native : nativeFor(kernel);
          natives.add(handle);
          return FakeDriver(lease, kernel: kernel, native: handle);
        },
        supported: kernels.toSet());
    final session = await host.host.open(request());
    final control = KernelControl(host.host, FakePlayback(host),
        consent: (title, message, accept, stopped) async {
          asked.add('$title\n$message\n$accept');
          return approve;
        },
        harness: () => harness);
    return (
      harness: Harness([KernelControlCapability(control)]),
      control: control,
      rig: host,
      session: session,
      asked: asked,
      natives: natives,
      supported: kernels,
    );
  }

  group('reading', () {
    test(
        'Media Kit: mpv and ffmpeg versions, a snapshot and the properties '
        'asked for with mpv\'s own error', () async {
      final r = await rig(KernelId.mediaKit);
      final read = await invokeCompleted(r.harness, 'playback.kernel', {
        'properties': ['deband', 'no-such-property']
      });
      expect(read['kernel'], containsPair('id', 'media_kit'));
      expect(read['kernel'], containsPair('configured', 'media_kit'));
      expect((read['kernel'] as Map)['version'],
          {'mpv': 'mpv v0.40.0', 'ffmpeg': '7.1.1'});
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
          unorderedEquals(['mdk', 'media_kit', 'video_player', 'erika']));
      expect(read['overrides'], isEmpty);
      expect(read['kernelOverride'], isNull);
      await r.rig.host.close(reason: 'test');
    });

    test('MDK: its version, decoder lists and the properties set on it',
        () async {
      final r = await rig(KernelId.mdk);
      final read = await invokeCompleted(r.harness, 'playback.kernel', {
        'properties': ['avformat.fflags']
      });
      expect(read['kernel'], containsPair('id', 'mdk'));
      expect((read['kernel'] as Map)['version'], {'mdk': '0.33.1'});
      expect(read['decoders'], {
        'video': ['VT', 'FFmpeg'],
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
      await r.rig.host.close(reason: 'test');
    });

    test(
        'Erika: decoder, frame, audio and HDR facts as reported, a window '
        'between reads, and what it does not expose', () async {
      final native = FakeErika();
      final r = await rig(KernelId.erika, native: native);
      final first =
          (await invokeCompleted(r.harness, 'playback.kernel', {}))['erika']
              as Map;
      expect(first['window'], isNull);
      expect(first['windowUnavailable'], 'no_previous_read');
      expect(first['decoder'], containsPair('hardware', true));
      expect(first['decoder'], containsPair('fellBack', true));
      expect(first['decoder'], containsPair('activeBackend', 'videoToolbox'));
      expect((first['frames'] as Map)['nominalFps'], 23.976);
      expect((first['frames'] as Map)['lateDropped'], 3);
      final diagnostics = first['diagnostics'] as Map;
      expect(diagnostics['schema'], 1);
      expect(diagnostics['note'], isNot(contains('token=abc')));
      expect((first['hdr'] as Map)['sdrTonemapFrames'], 1000);
      expect(first['resources'], {'videoFrameBytes': 4096, 'drawableCount': 3});
      expect(first['debugHud'], false);
      expect(first['notReported'],
          containsAll(['network.throughput', 'hdr.metadata']));

      native.underflow = 512;
      final second =
          (await invokeCompleted(r.harness, 'playback.kernel', {}))['erika']
              as Map;
      final window = second['window'] as Map;
      expect(window['source'], 'previous_read');
      expect(window['seconds'], 2.0);
      expect(window['decodedFrames'], 48);
      expect(window['decodedFps'], 24.0);
      expect(window['audioUnderflowFrames'], 512);
      expect(window['backpressureDrops'], 1);
      expect(window['paused'], false);

      final sampled = (await invokeCompleted(
          r.harness, 'playback.kernel', {'sampleMs': 500}))['erika'] as Map;
      expect((sampled['window'] as Map)['source'], 'sampled');
      expect((sampled['window'] as Map)['decodedFrames'], 48);
      await r.rig.host.close(reason: 'test');
    });

    test('video_player: its controller\'s state by name, nothing to set',
        () async {
      final r = await rig(KernelId.videoPlayer, native: FakeState());
      final read = await invokeCompleted(r.harness, 'playback.kernel', {
        'properties': ['isPlaying', 'nope']
      });
      expect(read['kernel'], containsPair('id', 'video_player'));
      expect((read['kernel'] as Map)['version'], {'video_player': '2.9.5'});
      expect((read['snapshot'] as Map)['position'], '1000');
      expect(read['properties'], {
        'isPlaying': {'value': 'true', 'error': null},
        'nope': {'value': null, 'error': 'no state named nope'},
      });
      expect((read['controls'] as Map)['properties'],
          {'read': 'named_state', 'write': 'none'});
      await r.rig.host.close(reason: 'test');
    });

    test('nothing playing is unavailable, a session that changed a conflict',
        () async {
      final r = await rig(KernelId.mediaKit);
      final conflict = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': 'internal:other',
            'properties': {'a': 'b'}
          },
          Invocation(origin: 'test'));
      expect((conflict as Failed).failure.code, FailureCode.conflict);
      await r.rig.host.close(reason: 'test');
      final none = await r.harness
          .invokeJson('playback.kernel', {}, Invocation(origin: 'test'));
      expect((none as Failed).failure.code, FailureCode.unavailable);
    });

    test('which Erika methods only read', () {
      expect(erikaReadsOnly('listMethods', const {}), true);
      expect(erikaReadsOnly('getDiagnosticsSnapshot', const {}), true);
      expect(erikaReadsOnly('exportFrames', const {}), true);
      expect(erikaReadsOnly('invokeJson', const {'method': 'getLogs'}), true);
      expect(erikaReadsOnly('pause', const {}), false);
      expect(erikaReadsOnly('invokeJson', const {'method': 'seek'}), false);
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
    });
  });

  group('changing for this playback', () {
    test(
        'mpv takes the value now; it is the kernel instance\'s, and another '
        'instance ends it', () async {
      final r = await rig(KernelId.mediaKit);
      final mpv = r.natives.single as FakeMpv;
      final result =
          await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': r.session.id,
        'properties': {'hwdec': 'no', 'deband': 'yes', 'vf': 'hflip'},
      });
      final changes = (result['changes'] as List).cast<Map>();
      expect(changes.first, containsPair('before', 'auto-copy'));
      expect(changes.first, containsPair('requested', 'no'));
      expect(changes.first, containsPair('after', 'no'));
      expect(changes.first, containsPair('error', null));
      expect(changes.first, containsPair('restorable', true));
      expect(mpv.mpv['hwdec'], 'no');

      // A swap is another instance: the changes ended with the old one.
      await r.session.swapKernel(KernelId.mdk, origin: 'test');
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      expect(read['kernelOverride'], containsPair('kernel', 'mdk'));
      final ended = [
        for (final c in (read['changes'] as List).cast<Map>())
          if (c['action'] == 'ended') c['name']
      ];
      expect(ended, unorderedEquals(['hwdec', 'deband', 'vf']));
      await r.rig.host.close(reason: 'test');
    });

    test(
        'each change is recorded with who and when, and restore puts the '
        'original back', () async {
      final r = await rig(KernelId.mediaKit);
      final mpv = r.natives.single as FakeMpv;
      final outcome = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': r.session.id,
            'properties': {'hwdec': 'no'},
          },
          Invocation(origin: 'conversation:main', id: 'inv-1'));
      expect(outcome, isA<Completed>());
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': r.session.id,
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
      expect(first['kernel'], 'media_kit');

      final restored = await invokeCompleted(
          r.harness, 'playback.restore_kernel_properties', {
        'names': ['hwdec', 'deband']
      });
      expect(restored['restored'], [
        containsPair('restored', true),
        {'name': 'deband', 'restored': false, 'reason': 'not_changed'},
      ]);
      expect(mpv.mpv['hwdec'], 'auto-copy');
      read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(read['overrides'], isEmpty);
      expect(
          (read['changes'] as List).first, containsPair('action', 'restore'));

      // A value changed since is left as found.
      await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': r.session.id,
        'properties': {'vf': 'hflip'},
      });
      mpv.mpv['vf'] = 'vflip';
      final left = await invokeCompleted(
          r.harness, 'playback.restore_kernel_properties', {});
      expect((left['restored'] as List).single,
          containsPair('reason', 'changed_since'));
      expect(mpv.mpv['vf'], 'vflip');
      await r.rig.host.close(reason: 'test');
    });

    test(
        'a setting that can send traffic elsewhere waits for the person, '
        'and a no changes nothing', () async {
      final declined = await rig(KernelId.mediaKit, approve: false);
      final mpv = declined.natives.single as FakeMpv;
      final outcome = await declined.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': declined.session.id,
            'properties': {
              'http-proxy': 'http://user:secret@proxy.example:8080',
              'deband': 'yes'
            },
          },
          Invocation(origin: 'test'));
      expect((outcome as Failed).failure.code, FailureCode.conflict);
      expect(outcome.failure.message, '用户没有同意这次播放使用这些网络设置');
      expect(mpv.mpv['http-proxy'], '');
      expect(mpv.mpv['deband'], 'no');
      expect(declined.asked.single, contains('http-proxy'));
      expect(declined.asked.single, isNot(contains('secret')));
      await declined.rig.host.close(reason: 'test');

      final allowed = await rig(KernelId.mediaKit);
      final result = await invokeCompleted(
          allowed.harness, 'playback.set_kernel_properties', {
        'sessionId': allowed.session.id,
        'properties': {'external-files': 'https://example.com/a.ass'},
      });
      expect(allowed.asked, hasLength(1));
      expect((result['changes'] as List).single,
          containsPair('consent', 'user_approved'));
      expect((allowed.natives.single as FakeMpv).mpv['external-files'],
          'https://example.com/a.ass');
      expect(kernelSettingConsent('hwdec', 'no'), isNull);
      for (final name in [
        'user-agent',
        'http-header-fields',
        'cookies-file',
        'tls-verify',
        'referrer',
        'avio.http_proxy',
        'avformat.headers'
      ]) {
        expect(kernelSettingConsent(name, 'x'), 'network', reason: name);
      }
      await allowed.rig.host.close(reason: 'test');
    });

    test(
        'a question that waits for the person goes away when the kernel '
        'does', () async {
      final r = await rig(KernelId.mediaKit);
      final gate = Completer<bool>();
      final control = KernelControl(r.rig.host, FakePlayback(r.rig),
          consent: (title, message, accept, stopped) {
        stopped.then((_) {
          if (!gate.isCompleted) gate.complete(true);
        });
        return gate.future;
      });
      final harness = Harness([KernelControlCapability(control)]);
      final pending = harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': r.session.id,
            'properties': {'user-agent': 'x'},
          },
          Invocation(origin: 'test'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await r.session.swapKernel(KernelId.mdk, origin: 'test');
      final outcome = await pending;
      expect((outcome as Failed).failure.code, FailureCode.conflict);
      expect((r.natives.first as FakeMpv).mpv['user-agent'], 'NipaPlay/1.0');
      await r.rig.host.close(reason: 'test');
    });

    test('MDK: decoders go back; a property MDK never reported cannot',
        () async {
      final r = await rig(KernelId.mdk);
      final mdk = r.natives.single as FakeMdk;
      final result =
          await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': r.session.id,
        'properties': {'video.avfilter': 'hflip', 'auto_load': '1'},
        'videoDecoders': ['FFmpeg', 'dav1d'],
      });
      final changes = {
        for (final c in (result['changes'] as List).cast<Map>()) c['name']: c
      };
      expect(changes['video.avfilter'], containsPair('restorable', false));
      expect(changes['auto_load'], containsPair('before', '0'));
      expect(
          changes['videoDecoders'], containsPair('before', ['VT', 'FFmpeg']));
      expect(mdk.video, ['FFmpeg', 'dav1d']);
      final restored = await invokeCompleted(
          r.harness, 'playback.restore_kernel_properties', {});
      expect(mdk.video, ['VT', 'FFmpeg']);
      expect(mdk.props['auto_load'], '0');
      final byName = {
        for (final c in (restored['restored'] as List).cast<Map>()) c['name']: c
      };
      expect(
          byName['video.avfilter'], containsPair('reason', 'original_unknown'));
      await r.rig.host.close(reason: 'test');
    });

    test('Erika: upscaler and debug HUD for this media, others refused',
        () async {
      final r = await rig(KernelId.erika);
      final erika = r.natives.single as FakeErika;
      final result =
          await invokeCompleted(r.harness, 'playback.set_kernel_properties', {
        'sessionId': r.session.id,
        'properties': {'upscaler': 'artCnnC4F16', 'debugHud': 'true'},
      });
      expect(
          (result['changes'] as List)
              .cast<Map>()
              .map((c) => [c['name'], c['before'], c['after']]),
          [
            ['upscaler', 'off', 'artCnnC4F16'],
            ['debugHud', 'false', 'true'],
          ]);
      expect(erika.hud, isTrue);
      expect(erika.mode, PlayerUpscalerMode.erikaArtCnnC4F16);
      final refused = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': r.session.id,
            'properties': {'hwdec': 'no'},
          },
          Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.invalidInput);
      expect(refused.failure.message, contains('upscaler'));
      await r.rig.host.close(reason: 'test');
    });

    test('video_player takes no properties', () async {
      final r = await rig(KernelId.videoPlayer);
      final refused = await r.harness.invokeJson(
          'playback.set_kernel_properties',
          {
            'sessionId': r.session.id,
            'properties': {'a': 'b'},
          },
          Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.unavailable);
      await r.rig.host.close(reason: 'test');
    });
  });

  group('reopening on another kernel', () {
    test(
        'the same session moves to a new instance; the next media opens on '
        'the kernel setting', () async {
      final r = await rig(KernelId.mediaKit);
      final before = r.session.driver!;
      await r.session.seek(const Duration(minutes: 3), origin: 'test');
      final result =
          await invokeCompleted(r.harness, 'playback.reopen_with_kernel', {
        'sessionId': r.session.id,
        'kernel': 'mdk',
      });
      expect(result['kernel'], {
        'requested': 'mdk',
        'actual': 'mdk',
        'name': 'MDK',
        'configured': 'media_kit',
      });
      expect(result['opened'], true);
      expect(result['replaced'], true);
      expect(before.fenced, true);
      expect(r.session.driver!.kernel, KernelId.mdk);
      expect(r.session.driver, isNot(same(before)));
      final preserved = result['preserved'] as Map;
      expect((preserved['positionMs'] as Map)['before'], closeTo(180000, 200));
      expect((preserved['positionMs'] as Map)['after'], closeTo(180000, 400));
      expect(preserved['paused'], {'before': false, 'after': false});
      expect(result['nextMediaOpensConfiguredKernel'], true);
      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect(
          read['kernelOverride'], {'kernel': 'mdk', 'configured': 'media_kit'});
      expect((read['changes'] as List).cast<Map>().map((c) => c['action']),
          contains('reopen'));
      await r.rig.host.close(reason: 'test');
      // The next media: a new session on the setting.
      final next = await r.rig.host.open(request());
      expect(next.driver!.kernel, KernelId.mediaKit);
      await r.rig.host.close(reason: 'test');
    });

    test('a kernel this device cannot run is refused', () async {
      final r = await rig(KernelId.mediaKit,
          supported: [KernelId.mdk, KernelId.mediaKit]);
      final outcome = await r.harness.invokeJson(
          'playback.reopen_with_kernel',
          {'sessionId': r.session.id, 'kernel': 'erika'},
          Invocation(origin: 'test'));
      expect((outcome as Failed).failure.code, FailureCode.unavailable);
      expect(r.session.driver!.kernel, KernelId.mediaKit);
      await r.rig.host.close(reason: 'test');
    });

    test(
        'a kernel that cannot open the media fails the session; another '
        'swap brings it back', () async {
      var made = 0;
      final host = FakeHost(
          kernel: 'mdk',
          driver: (kernel, lease) => FakeDriver(lease,
              kernel: kernel,
              failOpen: ++made == 2
                  ? const KernelOpenFailure('media_open', 'no such codec')
                  : null),
          supported: {...KernelId.values});
      final session = await host.host.open(request());
      final control = KernelControl(host.host, FakePlayback(host));
      final harness = Harness([KernelControlCapability(control)]);
      final failed =
          await invokeCompleted(harness, 'playback.reopen_with_kernel', {
        'sessionId': session.id,
        'kernel': 'erika',
      });
      expect(failed['opened'], false);
      expect(failed['failure'], 'no such codec');
      expect(session.phase.value, SessionPhase.failed);
      expect(host.arbiter.owner, isNull);
      final back =
          await invokeCompleted(harness, 'playback.reopen_with_kernel', {
        'sessionId': session.id,
        'kernel': 'mdk',
      });
      expect(back['opened'], true);
      expect(session.phase.value, SessionPhase.active);
      expect(session.fault.value, isNull);
      await host.host.close(reason: 'test');
    });
  });

  group('passing through', () {
    test(
        'an mpv command goes to mpv as given; one that changes a property '
        'holds like a property change', () async {
      final r = await rig(KernelId.mediaKit);
      final mpv = r.natives.single as FakeMpv;
      final vf = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': r.session.id,
        'command': ['vf', 'add', 'hflip'],
      });
      expect(mpv.commands.single, ['vf', 'add', 'hflip']);
      expect(vf['property'], {
        'name': 'vf',
        'before': '',
        'after': 'hflip',
        'restorable': true,
      });
      expect(vf['lasting'], 'property');
      expect(vf['error'], isNull);

      final text = await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': r.session.id,
        'command': ['expand-text', r'${hwdec-current}'],
      });
      expect(text['result'], r'expanded ${hwdec-current}');
      expect(text['lasting'], 'none');

      final bogus =
          await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': r.session.id,
        'command': ['no-such-command'],
      });
      expect(bogus['error'], 'invalid parameter');

      final program =
          await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': r.session.id,
        'command': ['subprocess', 'curl', 'https://example.com'],
      });
      expect(r.asked, isEmpty, reason: 'running a program does not wait');
      expect(program['result'], {'status': 0, 'stdout': 'hi'});

      final read = await invokeCompleted(r.harness, 'playback.kernel', {});
      expect((read['changes'] as List).cast<Map>().map((c) => c['action']),
          everyElement('command'));
      await r.rig.host.close(reason: 'test');
    });

    test('load-script takes a script in the harness', () async {
      final harness = await Directory.systemTemp.createTemp('kc-harness-');
      addTearDown(() => harness.delete(recursive: true));
      final script = File('${harness.path}/scripts/probe.lua');
      await script.create(recursive: true);
      final r = await rig(KernelId.mediaKit, harness: harness.path);
      final mpv = r.natives.single as FakeMpv;
      final outside = await r.harness.invokeJson(
          'playback.kernel_command',
          {
            'sessionId': r.session.id,
            'command': ['load-script', '/etc/hosts'],
          },
          Invocation(origin: 'test'));
      expect((outside as Failed).failure.code, FailureCode.invalidInput);
      expect(mpv.commands, isEmpty);
      final loaded =
          await invokeCompleted(r.harness, 'playback.kernel_command', {
        'sessionId': r.session.id,
        'command': ['load-script', script.path],
      });
      expect(loaded['lasting'], 'unknown');
      await r.rig.host.close(reason: 'test');
    });

    test('a command that would send traffic elsewhere waits for the person',
        () async {
      final r = await rig(KernelId.mediaKit, approve: false);
      final mpv = r.natives.single as FakeMpv;
      final outcome = await r.harness.invokeJson(
          'playback.kernel_command',
          {
            'sessionId': r.session.id,
            'command': ['loadfile', 'https://user:pw@example.com/v.mkv'],
          },
          Invocation(origin: 'test'));
      expect((outcome as Failed).failure.message, '用户没有同意这次播放使用这些网络设置');
      expect(mpv.commands, isEmpty);
      expect(r.asked.single, isNot(contains('pw@')));
      expect(
          kernelCommandConsent(['set', 'http-proxy', 'http://p:1']), 'network');
      expect(
          mpvCommandProperty(
              ['no-osd', 'cycle-values', '!reverse', 'hwdec', 'no', 'auto']),
          'hwdec');
      await r.rig.host.close(reason: 'test');
    });

    test('commands are Media Kit\'s, invoke is Erika\'s', () async {
      final erika = await rig(KernelId.erika);
      final command = await erika.harness.invokeJson(
          'playback.kernel_command',
          {
            'sessionId': erika.session.id,
            'command': ['set', 'a', 'b']
          },
          Invocation(origin: 'test'));
      expect((command as Failed).failure.code, FailureCode.unavailable);
      final read =
          await invokeCompleted(erika.harness, 'playback.kernel_invoke', {
        'sessionId': erika.session.id,
        'method': 'getPresenterStats',
      });
      expect(read['supported'], true);
      expect(read['result'], {'decodedVideoFrames': 1});
      final missing =
          await invokeCompleted(erika.harness, 'playback.kernel_invoke', {
        'sessionId': erika.session.id,
        'method': 'getDiagnosticsJson',
      });
      expect(missing['supported'], false);
      expect(missing['error'], contains('no method'));
      final table =
          await invokeCompleted(erika.harness, 'playback.kernel_invoke', {
        'sessionId': erika.session.id,
        'method': 'listMethods',
      });
      expect(((table['result'] as Map)['methods'] as List).first,
          containsPair('name', 'listMethods'));
      await erika.rig.host.close(reason: 'test');

      final mpv = await rig(KernelId.mediaKit);
      final refused = await mpv.harness.invokeJson(
          'playback.kernel_invoke',
          {
            'sessionId': mpv.session.id,
            'method': 'm',
          },
          Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.unavailable);
      await mpv.rig.host.close(reason: 'test');
    });

    test(
        'watching reads once, or each change over a bounded time, and ends '
        'when the kernel is replaced', () async {
      final r = await rig(KernelId.mediaKit);
      final mpv = r.natives.single as FakeMpv;
      final once =
          await invokeCompleted(r.harness, 'playback.watch_kernel_properties', {
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
          () => mpv.mpv['hwdec-current'] = 'no');
      final watched =
          await invokeCompleted(r.harness, 'playback.watch_kernel_properties', {
        'properties': ['hwdec-current'],
        'durationMs': 700,
        'intervalMs': 100,
      });
      expect(
          (watched['changes'] as List).single,
          allOf(containsPair('name', 'hwdec-current'),
              containsPair('value', 'no')));
      expect(watched['samples'], greaterThan(3));

      Timer(const Duration(milliseconds: 150),
          () => r.session.swapKernel(KernelId.mdk, origin: 'test'));
      final cut =
          await invokeCompleted(r.harness, 'playback.watch_kernel_properties', {
        'properties': ['hwdec-current'],
        'durationMs': 2000,
        'intervalMs': 100,
      });
      expect(cut['endedBy'], 'player_replaced');
      await r.rig.host.close(reason: 'test');

      final erika = await rig(KernelId.erika);
      final refused = await erika.harness.invokeJson(
          'playback.watch_kernel_properties',
          {
            'properties': ['x'],
          },
          Invocation(origin: 'test'));
      expect((refused as Failed).failure.code, FailureCode.unavailable);
      await erika.rig.host.close(reason: 'test');
    });
  });
}

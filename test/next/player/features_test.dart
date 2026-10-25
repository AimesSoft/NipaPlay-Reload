import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/next/capabilities/media_frames.dart';
import 'package:nipaplay/next/player/features/capture.dart';
import 'package:nipaplay/next/player/features/external_handoff.dart';
import 'package:nipaplay/next/player/features/kernel_features.dart';
import 'package:nipaplay/next/player/features/timeline_preview.dart';
import 'package:nipaplay/next/player/features/windows.dart';
import 'package:nipaplay/next/player/features/settings_adapter.dart';
import 'package:nipaplay/next/player/kernel/driver.dart';
import 'package:nipaplay/next/player/ports/session_playback.dart';
import 'package:nipaplay/services/player_remote_control_bridge.dart';
import 'package:nipaplay/services/remote_control_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_driver.dart';

const _media = MediaFacts(
    duration: Duration(minutes: 5),
    width: 32,
    height: 18,
    frameRate: 25,
    chapters: [
      ChapterFacts('开始', 0),
      ChapterFacts('中段', 60000),
      ChapterFacts('结尾', 180000)
    ]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late String video;
  late SessionPlayback playback;
  late FakeHost rig;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('next-features-');
    video = '${temp.path}/带 空格.mkv';
    await File(video).writeAsString('fake media');
    rig = FakeHost(make: (lease) => _FrameDriver(lease));
    playback = SessionPlayback(rig.host);
  });
  tearDown(() async {
    await playback.close(reason: 'test');
    await playback.dispose();
    await temp.delete(recursive: true);
  });

  test('a kernel that reports no chapters says so, not an empty list of them',
      () async {
    final plain = FakeHost();
    final other = SessionPlayback(plain.host);
    addTearDown(() async {
      await other.close(reason: 'test');
      await other.dispose();
    });
    await other.openItem(PlayableItem(videoPath: video));
    final chapters = await other.inspection.inspect('playback.chapters', {});
    expect(chapters['kernelProvidesChapters'], false);
    expect(chapters['items'], isEmpty);
    expect(other.session!.media.value!.toJson()['chapters'], isNull);
  });

  test(
      'chapter seeks and bidirectional native frame steps use the current session',
      () async {
    await playback.openItem(PlayableItem(videoPath: video));
    final id = playback.snapshot().sessionId;
    final chapters = await playback.inspection.inspect('playback.chapters', {});
    expect((chapters['items'] as List).length, 3);
    expect(chapters['kernelProvidesChapters'], true);
    await playback.inspection
        .inspect('playback.navigate', {'sessionId': id, 'chapterIndex': 1});
    expect(playback.position.inMilliseconds, closeTo(60000, 100));
    await playback.port.setPaused(true);
    final initial = rig.drivers.single.position;
    final forward = await playback.inspection
        .inspect('playback.navigate', {'frameDelta': 1});
    expect(forward['method'], 'native_frame_step');
    expect(playback.position, initial + const Duration(milliseconds: 40));
    await playback.inspection.inspect('playback.navigate', {'frameDelta': -1});
    expect(playback.position, initial);
    expect(playback.playIntent, isFalse);
    expect(
        () => playback.inspection.inspect(
            'playback.navigate', {'sessionId': 'old', 'chapterIndex': 0}),
        throwsA(isA<Failure>()
            .having((e) => e.code, 'code', FailureCode.conflict)));
    expect(
        () =>
            playback.inspection.inspect('playback.navigate', {'frameDelta': 0}),
        throwsA(isA<Failure>()));
  });

  test(
      'retry creates a new kernel while preserving position, pause, rate and volume',
      () async {
    await playback.openItem(PlayableItem(videoPath: video),
        start: const Duration(seconds: 70));
    await playback.port.setPaused(true);
    await playback.setRate(1.5);
    await playback.setVolume(0.3);
    final old = playback.session!;
    final result = await playback.inspection
        .inspect('playback.retry', {'sessionId': old.id});
    expect(result['commandStatus'], 'accepted');
    expect(playback.session!.id, isNot(old.id));
    expect(rig.drivers.first.released, isTrue);
    expect(playback.position.inMilliseconds, closeTo(70000, 100));
    expect(playback.playIntent, isFalse);
    // The new instance starts with the current session's levels.
    expect(playback.rate, 1.5);
    expect(playback.volume, 0.3);
    final reset = await playback.inspection.inspect('playback.retry',
        {'sessionId': playback.session!.id, 'preservePosition': false});
    expect(reset['commandStatus'], 'accepted');
    expect(playback.position, Duration.zero);
  });

  test('retry is the same again: on the kernel the session was on, not the setting',
      () async {
    final rig = FakeHost(
        supported: {KernelId.mdk, KernelId.erika},
        driver: (kernel, lease) => _FrameDriver(lease, kernel: kernel));
    final playback = SessionPlayback(rig.host);
    addTearDown(() async {
      await playback.close(reason: 'test');
      await playback.dispose();
    });
    await playback.openItem(PlayableItem(videoPath: video));
    final first = playback.session!;
    expect(first.kernelId, KernelId.mdk);
    await first.swapKernel(KernelId.erika, origin: 'test');
    expect(first.kernelId, KernelId.erika);
    await playback.inspection.inspect('playback.retry', {'sessionId': first.id});
    expect(playback.session!.id, isNot(first.id));
    expect(playback.session!.kernelId, KernelId.erika);
    expect(rig.drivers.last.kernel, KernelId.erika);
  });

  test('remote bridge pauses and seeks Next, and enforces receiver permission',
      () async {
    await playback.openItem(PlayableItem(videoPath: video),
        start: const Duration(seconds: 30));
    final bridge = PlayerRemoteControlBridge.instance;
    var nextOpen = true;
    bridge.attachNext(playback, () => nextOpen);
    addTearDown(() => bridge.detachNext(playback));
    final pause = await bridge.executeCommand('toggle_play_pause', {});
    expect(pause['success'], true);
    expect(playback.playIntent, false);
    final before = playback.position;
    final seek =
        await bridge.executeCommand('seek_by_seconds', {'seconds': 11.25});
    expect(seek['success'], true);
    expect(playback.position, before + const Duration(milliseconds: 11250));
    expect(((seek['payload'] as Map)['snapshot'] as Map)['sessionId'],
        playback.session!.id);
    final menu =
        await bridge.buildPayload(paneId: 'chapters', includeParameters: true);
    expect((menu['parameters'] as List).single['options'], hasLength(3));
    final jump = await bridge.executeCommand(
        'set_parameter', {'key': 'playback.chapter', 'value': 2});
    expect(jump['success'], true);
    expect(playback.position.inMilliseconds, closeTo(180000, 100));
    await RemoteControlSettings.setReceiverEnabled(false);
    final rejected =
        await bridge.executeCommand('seek_by_seconds', {'seconds': 20});
    expect(rejected['success'], false);
    expect(playback.position.inMilliseconds, closeTo(180000, 100));
    nextOpen = false;
    expect((await bridge.buildPayload())['available'], false);
  });

  test(
      'external handoff passes one literal media argument and reports no invented telemetry',
      () async {
    final script = File(
        '${temp.path}/fake-player${Platform.isWindows ? '.cmd' : ''}');
    final argsFile = File('${temp.path}/args.txt');
    if (Platform.isWindows) {
      await script.writeAsString('@echo off\r\n'
          'chcp 65001 >nul\r\n'
          '>"${argsFile.path.replaceAll('/', r'\')}" echo %~1\r\n'
          'ping -n 2 127.0.0.1 >nul\r\n');
    } else {
      await script.writeAsString(
          '#!/bin/sh\nprintf "%s\\n" "\u0024@" > "${argsFile.path}"\nsleep 1\n');
      await Process.run('/bin/chmod', ['+x', script.path]);
    }
    final external = ExternalHandoff(
        enabled: () => true,
        playerPath: () => script.path,
        playerType: () => ExternalPlayerType.generic);
    await playback.dispose();
    playback = SessionPlayback(rig.host, externalHandoff: external);
    await playback.openItem(PlayableItem(videoPath: video));
    expect(rig.drivers, isEmpty);
    final snapshot = playback.snapshot();
    expect(snapshot.player, 'external');
    expect(snapshot.external!['status'], '在外部播放器中播放');
    expect(snapshot.positionMs, isNull);
    expect(snapshot.paused, isNull);
    expect(snapshot.supportedControls, isEmpty);
    final exited = external.launchExit!;
    expect(() => playback.port.seekTo(Duration.zero), throwsA(isA<Failure>()));
    expect(() => playback.port.setPaused(true), throwsA(isA<Failure>()));
    expect(
        (await playback.controls
            .external({'command': 'state'}))['controlAvailable'],
        false);
    await exited.timeout(const Duration(seconds: 30));
    await pumpEventQueue();
    expect(await argsFile.readAsLines(), [video]);
    expect(external.active, isFalse);
  });

  test('external argument conventions preserve type, start and user-agent', () {
    expect(
        ExternalHandoff.launchArguments('/v a.mkv', ExternalPlayerType.mpv,
            start: const Duration(milliseconds: 1250), userAgent: 'Nipa Agent'),
        ['--start=1.25', '--user-agent=Nipa Agent', '--', '/v a.mkv']);
    expect(
        ExternalHandoff.launchArguments('/v.mkv', ExternalPlayerType.vlc,
            start: const Duration(seconds: 10)),
        ['--start-time=10.0', '/v.mkv']);
  });

  test('Next feature preferences preserve the shared storage representation',
      () async {
    expect(
        await writeNextFeatureSetting(
            'player.screenshotQuality', 'screenshot_quality', 'max'),
        true);
    expect(
        await writeNextFeatureSetting(
            'player.screenshotSaveTarget', 'screenshot_save_target', 'file'),
        true);
    expect(
        await writeNextFeatureSetting(
            'player.timelinePreviewEnabled', 'timeline_preview_enabled', true),
        true);
    expect(
        await writeNextFeatureSetting('subtitle.scale', 'subtitle_scale', 1.5),
        false);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('screenshot_quality'), 3);
    expect(prefs.getInt('screenshot_save_target'), 2);
    expect(prefs.getBool('timeline_preview_enabled'), true);
    expect(prefs.containsKey('subtitle_scale'), false);
  });

  test('capture encoding runs independently and preserves RGBA pixels',
      () async {
    final picture = KernelPicture(
        4,
        2,
        Uint8List.fromList(
            List.generate(32, (i) => i % 4 == 0 || i % 4 == 3 ? 255 : 0)));
    final bytes = await PlaybackCapture.encodePicture(picture);
    final decoded = img.decodePng(bytes)!;
    expect(decoded.width, 4);
    expect(decoded.height, 2);
    expect(decoded.getPixel(3, 1).r, 255);
    expect(decoded.getPixel(3, 1).g, 0);
    final output = '${temp.path}/exists.png';
    await File(output).writeAsString('keep');
    await expectLater(
        PlaybackCapture.validateOutput(output), throwsA(isA<Failure>()));
    await expectLater(
        PlaybackCapture.claimOutput(output), throwsA(isA<Failure>()));
    expect(await File(output).readAsString(), 'keep');
  });

  test('GIF uses the bundled plugin and removes its claimed output on failure',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    const channel = MethodChannel('erika_flutter/player');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await playback.openItem(PlayableItem(videoPath: video));
    final output = '${temp.path}/sample.gif';
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'exportGif');
      final args = Map<String, Object?>.from(call.arguments as Map);
      expect(args['inputUri'], playback.session!.source.uri);
      expect(args['startMillis'], 1000);
      expect(args['endMillis'], 2000);
      expect(args['quality'], 1);
      expect(args['overwrite'], true);
      expect(await File(output).length(), 0);
      calls++;
      if (calls == 2) throw PlatformException(code: 'export_failed');
      await File(output).writeAsBytes([71, 73, 70]);
      return {
        'outputPath': output,
        'width': 320,
        'height': 180,
        'frameCount': 6,
        'fileSize': 3,
      };
    });
    final input = <String, Object?>{
      'kind': 'gif',
      'outputPath': output,
      'startMs': 1000,
      'endMs': 2000,
      'fps': 6,
      'width': 320,
      'height': 180,
      'quality': 'high',
    };
    final receipt = await playback.controls.capture(input);
    expect(receipt['frames'], 6);
    expect(receipt['bytes'], 3);
    expect(receipt['danmakuIncluded'], false);
    await expectLater(
        playback.controls.capture(input), throwsA(isA<Failure>()));
    expect(calls, 1);
    expect(await File(output).readAsBytes(), [71, 73, 70]);
    await File(output).delete();
    await expectLater(
        playback.controls.capture(input), throwsA(isA<PlatformException>()));
    expect(await File(output).exists(), false);
  });

  testWidgets(
      'capture includes the displayed danmaku layer and can exclude it without changing tracks',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'screenshot_crop_letterbox': false, 'screenshot_quality': 2});
    await tester.runAsync(() async {
      await playback.openItem(PlayableItem(videoPath: video));
      await playback.port.setPaused(true);
    });
    await tester.pumpWidget(MaterialApp(
        home: PlaybackCaptureScene(
      capture: playback.capture,
      video: const ColoredBox(color: Color(0xFF0000FF)),
      overlays: [
        PlaybackCaptureLayer(
            capture: playback.capture,
            danmaku: true,
            child: const Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                    width: 160,
                    height: 100,
                    child: ColoredBox(
                        color: Color(0xFF00FF00),
                        child: DefaultTextStyle(
                            style: TextStyle(fontSize: 14, color: Colors.black),
                            child: Text('测试弹幕'))))))
      ],
    )));
    Future<img.Image> shot(bool include) => tester.runAsync(() async {
          final pending = playback.capture.capture(playback.session!, {
            'kind': 'screenshot',
            'includeDanmaku': include,
            'outputPath': '${temp.path}/scene-$include.png'
          });
          await Future<void>.delayed(const Duration(milliseconds: 40));
          await tester.pump();
          final result = await pending;
          return img
              .decodePng(await File(result['path'] as String).readAsBytes())!;
        }).then((value) => value!);
    final included = await shot(true);
    final excluded = await shot(false);
    // A pixel in the displayed comment's background, away from its glyphs.
    expect(included.getPixel(140, 80).g, 255);
    expect(excluded.getPixel(140, 80).b, 255);
    expect(playback.capture.options.value.danmaku, true);
    expect(rig.drivers.single.log.where((e) => e.contains('track')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => playback.close(reason: 'widget-test'));
  });

  test('preview discards stale requests and releases its independent decoder',
      () async {
    final source = _FrameSource();
    final preview = TimelinePreview(engine: _Engine(source))..enabled = true;
    final first = preview.at(video, const Duration(seconds: 1));
    await pumpEventQueue();
    final skipped = preview.at(video, const Duration(seconds: 2));
    final latest = preview.at(video, const Duration(seconds: 3));
    expect(await skipped, isNull);
    source.gate.complete();
    expect(await first, isNull);
    expect(await latest, isNotNull);
    expect(source.requests, [1000, 3000]);
    await preview.dispose();
    expect(source.closed, true);
    expect(await preview.at(video, Duration.zero), isNull);
    expect(rig.drivers, isEmpty);
  });

  test(
      'PIP restores the prior topmost state and returning does not restart playback',
      () async {
    await playback.openItem(PlayableItem(videoPath: video));
    final id = playback.session!.id;
    final window = _Window();
    final windows = PlaybackWindows(create: (_, __, ___) async => window);
    await windows.detach((_) => const SizedBox(), 16 / 9);
    await windows.setPictureInPicture(true, 16 / 9);
    expect(windows.pictureInPicture, true);
    expect(window.alwaysOnTop, true);
    await windows.setPictureInPicture(false, 16 / 9);
    expect(window.alwaysOnTop, false);
    await windows.returnToMain();
    expect(windows.detached, false);
    expect(window.closed, true);
    expect(playback.session!.id, id);
    expect(rig.drivers, hasLength(1));
    await windows.shutdown();
  });

  test('PIP failure rolls back the OS flags', () async {
    final window = _Window()..failPip = true;
    final windows = PlaybackWindows(create: (_, __, ___) async => window);
    await windows.detach((_) => const SizedBox(), 16 / 9);
    await expectLater(
        windows.setPictureInPicture(true, 16 / 9), throwsStateError);
    expect(windows.pictureInPicture, false);
    expect(window.alwaysOnTop, false);
    await windows.shutdown();
  });
}

class _FrameDriver extends FakeDriver implements KernelFrameFeatures {
  _FrameDriver(super.lease, {super.kernel}) : super(mediaFacts: _media);
  @override
  Future<SeekOutcome> stepFrame(int delta) async {
    if (fenced) throw const KernelFenced();
    final next = position + Duration(milliseconds: delta * 40);
    sample(next, advancing: false);
    return SeekOutcome(SeekResult.done, next);
  }

  @override
  Future<KernelPicture> snapshotPicture() async =>
      KernelPicture(32, 18, Uint8List(32 * 18 * 4));
}

class _Engine implements FrameEngine {
  _Engine(this.source);
  final _FrameSource source;
  @override
  String get name => 'test';
  @override
  Future<FrameSource> open(String source,
          {int? width,
          int? maxEdge,
          String format = 'jpeg',
          required Duration timeout}) async =>
      this.source;
}

class _FrameSource implements FrameSource {
  final gate = Completer<void>();
  final requests = <int>[];
  bool closed = false;
  @override
  Future<RawFrame> frameAt(int atMs) async {
    requests.add(atMs);
    await gate.future;
    return RawFrame(
        width: 2, height: 2, rgba: Uint8List(16), timestampMs: atMs);
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  String get engine => 'test';
  @override
  int? get durationMs => 60000;
  @override
  int? get videoWidth => 2;
  @override
  int? get videoHeight => 2;
}

class _Window implements PlaybackWindowPort {
  @override
  bool closed = false;
  @override
  bool alwaysOnTop = false;
  bool failPip = false;
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> setAlwaysOnTop(bool value) async {
    alwaysOnTop = value;
  }

  @override
  Future<void> setPictureInPicture(bool value, double aspect) async {
    if (value && failPip) throw StateError('test');
  }
}

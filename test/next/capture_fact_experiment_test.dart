// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/player/classic/classic_playback_controls.dart';
import 'package:nipaplay/next/capabilities/playback_controls_capability.dart';
import 'package:nipaplay/next/player/classic/danmaku_port.dart';
import 'package:nipaplay/next/settings/application_settings.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class _Frames extends Fake implements AbstractPlayer {
  int snapshots = 0;
  final List<bool> visibilityCalls = [];
  Future<void> setDanmakuEnabled(bool enabled) async {
    visibilityCalls.add(enabled);
  }

  @override
  void setDecoders(PlayerMediaType type, List<String> decoders) {}
  @override
  void setProperty(String key, String value) {}
  @override
  String? getProperty(String key) => null;
  @override
  PlayerMediaInfo get mediaInfo => PlayerMediaInfo(duration: 10000, video: [
        PlayerVideoStreamInfo(
            codec: PlayerVideoCodecParams(width: 16, height: 16))
      ]);
  @override
  List<int> get activeSubtitleTracks => [];
  @override
  Future<PlayerFrame?> snapshot({int width = 0, int height = 0}) async {
    snapshots++;
    final image = img.Image(width: 16, height: 16);
    img.fill(image, color: img.ColorRgb8(0, 0, 255));
    return PlayerFrame(
        width: 16, height: 16, bytes: Uint8List.fromList(img.encodePng(image)));
  }
}

class _KernelPlayer extends Player {
  _KernelPlayer(super.delegate, this.kernel) : super.withDelegate();
  final String kernel;
  @override
  String getPlayerKernelName() => kernel;
  @override
  bool get supportsNativeDanmaku => kernel == 'Erika';
}

class _Video extends VideoPlayerState {
  _Video(super.suppliedPlayer) : super.forSettings();
  @override
  bool get hasVideo => true;
  @override
  String get currentVideoPath => '/fixture/video.mkv';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('nipa-x16-');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(root.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    ApplicationSettings.video = null;
    await root.delete(recursive: true);
  });

  for (final kernel in ['Erika', 'MDK', 'Media Kit', 'Video Player']) {
    testWidgets('X16 $kernel screenshot pixels and facts', (tester) async {
      final frames = _Frames();
      final video = _Video(_KernelPlayer(frames, kernel));
      expect(video.isNativeDanmakuActive, kernel == 'Erika');
      addTearDown(video.subtitleManager.dispose);
      final api =
          Harness([PlaybackControlsCapability(ClassicPlaybackControls(video))]);
      expect(api.lookup('playback.capture')!.spec.description,
          contains('Erika snapshots exclude native danmaku'));
      // Exercise the existing repaint-boundary capture path with a visible
      // red comment marker, honoring the same visibility flags as the player UI.
      await tester.pumpWidget(MaterialApp(
          home: Center(
              child: RepaintBoundary(
        key: video.screenshotBoundaryKey,
        child: AnimatedBuilder(
            animation: video,
            builder: (context, child) => SizedBox(
                  width: 16,
                  height: 16,
                  child: ColoredBox(
                      color: video.danmakuVisible &&
                              !video.shouldHideDanmakuForScreenshot
                          ? const Color(0xFFFF0000)
                          : const Color(0xFF0000FF)),
                )),
      ))));
      final cases = <({bool? include, bool setting, bool visible})>[
        (include: true, setting: true, visible: true),
        (include: false, setting: true, visible: true),
        (include: null, setting: false, visible: true),
        (include: true, setting: false, visible: true),
        (include: null, setting: true, visible: true),
        (include: true, setting: true, visible: false),
      ];
      for (var i = 0; i < cases.length; i++) {
        final c = cases[i];
        await video.setScreenshotCaptureIncludesDanmaku(c.setting);
        await video.setDanmakuVisible(c.visible);
        await tester.pump();
        final requested = c.include ?? c.setting;
        final included = kernel != 'Erika' && requested && c.visible;
        late JsonMap result;
        late String observedPixel;
        await tester.runAsync(() async {
          final pending = invokeCompleted(api, 'playback.capture', {
            'kind': 'screenshot',
            'outputPath': '${root.path}/$i.png',
            if (c.include != null) 'includeDanmaku': c.include,
          });
          if (kernel != 'Erika') {
            var finished = false;
            final rendering = pending.whenComplete(() => finished = true);
            final deadline = DateTime.now().add(const Duration(seconds: 3));
            while (!finished && DateTime.now().isBefore(deadline)) {
              await Future<void>.delayed(const Duration(milliseconds: 10));
              await tester.pump();
            }
            expect(finished, true,
                reason: 'Repaint-boundary capture must complete.');
            await rendering;
          }
          result = await pending;
          final image = img
              .decodePng(await File(result['path'] as String).readAsBytes())!;
          final pixel = image.getPixel(0, 0);
          observedPixel =
              '${pixel.r.toInt()},${pixel.g.toInt()},${pixel.b.toInt()}';
          expect(pixel.r, included ? 255 : 0);
          expect(pixel.b, included ? 0 : 255);
        });
        expect(result['danmakuRequested'], requested);
        expect(result['danmakuIncluded'], included);
        if (kernel == 'Erika') {
          expect(result['danmakuReason'], contains('Erika native danmaku'));
          expect(result['danmakuReason'],
              contains('does not indicate unloaded tracks'));
        } else {
          expect(result['danmakuReason'], included ? isNull : isNotNull);
        }
        expect(video.screenshotCaptureIncludesDanmaku, c.setting);
        expect(video.shouldHideDanmakuForScreenshot, false);
        print(
            'X16 $kernel input=${c.include} setting=${c.setting} visible=${c.visible} '
            'result=${jsonEncode({...result}..remove('path'))} '
            'rgb=$observedPixel');
      }
      expect(frames.snapshots, kernel == 'Erika' ? cases.length : 0);
      if (kernel == 'Erika') expect(frames.visibilityCalls.last, false);
      final port = VideoDanmakuPort(video);
      video.danmakuTracks['native-fixture'] = {
        'name': 'fixture',
        'source': 'bilibili',
        'platform': 'bilibili',
        'platformVideoId': '101',
        'count': 1,
        'bindingId': 'fixture-binding',
        'bindingRevision': 1,
      };
      video.danmakuTrackEnabled['native-fixture'] = true;
      expect(port.loaded('fixture-binding'), isNotNull);
      expect(port.registry.single['enabled'], true);
      expect(video.danmakuVisible, false);
      print(
          'X16 $kernel registry: loaded=${port.loaded('fixture-binding') != null} '
          'enabled=${port.registry.single['enabled']} displaySwitch=${video.danmakuVisible}');
      final settings = ApplicationSettings.entries();
      expect(
          settings
              .singleWhere((s) => s.key == 'player.screenshotIncludeDanmaku')
              .description,
          contains('Erika'));
      expect(
          settings.singleWhere((s) => s.key == 'danmaku.visible').description,
          contains('不代表'));
    });
  }
}

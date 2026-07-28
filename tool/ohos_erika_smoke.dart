import 'dart:async';
import 'dart:convert';

import 'package:erika_flutter/erika_flutter.dart';
import 'package:flutter/material.dart';

const String _mediaUri = String.fromEnvironment('ERIKA_SMOKE_URI');
const bool _requireZeroCopy = bool.fromEnvironment(
  'ERIKA_REQUIRE_ZERO_COPY',
);
const bool _denseDanmaku = bool.fromEnvironment('ERIKA_DENSE_DANMAKU');
const bool _loopPreview = bool.fromEnvironment('ERIKA_LOOP_PREVIEW');

String _denseDanmakuJson() {
  return jsonEncode(
    List<Map<String, Object>>.generate(1200, (index) {
      final mode = switch (index % 10) {
        0 => 'top',
        1 => 'bottom',
        _ => 'scroll',
      };
      return <String, Object>{
        'time': index / 150.0,
        'content': '鸿蒙 4K HDR 弹幕压力测试 ${index + 1}',
        'type': mode,
        'color': switch (index % 4) {
          0 => '#ffffff',
          1 => '#ffeb3b',
          2 => '#4fc3f7',
          _ => '#ff80ab',
        },
        'fontSize': 30,
      };
    }),
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ErikaOhosSmokeApp());
}

class _ErikaOhosSmokeApp extends StatefulWidget {
  const _ErikaOhosSmokeApp();

  @override
  State<_ErikaOhosSmokeApp> createState() => _ErikaOhosSmokeAppState();
}

class _ErikaOhosSmokeAppState extends State<_ErikaOhosSmokeApp> {
  final ErikaPlayer _player = ErikaPlayer();
  StreamSubscription<ErikaPlayerEvent>? _eventSubscription;
  String _activeVideoBackend = 'unknown';
  int _videoDecoderFallbacks = 0;
  String _status = 'waiting for surface';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_mediaUri.isEmpty) {
      _setStatus('FAIL: ERIKA_SMOKE_URI is empty');
      return;
    }
    try {
      _eventSubscription ??= _player.events.listen((event) {
        final decoder = event.decoder;
        if (decoder == null) {
          return;
        }
        _activeVideoBackend = decoder.activeBackend;
        _videoDecoderFallbacks = decoder.fallbackCount;
        debugPrint(
          '[ErikaOHOSSmoke] decoder stage=${decoder.stage} '
          'requested=${decoder.requestedBackend} '
          'active=${decoder.activeBackend} '
          'fallbacks=${decoder.fallbackCount} '
          'reason=${decoder.reason}',
        );
      });
      _setStatus('opening media');
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await _player.open(_mediaUri);
      if (_denseDanmaku) {
        await _player.setDanmakuConfig(
          enabled: true,
          displayArea: 1,
          allowStacking: true,
          allowScrollOverwrite: true,
          maxQuantity: 1200,
          maxLinesPerMode: 30,
        );
        await _player.loadDanmakuJson(_denseDanmakuJson());
      }
      await _player.play();
      _setStatus('playing');
      await Future<void>.delayed(const Duration(seconds: 2));
      _setStatus('seeking');
      await _player.seek(const Duration(seconds: 1));
      _setStatus('playing after seek');
      await Future<void>.delayed(const Duration(seconds: 3));
      final stats = await _player.getPresenterStats();
      final passed = stats.renderedVideoFrames > 0 &&
          stats.pushedAudioFrames > 0 &&
          stats.audioClockReadFrames > 0 &&
          stats.renderFailures == 0 &&
          stats.audioFailures == 0 &&
          _activeVideoBackend == 'avcodec' &&
          _videoDecoderFallbacks == 0 &&
          (!_denseDanmaku ||
              (stats.danmakuFrames > 0 &&
                  stats.danmakuItems > 0 &&
                  stats.videoFrameBackpressureDrops == 0)) &&
          (!_requireZeroCopy ||
              (stats.zeroCopyVideoFrames > 0 &&
                  stats.sharedHandleVideoFrames > 0 &&
                  stats.cpuVideoFrameFallbacks == 0));
      final result = 'backend=$_activeVideoBackend '
          'fallbacks=$_videoDecoderFallbacks '
          'video=${stats.renderedVideoFrames} '
          'audioPush=${stats.pushedAudioFrames} '
          'audioRead=${stats.audioClockReadFrames} '
          'zeroCopy=${stats.zeroCopyVideoFrames} '
          'shared=${stats.sharedHandleVideoFrames} '
          'cpuFallback=${stats.cpuVideoFrameFallbacks} '
          'danmakuFrames=${stats.danmakuFrames} '
          'danmakuItems=${stats.danmakuItems} '
          'backpressure=${stats.videoFrameBackpressureDrops} '
          'renderFailures=${stats.renderFailures} '
          'audioFailures=${stats.audioFailures}';
      _setStatus('${passed ? "PASS" : "FAIL"}: $result');
      debugPrint('[ErikaOHOSSmoke] ${passed ? "PASS" : "FAIL"} $result');
      if (passed && _loopPreview) {
        while (mounted) {
          await _player.seek(Duration.zero);
          await Future<void>.delayed(const Duration(seconds: 7));
        }
      }
    } catch (error, stackTrace) {
      _setStatus('FAIL: $error');
      debugPrint('[ErikaOHOSSmoke] FAIL: $error\n$stackTrace');
    }
  }

  void _setStatus(String value) {
    if (!mounted) {
      return;
    }
    setState(() {
      _status = value;
    });
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            ErikaVideoView(player: _player, debugLabel: 'ohos-smoke'),
            Align(
              alignment: Alignment.topCenter,
              child: SafeArea(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

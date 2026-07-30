import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/decoder_manager.dart';

const String _mediaUri = String.fromEnvironment('MDK_SMOKE_URI');
const bool _requireHardwareDecoder = bool.fromEnvironment(
  'MDK_SMOKE_REQUIRE_HARDWARE',
  defaultValue: true,
);

bool _isOhosHardwareVideoDecoder(String? decoder) {
  return decoder == 'OH' || decoder == 'OHVideoDecoder';
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _MdkOhosSmokeApp());
}

class _MdkOhosSmokeApp extends StatefulWidget {
  const _MdkOhosSmokeApp();

  @override
  State<_MdkOhosSmokeApp> createState() => _MdkOhosSmokeAppState();
}

class _MdkOhosSmokeAppState extends State<_MdkOhosSmokeApp> {
  Player? _player;
  String _status = 'initializing MDK';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_run());
    });
  }

  Future<void> _run() async {
    if (_mediaUri.isEmpty) {
      _setStatus('FAIL: MDK_SMOKE_URI is empty');
      return;
    }

    PlayerKernelType? originalKernel;
    try {
      await PlayerFactory.initialize();
      originalKernel = PlayerFactory.getKernelType();
      await PlayerFactory.saveKernelType(PlayerKernelType.mdk);

      final player = Player();
      _player = player;
      if (mounted) {
        setState(() {});
      }

      if (player.getPlayerKernelName() != 'MDK') {
        throw StateError(
          'factory created ${player.getPlayerKernelName()} instead of MDK',
        );
      }

      // The created player keeps its delegate, so restore the user's preferred
      // kernel before starting playback.
      await PlayerFactory.saveKernelType(originalKernel);
      originalKernel = null;

      _setStatus('opening media with MDK');
      if (_requireHardwareDecoder) {
        DecoderManager(player: player);
        await _waitUntil(
          () => player.getDecoders(MediaType.video).contains('OH'),
          timeout: const Duration(seconds: 5),
          description: 'HarmonyOS decoder preference migration',
          diagnostics: () =>
              'configuredDecoders=${player.getDecoders(MediaType.video)}',
        );
      }
      player.media = _mediaUri;
      await player.prepare();

      await _waitUntil(
        () =>
            player.mediaInfo.duration > 0 &&
            player.state != PlaybackState.stopped,
        timeout: const Duration(seconds: 15),
        description: 'media preparation',
        diagnostics: () => 'state=${player.state.name} '
            'duration=${player.mediaInfo.duration} '
            'texture=${player.textureId.value} '
            'media=${player.media}',
      );

      final createdTextureId = await player.updateTexture();
      if (createdTextureId == null || createdTextureId < 0) {
        throw StateError('MDK failed to create a video texture');
      }

      player.state = PlaybackState.playing;
      _setStatus('playing with MDK');
      final startPosition = player.position;

      await _waitUntil(
        () => player.position >= startPosition + 2000,
        timeout: const Duration(seconds: 10),
        description: 'playback position advance',
        diagnostics: () => 'state=${player.state.name} '
            'position=${player.position} '
            'videoDecoder=${player.getProperty("decoder.video")} '
            'audioDecoder=${player.getProperty("decoder.audio")}',
      );

      final info = await player.getDetailedMediaInfoAsync();
      final videoTracks = player.mediaInfo.video?.length ?? 0;
      final audioTracks = player.mediaInfo.audio?.length ?? 0;
      final textureId = player.textureId.value;
      final endPosition = player.position;
      final videoDecoder = player.getProperty('decoder.video');
      final audioDecoder = player.getProperty('decoder.audio');
      final configuredDecoders = player.getDecoders(MediaType.video);
      final hardwareDecoderActive =
          !_requireHardwareDecoder || _isOhosHardwareVideoDecoder(videoDecoder);

      final passed = player.getPlayerKernelName() == 'MDK' &&
          player.mediaInfo.duration > 0 &&
          textureId != null &&
          textureId >= 0 &&
          endPosition >= startPosition + 2000 &&
          videoTracks > 0 &&
          audioTracks > 0 &&
          hardwareDecoderActive;
      final result = 'kernel=${player.getPlayerKernelName()} '
          'requestedDecoders=${_requireHardwareDecoder ? configuredDecoders : "default"} '
          'duration=${player.mediaInfo.duration} '
          'position=$startPosition->$endPosition '
          'texture=$textureId '
          'videoTracks=$videoTracks '
          'audioTracks=$audioTracks '
          'videoDecoder=${videoDecoder ?? "pending"} '
          'audioDecoder=${audioDecoder ?? "pending"} '
          'infoKernel=${info["kernel"]}';

      _setStatus('${passed ? "PASS" : "FAIL"}: $result');
      debugPrint('[MdkOHOSSmoke] ${passed ? "PASS" : "FAIL"} $result');
    } catch (error, stackTrace) {
      _setStatus('FAIL: $error');
      debugPrint('[MdkOHOSSmoke] FAIL: $error\n$stackTrace');
    } finally {
      if (originalKernel != null) {
        await PlayerFactory.saveKernelType(originalKernel);
      }
    }
  }

  Future<void> _waitUntil(
    bool Function() condition, {
    required Duration timeout,
    required String description,
    required String Function() diagnostics,
  }) async {
    final deadline = DateTime.now().add(timeout);
    var checks = 0;
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(
          '$description timed out: ${diagnostics()}',
          timeout,
        );
      }
      checks++;
      if (checks % 10 == 0) {
        debugPrint('[MdkOHOSSmoke] waiting for $description: ${diagnostics()}');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
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
    unawaited(_player?.disposeAsync());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (player != null)
              ValueListenableBuilder<int?>(
                valueListenable: player.textureId,
                builder: (context, textureId, _) {
                  if (textureId == null || textureId < 0) {
                    return const SizedBox.shrink();
                  }
                  return Texture(
                    textureId: textureId,
                    filterQuality: FilterQuality.medium,
                  );
                },
              ),
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fvp/mdk.dart' as mdk;
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/screen_orientation_manager.dart';

const _uri = String.fromEnvironment('MDK_SMOKE_URI');
const _cycles = int.fromEnvironment('MDK_SMOKE_CYCLES', defaultValue: 4);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: _ReopenSmoke()));
}

class _ReopenSmoke extends StatefulWidget {
  const _ReopenSmoke();

  @override
  State<_ReopenSmoke> createState() => _ReopenSmokeState();
}

class _ReopenSmokeState extends State<_ReopenSmoke> {
  mdk.Player? _player;
  String _status = 'Starting MDK reopen test';
  bool _passed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _report(String message) {
    debugPrint('[MdkReopenSmoke] $message');
    if (mounted) setState(() => _status = message);
  }

  Future<void> _waitFor(bool Function() condition, String description) async {
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException(description);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Future<void> _run() async {
    try {
      if (_uri.isEmpty) throw StateError('MDK_SMOKE_URI is required');
      await globals.initializeStartupDeviceProfile();
      final player = mdk.Player();
      _player = player;
      player.videoDecoders = ['OH', 'FFmpeg'];
      player.volume = 0;
      if (mounted) setState(() {});
      final idleFrame = await player
          .snapshot(width: 160, height: 90)
          .timeout(const Duration(seconds: 1));
      if (idleFrame != null) {
        throw StateError('An idle player has no surface to capture');
      }

      var capturedFrames = 0;
      for (var cycle = 1; cycle <= _cycles; cycle++) {
        _report('Cycle $cycle/$_cycles: opening');
        player.media = _uri;
        final prepared = await player.prepare().timeout(
              const Duration(seconds: 10),
            );
        if (prepared < 0) throw StateError('prepare returned $prepared');
        await _waitFor(
          () => player.state == mdk.PlaybackState.paused,
          'cycle $cycle did not finish preparing: state=${player.state.name}',
        );
        final texture = await player.updateTexture().timeout(
              const Duration(seconds: 10),
            );
        if (texture < 0) throw StateError('video texture was not created');
        player.state = mdk.PlaybackState.playing;
        final start = player.position;
        await _waitFor(
          () => player.position >= start + 750,
          'cycle $cycle playback did not advance (start=$start)',
        );

        await ScreenOrientationManager.instance.setPhonePlaybackLandscape();
        await _waitFor(
          () => ScreenOrientationManager.instance.isLandscape,
          'cycle $cycle could not enter landscape',
        );
        _report('Cycle $cycle/$_cycles: playing, texture=$texture');
        await Future<void>.delayed(const Duration(milliseconds: 350));
        final frame = await player
            .snapshot(width: 160, height: 90)
            .timeout(const Duration(seconds: 2));
        // A renderer can skip readback during rotation. A skipped frame must
        // return null promptly, and successful readbacks must have valid size.
        if (frame != null) {
          if (frame.length != 160 * 90 * 4) {
            throw StateError('cycle $cycle returned an invalid frame');
          }
          capturedFrames++;
        }
        _report('Cycle $cycle/$_cycles: snapshot ${frame?.length ?? 0} bytes');

        // Match the phone back path: return to portrait, stop, clear media,
        // release the old surface, then reuse this same native player.
        await ScreenOrientationManager.instance.setPhonePlaybackPortrait();
        await _waitFor(
          () => !ScreenOrientationManager.instance.isLandscape,
          'cycle $cycle could not return to portrait',
        );
        player.state = mdk.PlaybackState.stopped;
        player.media = '';
        await player.updateTexture(width: -1).timeout(
              const Duration(seconds: 5),
            );
        _report('Cycle $cycle/$_cycles: stopped and surface released');
      }

      if (capturedFrames == 0) {
        throw StateError('No surface readback succeeded');
      }
      await player.dispose().timeout(const Duration(seconds: 8));
      _player = null;
      _passed = true;
      _report('PASS: $_cycles MDK play/back/reopen cycles, '
          '$capturedFrames surface snapshots');
    } catch (error, stack) {
      final player = _player;
      _report('FAIL: $error; state=${player?.state.name} '
          'position=${player?.position} '
          'duration=${player?.mediaInfo.duration}');
      debugPrint('[MdkReopenSmoke] $stack');
    }
  }

  @override
  void dispose() {
    unawaited(_player?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (player != null)
            ValueListenableBuilder<int?>(
              valueListenable: player.textureId,
              builder: (context, id, _) => id == null || id < 0
                  ? const SizedBox.shrink()
                  : Texture(textureId: id),
            ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(20),
                child: Text(
                  _status,
                  style: TextStyle(
                    color: _passed ? Colors.greenAccent : Colors.white,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

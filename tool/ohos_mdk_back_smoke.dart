import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/main.dart' as app;
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/player_abstraction/player_abstraction.dart'
    show PlaybackState;
import 'package:nipaplay/services/playback_source_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/back_button_widget.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/screen_orientation_manager.dart';
import 'package:nipaplay/utils/tab_change_notifier.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

const _uri = String.fromEnvironment('MDK_SMOKE_URI');
const _cycles = int.fromEnvironment('MDK_SMOKE_CYCLES', defaultValue: 3);
String _status = 'Waiting for the complete app';
bool _passed = false;
OverlayEntry? _reportOverlay;

void main() {
  app.main(const []);
  unawaited(_run());
}

void _report(String message) {
  _status = message;
  debugPrint('[MdkBackSmoke] $message');
  _reportOverlay?.markNeedsBuild();
  // Test-only telemetry stays on the fixture server reached through hdc rport.
  unawaited(() async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(_uri).replace(
        path: '/__mdk_back_smoke',
        queryParameters: {'status': message},
      );
      final request = await client.getUrl(uri);
      final response = await request.close();
      await response.drain<void>();
    } catch (_) {
      // The on-device overlay remains available without the fixture server.
    } finally {
      client.close(force: true);
    }
  }());
}

Future<void> _waitFor(bool Function() condition, String description,
    {Duration timeout = const Duration(seconds: 12)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException(description);
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void _tapTopLeftBack() {
  Element? backElement;
  void findBack(Element element) {
    if (element.widget is BackButtonWidget &&
        (element.widget as BackButtonWidget).videoState.hasVideo) {
      backElement = element;
      return;
    }
    element.visitChildren(findBack);
  }

  findBack(globals.navigatorKey.currentContext! as Element);
  if (backElement == null) throw StateError('Top-left back button not found');
  GestureDetector? button;
  void findTap(Element element) {
    final widget = element.widget;
    if (widget is GestureDetector && widget.onTapUp != null) button = widget;
    element.visitChildren(findTap);
  }

  backElement!.visitChildren(findTap);
  if (button == null) throw StateError('Back button has no tap handler');
  button!.onTapUp!(TapUpDetails(kind: PointerDeviceKind.touch));
}

Future<void> _run() async {
  final fixturePaths = <String>[];
  VideoPlayerState? videoState;
  try {
    if (_uri.isEmpty) throw StateError('MDK_SMOKE_URI is required');
    await _waitFor(
      () => globals.navigatorKey.currentContext != null,
      'App startup',
      timeout: const Duration(seconds: 30),
    );
    // Let the main app finish restoring its initial tab before selecting video.
    await Future<void>.delayed(const Duration(seconds: 2));
    final context = globals.navigatorKey.currentContext!;
    if (!context.mounted) throw StateError('App context was disposed');
    final state = context.read<VideoPlayerState>();
    final tabs = context.read<TabChangeNotifier>();
    videoState = state;
    if (state.player.getPlayerKernelName() != 'MDK') {
      throw StateError('Select the MDK kernel before this regression test');
    }
    _reportOverlay = OverlayEntry(
      builder: (_) => Positioned(
        right: 12,
        top: 60,
        child: IgnorePointer(
          child: Material(
            color: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _status,
                style: TextStyle(
                  color: _passed ? Colors.greenAccent : Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    globals.navigatorKey.currentState!.overlay!.insert(_reportOverlay!);

    for (var cycle = 1; cycle <= _cycles; cycle++) {
      _report('Back-button cycle $cycle/$_cycles: opening');
      tabs.changePage(AppPageIds.video);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final uri = '$_uri?back-cycle=$cycle';
      fixturePaths.add(uri);
      await state
          .initializePlayer(
            uri,
            actualPlayUrl: uri,
            playbackDetailContext: PlaybackSourceService.fallback(
              PlayableItem(videoPath: uri, title: 'MDK back-button fixture'),
            ),
            manualMatchHandled: true,
            episodeFileSelectionHandled: true,
          )
          .timeout(const Duration(seconds: 25));
      await _waitFor(
        () => state.player.state != PlaybackState.stopped,
        'cycle $cycle native player did not prepare',
      );
      state.play();
      state.player.volume = 0;
      await _waitFor(
        () => state.player.position >= 750 && state.isFullscreen,
        'cycle $cycle did not start landscape playback',
      );

      final exit = Stopwatch()..start();
      _report('Back-button cycle $cycle/$_cycles: leaving landscape');
      _tapTopLeftBack();
      await _waitFor(
        () =>
            !state.isFullscreen &&
            !ScreenOrientationManager.instance.isLandscape,
        'cycle $cycle did not return to portrait',
      );
      _tapTopLeftBack();
      await _waitFor(
        () => !state.hasVideo,
        'cycle $cycle did not finish resetting',
      );
      _report(
          'Back-button cycle $cycle/$_cycles: reset ${exit.elapsedMilliseconds}ms');
    }
    _passed = true;
    _report('PASS: $_cycles full-app MDK top-left-back/replay cycles');
  } catch (error, stack) {
    _report('FAIL: $error; status=${videoState?.status.name} '
        'native=${videoState?.player.state.name} '
        'position=${videoState?.player.position} '
        'texture=${videoState?.player.textureId.value}');
    debugPrint('[MdkBackSmoke] $stack');
  } finally {
    for (final path in fixturePaths) {
      await WatchHistoryManager.removeHistoryItem(path);
    }
  }
}

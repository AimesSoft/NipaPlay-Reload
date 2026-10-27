import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/classic_mode_policy.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

import '../../next_runtime.dart';
import '../player/playback.dart';
import '../player/stage.dart';
import '../player/video_stage.dart';
import '../../player/ports/session_playback.dart';
import 'next_shell.dart';
import 'file_open_host.dart';
import 'next_ui_preference.dart';
import 'window_chrome.dart';

/// Mounts exactly one interface. Classic is disposed while Next is open;
/// playback shutdown and progress persistence belong to NextRuntime.
class NextUiGate extends StatefulWidget {
  const NextUiGate(
      {super.key,
      this.classic,
      this.classicBuilder,
      this.launchFilePath,
      this.openNextFile})
      : assert(classic != null || classicBuilder != null);
  final Widget? classic;
  final Widget Function(String? launchFilePath)? classicBuilder;
  final String? launchFilePath;
  final Future<void> Function(String path)? openNextFile;

  @override
  State<NextUiGate> createState() => _NextUiGateState();
}

class _NextUiGateState extends State<NextUiGate> {
  LabsSettingsProvider? _labs;
  NextUiPreference? _preference;
  Future<void>? _ready;
  VoidCallback? _unbindMode;
  bool _launchClaimed = false, _classicEntry = false;
  String? _classicLaunch;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final labs = context.read<LabsSettingsProvider>();
    final preference = context.read<NextUiPreference>();
    if (identical(labs, _labs) && identical(preference, _preference)) return;
    _unbindMode?.call();
    _labs = labs;
    _preference = preference;
    _ready = Future.wait([labs.ready, preference.ready]);
    _unbindMode = ClassicModePolicy.bind(labs, preference);
  }

  /// How far the conversation is in beside the video; the panel moves it.
  final _stage = ValueNotifier<double>(0);

  @override
  void dispose() {
    _unbindMode?.call();
    _stage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labs = context.watch<LabsSettingsProvider>();
    final preference = context.watch<NextUiPreference>();
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, ready) {
        if (ready.connectionState != ConnectionState.done) {
          return const SizedBox.expand();
        }
        return _interface(context, labs, preference);
      },
    );
  }

  Widget _interface(BuildContext context, LabsSettingsProvider labs,
      NextUiPreference preference) {
    final on = NextUiPreference.interfaceOpen(
        nextEnabled: labs.enableAgentEndpoint, preference: preference.enabled);
    globals.nextShellHostsPlayer = on;
    if (!on) {
      if (!_classicEntry) {
        _classicLaunch = _launchClaimed ? null : widget.launchFilePath;
        _launchClaimed = true;
        _classicEntry = true;
      }
      return widget.classicBuilder?.call(_classicLaunch) ?? widget.classic!;
    }
    _classicEntry = false;
    final nextLaunch = _launchClaimed ? null : widget.launchFilePath;
    _launchClaimed = true;
    final window = DesktopPlayerWindowService.instance;
    final playback = NextPlaybackScope.maybeOf(context) ??
        context.read<NextRuntime>().playback;
    final nextWindows = playback is SessionPlayback ? playback.windows : null;
    return NextFileOpenHost(
      launchFilePath: nextLaunch,
      openFile: widget.openNextFile,
      child: NextPlaybackScope(
        playback: playback,
        child: PlaybackSelector<(bool, bool)>(
          playback: playback,
          listenable: Listenable.merge([
            window,
            playback.transport,
            if (nextWindows != null) nextWindows
          ]),
          selector: (p) => (
            p.transport.value.active &&
                !(nextWindows?.detached ?? window.isPlayerDetached),
            // The system draws the video under the window (Erika, Media
            // Kit's native video), not Flutter in a texture.
            p.transport.value.systemDrawn,
          ),
          builder: (context, frame, _) {
            final (playing, systemDrawn) = frame;
            final stage =
                playback is VideoStageHost ? playback as VideoStageHost : null;
            return Stack(
              fit: StackFit.expand,
              children: [
                NextStageRoom(
                  slide: _stage,
                  docked: playing,
                  fit: !systemDrawn,
                  stepped: systemDrawn,
                  backdrop: true,
                  child: Stack(fit: StackFit.expand, children: [
                    if (stage != null && playing)
                      NextVideoStage(key: nextWindows?.stageKey, host: stage),
                  ]),
                ),
                // Next's window chrome stays while the video is on, so the
                // traffic lights keep their place on the player's bar too.
                NextStage(
                  slide: _stage,
                  stepped: systemDrawn,
                  child: NextWindowChromeScope(
                    active: true,
                    child: NextShell(
                      onLeave: () => preference.setEnabled(false),
                      playing: playing,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

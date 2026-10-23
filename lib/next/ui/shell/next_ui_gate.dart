import 'package:flutter/widgets.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';

import '../../next_runtime.dart';
import '../player/playback.dart';
import '../player/stage.dart';
import 'next_shell.dart';
import 'next_ui_preference.dart';
import 'window_chrome.dart';

/// Chooses between Classic and the Next shell.
///
/// With the preference off this is Classic exactly as before: the same
/// widget, visible, focusable and animating. With it on, Classic stays
/// mounted underneath (its services, hotkeys and player keep working) and
/// is revealed while a video is open, since playback still uses Classic's
/// player: its video, danmaku and subtitles show through, and the shell
/// draws the controls over them ([NextShell.playing]). With the
/// conversation open beside the video, Classic goes left of it, black under
/// the panel ([NextStageRoom]): drawn smaller as one picture while Flutter
/// draws the video, laid out there while the system does (its picture
/// follows Classic's layout). A video moved out to its own window leaves
/// this one to the shell's pages.
class NextUiGate extends StatefulWidget {
  const NextUiGate({super.key, required this.classic});
  final Widget classic;

  @override
  State<NextUiGate> createState() => _NextUiGateState();
}

class _NextUiGateState extends State<NextUiGate> {
  final _classicKey = GlobalKey(debugLabel: 'classic');

  /// How far the conversation is in beside the video; the panel moves it.
  final _stage = ValueNotifier<double>(0);

  @override
  void dispose() {
    _stage.dispose();
    super.dispose();
  }

  Widget _classic(bool hidden) =>
      _ClassicHost(key: _classicKey, hidden: hidden, child: widget.classic);

  @override
  Widget build(BuildContext context) {
    final labs = context.watch<LabsSettingsProvider>();
    final preference = context.watch<NextUiPreference>();
    final on = NextUiPreference.interfaceOpen(
        nextEnabled: labs.enableAgentEndpoint, preference: preference.enabled);
    globals.nextShellHostsPlayer = on;
    if (!on) return _classic(false);
    final window = DesktopPlayerWindowService.instance;
    final playback = NextPlaybackScope.maybeOf(context) ??
        context.read<NextRuntime>().playback;
    return NextPlaybackScope(
      playback: playback,
      child: PlaybackSelector<(bool, bool)>(
        playback: playback,
        listenable: Listenable.merge([window, playback.transport]),
        selector: (p) => (
          p.transport.value.active && !window.isPlayerDetached,
          // The system draws the video under the window (Erika, Media
          // Kit's native video), not Flutter in a texture.
          p.transport.value.systemDrawn,
        ),
        builder: (context, frame, _) {
          final (playing, systemDrawn) = frame;
          return Stack(
            fit: StackFit.expand,
            children: [
              NextStageRoom(
                slide: _stage,
                docked: playing,
                fit: !systemDrawn,
                stepped: systemDrawn,
                backdrop: true,
                child: _classic(!playing),
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
    );
  }
}

class _ClassicHost extends StatelessWidget {
  const _ClassicHost({super.key, required this.hidden, required this.child});
  final bool hidden;
  final Widget child;

  // One structure in both states, so Classic is never remounted when the
  // shell hides or reveals it; with [hidden] false every wrapper is inert.
  @override
  Widget build(BuildContext context) => ExcludeFocus(
        excluding: hidden,
        child: Offstage(
          offstage: hidden,
          child: TickerMode(enabled: !hidden, child: child),
        ),
      );
}

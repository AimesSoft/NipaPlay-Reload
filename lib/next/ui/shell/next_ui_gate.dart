import 'package:flutter/widgets.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

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
/// draws the controls over them ([NextShell.playing]). A video moved out
/// to its own window leaves this one to the shell's pages.
class NextUiGate extends StatefulWidget {
  const NextUiGate({super.key, required this.classic});
  final Widget classic;

  @override
  State<NextUiGate> createState() => _NextUiGateState();
}

class _NextUiGateState extends State<NextUiGate> {
  final _classicKey = GlobalKey(debugLabel: 'classic');

  static bool _playing(PlayerStatus status) => const {
        PlayerStatus.loading,
        PlayerStatus.recognizing,
        PlayerStatus.ready,
        PlayerStatus.playing,
        PlayerStatus.paused,
      }.contains(status);

  Widget _classic(bool hidden) =>
      _ClassicHost(key: _classicKey, hidden: hidden, child: widget.classic);

  @override
  Widget build(BuildContext context) {
    final labs = context.watch<LabsSettingsProvider>();
    final preference = context.watch<NextUiPreference>();
    final on =
        globals.isDesktop && labs.enableAgentEndpoint && preference.enabled;
    globals.nextShellHostsPlayer = on;
    if (!on) return _classic(false);
    final window = DesktopPlayerWindowService.instance;
    return ListenableBuilder(
      listenable: window,
      builder: (context, _) => Selector<VideoPlayerState, bool>(
        selector: (_, player) =>
            _playing(player.status) && !window.isPlayerDetached,
        builder: (context, playing, _) => Stack(
          fit: StackFit.expand,
          children: [
            _classic(!playing),
            // Next's window chrome stays while the video is on, so the
            // traffic lights keep their place on the player's bar too.
            NextWindowChromeScope(
              active: true,
              child: NextShell(
                onLeave: () => preference.setEnabled(false),
                playing: playing,
              ),
            ),
          ],
        ),
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

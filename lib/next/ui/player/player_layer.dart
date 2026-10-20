import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/services/intro_skip/skip_segment.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../ui_data/ui_data.dart' show NextNowPlaying, UiNowPlaying;
import '../shell/nipa_setup.dart';
import '../shell/shell_controller.dart';
import '../shell/window_chrome.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import 'player_menus.dart';
import 'playback.dart';
import 'timeline.dart';

enum _Menu { subtitles, episodes }

/// Next's controls over Classic's video. The picture, danmaku, subtitles,
/// clicks on the picture (pause, double click for full screen), the
/// right-click menu and the hotkeys stay Classic's; this draws what is
/// over them: back and the title on the window's bar, Nipa on the right,
/// the timeline with its heat and the controls below.
///
/// They come with the pointer and go when it rests, as Classic's do
/// ([VideoPlayerState.showControls]); they stay while the pointer is on
/// them, a menu is open or Nipa's panel is. ⌘K asks Nipa, in the panel
/// over the video.
class NextPlayerLayer extends StatefulWidget {
  const NextPlayerLayer({super.key});

  @override
  State<NextPlayerLayer> createState() => _NextPlayerLayerState();
}

class _NextPlayerLayerState extends State<NextPlayerLayer> {
  NextShellController? _shell;
  NextPlayback? _own;
  NextPlayback? _playback;
  bool _overChrome = false;
  bool _scrubbing = false;
  _Menu? _menu;
  bool _holding = false;
  final _menuFocus = FocusNode(debugLabel: 'next.player.menu');

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (!identical(shell, _shell)) {
      _shell?.panelOpen.removeListener(_panelChanged);
      _shell = shell..panelOpen.addListener(_panelChanged);
    }
    final playback = NextPlaybackScope.maybeOf(context) ??
        (_own ??= NextPlayback(context.read<VideoPlayerState>()));
    if (!identical(playback, _playback)) {
      _release();
      _playback = playback;
      _syncHold();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _shell?.panelOpen.removeListener(_panelChanged);
    _release();
    _menuFocus.dispose();
    super.dispose();
  }

  void _panelChanged() {
    if (_shell!.panelOpen.value) _menu = null;
    setState(() {});
    _syncHold();
  }

  /// Classic's hotkeys rest while a menu or the panel is open: space and
  /// Esc belong to them then. The lock notifies Classic's listeners, so it
  /// is taken and given back after the build or teardown that asked.
  void _syncHold() {
    final want = _menu != null || (_shell?.panelOpen.value ?? false);
    if (want == _holding) return;
    _holding = want;
    final playback = _playback!;
    scheduleMicrotask(want ? playback.holdHotkeys : playback.releaseHotkeys);
  }

  void _release() {
    if (!_holding) return;
    _holding = false;
    scheduleMicrotask(_playback!.releaseHotkeys);
  }

  /// ⌘K wherever the focus is (Classic's video holds it while watching).
  bool _onKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.keyK) return false;
    final keys = HardwareKeyboard.instance;
    if (!(keys.isMetaPressed || keys.isControlPressed) ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return false;
    }
    _closeMenu();
    _shell?.ask();
    return true;
  }

  void _toggleMenu(_Menu which) {
    if (_menu == which) return _closeMenu();
    setState(() => _menu = which);
    _syncHold();
    // Esc is the menu's while it is open.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _menu != null) _menuFocus.requestFocus();
    });
  }

  void _closeMenu() {
    if (_menu == null) return;
    setState(() => _menu = null);
    _syncHold();
    if (_menuFocus.hasFocus) {
      _menuFocus.unfocus(disposition: UnfocusDisposition.previouslyFocusedChild);
    }
  }

  void _hoverChrome(bool over) {
    if (_overChrome == over) return;
    setState(() => _overChrome = over);
    _playback!.hover(over);
  }

  void _scrub(bool on) => setState(() => _scrubbing = on);

  Future<void> _back() async {
    _closeMenu();
    _shell?.closePanel();
    try {
      await _playback!.leave();
    } catch (e) {
      debugPrint('[NextPlayer] leave: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    final playback = _playback!;
    return Selector<VideoPlayerState, (bool, bool, bool)>(
      selector: (_, s) => (
        s.hasVideo,
        s.status == PlayerStatus.loading ||
            s.status == PlayerStatus.recognizing,
        s.showControls,
      ),
      builder: (context, frame, _) {
        final (hasVideo, loading, controls) = frame;
        final pinned = _overChrome ||
            _scrubbing ||
            _menu != null ||
            shell.panelOpen.value;
        final shown = hasVideo && (controls || pinned);
        return Stack(fit: StackFit.expand, children: [
          if (loading && !hasVideo) const Positioned.fill(child: _Loading()),
          if (hasVideo) ...[
            Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 150,
                child: _Shade(shown: shown, top: true)),
            Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 280,
                child: _Shade(shown: shown, top: false)),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: _Fade(
                shown: shown,
                from: const Offset(0, -0.12),
                child: MouseRegion(
                  onEnter: (_) => _hoverChrome(true),
                  onExit: (_) => _hoverChrome(false),
                  child: _TopBar(onBack: _back, shell: shell),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _Fade(
                shown: shown,
                from: const Offset(0, 0.08),
                child: MouseRegion(
                  onEnter: (_) => _hoverChrome(true),
                  onExit: (_) => _hoverChrome(false),
                  child: _BottomBar(
                    playback: playback,
                    menu: _menu,
                    onMenu: _toggleMenu,
                    onScrub: _scrub,
                  ),
                ),
              ),
            ),
            _SkipSegment(raised: shown, playback: playback),
            if (_menu != null) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),
              Positioned(
                right: _BottomBar.menuRight(_menu!),
                bottom: _BottomBar.height + 2,
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.escape):
                        _closeMenu,
                  },
                  child: Focus(
                    focusNode: _menuFocus,
                    child: MouseRegion(
                      onEnter: (_) => _hoverChrome(true),
                      child: switch (_menu!) {
                        _Menu.subtitles => SubtitleMenu(
                            playback: playback, onDone: _closeMenu),
                        _Menu.episodes => EpisodeMenu(
                            playback: playback,
                            shell: shell,
                            onDone: _closeMenu),
                      },
                    ),
                  ),
                ),
              ),
            ],
          ],
        ]);
      },
    );
  }
}

/// The shade that lets the bars read over any picture.
class _Shade extends StatelessWidget {
  const _Shade({required this.shown, required this.top});
  final bool shown;
  final bool top;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          curve: NextMotion.ease,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: top
                    ? const [Color(0xB308080B), Color(0x0008080B)]
                    : const [
                        Color(0xE608080B),
                        Color(0x8C08080B),
                        Color(0x0008080B)
                      ],
                stops: top ? null : const [0, 0.42, 1],
              ),
            ),
          ),
        ),
      );
}

class _Fade extends StatelessWidget {
  const _Fade({required this.shown, required this.from, required this.child});
  final bool shown;
  final Offset from;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    return IgnorePointer(
      ignoring: !shown,
      child: AnimatedOpacity(
        opacity: shown ? 1 : 0,
        duration: const Duration(milliseconds: 220),
        curve: NextMotion.ease,
        child: AnimatedSlide(
          offset: shown || reduced ? Offset.zero : from,
          duration: const Duration(milliseconds: 260),
          curve: NextMotion.ease,
          child: child,
        ),
      ),
    );
  }
}

/// The window's bar over the video: back and what plays on the traffic
/// lights' line, Nipa on the right. The empty bar moves the window.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack, required this.shell});
  final VoidCallback onBack;
  final NextShellController shell;

  static double _left(NextChromeLayout chrome) => chrome.fullScreen
      ? NextMetrics.chromeEdge
      : math.max(NextMetrics.chromeEdge, chrome.leading + 14);

  @override
  Widget build(BuildContext context) => SizedBox(
        height: NextMetrics.topBar,
        child: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => unawaited(windowManager.startDragging()),
            ),
          ),
          Positioned.fill(
            child: ValueListenableBuilder(
              valueListenable: NextWindowChrome.layout,
              builder: (context, chrome, row) => Padding(
                padding: EdgeInsets.only(
                    left: _left(chrome), right: NextMetrics.chromeEdge),
                child: row,
              ),
              child: Row(children: [
                NextIconButton(
                    glyph: NextGlyph.chevronLeft, label: '返回', onTap: onBack),
                const SizedBox(width: 8),
                const Expanded(child: _Title()),
                const SizedBox(width: 16),
                _Nipa(shell: shell),
              ]),
            ),
          ),
        ]),
      );
}

/// The names of what plays: the library's work and episode when it knows the
/// file, Classic's otherwise (a file Next never matched).
class _Titles extends StatefulWidget {
  const _Titles({required this.builder});
  final Widget Function(BuildContext context, String work, String episode)
      builder;

  @override
  State<_Titles> createState() => _TitlesState();
}

class _TitlesState extends State<_Titles> {
  String? _path;
  Future<UiNowPlaying?>? _known;

  @override
  Widget build(BuildContext context) =>
      Selector<VideoPlayerState, (String?, String?, String?)>(
        selector: (_, s) => (s.currentVideoPath, s.animeTitle, s.episodeTitle),
        builder: (context, v, _) {
          if (v.$1 != _path) {
            _path = v.$1;
            _known = null;
            if (_path case final path?) {
              if (NextShellScope.of(context).services.data
                  case final NextNowPlaying data) {
                _known = data.nowPlaying(path);
              }
            }
          }
          return FutureBuilder(
            future: _known,
            builder: (context, known) {
              if (_known != null &&
                  known.connectionState != ConnectionState.done) {
                return widget.builder(context, '', '');
              }
              final k = known.data;
              return widget.builder(
                  context,
                  k?.work ?? v.$2?.trim() ?? '',
                  k == null ? v.$3?.trim() ?? '' : k.episode ?? '');
            },
          );
        },
      );
}

/// 葬送的芙莉莲 · 第5话 死者的幻影
class _Title extends StatelessWidget {
  const _Title();

  @override
  Widget build(BuildContext context) => _Titles(
        builder: (context, work, episode) {
          return Text.rich(
            TextSpan(children: [
              if (work.isNotEmpty)
                TextSpan(
                    text: work,
                    style: NextText.sans(15,
                        weight: FontWeight.w600, letterSpacing: 0.3)),
              if (work.isNotEmpty && episode.isNotEmpty)
                const TextSpan(text: '   '),
              if (episode.isNotEmpty)
                TextSpan(
                    text: episode,
                    style: NextText.sans(13.5, color: NextColors.p2)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: NextText.sans(15, shadows: const [
              Shadow(color: Color(0x80000000), blurRadius: 8),
            ]),
          );
        },
      );
}

/// Nipa, as on the shell's bar: a click opens the conversation over the
/// video, or puts it away.
class _Nipa extends StatelessWidget {
  const _Nipa({required this.shell});
  final NextShellController shell;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([shell.chat, shell.nipaSetup]),
        builder: (context, _) {
          final c = shell.chat;
          final unset = shell.nipaSetup.needsModel;
          return Pressable(
            onTap: shell.toggleChat,
            semanticLabel: 'Nipa',
            pressScale: 0.94,
            builder: (context, hovered) => Stack(
              clipBehavior: Clip.none,
              children: [
                NipaAvatar(
                  size: 28,
                  mood: c.mood,
                  hasNews: c.unseen,
                  sentence: c.moodSentence ?? (unset ? '还没有模型' : null),
                ),
                if (unset)
                  const Positioned(right: -1, bottom: -1, child: NipaSetupDot()),
              ],
            ),
          );
        },
      );
}

/// The timeline over the controls: play, next, the time on the left;
/// volume, danmaku, subtitles, episodes and full screen on the right.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playback,
    required this.menu,
    required this.onMenu,
    required this.onScrub,
  });
  final NextPlayback playback;
  final _Menu? menu;
  final void Function(_Menu which) onMenu;
  final ValueChanged<bool> onScrub;

  static const _side = 40.0;
  static const _button = 40.0;
  static const _gap = 6.0;
  static const height = 24 + _button + 2 + PlayerTimeline.height;

  /// Where a menu hangs, from the right edge: its right edge on its
  /// button's (episodes, then full screen, are right of subtitles).
  static double menuRight(_Menu which) => switch (which) {
        _Menu.subtitles => _side + (_button + _gap) * 2,
        _Menu.episodes => _side + (_button + _gap),
      };

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Clicks between the controls do not reach the picture.
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_side, 0, _side, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Selector<VideoPlayerState, (int, int, int, int)>(
            selector: (_, s) => (
              s.position.inMilliseconds,
              s.duration.inMilliseconds,
              s.bufferedPosition,
              s.danmakuListVersion,
            ),
            builder: (context, t, _) => PlayerTimeline(
              position: Duration(milliseconds: t.$1),
              duration: Duration(milliseconds: t.$2),
              buffered: Duration(milliseconds: t.$3),
              heat: playback.heat(),
              onSeek: playback.seek,
              onScrub: onScrub,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: _button,
            child: Row(children: [
              Selector<VideoPlayerState, bool>(
                selector: (_, s) => s.status == PlayerStatus.playing,
                builder: (context, playing, _) => _BarButton(
                  glyph: playing ? NextGlyph.pause : NextGlyph.play,
                  label: playing ? '暂停' : '播放',
                  size: 22,
                  onTap: playback.togglePlay,
                ),
              ),
              Selector<VideoPlayerState, bool>(
                selector: (_, s) => s.canPlayNextEpisode,
                builder: (context, can, _) => can
                    ? Padding(
                        padding: const EdgeInsets.only(left: _gap),
                        child: _BarButton(
                          glyph: NextGlyph.nextEpisode,
                          label: '下一集',
                          size: 19,
                          onTap: () => unawaited(playback.nextEpisode()),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 14),
              Selector<VideoPlayerState, (int, int)>(
                selector: (_, s) =>
                    (s.position.inSeconds, s.duration.inSeconds),
                builder: (context, t, _) => Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: playerTime(Duration(seconds: t.$1)),
                        style: NextText.num(13.5, color: NextColors.paper)),
                    TextSpan(
                        text: '  /  ${playerTime(Duration(seconds: t.$2))}',
                        style: NextText.num(13.5, color: NextColors.p3)),
                  ]),
                  maxLines: 1,
                ),
              ),
              const Spacer(),
              _Volume(playback: playback),
              const SizedBox(width: _gap),
              Selector<VideoPlayerState, bool>(
                selector: (_, s) => s.danmakuVisible,
                builder: (context, on, _) => _BarButton(
                  glyph: on ? NextGlyph.danmaku : NextGlyph.danmakuOff,
                  label: on ? '关闭弹幕' : '显示弹幕',
                  dim: !on,
                  onTap: playback.toggleDanmaku,
                ),
              ),
              const SizedBox(width: _gap),
              _BarButton(
                glyph: NextGlyph.subtitles,
                label: '字幕',
                lit: menu == _Menu.subtitles,
                onTap: () => onMenu(_Menu.subtitles),
              ),
              const SizedBox(width: _gap),
              _BarButton(
                glyph: NextGlyph.episodes,
                label: '剧集',
                lit: menu == _Menu.episodes,
                onTap: () => onMenu(_Menu.episodes),
              ),
              const SizedBox(width: _gap),
              Selector<VideoPlayerState, bool>(
                selector: (_, s) => s.isFullscreen,
                builder: (context, full, _) => _BarButton(
                  glyph:
                      full ? NextGlyph.exitFullscreen : NextGlyph.fullscreen,
                  label: full ? '退出全屏' : '全屏',
                  size: 19,
                  onTap: () => unawaited(playback.toggleFullscreen()),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// A round control: the glyph in paper, a faint disc under it on hover,
/// lit while its menu is open.
class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.size = 20,
    this.lit = false,
    this.dim = false,
  });
  final NextGlyph glyph;
  final String label;
  final VoidCallback onTap;
  final double size;
  final bool lit;
  final bool dim;

  @override
  Widget build(BuildContext context) => Pressable(
        onTap: onTap,
        semanticLabel: label,
        pressScale: 0.92,
        builder: (context, hovered) => AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: _BottomBar._button,
          height: _BottomBar._button,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: lit
                ? const Color(0x24FFFFFF)
                : hovered
                    ? const Color(0x17FFFFFF)
                    : const Color(0x00FFFFFF),
          ),
          child: NextIcon(glyph,
              size: size,
              stroke: 1.8,
              color: hovered || lit
                  ? NextColors.paper
                  : dim
                      ? NextColors.p3
                      : const Color(0xE6F5F1EA)),
        ),
      );
}

/// The speaker: a click mutes or brings the sound back; hovered, a slider
/// opens to its left.
class _Volume extends StatefulWidget {
  const _Volume({required this.playback});
  final NextPlayback playback;

  @override
  State<_Volume> createState() => _VolumeState();
}

class _VolumeState extends State<_Volume> {
  bool _open = false;
  bool _dragging = false;
  double _before = 0.6;
  Timer? _close;

  static const _width = 88.0;

  @override
  void dispose() {
    _close?.cancel();
    super.dispose();
  }

  void _hover(bool over) {
    _close?.cancel();
    if (over) {
      if (!_open) setState(() => _open = true);
    } else if (!_dragging) {
      _close = Timer(const Duration(milliseconds: 360), () {
        if (mounted) setState(() => _open = false);
      });
    }
  }

  void _set(double value) {
    unawaited(widget.playback.setVolume(value).catchError(
        (Object e) => debugPrint('[NextPlayer] volume: $e')));
  }

  void _toggleMute(double volume) {
    if (volume > 0.001) {
      _before = volume;
      _set(0);
    } else {
      _set(_before > 0.02 ? _before : 0.6);
    }
  }

  @override
  Widget build(BuildContext context) => Selector<VideoPlayerState, double>(
        selector: (_, s) => s.currentSystemVolume,
        builder: (context, volume, _) => MouseRegion(
          onEnter: (_) => _hover(true),
          onExit: (_) => _hover(false),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: NextMotion.ease,
              width: _open ? _width + 8 : 0,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.centerRight,
                  minWidth: _width + 8,
                  maxWidth: _width + 8,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _Slider(
                      value: volume,
                      onChanged: _set,
                      onDrag: (on) {
                        _dragging = on;
                        if (!on) _hover(false);
                      },
                    ),
                  ),
                ),
              ),
            ),
            _BarButton(
              glyph: volume <= 0.001 ? NextGlyph.muted : NextGlyph.volume,
              label: volume <= 0.001 ? '取消静音' : '静音',
              onTap: () => _toggleMute(volume),
            ),
          ]),
        ),
      );
}

class _Slider extends StatelessWidget {
  const _Slider(
      {required this.value, required this.onChanged, required this.onDrag});
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onDrag;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final width = c.maxWidth;
        double at(Offset p) => width <= 0 ? 0 : (p.dx / width).clamp(0.0, 1.0);
        return MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => onChanged(at(e.localPosition)),
            onHorizontalDragStart: (e) {
              onDrag(true);
              onChanged(at(e.localPosition));
            },
            onHorizontalDragUpdate: (e) => onChanged(at(e.localPosition)),
            onHorizontalDragEnd: (_) => onDrag(false),
            onHorizontalDragCancel: () => onDrag(false),
            child: SizedBox(
              height: 28,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: const Color(0x33FFFFFF),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: value.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: NextColors.paper,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: value.clamp(0.0, 1.0) * width - 5.5,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: NextColors.paper,
                    ),
                  ),
                ),
              ]),
            ),
          ),
        );
      });
}

/// 跳过片头 / 跳过片尾, while the video is in one; above the controls when
/// they show.
class _SkipSegment extends StatelessWidget {
  const _SkipSegment({required this.raised, required this.playback});
  final bool raised;
  final NextPlayback playback;

  @override
  Widget build(BuildContext context) =>
      Selector<VideoPlayerState, SkipSegmentKind?>(
        selector: (_, s) => playback.skippable,
        builder: (context, kind, _) => AnimatedPositioned(
          duration: const Duration(milliseconds: 260),
          curve: NextMotion.ease,
          right: _BottomBar._side,
          bottom: raised ? _BottomBar.height + 12 : 40,
          child: IgnorePointer(
            ignoring: kind == null,
            child: AnimatedOpacity(
              opacity: kind == null ? 0 : 1,
              duration: const Duration(milliseconds: 180),
              child: NextButton.ghost(
                height: 40,
                label: kind == SkipSegmentKind.ending ? '跳过片尾' : '跳过片头',
                onTap: () => unawaited(playback.skip()),
              ),
            ),
          ),
        ),
      );
}

/// While the video opens: the title and a pulse, nothing of the process.
class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: NextColors.ink,
        child: _Titles(
          builder: (context, work, episode) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (work.isNotEmpty)
                  Text(work,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.serif(34, letterSpacing: 1.2)),
                if (episode.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(episode,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(14, color: NextColors.p2)),
                ],
                const SizedBox(height: 26),
                const PulseDot(),
              ]),
            );
          },
        ),
      );
}

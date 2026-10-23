import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../../player/perf/budget.dart';
import '../../player/ports/session_playback.dart';
import '../../player/sources/auto_next_overlay.dart';
import '../../ui_data/ui_data.dart'
    show NextNowPlaying, NextUiData, UiNowPlaying;
import '../conversation/nipa_chat.dart';
import '../data/login_requests.dart';
import '../shell/nipa_setup.dart';
import '../shell/shell_controller.dart';
import '../shell/window_chrome.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/nipa_avatar.dart';
import '../widgets/progress.dart';
import 'player_menus.dart';
import 'player_more.dart';
import 'playback.dart';
import 'stage.dart';
import 'timeline.dart';

enum _Menu { subtitles, episodes, more }

/// Next's controls over the video. The picture is Next's own layer's
/// ([NextVideoStage]: clicks pause, a double click goes full screen, the
/// keys play, pause and seek); over P0's seam it is Classic's, with its
/// danmaku, subtitles, menu and hotkeys. This draws what is over it: back
/// and the title on the window's bar, Nipa on the right, the timeline with
/// its heat and the controls below.
///
/// They come with the pointer and go when it rests, as Classic's do
/// ([NextPlayback.showControls]); they stay while the pointer is on
/// them or a menu is open. ⌘K asks Nipa, in the panel beside the video:
/// the picture and these controls make room for it ([NextStage]) and keep
/// working there as they do in the whole window; what is said goes with
/// what plays and where it is ([_Watch]). ⋯ holds what the bar has no room
/// for (the speed, the
/// audio track, the picture's fit, the danmaku's look, a still, picture in
/// picture); a still taken shows a moment in the corner. A login Nipa asks
/// for waits in the conversation, told of by a note under her.
class NextPlayerLayer extends StatefulWidget {
  const NextPlayerLayer({super.key});

  @override
  State<NextPlayerLayer> createState() => _NextPlayerLayerState();
}

class _NextPlayerLayerState extends State<NextPlayerLayer> {
  NextShellController? _shell;
  NextPlayback? _playback;
  _Watch? _watch;
  bool _overChrome = false;
  bool _scrubbing = false;
  _Menu? _menu;
  bool _holding = false;
  final _menuFocus = FocusNode(debugLabel: 'next.player.menu');
  final _more = GlobalKey<MoreMenuState>();

  /// The still just taken (its file), or that none could be; and the
  /// flash that says it was.
  ({String? path})? _shot;
  int _flash = 0;
  Timer? _shotGone;

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
    final playback = NextPlaybackScope.of(context);
    if (!identical(playback, _playback)) {
      _release();
      _playback = playback;
      _syncHold();
    }
    if (!identical(_watch?.chat, shell.chat) ||
        !identical(_watch?.playback, playback)) {
      _watch?.dispose();
      _watch = _Watch(shell.chat, playback, shell.services.data);
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _shell?.panelOpen.removeListener(_panelChanged);
    _release();
    _watch?.dispose();
    _menuFocus.dispose();
    _shotGone?.cancel();
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

  /// Esc: back from a page of ⋯, else the menu closes.
  void _escape() {
    if (_more.currentState?.back() ?? false) return;
    _closeMenu();
  }

  Future<void> _screenshot() async {
    _closeMenu();
    String? path;
    try {
      path = await _playback!.screenshot();
    } catch (e) {
      debugPrint('[NextPlayer] screenshot: $e');
    }
    if (!mounted) return;
    _shotGone?.cancel();
    setState(() {
      _shot = (path: path);
      if (path != null) _flash++;
    });
    _shotGone = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _shot = null);
    });
  }

  void _pictureInPicture() {
    _closeMenu();
    unawaited(_playback!.pictureInPicture(context).catchError(
        (Object e) => debugPrint('[NextPlayer] picture in picture: $e')));
  }

  void _openShot(String path) {
    _shotGone?.cancel();
    setState(() => _shot = null);
    unawaited(_playback!.open(path).catchError(
        (Object e) => debugPrint('[NextPlayer] open still: $e')));
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
    final playback = _playback!;
    final stage = NextStage.maybeOf(context);
    final layer = _layer(playback);
    // With the conversation beside the video, all of this is laid out in
    // the picture's room, left of it.
    return stage == null
        ? layer
        : NextStageRoom(
            slide: stage.slide, stepped: stage.stepped, child: layer);
  }

  Widget _layer(NextPlayback playback) {
    final shell = _shell!;
    return PlaybackSelector<(bool, bool, bool)>(
      playback: playback,
      selector: (s) => (
        s.hasVideo,
        s.transport.value.opening,
        s.showControls,
      ),
      builder: (context, frame, _) {
        final (hasVideo, loading, controls) = frame;
        final pinned = _overChrome || _scrubbing || _menu != null;
        final shown = hasVideo && (controls || pinned);
        return Stack(fit: StackFit.expand, children: [
          if (playback case final SessionPlayback sessionPlayback)
            AutoNextOverlay(sources: sessionPlayback.sources),
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
                    shell: shell,
                    menu: _menu,
                    onMenu: _toggleMenu,
                    onScrub: _scrub,
                  ),
                ),
              ),
            ),
            if (_flash > 0 && !NextMotion.reduced(context))
              Positioned.fill(child: _Flash(key: ValueKey(_flash))),
            _SkipSegment(raised: shown, playback: playback),
            _Still(
              shot: _shot,
              raised: shown,
              playback: playback,
              onOpen: _openShot,
            ),
            _LoginNote(
              logins: shell.services.logins,
              controls: shown,
              covered: shell.panelOpen.value,
              onHover: _hoverChrome,
            ),
            // With the conversation beside the picture, the picture's last
            // margin is the way into it: Classic's settings menu, opened by
            // the pointer on the picture's right edge, would come up over
            // the conversation. Always here, so what follows keeps its place.
            Positioned(
              top: 0,
              right: 0,
              bottom: 0,
              width: shell.panelOpen.value ? NextStage.margin : 0,
              child: const MouseRegion(child: SizedBox.expand()),
            ),
            if (_menu != null) ...[
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeMenu,
                ),
              ),
              // Under its button, wherever the bar's width put it.
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, room) => Stack(children: [
                    Positioned(
                      right: _BottomBar.menuRight(_menu!, room.maxWidth),
                      bottom: _BottomBar.height + 2,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _escape,
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
                              _Menu.more => MoreMenu(
                                  key: _more,
                                  playback: playback,
                                  onScreenshot: () => unawaited(_screenshot()),
                                  onPictureInPicture: _pictureInPicture),
                            },
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ],
        ]);
      },
    );
  }
}

/// What plays, for what is said to Nipa over it: the file, what the
/// library knows it as, where the video is and whether it is paused, read
/// the moment something is said. Facts only: nothing acts on them here.
class _Watch {
  _Watch(this.chat, this.playback, this.data) {
    playback.media.addListener(_changed);
    playback.transport.addListener(_changed);
    // Not in the build that mounted the layer.
    scheduleMicrotask(() {
      if (_gone) return;
      chat.watch(read);
      _changed();
    });
  }

  final NipaChat chat;
  final NextPlayback playback;
  final NextUiData data;
  bool _gone = false;
  String? _path;
  Future<UiNowPlaying?>? _known;

  String? get _playing =>
      playback.transport.value.hasVideo ? playback.media.value.path : null;

  Future<UiNowPlaying?> _lookup(String path) {
    if (data case final NextNowPlaying library) {
      return library.nowPlaying(path).catchError((Object e) {
        debugPrint('[NextPlayer] what plays: $e');
        return null;
      });
    }
    return Future.value();
  }

  /// Another file: the library is asked what it is. The name stays as it
  /// was until it answers.
  void _changed() => PlayerPerf.span('watch.changed', _change);
  void _change() {
    if (_gone) return;
    final path = _playing;
    if (path == null || path == _path) return;
    _path = path;
    final known = _known = _lookup(path);
    unawaited(known.then((k) {
      if (!_gone && identical(known, _known)) {
        chat.watch(read, named: Watching.nameOf(path, k));
      }
    }));
  }

  /// What plays and where, now; null with no video up.
  Future<Watching?> read() async {
    final path = _playing;
    if (path == null) return null;
    // Where it is when this is asked, before anything waits.
    final position = playback.position;
    final duration = playback.duration;
    final paused = playback.transport.value.phase == PlaybackPhase.paused;
    final known = (path == _path ? _known : null) ?? _lookup(path);
    return Watching(
      path: path,
      known: await known.timeout(const Duration(seconds: 2),
          onTimeout: () => null),
      position: position,
      duration: duration,
      paused: paused,
    );
  }

  void dispose() {
    _gone = true;
    playback.media.removeListener(_changed);
    playback.transport.removeListener(_changed);
    // Not while the tree that let the layer go is locked.
    final read = this.read;
    scheduleMicrotask(() => chat.unwatch(read));
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
      PlaybackSelector<(String?, String?, String?)>(
        selector: (s) => (s.path, s.workTitle, s.episodeTitle),
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

/// The timeline over the controls: play, next, the time (and the speed,
/// when it is not the normal one) on the left; volume, danmaku, subtitles,
/// episodes, ⋯ and full screen on the right. Where the picture's room is
/// narrower than the controls at their widest ([_row]: the panel beside the
/// video in a small window), the row of controls is drawn smaller, whole.
class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.playback,
    required this.shell,
    required this.menu,
    required this.onMenu,
    required this.onScrub,
  });
  final NextPlayback playback;
  final NextShellController shell;
  final _Menu? menu;
  final void Function(_Menu which) onMenu;
  final ValueChanged<bool> onScrub;

  static const _side = 40.0;
  static const _button = 40.0;
  static const _gap = 6.0;
  static const height = 24 + _button + 2 + PlayerTimeline.height;

  /// The row of controls at its widest: an hour-long time, a speed, the
  /// volume's slider open.
  static const _row = 640.0;

  /// How much smaller the row is drawn in a room [width] wide.
  static double scale(double width) =>
      math.min(1, math.max(0.0, width - 2 * _side) / _row);

  /// Where a menu hangs, from the right edge of a room [width] wide: its
  /// right edge on its button's (episodes, ⋯ and full screen are right of
  /// subtitles).
  static double menuRight(_Menu which, double width) =>
      _side +
      scale(width) *
          switch (which) {
            _Menu.subtitles => (_button + _gap) * 3,
            _Menu.episodes => (_button + _gap) * 2,
            _Menu.more => _button + _gap,
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
          // What is watched moves by painting, not rebuilding: the line
          // reads the position each time the frame asks for a redraw.
          PlaybackSelector<(int, int, int)>(
            playback: playback,
            selector: (s) => (
              s.duration.inMilliseconds,
              s.buffered.inMilliseconds,
              s.danmakuVersion.value,
            ),
            builder: (context, t, _) => PlayerTimeline(
              live: () => playback.position,
              repaint: playback.frame,
              duration: Duration(milliseconds: t.$1),
              buffered: Duration(milliseconds: t.$2),
              heat: playback.heat(),
              onSeek: playback.seek,
              onScrub: onScrub,
              preview: switch (playback) {
                SessionPlayback(:final preview, :final session)
                    when preview.enabled && session != null =>
                  (at) => preview.at(session.source.uri, at),
                _ => null,
              },
            ),
          ),
          const SizedBox(height: 2),
          // One structure at every width, so nothing in the row is remounted
          // as the room narrows or widens.
          LayoutBuilder(
            builder: (context, room) => FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: math.max(room.maxWidth, _row),
                height: _button,
                child: Row(children: [
                  // The intent: the button answers the click at once.
                  PlaybackSelector<bool>(
                    playback: playback,
                    selector: (s) => s.playIntent,
                    builder: (context, playing, _) => _BarButton(
                      glyph: playing ? NextGlyph.pause : NextGlyph.play,
                      label: playing ? '暂停' : '播放',
                      size: 22,
                      onTap: playback.togglePlay,
                    ),
                  ),
                  _NextEpisode(playback: playback, shell: shell),
                  const SizedBox(width: 14),
                  PlaybackSelector<(int, int)>(
                    playback: playback,
                    selector: (s) =>
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
                  PlaybackSelector<double>(
                    playback: playback,
                    selector: (s) => s.rate,
                    builder: (context, rate, _) => (rate - 1).abs() < 0.001
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Text(MoreMenuState.rateText(rate),
                                style: NextText.num(13,
                                    weight: FontWeight.w600,
                                    color: NextColors.p2)),
                          ),
                  ),
                  const Spacer(),
                  _Volume(playback: playback),
                  const SizedBox(width: _gap),
                  if (playback.offersDanmaku) ...[
                    PlaybackSelector<bool>(
                      playback: playback,
                      selector: (s) => s.danmakuVisible,
                      builder: (context, on, _) => _BarButton(
                        glyph: on ? NextGlyph.danmaku : NextGlyph.danmakuOff,
                        label: on ? '关闭弹幕' : '显示弹幕',
                        dim: !on,
                        onTap: playback.toggleDanmaku,
                      ),
                    ),
                    const SizedBox(width: _gap),
                  ],
                  if (playback.offersSubtitles) ...[
                    _BarButton(
                      glyph: NextGlyph.subtitles,
                      label: '字幕',
                      lit: menu == _Menu.subtitles,
                      onTap: () => onMenu(_Menu.subtitles),
                    ),
                    const SizedBox(width: _gap),
                  ],
                  _BarButton(
                    glyph: NextGlyph.episodes,
                    label: '剧集',
                    lit: menu == _Menu.episodes,
                    onTap: () => onMenu(_Menu.episodes),
                  ),
                  const SizedBox(width: _gap),
                  _BarButton(
                    glyph: NextGlyph.more,
                    label: '更多',
                    lit: menu == _Menu.more,
                    onTap: () => onMenu(_Menu.more),
                  ),
                  const SizedBox(width: _gap),
                  PlaybackSelector<bool>(
                    playback: playback,
                    selector: (s) => s.fullscreen,
                    builder: (context, full, _) => _BarButton(
                      glyph: full
                          ? NextGlyph.exitFullscreen
                          : NextGlyph.fullscreen,
                      label: full ? '退出全屏' : '全屏',
                      size: 19,
                      onTap: () => unawaited(playback.toggleFullscreen()),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// 下一集. A file the library knows: the first episode after it in its
/// season that can be played now, played as the shell plays anything; with
/// none (a film, the last episode, the next not here yet) there is no
/// button. A file only Classic knows: Classic's playlist. Asked again for
/// each video, and when the controls come back while the next one is still
/// on its way.
class _NextEpisode extends StatefulWidget {
  const _NextEpisode({required this.playback, required this.shell});
  final NextPlayback playback;
  final NextShellController shell;

  @override
  State<_NextEpisode> createState() => _NextEpisodeState();
}

class _NextEpisodeState extends State<_NextEpisode> {
  bool _asked = false;
  String? _path;
  bool _shown = false;
  int _asking = 0;

  /// What the library said of [_path]; null until it has.
  ({PlayingWork? known})? _answer;

  void _ask() {
    final ask = ++_asking;
    unawaited(PlayingWork.of(widget.shell.services.data, _path).then((known) {
      if (mounted && ask == _asking) setState(() => _answer = (known: known));
    }));
  }

  @override
  Widget build(BuildContext context) =>
      PlaybackSelector<(String?, bool, bool)>(
        playback: widget.playback,
        selector: (s) => (s.path, s.showControls, s.canPlayNext),
        builder: (context, v, _) {
          final (path, shown, classic) = v;
          if (!_asked || path != _path) {
            _asked = true;
            _path = path;
            _answer = null;
            _ask();
          } else if (shown && !_shown && (_answer?.known?.waiting ?? false)) {
            _ask();
          }
          _shown = shown;
          final answer = _answer;
          if (answer == null) return const SizedBox.shrink();
          final VoidCallback? play;
          if (answer.known case final known?) {
            final next = known.next;
            play = next == null
                ? null
                : () => widget.shell.play(known.work, episode: next);
          } else {
            play = classic
                ? () => unawaited(widget.playback.nextEpisode())
                : null;
          }
          if (play == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(left: _BottomBar._gap),
            child: _BarButton(
              glyph: NextGlyph.nextEpisode,
              label: '下一集',
              size: 19,
              onTap: play,
            ),
          );
        },
      );
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
  Widget build(BuildContext context) => PlaybackSelector<double>(
        playback: widget.playback,
        selector: (s) => s.volume,
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
      PlaybackSelector<SkipSegmentKind?>(
        playback: playback,
        selector: (s) => s.skippable,
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

/// A still just taken: a white breath over the picture.
class _Flash extends StatelessWidget {
  const _Flash({super.key});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.32, end: 0),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOut,
          builder: (context, a, _) =>
              ColoredBox(color: Color.fromRGBO(255, 255, 255, a)),
        ),
      );
}

/// The still just taken, small in the corner for a moment (a click opens
/// it); or that none could be.
class _Still extends StatelessWidget {
  const _Still({
    required this.shot,
    required this.raised,
    required this.playback,
    required this.onOpen,
  });
  final ({String? path})? shot;
  final bool raised;
  final NextPlayback playback;
  final ValueChanged<String> onOpen;

  static const width = 192.0;

  @override
  Widget build(BuildContext context) {
    final shot = this.shot;
    final path = shot?.path;
    return PlaybackSelector<bool>(
      playback: playback,
      // Above 跳过片头 when that shows.
      selector: (s) => s.skippable != null,
      builder: (context, skip, _) => AnimatedPositioned(
        duration: const Duration(milliseconds: 260),
        curve: NextMotion.ease,
        right: _BottomBar._side,
        bottom: (raised ? _BottomBar.height + 12 : 40) + (skip ? 52 : 0),
        child: IgnorePointer(
          ignoring: shot == null,
          child: AnimatedOpacity(
            opacity: shot == null ? 0 : 1,
            duration: const Duration(milliseconds: 220),
            child: AnimatedSlide(
              offset: shot == null ? const Offset(0.08, 0) : Offset.zero,
              duration: const Duration(milliseconds: 260),
              curve: NextMotion.ease,
              child: shot == null
                  ? const SizedBox(width: width, height: width * 9 / 16)
                  : path == null
                      ? Container(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xCC121218),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: NextColors.line2),
                          ),
                          child: Text('截图失败',
                              style: NextText.sans(13, color: NextColors.p2)),
                        )
                      : Pressable(
                          onTap: () => onOpen(path),
                          semanticLabel: '打开截图',
                          pressScale: 0.97,
                          builder: (context, hovered) => Container(
                            width: width,
                            height: width * 9 / 16,
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: hovered
                                      ? NextColors.paper
                                      : const Color(0x8CF5F1EA),
                                  width: 1.5),
                            ),
                            decoration: BoxDecoration(
                              color: NextColors.ink2,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: nextShadowCard,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.file(
                                File(path),
                                fit: BoxFit.cover,
                                cacheWidth: (width *
                                        MediaQuery.devicePixelRatioOf(context))
                                    .round(),
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A login Nipa asked for while the video plays, its card waiting in the
/// conversation: 登录 弹弹play under her, for a moment when it comes and
/// whenever the controls show; a click opens the login window. None while
/// the conversation is open over the video, where the card is.
class _LoginNote extends StatefulWidget {
  const _LoginNote({
    required this.logins,
    required this.controls,
    required this.covered,
    required this.onHover,
  });
  final LoginRequests logins;
  final bool controls;
  final bool covered;
  final ValueChanged<bool> onHover;

  @override
  State<_LoginNote> createState() => _LoginNoteState();
}

class _LoginNoteState extends State<_LoginNote> {
  /// The logins already told of; one new shows without the controls too,
  /// for a moment.
  final _told = <LoginRequest>{};
  bool _fresh = false;
  Timer? _freshGone;

  /// Kept while the note fades out.
  String _label = '';

  @override
  void initState() {
    super.initState();
    _told.addAll(widget.logins.pending);
    widget.logins.addListener(_changed);
  }

  @override
  void didUpdateWidget(_LoginNote old) {
    super.didUpdateWidget(old);
    if (identical(old.logins, widget.logins)) return;
    old.logins.removeListener(_changed);
    widget.logins.addListener(_changed);
  }

  @override
  void dispose() {
    widget.logins.removeListener(_changed);
    _freshGone?.cancel();
    super.dispose();
  }

  void _changed() {
    final pending = widget.logins.pending;
    if (pending.any((r) => !_told.contains(r))) {
      _fresh = true;
      _freshGone?.cancel();
      _freshGone = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _fresh = false);
      });
    }
    _told
      ..clear()
      ..addAll(pending);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final waiting = widget.logins.pending.where((r) => !r.opening).firstOrNull;
    if (waiting != null) _label = '登录 ${waiting.platform}';
    final shown =
        waiting != null && !widget.covered && (widget.controls || _fresh);
    return Positioned(
      right: NextMetrics.chromeEdge,
      top: NextMetrics.topBar - 2,
      child: IgnorePointer(
        ignoring: !shown,
        child: AnimatedOpacity(
          opacity: shown ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: NextMotion.ease,
          child: Pressable(
            onTap: waiting == null
                ? null
                : () => unawaited(widget.logins.open(waiting)),
            onHover: widget.onHover,
            semanticLabel: _label,
            builder: (context, hovered) => AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color:
                    hovered ? const Color(0xE61C1C24) : const Color(0xCC121218),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NextColors.line2),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: NextColors.accent),
                ),
                const SizedBox(width: 8),
                Text(_label,
                    style: NextText.sans(12.5,
                        color: hovered ? NextColors.paper : NextColors.p2)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
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

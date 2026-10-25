import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../cards/card_views.dart';
import '../chat/chat_frame.dart';
import '../player/stage.dart';
import '../shell/shell_controller.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import '../widgets/attachments.dart';
import '../widgets/drop_zone.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';

/// The conversation side panel, on every page but the home: it slides in
/// from the right on a 420 ms spring while the page behind blurs and
/// darkens; Esc or a click outside closes it.
///
/// Beside a video it is docked instead: the picture is not dimmed and stays
/// live (a click on it is the video's), and the picture with its subtitles
/// and danmaku and the player's controls make room for the panel as it
/// slides ([NextStage]); Esc, × or Nipa close it. In a small window it is
/// narrower, so the picture keeps its room.
class ChatPanelLayer extends StatefulWidget {
  const ChatPanelLayer({super.key});

  @override
  State<ChatPanelLayer> createState() => _ChatPanelLayerState();
}

class _ChatPanelLayerState extends State<ChatPanelLayer>
    with SingleTickerProviderStateMixin {
  static const _open = Duration(milliseconds: 420);
  static const _spring = _SpringCurve();
  late final AnimationController _c = AnimationController(
      vsync: this,
      duration: _open,
      reverseDuration: const Duration(milliseconds: 260))
    ..addListener(_publish);
  NextShellController? _shell;
  ValueNotifier<double>? _stage;
  bool _reduced = false;
  bool _docked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = NextMotion.reduced(context);
    _stage = NextStage.maybeOf(context)?.slide;
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.panelOpen.removeListener(_sync);
    _shell?.removeListener(_playingChanged);
    _shell = shell
      ..panelOpen.addListener(_sync)
      ..addListener(_playingChanged);
    _docked = shell.playing;
    _sync();
  }

  void _sync() {
    if (_shell!.panelOpen.value) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  void _playingChanged() {
    if (_shell!.playing == _docked) return;
    setState(() => _docked = _shell!.playing);
  }

  /// Where the panel is on its way in or out: the spring in, ease out.
  double get _slide {
    if (_reduced) return 1;
    final t = _c.value;
    return _c.status == AnimationStatus.reverse
        ? Curves.easeOutCubic.transform(t)
        : _spring.transform(t);
  }

  /// The picture follows the panel, from the controller's tick (before the
  /// frame lays out), never from a build.
  void _publish() =>
      _stage?.value = _c.isDismissed || _compact ? 0 : _slide;

  /// A phone: the conversation rises from the foot as a sheet, over the
  /// page or under the video, which keeps its place.
  bool _compact = false;

  @override
  void dispose() {
    _shell?.panelOpen.removeListener(_sync);
    _shell?.removeListener(_playingChanged);
    // The picture has the window again.
    _stage?.value = 0;
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    final docked = _docked;
    _reduced = NextMotion.reduced(context);
    final width = docked
        ? NextStage.panelWidth(MediaQuery.sizeOf(context).width)
        : NextStage.panelMax;
    final sheet = RepaintBoundary(child: _Sheet(docked: docked));
    _compact = NextLayout.compact(context);
    if (_compact) return _phone(shell, docked, sheet);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.isDismissed) return const SizedBox.shrink();
        final t = _c.value;
        final slide = _slide;
        return Stack(children: [
          // The same two places either way, so the sheet keeps its state
          // when a video opens or closes under it.
          Positioned.fill(
            child: docked
                ? const SizedBox.shrink()
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: shell.closePanel,
                    child: _Dim(t),
                  ),
          ),
          Positioned(
            top: NextStage.margin,
            right: NextStage.margin,
            bottom: NextStage.margin,
            width: width,
            child: Opacity(
              opacity: _reduced ? t : math.min(1, t * 3),
              child: Transform.translate(
                offset: Offset((1 - slide) * NextStage.travel(width), 0),
                child: sheet,
              ),
            ),
          ),
        ]);
      },
    );
  }
}

extension on _ChatPanelLayerState {
  Widget _phone(NextShellController shell, bool docked, Widget sheet) {
    final size = MediaQuery.sizeOf(context);
    final bottom = math.max(MediaQuery.viewInsetsOf(context).bottom,
        MediaQuery.paddingOf(context).bottom);
    // Over a video the picture stays in sight above the sheet.
    final top = docked
        ? size.width * 9 / 16 + NextLayout.barTop(context) + 24
        : NextLayout.barTop(context) + 8;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.isDismissed) return const SizedBox.shrink();
        final t = _c.value;
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: shell.closePanel,
              child: _Dim(t),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            top: top,
            bottom: 0,
            child: Opacity(
              opacity: _reduced ? t : math.min(1, t * 3),
              child: Transform.translate(
                offset: Offset(0, (1 - _slide) * (size.height - top)),
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottom),
                  child: sheet,
                ),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

/// A damped spring that settles within the animation's 420 ms, with a
/// slight overshoot.
class _SpringCurve extends Curve {
  const _SpringCurve();
  static final _sim = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 188, damping: 21.9), 0, 1, 0);

  @override
  double transformInternal(double t) => _sim.x(t * 0.42);
}

/// `.dim`: the page behind blurs (6) and darkens (35 %).
class _Dim extends StatelessWidget {
  const _Dim(this.t);
  final double t;

  @override
  Widget build(BuildContext context) {
    final shade = ColoredBox(color: Color.fromRGBO(6, 6, 9, 0.35 * t));
    if (t <= 0.01) return shade;
    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.compose(
          outer: Glass.saturation(1 + 0.2 * t),
          inner: ui.ImageFilter.blur(
              sigmaX: 6 * t, sigmaY: 6 * t, tileMode: TileMode.clamp),
        ),
        child: shade,
      ),
    );
  }
}

/// `.sheet`: the conversation ([ChatFrame]) on frosted glass. Files
/// dropped anywhere on it go with what you say next. Beside a video
/// ([docked]) it casts no shadow: that would fall on the picture.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.docked});
  final bool docked;

  static final _radius = BorderRadius.circular(24);
  static const _shadow = [
    BoxShadow(color: Color(0x80000000), blurRadius: 80, offset: Offset(-30, 0)),
  ];

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    final actions = shell.services.actions;
    return NextDropZone(
      onDrop: shell.chat.attach,
      builder: (context, over) => Stack(children: [
        Positioned.fill(
          child: Glass(
            blur: 40,
            color: const Color(0xBD121218), // rgba(18,18,24,.74)
            borderColor: const Color(0x1AFFFFFF),
            radius: _radius,
            highlight: false,
            shadows: docked ? const [] : _shadow,
            child: ChatFrame(
              focusNode: shell.panelFocus,
              columnWidth: 520,
              textSize: 14.5,
              posterWidth: 136,
              sidePadding: 22,
              callbacks: CardCallbacks(
                onOpen: (work) {
                  shell.closePanel();
                  shell.openWork(work);
                },
                onPlay: (work, episode) => shell.play(work, episode: episode),
                onPauseTask: (t) => actions.pauseTask(t.taskId),
                onResumeTask: (t) => actions.resumeTask(t.taskId),
                onCancelTask: (t) => actions.cancelTask(t.taskId),
                onChoose: (answer) => unawaited(shell.chat.say(answer)),
              ),
              trailing: FrameButton(
                  glyph: NextGlyph.close,
                  label: '关闭',
                  onTap: shell.closePanel),
            ),
          ),
        ),
        Positioned.fill(child: DropGlow(over: over, radius: _radius)),
      ]),
    );
  }
}

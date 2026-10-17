import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../cards/card_views.dart';
import '../chat/chat_frame.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/attachments.dart';
import '../widgets/drop_zone.dart';
import '../widgets/glass.dart';
import '../widgets/icons.dart';

/// The conversation side panel, on every page but the home: it slides in
/// from the right on a 420 ms spring while the page behind blurs and
/// darkens; Esc or a click outside closes it.
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
      reverseDuration: const Duration(milliseconds: 260));
  NextShellController? _shell;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell?.panelOpen.removeListener(_sync);
    _shell = shell..panelOpen.addListener(_sync);
    _sync();
  }

  void _sync() {
    if (_shell!.panelOpen.value) {
      _c.forward();
    } else {
      _c.reverse();
    }
  }

  @override
  void dispose() {
    _shell?.panelOpen.removeListener(_sync);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = _shell!;
    const sheet = RepaintBoundary(child: _Sheet());
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.isDismissed) return const SizedBox.shrink();
        final t = _c.value;
        final reduced = NextMotion.reduced(context);
        final closing = _c.status == AnimationStatus.reverse;
        final slide = reduced
            ? 1.0
            : (closing
                ? Curves.easeOutCubic.transform(t)
                : _spring.transform(t));
        return Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: shell.closePanel,
              child: _Dim(t),
            ),
          ),
          Positioned(
            top: 12,
            right: 12,
            bottom: 12,
            width: 520,
            child: Opacity(
              opacity: reduced ? t : math.min(1, t * 3),
              child: Transform.translate(
                offset: Offset((1 - slide) * 560, 0),
                child: sheet,
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
/// dropped anywhere on it go with what you say next.
class _Sheet extends StatelessWidget {
  const _Sheet();

  static final _radius = BorderRadius.circular(24);

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
            shadows: const [
              BoxShadow(
                  color: Color(0x80000000),
                  blurRadius: 80,
                  offset: Offset(-30, 0)),
            ],
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

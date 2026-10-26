import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../data/collections.dart';
import '../settings/section_accounts.dart' show ServiceMark;
import '../widgets/service_icon.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/glass.dart';

/// Where the work stands with the person (在看、想看…) and their score, on
/// the accounts that know it: a quiet button in the detail page's actions,
/// opening a small panel where a choice is written at once. Nothing shows
/// for a work no account knows; it brings its own gap before it.
class CollectionButton extends StatefulWidget {
  const CollectionButton({super.key, required this.work});
  final UiWork work;

  @override
  State<CollectionButton> createState() => _CollectionButtonState();
}

/// Handles for `ext.nipaplay.nextui` in lab profiles.
abstract interface class CollectionDebug {
  /// Applies `open=true|false`, `status=<doing|wish|done|onHold|dropped>`
  /// and `rating=<1-10>`.
  Future<void> debug(Map<String, String> p);
  Map<String, Object?> debugStatus();
}

class _CollectionButtonState extends State<CollectionButton>
    implements CollectionDebug {
  NextShellController? _shell;
  StreamSubscription<void>? _accounts;

  /// What the accounts have, as last read or written.
  UiCollection? _held;

  /// What shows: the person's latest choices over [_held].
  UiCollection? _shown;
  Object? _error;
  int _reads = 0;
  Future<void>? _reading;

  /// Writes go one after another, each from what the accounts have.
  Future<void> _queue = Future.value();
  int _writing = 0;

  /// Accounts whose login window was asked for, until they are read again;
  /// those that could not open it.
  final _signing = <String>{};
  final _refused = <String>{};

  final _link = LayerLink();
  final _portal = OverlayPortalController();

  NextCollections get _data => _shell!.services.collections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shell = NextShellScope.of(context);
    if (identical(shell, _shell)) return;
    _shell = shell;
    _accounts?.cancel();
    // Signing in or out changes which accounts take it.
    _accounts = shell.services.settings.changes.listen((_) => _read());
    _read();
  }

  @override
  void didUpdateWidget(CollectionButton old) {
    super.didUpdateWidget(old);
    if (old.work.workId == widget.work.workId) return;
    _held = _shown = null;
    _read();
  }

  @override
  void dispose() {
    _accounts?.cancel();
    super.dispose();
  }

  Future<void> _read() => _reading = () async {
        final read = ++_reads;
        try {
          final c = await _data.of(widget.work.workId);
          if (!mounted || read != _reads || _writing > 0) return;
          setState(() {
            _held = _shown = c;
            _error = null;
            _signing.clear();
            _refused.clear();
          });
        } catch (error) {
          debugPrint('[NextUi] collection read failed: $error');
          if (mounted && read == _reads) setState(() => _error = error);
        }
      }();

  /// [c] with [status] and [rating] on every signed-in account.
  static UiCollection _with(UiCollection c, UiWatchStatus? status, int? rating,
          {bool? failed}) =>
      UiCollection(workId: c.workId, links: [
        for (final l in c.links)
          l.loggedIn ? _change(l, status, rating, failed: failed) : l
      ]);

  static UiCollectionLink _change(
          UiCollectionLink l, UiWatchStatus? status, int? rating,
          {bool? failed}) =>
      UiCollectionLink(
        provider: l.provider,
        id: l.id,
        loggedIn: l.loggedIn,
        status: status ?? l.status,
        rating: rating ?? l.rating,
        failed: failed ?? l.failed,
      );

  /// Shows [status] and/or [rating] at once and writes them after the
  /// writes before; an account that does not take one goes back to what
  /// it had and turns red.
  Future<void> _set({UiWatchStatus? status, int? rating}) {
    // A score goes with the standing it is for (Bangumi needs one).
    final next = status ?? _shown!.status;
    setState(() {
      _shown = _with(_shown!, status, rating);
      _writing++;
    });
    return _queue = _queue.then((_) async {
      final before = _held!;
      final after = _with(before, next, rating, failed: false);
      List<String> failed;
      try {
        failed = await _data.set(before, status: next, rating: rating);
      } catch (error) {
        debugPrint('[NextUi] collection write failed: $error');
        failed = [
          for (final l in before.links)
            if (l.loggedIn) l.provider
        ];
      }
      if (!mounted) return;
      setState(() {
        _held = UiCollection(workId: before.workId, links: [
          for (final (i, l) in after.links.indexed)
            failed.contains(l.provider)
                ? _change(before.links[i], null, null, failed: true)
                : l
        ]);
        if (--_writing == 0) _shown = _held;
      });
    });
  }

  void _show(bool open) {
    if (open == _portal.isShowing) return;
    setState(open ? _portal.show : _portal.hide);
  }

  Future<void> _login(String provider) async {
    _show(false);
    setState(() => _signing.add(provider));
    try {
      await _shell!.services.settings.login(provider);
    } catch (error) {
      debugPrint('[NextUi] login failed: $error');
      if (!mounted) return;
      setState(() {
        _signing.remove(provider);
        _refused.add(provider);
      });
    }
  }

  // —— Debug ——

  @override
  Future<void> debug(Map<String, String> p) async {
    await _reading;
    if (p['open'] case final open?) _show(open == 'true');
    if (p['status'] case final s?) {
      await _set(status: UiWatchStatus.values.byName(s));
    }
    if (p['rating'] case final r?) await _set(rating: int.parse(r));
  }

  @override
  Map<String, Object?> debugStatus() => {
        'work': widget.work.workId,
        'shown': _shown?.links.isNotEmpty ?? false,
        'open': _portal.isShowing,
        'status': _shown?.status?.name,
        'rating': _shown?.rating,
        'writing': _writing,
        'links': [
          for (final l in _shown?.links ?? const <UiCollectionLink>[])
            {
              'provider': l.provider,
              'loggedIn': l.loggedIn,
              'status': l.status?.name,
              'rating': l.rating,
              'failed': l.failed,
            }
        ],
        'signing': _signing.toList(),
        'refused': _refused.toList(),
        'error': _error?.toString(),
      };

  // —— Building ——

  @override
  Widget build(BuildContext context) {
    final c = _shown;
    final shown = c != null && c.links.isNotEmpty;
    return AnimatedOpacity(
      opacity: shown ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: NextMotion.ease,
        alignment: Alignment.centerLeft,
        child: !shown
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(left: 12),
                child: OverlayPortal(
                  controller: _portal,
                  overlayChildBuilder: (context) => _layer(),
                  child:
                      CompositedTransformTarget(link: _link, child: _button(c)),
                ),
              ),
      ),
    );
  }

  Widget _button(UiCollection c) {
    final status = c.status;
    final rating = c.rating;
    return Pressable(
      onTap: () => _show(!_portal.isShowing),
      semanticLabel: status?.label ?? '收藏',
      builder: (context, hovered) {
        final lit = hovered || _portal.isShowing;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 46,
          constraints: const BoxConstraints(minWidth: 46),
          padding: EdgeInsets.symmetric(horizontal: status == null ? 0 : 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: lit ? const Color(0x24FFFFFF) : const Color(0x1AFFFFFF),
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: NextColors.line2),
          ),
          child: status == null
              ? _Ribbon(
                  size: 18,
                  filled: false,
                  color: lit ? NextColors.paper : NextColors.p2)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const _Ribbon(
                      size: 15, filled: true, color: NextColors.accent),
                  const SizedBox(width: 9),
                  Text(status.label,
                      style: NextText.sans(15,
                          weight: FontWeight.w600, letterSpacing: 0.3)),
                  if (rating != null) ...[
                    const SizedBox(width: 12),
                    const _Stars.one(size: 12, color: NextColors.accent2),
                    const SizedBox(width: 4),
                    Text('$rating',
                        style: NextText.num(15, weight: FontWeight.w600)),
                  ],
                ]),
        );
      },
    );
  }

  /// The panel under the button; a click outside or Esc closes it.
  Widget _layer() => Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _show(false),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          child: CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomLeft,
            offset: const Offset(0, 10),
            child: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _show(false);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(
                      scale: 0.97 + 0.03 * t,
                      alignment: Alignment.topLeft,
                      child: child),
                ),
                child: _panel(_shown!),
              ),
            ),
          ),
        ),
      ]);

  Widget _panel(UiCollection c) {
    final writable = c.signedIn;
    final status = c.status;
    return Glass(
      blur: 30,
      color: const Color(0xC2121218),
      borderColor: const Color(0x1AFFFFFF),
      radius: BorderRadius.circular(18),
      shadows: const [
        BoxShadow(
            color: Color(0x80000000), blurRadius: 50, offset: Offset(0, 20))
      ],
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: SizedBox(
        width: 312,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              for (final (i, s) in UiWatchStatus.values.indexed) ...[
                if (i > 0) const SizedBox(width: 4),
                Expanded(
                  child: _StatusChip(
                    label: s.label,
                    selected: s == status,
                    onTap:
                        !writable || s == status ? null : () => _set(status: s),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _Rating(
                value: c.rating,
                // A score is for a standing: chosen first.
                onPick:
                    writable && status != null ? (v) => _set(rating: v) : null,
              ),
            ),
            const SizedBox(height: 10),
            Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                color: NextColors.line),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                for (final (i, l) in _marksOrder(c.links).indexed) ...[
                  if (i > 0) const SizedBox(width: 18),
                  _AccountMark(
                    link: l,
                    state: _stateOf(l),
                    onTap: switch (_stateOf(l)) {
                      _Sync.signedOut => () => _login(l.provider),
                      _Sync.failed => _read,
                      _ => null,
                    },
                  ),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹弹play first, then Bangumi.
  static List<UiCollectionLink> _marksOrder(List<UiCollectionLink> links) =>
      [...links]..sort((a, b) => b.provider.compareTo(a.provider));

  _Sync _stateOf(UiCollectionLink l) {
    if (_signing.contains(l.provider)) return _Sync.pending;
    if (_refused.contains(l.provider)) return _Sync.failed;
    if (!l.loggedIn) return _Sync.signedOut;
    if (_writing > 0) return _Sync.pending;
    return l.failed ? _Sync.failed : _Sync.synced;
  }
}

enum _Sync { synced, pending, failed, signedOut }

/// One of the five standings.
class _StatusChip extends StatelessWidget {
  const _StatusChip(
      {required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null && !selected ? 0.4 : 1,
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          pressScale: 0.96,
          builder: (context, hovered) => AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? NextColors.accentSoft
                  : (hovered
                      ? const Color(0x14FFFFFF)
                      : const Color(0x00FFFFFF)),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: selected
                      ? const Color(0x73FF2E55)
                      : const Color(0x00FF2E55)),
            ),
            child: Text(label,
                style: NextText.sans(13.5,
                    weight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected
                        ? NextColors.accent2
                        : (hovered ? NextColors.paper : NextColors.p2))),
          ),
        ),
      );
}

/// Five stars, each half a point of ten, and the score in figures. The
/// pointer previews what a click would give.
class _Rating extends StatefulWidget {
  const _Rating({required this.value, required this.onPick});
  final int? value;
  final ValueChanged<int>? onPick;

  @override
  State<_Rating> createState() => _RatingState();
}

class _RatingState extends State<_Rating> {
  int? _hover;

  static const _star = 22.0, _gap = 6.0;
  static const _width = _star * 5 + _gap * 4;

  static int _at(double x) {
    final i = (x / (_star + _gap)).floor().clamp(0, 4);
    final within = x - i * (_star + _gap);
    return i * 2 + (within < _star / 2 ? 1 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final pick = widget.onPick;
    final hover = pick == null ? null : _hover;
    final value = hover ?? widget.value;
    Widget stars = SizedBox(
      width: _width,
      height: _star + 8,
      child: Center(
        child: _Stars(
            value: value ?? 0,
            size: _star,
            gap: _gap,
            color: hover != null ? NextColors.accent2 : NextColors.accent),
      ),
    );
    if (pick != null) {
      stars = MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (e) => setState(() => _hover = _at(e.localPosition.dx)),
        onExit: (_) => setState(() => _hover = null),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => pick(_at(d.localPosition.dx)),
          child: stars,
        ),
      );
    }
    return Opacity(
      opacity: pick == null ? 0.4 : 1,
      child: Row(children: [
        stars,
        const Spacer(),
        if (value != null)
          Text('$value',
              style: NextText.num(22,
                  weight: FontWeight.w600,
                  color:
                      hover != null ? NextColors.accent2 : NextColors.paper)),
      ]),
    );
  }
}

/// Stars filled to [value] of ten (two to a star).
class _Stars extends StatelessWidget {
  const _Stars(
      {required this.value,
      required this.size,
      required this.color,
      this.gap = 0})
      : count = 5;

  /// A single filled star, beside a score.
  const _Stars.one({required this.size, required this.color})
      : value = 2,
        gap = 0,
        count = 1;

  final int value;
  final double size;
  final double gap;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(size * count + gap * (count - 1), size),
        painter: _StarsPainter(value, size, gap, count, color),
      );
}

class _StarsPainter extends CustomPainter {
  _StarsPainter(this.value, this.star, this.gap, this.count, this.color);
  final int value;
  final double star;
  final double gap;
  final int count;
  final Color color;

  /// A five-pointed star in a box of [size].
  static Path _path(double size) {
    final path = Path();
    final c = Offset(size / 2, size * 0.54);
    final outer = size * 0.5, inner = size * 0.21;
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(r * math.cos(a), r * math.sin(a));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final shape = _path(star);
    final empty = Paint()
      ..color = const Color(0x2EF5F1EA)
      ..style = PaintingStyle.fill;
    final full = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    for (var i = 0; i < count; i++) {
      canvas.save();
      canvas.translate(i * (star + gap), 0);
      final fill = (value - i * 2).clamp(0, 2) / 2;
      canvas.drawPath(shape, empty);
      if (fill > 0) {
        canvas.save();
        canvas.clipRect(Rect.fromLTWH(0, 0, star * fill, star));
        canvas.drawPath(shape, full);
        canvas.restore();
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_StarsPainter old) =>
      old.value != value ||
      old.color != color ||
      old.star != star ||
      old.count != count;
}

/// A bookmark ribbon: outlined before anything is marked, filled after.
class _Ribbon extends StatelessWidget {
  const _Ribbon(
      {required this.size, required this.filled, required this.color});
  final double size;
  final bool filled;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
      size: Size.square(size), painter: _RibbonPainter(filled, color));
}

class _RibbonPainter extends CustomPainter {
  _RibbonPainter(this.filled, this.color);
  final bool filled;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final path = Path()
      ..moveTo(7, 3.5)
      ..lineTo(17, 3.5)
      ..quadraticBezierTo(19, 3.5, 19, 5.5)
      ..lineTo(19, 20.5)
      ..lineTo(12, 16)
      ..lineTo(5, 20.5)
      ..lineTo(5, 5.5)
      ..quadraticBezierTo(5, 3.5, 7, 3.5)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_RibbonPainter old) =>
      old.filled != filled || old.color != color;
}

/// An account under the panel: its mark and name, and how it holds the
/// work — a mint dot when it has it, red when it did not take it, grey
/// with “登录” when nobody is signed in there.
class _AccountMark extends StatelessWidget {
  const _AccountMark(
      {required this.link, required this.state, required this.onTap});
  final UiCollectionLink link;
  final _Sync state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (_, brand) = ServiceMark.of(link.provider);
    final out = state == _Sync.signedOut;
    return Pressable(
      onTap: onTap,
      semanticLabel: out ? '登录 ${link.name}' : link.name,
      pressScale: 0.97,
      builder: (context, hovered) {
        final color = out ? NextColors.p3 : brand;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: out ? 0.08 : 0.16),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: ServiceIcon(link.provider, color: color, size: 15),
          ),
          const SizedBox(width: 7),
          Text(link.name,
              style: NextText.sans(12.5,
                  color: out
                      ? NextColors.p3
                      : (hovered ? NextColors.paper : NextColors.p2))),
          const SizedBox(width: 7),
          if (out)
            Text('登录',
                style: NextText.sans(12.5,
                    weight: FontWeight.w600,
                    color: hovered ? NextColors.paper : NextColors.accent2))
          else
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: switch (state) {
                  _Sync.synced => NextColors.mint,
                  _Sync.failed => NextColors.accent,
                  _ => NextColors.p4,
                },
              ),
            ),
        ]);
      },
    );
  }
}

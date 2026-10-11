import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artwork.dart';

/// Where a work's picture is drawn right now, in the coordinates of the
/// shell's navigator.
@immutable
class ArtFrame {
  const ArtFrame({
    required this.rect,
    required this.clip,
    required this.radius,
    required this.image,
    required this.tint,
    required this.alignment,
    required this.decodeWidth,
    required this.lifts,
    this.shade,
  });

  /// The box the picture covers (with [alignment]).
  final Rect rect;

  /// The part of [rect] that is visible; the home's hero shows only its top.
  final Rect clip;
  final double radius;
  final String? image;
  final int? tint;
  final Alignment alignment;

  /// The width the picture was decoded at, so the flight reuses that decode.
  final int decodeWidth;

  /// What darkens the picture where it is, e.g. the home hero's shade.
  final List<Gradient>? shade;

  /// See [ArtOrigin.lifts].
  final bool lifts;
}

/// Marks a work's picture as the place a shared element transition flies
/// from when the work opens, and back to when it closes.
class ArtOrigin extends StatefulWidget {
  const ArtOrigin({
    super.key,
    required this.workId,
    required this.image,
    required this.child,
    this.tint,
    this.shape = ArtShape.wide,
    this.alignment = Alignment.center,
    this.radius = 0,
    this.visible,
    this.shade,
    this.lifts = true,
  });

  final String workId;
  final String? image;
  final int? tint;
  final ArtShape shape;
  final Alignment alignment;
  final double radius;

  /// A box whose bounds are the visible part of the picture, when the page
  /// clips it.
  final GlobalKey? visible;
  final List<Gradient>? shade;

  /// A card's picture is lifted off the page (hidden here while its copy
  /// flies). A backdrop with words over it stays, and the flight fades in
  /// over it, so the words fade out instead of vanishing.
  final bool lifts;
  final Widget child;

  @override
  State<ArtOrigin> createState() => ArtOriginState();
}

class ArtOriginState extends State<ArtOrigin> {
  ArtOrigins? _registry;
  ValueListenable<TickerModeData>? _onstage;
  bool _hidden = false;
  double _dpr = 2;

  String get workId => widget.workId;
  bool get lifts => widget.lifts;

  /// Hidden while its copy flies, so the picture is never seen twice.
  set hidden(bool value) {
    if (_hidden == value || !mounted) return;
    setState(() => _hidden = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = ArtOriginScope.maybeOf(context);
    if (!identical(registry, _registry)) {
      _registry?._origins.remove(this);
      _registry = registry?.._origins.add(this);
    }
    _onstage = TickerMode.getValuesNotifier(context);
  }

  @override
  void dispose() {
    _registry?._origins.remove(this);
    super.dispose();
  }

  /// The picture's frame relative to [reference]; null while it is not on
  /// screen (an offstage section or route, or not laid out).
  ArtFrame? frame(RenderBox reference) {
    if (!mounted || !(_onstage?.value.enabled ?? true)) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    if (!reference.attached || box.size.isEmpty) return null;
    final rect = MatrixUtils.transformRect(
        box.getTransformTo(reference), Offset.zero & box.size);
    var clip = rect;
    final visibleBox = widget.visible?.currentContext?.findRenderObject();
    if (visibleBox is RenderBox && visibleBox.attached && visibleBox.hasSize) {
      clip = rect.intersect(MatrixUtils.transformRect(
          visibleBox.getTransformTo(reference), Offset.zero & visibleBox.size));
    }
    final screen = Offset.zero & reference.size;
    if (clip.width <= 0 || clip.height <= 0 || !clip.overlaps(screen)) {
      return null;
    }
    return ArtFrame(
      rect: rect,
      clip: clip,
      radius: widget.radius * rect.width / box.size.width,
      image: widget.image,
      tint: widget.tint,
      alignment: widget.alignment,
      decodeWidth: NextImage.decodeWidth(box.size, _dpr, widget.shape),
      lifts: widget.lifts,
      shade: widget.shade,
    );
  }

  @override
  Widget build(BuildContext context) {
    _dpr = MediaQuery.devicePixelRatioOf(context);
    return Opacity(opacity: _hidden ? 0 : 1, child: widget.child);
  }
}

/// The pictures on screen that a work can open from. The shell owns one and
/// tells it where the pointer last went down.
class ArtOrigins {
  final _origins = <ArtOriginState>{};
  Offset? _press;
  DateTime? _pressedAt;

  /// The shell's navigator box: frames are measured relative to it.
  RenderBox? Function()? reference;

  void press(Offset local) {
    _press = local;
    _pressedAt = DateTime.now();
  }

  /// The picture the user just opened [workId] from: the one under the
  /// pointer, else the nearest one to it, else the largest on screen. With
  /// [near], the one closest to that rect (coming back to a rebuilt page).
  ArtOriginState? find(String workId, {Rect? near}) {
    final reference = this.reference?.call();
    if (reference == null || !reference.attached) return null;
    final found = <(ArtOriginState, ArtFrame)>[
      for (final origin in _origins)
        if (origin.workId == workId)
          if (origin.frame(reference) case final frame?) (origin, frame)
    ];
    if (found.isEmpty) return null;
    double area(Rect r) => r.width * r.height;
    double distance(Rect r, Offset p) {
      final double dx =
          p.dx < r.left ? r.left - p.dx : (p.dx > r.right ? p.dx - r.right : 0);
      final double dy =
          p.dy < r.top ? r.top - p.dy : (p.dy > r.bottom ? p.dy - r.bottom : 0);
      return dx * dx + dy * dy;
    }

    if (near != null) {
      found.sort((a, b) => (a.$2.rect.center - near.center)
          .distanceSquared
          .compareTo((b.$2.rect.center - near.center).distanceSquared));
      return found.first.$1;
    }
    final pressed = _pressedAt != null &&
            DateTime.now().difference(_pressedAt!) <
                const Duration(milliseconds: 1500)
        ? _press
        : null;
    if (pressed != null) {
      final under = found.where((f) => f.$2.clip.contains(pressed)).toList()
        ..sort((a, b) => area(a.$2.clip).compareTo(area(b.$2.clip)));
      if (under.isNotEmpty) return under.first.$1;
      final close = found
          .where((f) => distance(f.$2.clip, pressed) < 360 * 360)
          .toList()
        ..sort((a, b) => distance(a.$2.clip, pressed)
            .compareTo(distance(b.$2.clip, pressed)));
      if (close.isNotEmpty) return close.first.$1;
    }
    found.sort((a, b) => area(b.$2.clip).compareTo(area(a.$2.clip)));
    return found.first.$1;
  }
}

class ArtOriginScope extends InheritedWidget {
  const ArtOriginScope(
      {super.key, required this.origins, required super.child});
  final ArtOrigins origins;

  static ArtOrigins? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ArtOriginScope>()?.origins;

  @override
  bool updateShouldNotify(ArtOriginScope old) => old.origins != origins;
}

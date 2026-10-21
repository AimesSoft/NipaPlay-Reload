import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/poster_art.dart';

/// A category's or folder's cover: its posters fanned out like a hand of
/// cards over a blur of its art, darker toward the lower left where its
/// name goes. Three posters fan out; two lean together; one stands before
/// an empty sleeve; without any, sleeves of its colour. [lift] (0–1, the
/// hover) opens the fan a little.
class FanCover extends StatelessWidget {
  const FanCover({
    super.key,
    required this.posters,
    this.backdrop,
    this.tint,
    this.lift = 0,
    this.at = Alignment.center,
    this.scale = 0.64,
  });

  final List<String> posters;
  final String? backdrop;
  final int? tint;
  final double lift;

  /// Where the fan stands in the cover.
  final Alignment at;

  /// A poster's height against the cover's.
  final double scale;

  Color get _base => tint == null ? const Color(0xFF2A2A34) : Color(tint!);

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final size = constraints.biggest;
        final art = backdrop ?? posters.firstOrNull;
        return Stack(fit: StackFit.expand, children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  Color.lerp(_base, NextColors.ink, 0.15)!,
                  Color.lerp(_base, NextColors.ink, 0.8)!,
                ],
              ),
            ),
          ),
          if (art != null)
            Opacity(opacity: 0.62 + 0.14 * lift, child: _Blur(art)),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomLeft,
                end: Alignment.topRight,
                colors: [Color(0xE608080B), Color(0x7308080B), Color(0x1408080B)],
                stops: [0, 0.45, 1],
              ),
            ),
          ),
          ..._fan(size),
        ]);
      });

  /// The cards from back to front.
  List<Widget> _fan(Size size) {
    final h = size.height * scale;
    final w = h * 2 / 3;
    final center = Offset(size.width / 2 + at.x * (size.width - w) / 2,
        size.height / 2 + at.y * (size.height - h) / 2);
    final t = lift;
    const deg = math.pi / 180;
    Widget place(Widget card,
            {double angle = 0, double dx = 0, double dy = 0, double grow = 1}) =>
        Positioned(
          left: center.dx - w / 2 + dx,
          top: center.dy - h / 2 + dy,
          width: w,
          height: h,
          child: Transform(
            // Turning about a point well below the cards spreads them like
            // a hand of cards.
            alignment: const Alignment(0, 2.8),
            transform: Matrix4.rotationZ(angle * deg)
              ..scaleByDouble(grow, grow, 1, 1),
            child: card,
          ),
        );
    final lifted = (dy: -h * 0.035 * t, grow: 1 + 0.025 * t);
    switch (posters) {
      case []:
        return [
          place(_Sleeve(_base, h, light: 0),
              angle: -(11 + 5 * t), dx: -w * (0.06 + 0.05 * t)),
          place(_Sleeve(_base, h, light: 0),
              angle: 11 + 5 * t, dx: w * (0.06 + 0.05 * t)),
          place(_Sleeve(_base, h, light: 1),
              dy: lifted.dy, grow: lifted.grow),
        ];
      case [final only]:
        return [
          place(_Sleeve(_base, h, light: 0.5),
              angle: -(8 + 5 * t), dx: -w * (0.06 + 0.04 * t)),
          place(_Poster(only, tint, h),
              angle: 1.5 * (1 - t), dy: lifted.dy, grow: lifted.grow),
        ];
      case [final front, final back]:
        return [
          place(_Poster(back, tint, h, shade: 0.24 - 0.1 * t),
              angle: -(7 + 4 * t), dx: -w * (0.17 + 0.05 * t)),
          place(_Poster(front, tint, h),
              angle: 5 + 3 * t,
              dx: w * (0.17 + 0.05 * t),
              dy: lifted.dy,
              grow: lifted.grow),
        ];
      default:
        final [first, second, third] = posters.take(3).toList();
        return [
          place(_Poster(second, tint, h, shade: 0.3 - 0.12 * t),
              angle: -(11 + 5 * t), dx: -w * (0.06 + 0.05 * t)),
          place(_Poster(third, tint, h, shade: 0.3 - 0.12 * t),
              angle: 11 + 5 * t, dx: w * (0.06 + 0.05 * t)),
          place(_Poster(first, tint, h), dy: lifted.dy, grow: lifted.grow),
        ];
    }
  }
}

class _Poster extends StatelessWidget {
  const _Poster(this.path, this.tint, this.height, {this.shade = 0});
  final String path;
  final int? tint;
  final double height;

  /// How much darker it sits behind the front one.
  final double shade;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height * 0.045);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
              color: const Color(0x8C000000),
              blurRadius: height * 0.14,
              offset: Offset(0, height * 0.06)),
        ],
      ),
      position: DecorationPosition.background,
      child: Container(
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          color: Color.fromRGBO(8, 8, 11, shade),
          border: Border.all(color: const Color(0x1FFFFFFF), width: 0.8),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: PosterArt(path, tint: tint),
        ),
      ),
    );
  }
}

/// An empty card of the cover's colour, where a poster would be.
class _Sleeve extends StatelessWidget {
  const _Sleeve(this.base, this.height, {required this.light});
  final Color base;
  final double height;

  /// 1 for the front one, 0 for those behind.
  final double light;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(height * 0.045);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(Color.lerp(base, NextColors.ink, 0.35),
                NextColors.paper, 0.06 + 0.1 * light)!,
            Color.lerp(base, NextColors.ink, 0.72 - 0.12 * light)!,
          ],
        ),
        border: Border.all(
            color: Color.fromRGBO(255, 255, 255, 0.08 + 0.08 * light),
            width: 0.8),
        boxShadow: [
          BoxShadow(
              color: const Color(0x73000000),
              blurRadius: height * 0.14,
              offset: Offset(0, height * 0.06)),
        ],
      ),
    );
  }
}

/// The art, decoded small and blurred: only its colours are wanted.
class _Blur extends StatelessWidget {
  const _Blur(this.path);
  final String path;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Transform.scale(
            scale: 1.3,
            child: SheetBuilder(
              path: path,
              builder: (context, sheet) => sheet != null
                  ? SheetCover(sheet)
                  : Image(
                      image: ResizeImage(artProvider(path), width: 96),
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
            ),
          ),
        ),
      );
}

/// Hover handling for covers: [builder] gets the fan's lift, eased; the
/// whole cover grows a little. Reduced motion keeps the fan still.
class _Hovering extends StatefulWidget {
  const _Hovering({required this.builder, required this.onTap, this.grow = 1.02});
  final Widget Function(BuildContext context, double lift) builder;
  final VoidCallback onTap;
  final double grow;

  @override
  State<_Hovering> createState() => _HoveringState();
}

class _HoveringState extends State<_Hovering> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final reduced = NextMotion.reduced(context);
    final on = _hovered && !reduced;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: on ? widget.grow : 1,
          duration: const Duration(milliseconds: 320),
          curve: NextMotion.ease,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: on ? 1 : 0),
            duration: const Duration(milliseconds: 420),
            curve: NextMotion.ease,
            builder: (context, lift, _) => widget.builder(context, lift),
          ),
        ),
      ),
    );
  }
}

/// A category in the cards form: its fan, and at the lower left its name
/// and how many it holds.
class CategoryCard extends StatelessWidget {
  const CategoryCard({
    super.key,
    required this.title,
    required this.count,
    required this.posters,
    this.backdrop,
    this.tint,
    required this.onOpen,
  });

  final String title;
  final int? count;
  final List<String> posters;
  final String? backdrop;
  final int? tint;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return _Hovering(
      onTap: onOpen,
      builder: (context, lift) => Container(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: const [
            BoxShadow(
                color: Color(0x73000000), blurRadius: 34, offset: Offset(0, 14)),
          ],
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: const Color(0x14FFFFFF)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(fit: StackFit.expand, children: [
            FanCover(
              posters: posters,
              backdrop: backdrop,
              tint: tint,
              lift: lift,
              at: const Alignment(0.36, -0.6),
              scale: 0.6,
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 20,
              child: CategoryName(title: title, count: count, size: 23),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A folder of a source's own structure, in a grid or a row: the same fan
/// in a poster's shape, its name and count below.
class FolderTile extends StatelessWidget {
  const FolderTile({
    super.key,
    required this.title,
    required this.count,
    required this.posters,
    required this.width,
    required this.onOpen,
  });

  final String title;
  final int? count;
  final List<String> posters;
  final double width;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _Hovering(
            onTap: onOpen,
            grow: 1.03,
            builder: (context, lift) => Container(
              height: width * 3 / 2,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x80000000),
                      blurRadius: 40,
                      offset: Offset(0, 18)),
                ],
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: const Color(0x14FFFFFF)),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: FanCover(
                  posters: posters,
                  lift: lift,
                  at: const Alignment(0, -0.1),
                  scale: 0.46,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CategoryName(title: title, count: count, size: 14.5),
        ],
      ),
    );
  }
}

/// A category's name and, after it, how many it holds: the same on a card,
/// a folder and a shelf.
class CategoryName extends StatelessWidget {
  const CategoryName(
      {super.key, required this.title, required this.count, required this.size});
  final String title;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final big = size > 18;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(size,
                  weight: big ? FontWeight.w700 : FontWeight.w600,
                  letterSpacing: big ? 0.4 : 0,
                  shadows: big
                      ? const [
                          Shadow(
                              color: Color(0x80000000),
                              blurRadius: 12,
                              offset: Offset(0, 2))
                        ]
                      : null)),
        ),
        if (count != null) ...[
          SizedBox(width: size * 0.42),
          Text('$count',
              style: NextText.num(size * 0.66,
                  weight: FontWeight.w500,
                  color: big ? NextColors.p2 : NextColors.p3)),
        ],
      ],
    );
  }
}

import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';
import 'artwork.dart';
import 'buttons.dart';
import 'progress.dart';

/// Hover handling shared by work cards: scale to 1.03 (not under reduced
/// motion), reveal the round play button, report hover to the page.
mixin _HoverCard<T extends StatefulWidget> on State<T> {
  bool hovered = false;

  void setHovered(bool value, ValueChanged<bool>? report) {
    if (hovered == value) return;
    setState(() => hovered = value);
    report?.call(value);
  }

  Widget hoverScale(BuildContext context, Widget child) => AnimatedScale(
        scale: hovered && !NextMotion.reduced(context) ? 1.03 : 1,
        duration: const Duration(milliseconds: 320),
        curve: NextMotion.ease,
        child: child,
      );

  Widget playOverlay(VoidCallback? onPlay, {double size = 46}) => onPlay == null
      ? const SizedBox.shrink()
      : Center(
          child: IgnorePointer(
            ignoring: !hovered,
            child: AnimatedOpacity(
              opacity: hovered ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: HoverPlayButton(onTap: onPlay, size: size),
            ),
          ),
        );
}

/// The 16:9 card (`.card .thumb`): artwork, bottom shade, title and caption
/// inside, optional watch progress and corner badge.
class WideCard extends StatefulWidget {
  const WideCard({
    super.key,
    required this.image,
    this.tint,
    this.title,
    this.caption,
    this.progress,
    this.badge,
    this.width = 296,
    this.height = 150,
    this.onOpen,
    this.onPlay,
    this.onHover,
    this.selected = false,
  });

  final String? image;
  final int? tint;
  final String? title;
  final String? caption;
  final double? progress;
  final String? badge;
  final double width;
  final double height;
  final VoidCallback? onOpen;
  final VoidCallback? onPlay;
  final ValueChanged<bool>? onHover;
  final bool selected;

  @override
  State<WideCard> createState() => _WideCardState();
}

class _WideCardState extends State<WideCard> with _HoverCard {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return MouseRegion(
      cursor:
          widget.onOpen == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setHovered(true, widget.onHover),
      onExit: (_) => setHovered(false, widget.onHover),
      child: GestureDetector(
        onTap: widget.onOpen,
        child: hoverScale(
          context,
          Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                if (widget.selected)
                  const BoxShadow(color: NextColors.paper, spreadRadius: 2),
                const BoxShadow(
                    color: Color(0x59000000),
                    blurRadius: 30,
                    offset: Offset(0, 10)),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: const Color(0x0FFFFFFF)),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(fit: StackFit.expand, children: [
                NextImage(widget.image, tint: widget.tint),
                if (widget.title != null || widget.caption != null)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Color(0xC7000000),
                          Color(0x33000000),
                          Color(0x00000000)
                        ],
                        stops: [0, 0.46, 0.7],
                      ),
                    ),
                  ),
                if (widget.badge != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0x80000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(widget.badge!,
                          style: NextText.sans(11,
                              weight: FontWeight.w600, color: NextColors.p2)),
                    ),
                  ),
                if (widget.title != null || widget.caption != null)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 20,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.title != null)
                          Text(widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NextText.sans(14.5,
                                  weight: FontWeight.w600,
                                  shadows: const [
                                    Shadow(
                                        color: Color(0x80000000),
                                        blurRadius: 6,
                                        offset: Offset(0, 1))
                                  ])),
                        if (widget.caption != null) ...[
                          const SizedBox(height: 3),
                          Text(widget.caption!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: NextText.sans(11.5, color: NextColors.p2)),
                        ],
                      ],
                    ),
                  ),
                if (widget.progress != null)
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 11,
                    child: ThinBar(
                      progress: widget.progress!,
                      track: const Color(0x38FFFFFF),
                      fill: NextColors.paper,
                    ),
                  ),
                playOverlay(widget.onPlay, size: 44),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The poster card (`.pick`): 2:3 artwork with a title and one reason below.
class PosterCard extends StatefulWidget {
  const PosterCard({
    super.key,
    required this.image,
    this.tint,
    required this.title,
    this.reason,
    this.width = 176,
    this.height = 252,
    this.selected = false,
    this.onOpen,
    this.onPlay,
    this.onHover,
  });

  final String? image;
  final int? tint;
  final String title;
  final String? reason;
  final double width;
  final double height;
  final bool selected;
  final VoidCallback? onOpen;
  final VoidCallback? onPlay;
  final ValueChanged<bool>? onHover;

  @override
  State<PosterCard> createState() => _PosterCardState();
}

class _PosterCardState extends State<PosterCard> with _HoverCard {
  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    final reduced = NextMotion.reduced(context);
    return SizedBox(
      width: widget.width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          MouseRegion(
            cursor: widget.onOpen == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            onEnter: (_) => setHovered(true, widget.onHover),
            onExit: (_) => setHovered(false, widget.onHover),
            child: GestureDetector(
              onTap: widget.onOpen,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: NextMotion.ease,
                transform: Matrix4.translationValues(
                    0, widget.selected && !reduced ? -6 : 0, 0),
                child: hoverScale(
                  context,
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    curve: NextMotion.ease,
                    height: widget.height,
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      boxShadow: widget.selected
                          ? const [
                              BoxShadow(
                                  color: NextColors.paper, spreadRadius: 2),
                              BoxShadow(
                                  color: Color(0x99000000),
                                  blurRadius: 50,
                                  offset: Offset(0, 22)),
                            ]
                          : const [
                              BoxShadow(
                                  color: Color(0x00F5F1EA), spreadRadius: 0),
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
                      child: Stack(fit: StackFit.expand, children: [
                        NextImage(widget.image,
                            shape: ArtShape.poster, tint: widget.tint),
                        playOverlay(widget.onPlay),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: NextText.sans(14.5, weight: FontWeight.w600)),
          if (widget.reason != null && widget.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(widget.reason!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: NextText.sans(12.5, color: NextColors.p3, height: 1.5)),
          ],
        ],
      ),
    );
  }
}

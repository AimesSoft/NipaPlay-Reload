import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/tokens.dart';
import '../widgets/buttons.dart';
import '../widgets/cards.dart';
import '../widgets/icons.dart';
import '../widgets/words.dart';

/// The season heading (`h3`), with ▾ when there is more than one season.
class SeasonHeader extends StatelessWidget {
  const SeasonHeader({super.key, required this.season, required this.onTap});
  final int? season;

  /// Opens the season list; null with a single season.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = Text(Words.season(season),
        style: NextText.sans(19, weight: FontWeight.w600, letterSpacing: 0.4));
    if (onTap == null) return label;
    return Pressable(
      onTap: onTap,
      semanticLabel: Words.season(season),
      pressScale: 0.98,
      builder: (context, hovered) =>
          Row(mainAxisSize: MainAxisSize.min, children: [
        label,
        const SizedBox(width: 6),
        RotatedBox(
          quarterTurns: 1,
          child: NextIcon(NextGlyph.chevronRight,
              size: 14, color: hovered ? NextColors.paper : NextColors.p3),
        ),
      ]),
    );
  }
}

/// One season's episodes in a horizontal row, opened at the current one.
class EpisodeRow extends StatefulWidget {
  const EpisodeRow({
    super.key,
    required this.work,
    required this.episodes,
    required this.currentId,
    required this.onPlay,
  });

  final UiWork work;
  final List<UiEpisode> episodes;
  final String? currentId;
  final void Function(UiEpisode episode) onPlay;

  static const tileWidth = 256.0, gap = 16.0;

  /// Still, title row and heat line.
  static const height = 144 + 10 + 19 + 8 + 22.0;

  @override
  State<EpisodeRow> createState() => _EpisodeRowState();
}

class _EpisodeRowState extends State<EpisodeRow> {
  ScrollController? _scroll;

  /// Starts at the first episode, unless the current one would be cut off:
  /// then it is second from the left.
  ScrollController _controller(double width) {
    final at =
        widget.episodes.indexWhere((e) => e.episodeId == widget.currentId);
    const step = EpisodeRow.tileWidth + EpisodeRow.gap;
    final right = NextMetrics.gutter + at * step + EpisodeRow.tileWidth;
    return ScrollController(
        initialScrollOffset:
            at > 0 && right > width - 56 ? (at - 1) * step : 0);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: EpisodeRow.height,
        child: ListView.separated(
          controller: _scroll ??= _controller(MediaQuery.sizeOf(context).width),
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.only(left: NextMetrics.gutter, right: 56),
          itemCount: widget.episodes.length,
          separatorBuilder: (_, __) => const SizedBox(width: EpisodeRow.gap),
          itemBuilder: (context, i) {
            final episode = widget.episodes[i];
            return EpisodeTile(
              work: widget.work,
              episode: episode,
              current: episode.episodeId == widget.currentId,
              onPlay: episode.playable ? () => widget.onPlay(episode) : null,
            );
          },
        ),
      );
}

/// `.ep`: 16:9 still with the big number, title and runtime, the danmaku
/// heat line. Watched episodes have a full bar; the current one a white
/// outline. Hover scales 1.03 and shows play; a click plays.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.work,
    required this.episode,
    required this.current,
    required this.onPlay,
  });

  final UiWork work;
  final UiEpisode episode;
  final bool current;

  /// Null when NipaPlay has nothing to play it from yet.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final title = episode.title;
    return SizedBox(
      width: EpisodeRow.tileWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Opacity(
            opacity: onPlay == null ? 0.55 : 1,
            child: WideCard(
              image: episode.still,
              tint: work.artwork.tint,
              width: EpisodeRow.tileWidth,
              height: 144,
              progress: episode.progress,
              selected: current,
              label: Text(episode.number.toString().padLeft(2, '0'),
                  style: NextText.num(28,
                      weight: FontWeight.w700,
                      letterSpacing: -0.56,
                      color: const Color(0xEBFFFFFF))),
              onOpen: onPlay,
              onPlay: onPlay,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 19,
            child: Row(children: [
              Expanded(
                child: Text(title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: NextText.sans(13.5, weight: FontWeight.w600)),
              ),
              if (episode.runtime != null) ...[
                const SizedBox(width: 8),
                NumText(Words.runtime(episode.runtime!),
                    style: NextText.sans(12,
                        weight: FontWeight.w500, color: NextColors.p3)),
              ],
            ]),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 22,
            width: EpisodeRow.tileWidth,
            child: episode.heat == null || episode.heat!.isEmpty
                ? null
                : CustomPaint(painter: HeatPainter(episode.heat!)),
          ),
        ],
      ),
    );
  }
}

/// `.spark`: where the danmaku gather over the episode, a smooth crimson
/// line over a faint fill.
class HeatPainter extends CustomPainter {
  HeatPainter(this.heat);
  final List<double> heat;

  /// Neighbouring buckets blended so the line reads as a shape, not noise.
  static List<double> smooth(List<double> values) {
    const weights = [0.06, 0.24, 0.4, 0.24, 0.06];
    return [
      for (var i = 0; i < values.length; i++)
        () {
          var sum = 0.0, total = 0.0;
          for (var k = -2; k <= 2; k++) {
            final j = i + k;
            if (j < 0 || j >= values.length) continue;
            sum += values[j] * weights[k + 2];
            total += weights[k + 2];
          }
          return sum / total;
        }()
    ];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final values = smooth(heat);
    final peak = values.fold<double>(0, math.max);
    final h = size.height;
    final points = [
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1 ? 0 : size.width * i / (values.length - 1),
          h - 2 - (peak == 0 ? 0 : values[i] / peak) * (h - 4),
        )
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final p0 = points[math.max(0, i - 1)], p1 = points[i];
      final p2 = points[i + 1], p3 = points[math.min(points.length - 1, i + 2)];
      final c1 = p1 + (p2 - p0) / 6, c2 = p2 - (p3 - p1) / 6;
      line.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(fill, Paint()..color = const Color(0x29FF2E55));
    canvas.drawPath(
        line,
        Paint()
          ..color = const Color(0xD9FF2E55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(HeatPainter old) => !identical(old.heat, heat);
}

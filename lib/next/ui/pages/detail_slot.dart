import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../shell/shell_controller.dart';
import '../theme/tokens.dart';
import '../widgets/artwork.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
import '../widgets/words.dart';

/// Where the detail page goes (next stage): the route, the back gesture and
/// the full-bleed backdrop are in place; episodes, seasons, parallax and
/// the shared element transition come with the page itself.
class DetailSlot extends StatelessWidget {
  const DetailSlot({super.key, required this.work});
  final UiWork work;

  @override
  Widget build(BuildContext context) {
    final shell = NextShellScope.of(context);
    return ColoredBox(
      color: NextColors.ink,
      child: Stack(fit: StackFit.expand, children: [
        NextImage(work.artwork.backdrop,
            tint: work.artwork.tint, alignment: const Alignment(0, -0.6)),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Color(0xF208080B),
              Color(0xCC08080B),
              Color(0x3808080B),
              Color(0x0D08080B),
            ], stops: [
              0,
              .3,
              .62,
              1
            ]),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [NextColors.ink, Color(0xD908080B), Color(0x0008080B)],
              stops: [0, .26, .55],
            ),
          ),
        ),
        Positioned(
          left: NextMetrics.gutter,
          top: 78,
          child: Pressable(
            onTap: () => Navigator.of(context).pop(),
            semanticLabel: '返回',
            builder: (context, hovered) => Row(children: [
              NextIcon(NextGlyph.chevronLeft,
                  size: 16, color: hovered ? NextColors.paper : NextColors.p2),
              const SizedBox(width: 4),
              Text('返回',
                  style: NextText.sans(13.5,
                      color: hovered ? NextColors.paper : NextColors.p2)),
            ]),
          ),
        ),
        Positioned(
          left: NextMetrics.gutter,
          top: 150,
          width: 600,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (work.originalTitle != null &&
                  work.originalTitle != work.title)
                Text(work.originalTitle!,
                    style: NextText.sans(13,
                        color: NextColors.p3, letterSpacing: 2.6)),
              Padding(
                padding: const EdgeInsets.only(top: 18, bottom: 10),
                child: Text(work.title,
                    style:
                        NextText.serif(64, letterSpacing: 2.56, height: 1.08)),
              ),
              MetaLine(work, allRatings: true, studio: true),
              if (work.overview != null)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(work.overview!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: NextText.sans(14.5,
                          color: NextColors.p2, height: 1.75)),
                ),
              const SizedBox(height: 26),
              PlayButton(
                  label: (work.next?.progress ?? 0) > 0
                      ? '继续 ${Words.episode(work.next!.number)}'
                      : '播放',
                  onTap: () => shell.play(work)),
            ],
          ),
        ),
      ]),
    );
  }
}

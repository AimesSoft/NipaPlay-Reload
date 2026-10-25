import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../../ui_data/ui_data.dart';
import '../theme/layout.dart';
import '../theme/tokens.dart';
import 'artwork.dart';

/// `.logo` (96 high, drop shadow) or the Songti title when there is none.
class WorkTitle extends StatelessWidget {
  const WorkTitle({super.key, required this.work, this.margins = true});
  final UiWork work;

  /// The concept's margins around it (`.logo` 20/16, `.title-serif` 18/10).
  final bool margins;

  static EdgeInsets marginsOf(UiWork work) => work.artwork.logo == null
      ? const EdgeInsets.only(top: 18, bottom: 10)
      : const EdgeInsets.only(top: 20, bottom: 16);

  /// 64 px as in the concept; long titles step down to stay within two
  /// lines of the 600 px column.
  static double serifSize(String title) => title.characters.length <= 8
      ? 64
      : title.characters.length <= 12
          ? 52
          : 44;

  @override
  Widget build(BuildContext context) {
    final title = _bare(NextLayout.compact(context));
    return margins ? Padding(padding: marginsOf(work), child: title) : title;
  }

  /// On a phone the title is drawn for its narrow column: smaller, so a
  /// long one still fits in two lines.
  Widget _bare(bool compact) {
    final logo = work.artwork.logo;
    final logoHeight = compact ? 72.0 : 96.0;
    if (logo == null) {
      final size = serifSize(work.title) * (compact ? 0.6 : 1);
      return Text(work.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style:
              NextText.serif(size, letterSpacing: size * 0.04, height: 1.08));
    }
    return Transform.translate(
      offset: const Offset(-6, 0),
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: compact ? 300 : 460, maxHeight: logoHeight),
        child: SizedBox(
          height: logoHeight,
          child: Stack(clipBehavior: Clip.none, children: [
            // drop-shadow(0 6px 24px rgba(0,0,0,.45)), one small layer.
            Positioned.fill(
              top: 6,
              bottom: -6,
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: ColorFiltered(
                  colorFilter: const ColorFilter.mode(
                      Color(0x73000000), BlendMode.srcIn),
                  child: NextImage(logo,
                      shape: ArtShape.logo,
                      fit: BoxFit.contain,
                      alignment: Alignment.centerLeft),
                ),
              ),
            ),
            Positioned.fill(
              child: NextImage(logo,
                  shape: ArtShape.logo,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft),
            ),
          ]),
        ),
      ),
    );
  }
}

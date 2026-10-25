import 'package:flutter/widgets.dart';

import '../theme/layout.dart';
import '../theme/tokens.dart';

/// A titled, horizontally scrolling row (`.shelf`). Cards may scale and
/// cast shadows past the row, so the viewport does not clip vertically.
class Shelf extends StatelessWidget {
  const Shelf({
    super.key,
    required this.title,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.gutter,
    this.gap = 16,
    this.storageKey,
    this.trailing,
  });

  final String title;
  final double height;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  /// The left edge; the layout's ([NextLayout.gutter]) unless given.
  final double? gutter;
  final double gap;

  /// Keeps the horizontal position when coming back to the page.
  final String? storageKey;

  /// Beside the title, e.g. tabs that choose what the row shows.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final gutter = this.gutter ?? NextLayout.gutter(context);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(left: gutter),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(title,
                    style: NextText.sans(19,
                        weight: FontWeight.w600, letterSpacing: 0.4)),
                if (trailing case final t?) ...[
                  const SizedBox(width: 28),
                  Flexible(child: t),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: height,
            child: ListView.separated(
              key: storageKey == null ? null : PageStorageKey(storageKey),
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              padding: EdgeInsets.only(
                  left: gutter, right: NextLayout.end(context)),
              itemCount: itemCount,
              separatorBuilder: (_, __) => SizedBox(width: gap),
              itemBuilder: itemBuilder,
            ),
          ),
        ],
      );
  }
}

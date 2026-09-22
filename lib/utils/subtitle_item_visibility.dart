import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Whether the entire subtitle row is inside its scroll viewport.
bool isSubtitleItemFullyVisible(
  BuildContext itemContext,
  ScrollController controller,
) {
  if (!controller.hasClients) return false;
  final item = itemContext.findRenderObject();
  if (item == null || !item.attached) return false;
  final viewport = RenderAbstractViewport.maybeOf(item);
  if (viewport == null) return false;

  final offset = controller.offset;
  final leading = viewport.getOffsetToReveal(item, 0).offset;
  final trailing = viewport.getOffsetToReveal(item, 1).offset;
  const tolerance = 1.0;
  return leading >= offset - tolerance && trailing <= offset + tolerance;
}

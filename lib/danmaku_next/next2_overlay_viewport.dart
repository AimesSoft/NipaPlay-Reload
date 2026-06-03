import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

class Next2OverlayViewport {
  const Next2OverlayViewport._();

  static Size resolveLayoutSize(
    BuildContext context,
    BoxConstraints constraints,
  ) {
    final constrainedSize = _constraintsSize(constraints);
    if (constrainedSize.isEmpty || !globals.isMobilePlatform) {
      return constrainedSize;
    }

    final view = View.of(context);
    final dpr = view.devicePixelRatio;
    final viewSize = dpr > 0
        ? Size(
            view.physicalSize.width / dpr,
            view.physicalSize.height / dpr,
          )
        : constrainedSize;
    final mediaSize = MediaQuery.maybeOf(context)?.size ?? viewSize;
    final viewportSize = Size(
      viewSize.width > mediaSize.width ? viewSize.width : mediaSize.width,
      viewSize.height > mediaSize.height ? viewSize.height : mediaSize.height,
    );

    if (viewportSize.isEmpty) {
      return constrainedSize;
    }

    var width = constrainedSize.width;
    var height = constrainedSize.height;
    const edgeTolerance = 2.0;

    final fillsViewportHeight =
        (height - viewportSize.height).abs() <= edgeTolerance ||
            height >= viewportSize.height - edgeTolerance;
    final fillsViewportWidth =
        (width - viewportSize.width).abs() <= edgeTolerance ||
            width >= viewportSize.width - edgeTolerance;

    if (fillsViewportHeight && viewportSize.width > width) {
      width = viewportSize.width;
    }
    if (fillsViewportWidth && viewportSize.height > height) {
      height = viewportSize.height;
    }

    return Size(width, height);
  }

  static Widget buildLayer({
    required Size layoutSize,
    required Size constrainedSize,
    required Widget child,
  }) {
    final sameSize = (layoutSize.width - constrainedSize.width).abs() < 0.5 &&
        (layoutSize.height - constrainedSize.height).abs() < 0.5;
    if (sameSize) {
      return SizedBox.expand(child: child);
    }

    return OverflowBox(
      alignment: Alignment.center,
      minWidth: layoutSize.width,
      maxWidth: layoutSize.width,
      minHeight: layoutSize.height,
      maxHeight: layoutSize.height,
      child: SizedBox(
        width: layoutSize.width,
        height: layoutSize.height,
        child: child,
      ),
    );
  }

  static Size _constraintsSize(BoxConstraints constraints) {
    final width = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.minWidth;
    final height = constraints.maxHeight.isFinite
        ? constraints.maxHeight
        : constraints.minHeight;
    return Size(width, height);
  }
}

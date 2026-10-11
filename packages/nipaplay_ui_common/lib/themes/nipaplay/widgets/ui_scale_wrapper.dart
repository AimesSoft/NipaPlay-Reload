import 'package:flutter/widgets.dart';

class UiScaleWrapper extends StatelessWidget {
  final double scale;
  final Widget child;

  const UiScaleWrapper({
    super.key,
    required this.scale,
    required this.child,
  });

  EdgeInsets _scaleInsets(EdgeInsets insets, double scale) {
    return EdgeInsets.fromLTRB(
      insets.left / scale,
      insets.top / scale,
      insets.right / scale,
      insets.bottom / scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (scale == 1.0) {
      return child;
    }

    final mediaQuery = MediaQuery.of(context);
    final double effectiveScale = scale <= 0 ? 1.0 : scale;
    final Size scaledSize = Size(
      mediaQuery.size.width / effectiveScale,
      mediaQuery.size.height / effectiveScale,
    );
    final scaledData = mediaQuery.copyWith(
      size: scaledSize,
      padding: _scaleInsets(mediaQuery.padding, effectiveScale),
      viewInsets: _scaleInsets(mediaQuery.viewInsets, effectiveScale),
      viewPadding: _scaleInsets(mediaQuery.viewPadding, effectiveScale),
      systemGestureInsets:
          _scaleInsets(mediaQuery.systemGestureInsets, effectiveScale),
    );

    return MediaQuery(
      data: scaledData,
      child: Align(
        alignment: Alignment.topLeft,
        child: Transform.scale(
          scale: effectiveScale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: scaledSize.width,
            height: scaledSize.height,
            child: child,
          ),
        ),
      ),
    );
  }
}

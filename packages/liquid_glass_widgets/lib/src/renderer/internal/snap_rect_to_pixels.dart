import 'package:flutter/rendering.dart';
import 'package:meta/meta.dart';

@internal
extension SnapRectToPixels on Rect {
  Rect snapToPixels(double devicePixelRatio) {
    return Rect.fromLTRB(
      left.snapToPixel(devicePixelRatio: devicePixelRatio),
      top.snapToPixel(devicePixelRatio: devicePixelRatio),
      right.snapToPixel(devicePixelRatio: devicePixelRatio),
      bottom.snapToPixel(devicePixelRatio: devicePixelRatio),
    );
  }
}

extension on double {
  double snapToPixel({required double devicePixelRatio}) {
    return (this * devicePixelRatio).roundToDouble() / devicePixelRatio;
  }
}

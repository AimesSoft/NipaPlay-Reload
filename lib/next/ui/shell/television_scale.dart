import 'package:flutter/widgets.dart';
import 'package:nipaplay/utils/globals.dart' as globals;

/// A television is read from across the room. There Next lays itself out
/// on a page [factor] times smaller than the screen and is drawn [factor]
/// times larger, so type, cards and controls grow together and keep the
/// proportions they have in a window.
class NextTelevisionScale extends StatelessWidget {
  const NextTelevisionScale({super.key, required this.child});
  final Widget child;

  static const factor = 1.6;

  @override
  Widget build(BuildContext context) {
    if (!globals.isTelevision) return child;
    final media = MediaQuery.of(context);
    final size = media.size / factor;
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: media.copyWith(
            size: size,
            // Pictures are decoded for the pixels they will cover.
            devicePixelRatio: media.devicePixelRatio * factor,
            padding: media.padding / factor,
            viewPadding: media.viewPadding / factor,
            viewInsets: media.viewInsets / factor,
          ),
          child: child,
        ),
      ),
    );
  }
}

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AirPlayRoutePicker extends StatelessWidget {
  const AirPlayRoutePicker({
    super.key,
    this.size = 28,
    this.tintColor = Colors.white,
    this.activeTintColor = Colors.white,
    this.prioritizesVideoDevices = true,
  });

  final double size;
  final Color tintColor;
  final Color activeTintColor;
  final bool prioritizesVideoDevices;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      width: size,
      height: size,
      child: UiKitView(
        viewType: 'nipaplay/airplay_route_picker',
        creationParams: <String, dynamic>{
          'tintColor': tintColor.toARGB32(),
          'activeTintColor': activeTintColor.toARGB32(),
          'prioritizesVideoDevices': prioritizesVideoDevices,
        },
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      ),
    );
  }
}

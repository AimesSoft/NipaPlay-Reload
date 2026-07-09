import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/themes/nipaplay/widgets/indicator_widget.dart';

class BrightnessIndicator extends StatelessWidget {
  const BrightnessIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return IndicatorWidget(
      isVisible: (videoState) => videoState.isBrightnessIndicatorVisible,
      getValue: (videoState) => videoState.currentScreenBrightness,
      getIcon: (videoState) => Ionicons.sunny_outline,
    );
  }
}

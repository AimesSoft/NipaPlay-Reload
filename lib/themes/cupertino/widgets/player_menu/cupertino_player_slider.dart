import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

class CupertinoPlayerSlider extends StatelessWidget {
  const CupertinoPlayerSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
  }) : assert(max >= min);

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final double clampedValue = value.clamp(min, max);
    return SizedBox(
      height: 44,
      child: AdaptiveSlider(
        value: clampedValue,
        min: min,
        max: max,
        divisions: divisions,
        activeColor: activeColor ?? CupertinoTheme.of(context).primaryColor,
        onChanged: onChanged,
      ),
    );
  }
}

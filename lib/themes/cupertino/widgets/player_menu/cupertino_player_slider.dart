import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

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
    return LayoutBuilder(
      builder: (context, constraints) {
        final double? width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : null;
        return SizedBox(
          height: 44,
          width: width,
          child: AdaptiveSlider(
            value: clampedValue,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: activeColor ?? CupertinoTheme.of(context).primaryColor,
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

const Color _fluentAccentColor = Color(0xFFFF2E55);

class SettingsSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final String Function(double value) displayTextBuilder;
  final double min;
  final double max;
  final double? step;

  const SettingsSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.displayTextBuilder,
    this.min = 0.0,
    this.max = 1.0,
    this.step,
  });

  @override
  State<SettingsSlider> createState() => _SettingsSliderState();
}

class _SettingsSliderState extends State<SettingsSlider> {
  int? _calculateDivisions() {
    if (widget.step == null || widget.step! <= 0) {
      return null;
    }
    final total = (widget.max - widget.min) / widget.step!;
    final divisions = total.round();
    return divisions > 0 ? divisions : null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final divisions = _calculateDivisions();
    final accentColor = fluent.AccentColor.swatch({
      'normal': _fluentAccentColor,
      'default': _fluentAccentColor,
    });
    final displayText = widget.displayTextBuilder(widget.value);
    final labelStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: 14,
    );
    final valueStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 13,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: widget.label,
            style: labelStyle,
            children: [
              TextSpan(
                text: '  $displayText',
                style: valueStyle,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        fluent.FluentTheme(
          data: fluent.FluentThemeData(
            brightness: Theme.of(context).brightness,
            accentColor: accentColor,
          ),
          child: SizedBox(
            child: fluent.Slider(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: divisions,
              onChanged: widget.onChanged,
              label: displayText,
            ),
          ),
        ),
      ],
    );
  }
}

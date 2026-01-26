import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

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
  final GlobalKey _sliderKey = GlobalKey();
  OverlayEntry? _overlayEntry;

  double _progressForValue(double value) {
    return ((value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);
  }

  int? _calculateDivisions() {
    if (widget.step == null || widget.step! <= 0) {
      return null;
    }
    final total = (widget.max - widget.min) / widget.step!;
    final divisions = total.round();
    return divisions > 0 ? divisions : null;
  }

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay(BuildContext context, double value) {
    _removeOverlay();
    final RenderBox? sliderBox =
        _sliderKey.currentContext?.findRenderObject() as RenderBox?;
    if (sliderBox == null) return;
    final position = sliderBox.localToGlobal(Offset.zero);
    final size = sliderBox.size;
    final progress = _progressForValue(value);
    final bubbleX = position.dx + (progress * size.width) - 20;
    final bubbleY = position.dy - 40;
    final blurEnabled =
        context.read<AppearanceSettingsProvider>().enableWidgetBlurEffect;
    _overlayEntry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned(
              left: bubbleX,
              top: bubbleY,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: blurEnabled ? 10 : 0,
                    sigmaY: blurEnabled ? 10 : 0,
                  ),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 0.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      widget.displayTextBuilder(value),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final divisions = _calculateDivisions();
    final accentColor = fluent.AccentColor.swatch({
      'normal': _fluentAccentColor,
      'default': _fluentAccentColor,
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        fluent.FluentTheme(
          data: fluent.FluentThemeData(
            brightness: Theme.of(context).brightness,
            accentColor: accentColor,
          ),
          child: SizedBox(
            key: _sliderKey,
            child: fluent.Slider(
              value: widget.value,
              min: widget.min,
              max: widget.max,
              divisions: divisions,
              onChanged: (value) {
                widget.onChanged(value);
                if (_overlayEntry != null) {
                  _showOverlay(context, value);
                }
              },
              onChangeStart: (value) => _showOverlay(context, value),
              onChangeEnd: (_) => _removeOverlay(),
              label: widget.displayTextBuilder(widget.value),
            ),
          ),
        ),
      ],
    );
  }
}

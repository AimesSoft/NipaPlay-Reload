import 'package:flutter/cupertino.dart';

class CupertinoPlayerSlider extends StatefulWidget {
  const CupertinoPlayerSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  }) : assert(max >= min);

  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  @override
  State<CupertinoPlayerSlider> createState() => _CupertinoPlayerSliderState();
}

class _CupertinoPlayerSliderState extends State<CupertinoPlayerSlider> {
  static const double _thumbRestSize = 14;
  static const double _thumbActiveSize = 18;
  static const double _trackHeight = 4;

  late double _localValue;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _localValue = _clampValue(widget.value);
  }

  @override
  void didUpdateWidget(CupertinoPlayerSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging || widget.value != oldWidget.value) {
      _localValue = _clampValue(widget.value);
    }
  }

  double get _range => (widget.max - widget.min).abs();

  double get _progress {
    if (_range == 0) return 0;
    return ((_localValue - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);
  }

  double _clampValue(double input) {
    if (widget.max == widget.min) return widget.min;
    return input.clamp(widget.min, widget.max);
  }

  void _setDragging(bool dragging) {
    if (_isDragging == dragging) return;
    setState(() {
      _isDragging = dragging;
    });
  }

  void _updateValueFromProgress(double progress) {
    final double normalized = progress.clamp(0.0, 1.0);
    double newValue = widget.min + (widget.max - widget.min) * normalized;
    if (widget.divisions != null &&
        widget.divisions! > 0 &&
        widget.max != widget.min) {
      final double step = (widget.max - widget.min) / widget.divisions!;
      final double steps =
          ((newValue - widget.min) / step).round().toDouble();
      newValue = widget.min + steps * step;
    }
    newValue = _clampValue(newValue);
    setState(() {
      _localValue = newValue;
    });
    widget.onChanged(newValue);
  }

  double _progressFromDx(double dx, double width) {
    if (width <= 0) return 0.0;
    return (dx / width).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final Color activeColor =
        widget.activeColor ?? CupertinoTheme.of(context).primaryColor;
    final Color inactiveColor = widget.inactiveColor ??
        CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey3,
          context,
        );
    final Color thumbColor = widget.thumbColor ??
        CupertinoDynamicColor.resolve(CupertinoColors.white, context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 0;
        if (width <= 0) {
          return const SizedBox(height: 32);
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _setDragging(true);
            _updateValueFromProgress(
              _progressFromDx(details.localPosition.dx, width),
            );
          },
          onHorizontalDragUpdate: (details) {
            _updateValueFromProgress(
              _progressFromDx(details.localPosition.dx, width),
            );
          },
          onHorizontalDragEnd: (_) {
            _setDragging(false);
          },
          onTapDown: (details) {
            _setDragging(true);
            _updateValueFromProgress(
              _progressFromDx(details.localPosition.dx, width),
            );
          },
          onTapUp: (_) {
            _setDragging(false);
          },
          onTapCancel: () => _setDragging(false),
          child: SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.centerLeft,
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    color: inactiveColor.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(_trackHeight / 2),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: _progress,
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: _trackHeight,
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(_trackHeight / 2),
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: 0.2,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (width - _thumbSize).clamp(0.0, double.infinity) *
                      _progress,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOut,
                    width: _thumbSize,
                    height: _thumbSize,
                    decoration: BoxDecoration(
                      color: thumbColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: CupertinoColors.black.withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double get _thumbSize => _isDragging ? _thumbActiveSize : _thumbRestSize;
}

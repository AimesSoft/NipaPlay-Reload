import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/services/large_screen_ui_sfx_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:provider/provider.dart';

class NipaplayLargeScreenEditableSlider extends StatefulWidget {
  const NipaplayLargeScreenEditableSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
    this.label,
    this.onChangeStart,
    this.onChangeEnd,
    this.focusNode,
    this.autofocus = false,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<NipaplayLargeScreenEditableSlider> createState() =>
      _NipaplayLargeScreenEditableSliderState();
}

class _NipaplayLargeScreenEditableSliderState
    extends State<NipaplayLargeScreenEditableSlider> {
  bool _hasFocus = false;

  bool get _canEdit {
    return widget.onChanged != null && widget.max > widget.min;
  }

  double get _step {
    final divisions = widget.divisions;
    if (divisions != null && divisions > 0) {
      return (widget.max - widget.min) / divisions;
    }
    return (widget.max - widget.min) / 20;
  }

  void _adjustValue(bool increase) {
    if (!_canEdit) {
      return;
    }
    final step = _step;
    if (step <= 0) {
      return;
    }
    final nextValue = (widget.value + (increase ? step : -step))
        .clamp(widget.min, widget.max)
        .toDouble();
    // 仅在大屏幕模式下播放滑动条音效，每次步进播放一次以产生刻度感。
    if (NipaplayLargeScreenModeScope.isActiveOf(context)) {
      context.read<LargeScreenUiSfxService>().playSliderChange();
    }
    widget.onChangeStart?.call(widget.value);
    widget.onChanged?.call(nextValue);
    widget.onChangeEnd?.call(nextValue);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isActivate = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;

    if (isLeft) {
      _adjustValue(false);
      return KeyEventResult.handled;
    }
    if (isRight) {
      _adjustValue(true);
      return KeyEventResult.handled;
    }
    if (isActivate) {
      return KeyEventResult.handled;
    }

    // Up and down deliberately bubble to the owning two-column panel, which
    // moves focus to the previous or next control. Left and right never bubble
    // while this slider owns focus, so they cannot accidentally return to tabs.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreenModeActive =
        NipaplayLargeScreenModeScope.isActiveOf(context);
    final normalizedValue =
        widget.value.clamp(widget.min, widget.max).toDouble();
    final materialTheme = Theme.of(context);
    final accent = AppAccentColors.current;
    final inactiveTrackColor = materialTheme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.28)
        : Colors.black.withValues(alpha: 0.24);
    final disabledTrackColor = materialTheme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);
    final sliderStyle = fluent.SliderThemeData(
      margin: EdgeInsets.zero,
      useThumbBall: true,
      trackHeight: const WidgetStatePropertyAll<double>(4),
      thumbRadius: const WidgetStatePropertyAll<double>(10),
      thumbBallInnerFactor: const WidgetStatePropertyAll<double>(0.52),
      activeColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.disabled)
            ? accent.withValues(alpha: 0.34)
            : accent;
      }),
      inactiveColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.disabled)
            ? disabledTrackColor
            : inactiveTrackColor;
      }),
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.disabled)
            ? accent.withValues(alpha: 0.45)
            : accent;
      }),
      labelBackgroundColor: materialTheme.colorScheme.surface,
      labelForegroundColor: materialTheme.colorScheme.onSurface,
    );
    final slider = fluent.FluentTheme(
      data: fluent.FluentThemeData(
        brightness: materialTheme.brightness,
        accentColor: fluent.AccentColor.swatch({
          'normal': accent,
          'default': accent,
        }),
      ),
      child: fluent.Slider(
        value: normalizedValue,
        min: widget.min,
        max: widget.max,
        divisions: widget.divisions,
        onChangeStart: widget.onChangeStart,
        onChangeEnd: widget.onChangeEnd,
        onChanged: widget.onChanged,
        label: widget.label,
        style: sliderStyle,
      ),
    );

    if (!isLargeScreenModeActive) {
      return slider;
    }

    final colorScheme = materialTheme.colorScheme;
    final borderColor = _hasFocus
        ? AppAccentColors.current
        : colorScheme.onSurface.withValues(alpha: 0.12);

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (focused) {
        if (_hasFocus == focused) return;
        setState(() => _hasFocus = focused);
      },
      onKeyEvent: _handleKeyEvent,
      descendantsAreFocusable: false,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: _hasFocus ? 2 : 1.2),
        ),
        child: slider,
      ),
    );
  }
}

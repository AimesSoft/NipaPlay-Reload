import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';

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
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

  static int _editingCount = 0;

  static bool get isAnyEditing => _editingCount > 0;

  @override
  State<NipaplayLargeScreenEditableSlider> createState() =>
      _NipaplayLargeScreenEditableSliderState();
}

class _NipaplayLargeScreenEditableSliderState
    extends State<NipaplayLargeScreenEditableSlider> {
  bool _isEditing = false;
  bool _hasFocus = false;
  double? _editingStartValue;

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

  void _beginEditing() {
    if (!_canEdit || _isEditing) {
      return;
    }
    widget.onChangeStart?.call(widget.value);
    setState(() {
      _setEditingState(true);
      _editingStartValue = widget.value;
    });
  }

  void _cancelEditing() {
    if (!_isEditing) {
      return;
    }
    final startValue = _editingStartValue;
    if (startValue != null && widget.onChanged != null) {
      widget.onChanged!(startValue.clamp(widget.min, widget.max).toDouble());
    }
    widget.onChangeEnd?.call(startValue ?? widget.value);
    setState(() {
      _setEditingState(false);
      _editingStartValue = null;
    });
  }

  void _setEditingState(bool value) {
    if (_isEditing == value) {
      return;
    }
    _isEditing = value;
    if (value) {
      NipaplayLargeScreenEditableSlider._editingCount++;
    } else if (NipaplayLargeScreenEditableSlider._editingCount > 0) {
      NipaplayLargeScreenEditableSlider._editingCount--;
    }
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
    widget.onChanged?.call(nextValue);
  }

  @override
  void dispose() {
    if (_isEditing && NipaplayLargeScreenEditableSlider._editingCount > 0) {
      NipaplayLargeScreenEditableSlider._editingCount--;
    }
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;
    final isEnter = key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.gameButtonA;
    final isEscape = key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack ||
        key == LogicalKeyboardKey.gameButtonB;
    final isLeft = key == LogicalKeyboardKey.arrowLeft;
    final isRight = key == LogicalKeyboardKey.arrowRight;
    final isUp = key == LogicalKeyboardKey.arrowUp;
    final isDown = key == LogicalKeyboardKey.arrowDown;

    if (!_isEditing) {
      if (isEnter) {
        _beginEditing();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (isEscape) {
      _cancelEditing();
      return KeyEventResult.handled;
    }

    if (isLeft || isDown) {
      _adjustValue(false);
      return KeyEventResult.handled;
    }

    if (isRight || isUp) {
      _adjustValue(true);
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isLargeScreenModeActive =
        NipaplayLargeScreenModeScope.isActiveOf(context);
    final normalizedValue = widget.value.clamp(widget.min, widget.max).toDouble();
    final slider = fluent.Slider(
      value: normalizedValue,
      min: widget.min,
      max: widget.max,
      divisions: widget.divisions,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
      onChanged: widget.onChanged,
      label: widget.label,
    );

    if (!isLargeScreenModeActive) {
      return slider;
    }

    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = _isEditing
        ? const Color(0xFFFF2E55)
        : (_hasFocus ? colorScheme.onSurface.withValues(alpha: 0.5) : Colors.transparent);

    return Actions(
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            _beginEditing();
            return null;
          },
        ),
      },
      child: Focus(
        onFocusChange: (focused) {
          if (_hasFocus == focused) {
            return;
          }
          setState(() {
            _hasFocus = focused;
            if (!focused) {
              _setEditingState(false);
              _editingStartValue = null;
            }
          });
        },
        onKeyEvent: _handleKeyEvent,
        descendantsAreFocusable: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: slider,
        ),
      ),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive radio button that renders platform-specific radio styles
///
/// On iOS: Uses custom iOS-style radio with Cupertino design
/// On Android: Uses Material Design Radio
///
/// Example:
/// ```dart
/// enum Options { option1, option2, option3 }
/// Options? _selectedOption = Options.option1;
///
/// AdaptiveRadio<Options>(
///   value: Options.option1,
///   groupValue: _selectedOption,
///   onChanged: (Options? value) {
///     setState(() {
///       _selectedOption = value;
///     });
///   },
/// )
/// ```
class AdaptiveRadio<T> extends StatelessWidget {
  /// Creates an adaptive radio button
  const AdaptiveRadio({
    super.key,
    required this.value,
    required this.groupValue,
    required this.onChanged,
    this.activeColor,
    this.focusColor,
    this.hoverColor,
    this.toggleable = false,
  });

  /// The value represented by this radio button
  final T value;

  /// The currently selected value for a group of radio buttons
  ///
  /// This radio button is considered selected if its [value] matches the [groupValue]
  final T? groupValue;

  /// Called when the user selects this radio button
  ///
  /// The radio button passes [value] as a parameter to this callback
  /// If [toggleable] is true, this will be called with null when tapping on a selected radio
  final ValueChanged<T?>? onChanged;

  /// The color to use when this radio button is selected
  ///
  /// On iOS: Uses the color for the radio button when selected
  /// On Android: Uses the color for the radio button
  final Color? activeColor;

  /// The color for the radio's Material when it has the input focus
  final Color? focusColor;

  /// The color for the radio's Material when a pointer is hovering over it
  final Color? hoverColor;

  /// Set to true if this radio button is allowed to be returned to an indeterminate state by selecting it again when selected
  ///
  /// To indicate returning to an indeterminate state, [onChanged] will be called with null
  final bool toggleable;

  @override
  Widget build(BuildContext context) {
    // iOS - Use custom iOS-style radio
    if (PlatformInfo.isIOS) {
      return _IOSRadio<T>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: activeColor ?? CupertinoColors.systemBlue,
        toggleable: toggleable,
      );
    }

    // Android - Use Material Design Radio
    if (PlatformInfo.isAndroid) {
      // ignore: deprecated_member_use
      return Radio<T>(
        value: value,
        // ignore: deprecated_member_use
        groupValue: groupValue,
        // ignore: deprecated_member_use
        onChanged: onChanged,
        activeColor: activeColor,
        focusColor: focusColor,
        hoverColor: hoverColor,
        toggleable: toggleable,
      );
    }

    // Fallback for other platforms (web, desktop, etc.)
    // ignore: deprecated_member_use
    return Radio<T>(
      value: value,
      // ignore: deprecated_member_use
      groupValue: groupValue,
      // ignore: deprecated_member_use
      onChanged: onChanged,
      activeColor: activeColor,
      focusColor: focusColor,
      hoverColor: hoverColor,
      toggleable: toggleable,
    );
  }
}

/// iOS-style radio widget
class _IOSRadio<T> extends StatelessWidget {
  const _IOSRadio({
    required this.value,
    required this.groupValue,
    required this.onChanged,
    required this.activeColor,
    required this.toggleable,
  });

  final T value;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final Color activeColor;
  final bool toggleable;

  bool get _selected => value == groupValue;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return GestureDetector(
      onTap: onChanged == null
          ? null
          : () {
              if (toggleable && _selected) {
                onChanged!(null);
              } else if (!_selected) {
                onChanged!(value);
              }
            },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _selected
              ? activeColor
              : (isDark
                    ? CupertinoColors.systemGrey5.darkColor
                    : CupertinoColors.white),
          border: Border.all(
            color: _selected
                ? activeColor
                : (isDark
                      ? CupertinoColors.systemGrey3
                      : CupertinoColors.systemGrey4),
            width: _selected ? 6 : 1.5,
          ),
        ),
      ),
    );
  }
}

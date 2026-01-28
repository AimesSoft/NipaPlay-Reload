import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// An adaptive checkbox that renders platform-specific checkbox styles
///
/// On iOS: Uses custom iOS-style checkbox with Cupertino design
/// On Android: Uses Material Design Checkbox
///
/// Example:
/// ```dart
/// bool _value = false;
///
/// AdaptiveCheckbox(
///   value: _value,
///   onChanged: (bool? newValue) {
///     setState(() {
///       _value = newValue ?? false;
///     });
///   },
/// )
/// ```
class AdaptiveCheckbox extends StatelessWidget {
  /// Creates an adaptive checkbox
  const AdaptiveCheckbox({
    super.key,
    required this.value,
    this.tristate = false,
    required this.onChanged,
    this.activeColor,
    this.checkColor,
    this.focusColor,
    this.hoverColor,
  });

  /// Whether this checkbox is checked
  ///
  /// When [tristate] is true, a value of null corresponds to the mixed state
  final bool? value;

  /// If true, the checkbox's value can be true, false, or null
  ///
  /// When tristate is false, the checkbox value must not be null
  final bool tristate;

  /// Called when the value of the checkbox should change
  ///
  /// The checkbox passes the new value to the callback but does not actually
  /// change state until the parent widget rebuilds the checkbox with the new
  /// value.
  ///
  /// If null, the checkbox will be displayed as disabled.
  final ValueChanged<bool?>? onChanged;

  /// The color to use when this checkbox is checked
  ///
  /// On iOS: Uses the color for the checkbox background when checked
  /// On Android: Uses the color for the checkbox
  final Color? activeColor;

  /// The color to use for the check icon when this checkbox is checked
  ///
  /// On iOS: The color of the checkmark
  /// On Android: The color of the checkmark
  final Color? checkColor;

  /// The color for the checkbox's Material when it has the input focus
  final Color? focusColor;

  /// The color for the checkbox's Material when a pointer is hovering over it
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    // iOS - Use custom iOS-style checkbox
    if (PlatformInfo.isIOS) {
      return _IOSCheckbox(
        value: value,
        tristate: tristate,
        onChanged: onChanged,
        activeColor: activeColor ?? CupertinoColors.systemBlue,
        checkColor: checkColor ?? CupertinoColors.white,
      );
    }

    // Android - Use Material Design Checkbox
    if (PlatformInfo.isAndroid) {
      return Checkbox(
        value: value,
        tristate: tristate,
        onChanged: onChanged,
        activeColor: activeColor,
        checkColor: checkColor,
        focusColor: focusColor,
        hoverColor: hoverColor,
      );
    }

    // Fallback for other platforms (web, desktop, etc.)
    return Checkbox(
      value: value,
      tristate: tristate,
      onChanged: onChanged,
      activeColor: activeColor,
      checkColor: checkColor,
      focusColor: focusColor,
      hoverColor: hoverColor,
    );
  }
}

/// iOS-style checkbox widget for iOS 18 and below
class _IOSCheckbox extends StatelessWidget {
  const _IOSCheckbox({
    required this.value,
    required this.tristate,
    required this.onChanged,
    required this.activeColor,
    required this.checkColor,
  });

  final bool? value;
  final bool tristate;
  final ValueChanged<bool?>? onChanged;
  final Color activeColor;
  final Color checkColor;

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;

    return GestureDetector(
      onTap: onChanged == null
          ? null
          : () {
              if (tristate) {
                // Cycle: false -> true -> null -> false
                if (value == false) {
                  onChanged!(true);
                } else if (value == true) {
                  onChanged!(null);
                } else {
                  onChanged!(false);
                }
              } else {
                onChanged!(!(value ?? false));
              }
            },
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: value == true
              ? activeColor
              : (isDark
                    ? CupertinoColors.systemGrey5.darkColor
                    : CupertinoColors.white),
          border: Border.all(
            color: value == true
                ? activeColor
                : (isDark
                      ? CupertinoColors.systemGrey3
                      : CupertinoColors.systemGrey4),
            width: value == true ? 0 : 1.5,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        child: value == true
            ? Icon(CupertinoIcons.checkmark, size: 14, color: checkColor)
            : value == null
            ? Center(
                child: Container(
                  width: 8,
                  height: 2,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

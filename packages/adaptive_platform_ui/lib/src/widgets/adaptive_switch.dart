import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import 'ios26/ios26_switch.dart';

/// An adaptive switch that renders platform-specific switch styles
///
/// On iOS 26+: Uses native iOS 26 UISwitch with native animations
/// On iOS <26 (iOS 18 and below): Uses CupertinoSwitch with traditional iOS styling
/// On Android: Uses Material Design Switch
///
/// Example:
/// ```dart
/// bool _value = false;
///
/// AdaptiveSwitch(
///   value: _value,
///   onChanged: (bool newValue) {
///     setState(() {
///       _value = newValue;
///     });
///   },
/// )
/// ```
class AdaptiveSwitch extends StatelessWidget {
  /// Creates an adaptive switch
  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  /// Whether this switch is on or off
  final bool value;

  /// Called when the user toggles the switch on or off
  ///
  /// The switch passes the new value to the callback but does not actually
  /// change state until the parent widget rebuilds the switch with the new
  /// value.
  ///
  /// If null, the switch will be displayed as disabled.
  final ValueChanged<bool>? onChanged;

  /// The color to use when this switch is on
  ///
  /// On iOS: Uses the color for the track when on
  /// On Android: Uses the color for the track
  final Color? activeColor;

  /// The color of the thumb (handle)
  ///
  /// On iOS: The color of the circular knob
  /// On Android: The color of the circular knob
  final Color? thumbColor;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ - Use native iOS 26 switch
    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26Switch(
        value: value,
        onChanged: onChanged,
        activeColor: activeColor,
        thumbColor: thumbColor,
      );
    }

    // iOS 18 and below - Use traditional CupertinoSwitch
    if (PlatformInfo.isIOS) {
      return CupertinoSwitch(
        value: value,
        onChanged: onChanged,
        activeTrackColor: activeColor,
        thumbColor: thumbColor ?? CupertinoColors.white,
      );
    }

    // Android - Use Material Design Switch
    if (PlatformInfo.isAndroid) {
      return Switch(
        value: value,
        onChanged: onChanged,
        thumbColor: thumbColor != null
            ? WidgetStateProperty.all(thumbColor)
            : null,
        trackColor: activeColor != null
            ? WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return activeColor;
                }
                return null;
              })
            : null,
      );
    }

    // Fallback for other platforms (web, desktop, etc.)
    return Switch(
      value: value,
      onChanged: onChanged,
      thumbColor: thumbColor != null
          ? WidgetStateProperty.all(thumbColor)
          : null,
      trackColor: activeColor != null
          ? WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return activeColor;
              }
              return null;
            })
          : null,
    );
  }
}

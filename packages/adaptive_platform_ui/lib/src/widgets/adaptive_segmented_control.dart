import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';
import 'ios26/ios26_segmented_control.dart';

/// An adaptive segmented control that renders platform-specific styles
///
/// On iOS 26+: Uses native iOS 26 UISegmentedControl with Liquid Glass
/// On iOS <26 (iOS 18 and below): Uses CupertinoSlidingSegmentedControl
/// On Android: Uses Material SegmentedButton
class AdaptiveSegmentedControl extends StatelessWidget {
  /// Creates an adaptive segmented control
  const AdaptiveSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 36.0,
    this.shrinkWrap = false,
    this.sfSymbols,
    this.iconSize,
    this.iconColor,
  });

  /// Segment labels to display, in order
  final List<String> labels;

  /// The index of the selected segment
  final int selectedIndex;

  /// Called when the user selects a segment
  final ValueChanged<int> onValueChanged;

  /// Whether the control is interactive
  final bool enabled;

  /// Tint color for the selected segment
  final Color? color;

  /// Height of the control
  final double height;

  /// Whether the control should shrink to fit content
  final bool shrinkWrap;

  /// Optional SF Symbol names or IconData
  final List<dynamic>? sfSymbols;

  /// Icon size
  final double? iconSize;

  /// Icon color
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    // iOS 26+ - Use native iOS 26 segmented control
    if (PlatformInfo.isIOS26OrHigher()) {
      return IOS26SegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: onValueChanged,
        enabled: enabled,
        color: color,
        height: height,
        shrinkWrap: shrinkWrap,
        icons: sfSymbols,
        iconSize: iconSize,
        iconColor: iconColor,
      );
    }

    // iOS <26 (iOS 18 and below) - Use CupertinoSlidingSegmentedControl
    if (PlatformInfo.isIOS) {
      return _buildCupertinoSegmentedControl(context);
    }

    // Android - Use Material SegmentedButton
    if (PlatformInfo.isAndroid) {
      return _buildMaterialSegmentedButton(context);
    }

    // Fallback
    return _buildCupertinoSegmentedControl(context);
  }

  Widget _buildCupertinoSegmentedControl(BuildContext context) {
    // Build children map from labels or icons
    final Map<int, Widget> children = {};

    // Check if using icons
    final useIcons = sfSymbols != null && sfSymbols!.isNotEmpty;
    final itemCount = useIcons ? sfSymbols!.length : labels.length;

    for (int i = 0; i < itemCount; i++) {
      if (useIcons) {
        // Icon mode
        final dynamic icon = sfSymbols![i];
        children[i] = Padding(
          padding: const EdgeInsets.all(8),
          child: icon is IconData
              ? Icon(icon, size: iconSize ?? 20, color: iconColor)
              : Text(icon.toString()),
        );
      } else {
        // Text mode
        children[i] = Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            labels[i],
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        );
      }
    }

    Widget control = CupertinoSlidingSegmentedControl<int>(
      children: children,
      groupValue: selectedIndex,
      onValueChanged: (int? value) {
        if (enabled && value != null) {
          onValueChanged(value);
        }
      },
    );

    if (shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return SizedBox(height: height, child: control);
  }

  Widget _buildMaterialSegmentedButton(BuildContext context) {
    final segments = <ButtonSegment<int>>[];

    // Check if using icons
    final useIcons = sfSymbols != null && sfSymbols!.isNotEmpty;
    final itemCount = useIcons ? sfSymbols!.length : labels.length;

    for (int i = 0; i < itemCount; i++) {
      if (useIcons) {
        // Icon mode
        final dynamic icon = sfSymbols![i];
        segments.add(
          ButtonSegment<int>(
            value: i,
            icon: icon is IconData
                ? Icon(icon, size: iconSize ?? 20, color: iconColor)
                : Icon(Icons.circle, size: iconSize ?? 20, color: iconColor),
          ),
        );
      } else {
        // Text mode
        segments.add(
          ButtonSegment<int>(
            value: i,
            label: Text(
              labels[i],
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
          ),
        );
      }
    }

    Widget control = SegmentedButton<int>(
      segments: segments,
      selected: {selectedIndex},
      onSelectionChanged: enabled
          ? (Set<int> newSelection) {
              if (newSelection.isNotEmpty) {
                onValueChanged(newSelection.first);
              }
            }
          : null,
      style: SegmentedButton.styleFrom(
        minimumSize: Size.fromHeight(height),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      ),
    );

    if (shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return control;
  }
}

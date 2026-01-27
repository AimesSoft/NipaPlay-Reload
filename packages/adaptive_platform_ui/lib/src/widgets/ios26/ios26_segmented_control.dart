import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Native iOS 26 segmented control implementation using platform views
class IOS26SegmentedControl extends StatefulWidget {
  const IOS26SegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
    this.enabled = true,
    this.color,
    this.height = 32.0,
    this.shrinkWrap = false,
    this.icons,
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

  /// Optional SF Symbol names for icons (iOS only)
  final List<dynamic>? icons;

  /// Icon size (when using icons)
  final double? iconSize;

  /// Icon color (when using icons)
  final Color? iconColor;

  @override
  State<IOS26SegmentedControl> createState() => _IOS26SegmentedControlState();
}

class _IOS26SegmentedControlState extends State<IOS26SegmentedControl> {
  static int _nextId = 0;
  late final int _id;
  late final MethodChannel _channel;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel(
      'adaptive_platform_ui/ios26_segmented_control_$_id',
    );
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    if (call.method == 'valueChanged') {
      final index = call.arguments['index'] as int;
      final itemCount = (widget.icons != null && widget.icons!.isNotEmpty)
          ? widget.icons!.length
          : widget.labels.length;

      if (index >= 0 && index < itemCount && widget.enabled) {
        widget.onValueChanged(index);
      }
    }
  }

  @override
  void didUpdateWidget(IOS26SegmentedControl oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _channel.invokeMethod('setSelectedIndex', {
        'index': widget.selectedIndex,
      });
    }
  }

  int _colorToARGB(Color color) {
    return ((color.a * 255.0).round() & 0xff) << 24 |
        ((color.r * 255.0).round() & 0xff) << 16 |
        ((color.g * 255.0).round() & 0xff) << 8 |
        ((color.b * 255.0).round() & 0xff);
  }

  Map<String, dynamic> _buildCreationParams() {
    final bool isDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    final params = <String, dynamic>{
      'id': _id,
      'labels': widget.labels,
      'selectedIndex': widget.selectedIndex,
      'enabled': widget.enabled,
      'isDark': isDark,
    };

    // Add SF symbols if provided
    if (widget.icons != null && widget.icons!.isNotEmpty) {
      params['sfSymbols'] = widget.icons!;
    }

    // Add color if provided
    if (widget.color != null) {
      params['tintColor'] = _colorToARGB(widget.color!);
    }

    // Add icon size if provided
    if (widget.iconSize != null) {
      params['iconSize'] = widget.iconSize!;
    }

    // Add icon color if provided
    if (widget.iconColor != null) {
      params['iconColor'] = _colorToARGB(widget.iconColor!);
    }

    return params;
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      Widget control = UiKitView(
        viewType: 'adaptive_platform_ui/ios26_segmented_control',
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
          Factory<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(),
          ),
          Factory<PanGestureRecognizer>(() => PanGestureRecognizer()),
        },
      );

      // Wrap in SizedBox for height
      control = SizedBox(height: widget.height, child: control);

      // Center if shrinkWrap is true (but don't use IntrinsicWidth with UiKitView)
      if (widget.shrinkWrap) {
        control = Center(child: control);
      }

      return control;
    }

    // Fallback for non-iOS (should not reach here in normal usage)
    final Map<int, Widget> children = {};
    for (int i = 0; i < widget.labels.length; i++) {
      children[i] = Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          widget.labels[i],
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      );
    }

    Widget control = CupertinoSegmentedControl<int>(
      children: children,
      groupValue: widget.selectedIndex,
      onValueChanged: widget.enabled ? widget.onValueChanged : (_) {},
    );

    if (widget.shrinkWrap) {
      control = Center(child: IntrinsicWidth(child: control));
    }

    return SizedBox(height: widget.height, child: control);
  }
}

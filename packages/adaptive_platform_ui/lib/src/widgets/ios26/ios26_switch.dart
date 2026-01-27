import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

/// Native iOS 26 switch implementation using platform views
///
/// This switch uses UIKit platform views to render native iOS 26 UISwitch
/// designs. It communicates with the native iOS side via platform channels.
///
/// Features:
/// - Native iOS 26 switch animations
/// - Haptic feedback
/// - Native gesture handling
/// - Automatic light/dark mode support
class IOS26Switch extends StatefulWidget {
  /// Creates an iOS 26 style switch
  const IOS26Switch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.thumbColor,
  });

  /// Whether this switch is on or off
  final bool value;

  /// Called when the user toggles the switch on or off
  final ValueChanged<bool>? onChanged;

  /// The color to use when this switch is on
  final Color? activeColor;

  /// The color of the thumb (handle)
  final Color? thumbColor;

  @override
  State<IOS26Switch> createState() => _IOS26SwitchState();
}

class _IOS26SwitchState extends State<IOS26Switch> {
  static int _nextId = 0;
  late final int _id;
  late final MethodChannel _channel;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel('adaptive_platform_ui/ios26_switch_$_id');
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'valueChanged':
        final value = call.arguments['value'] as bool;
        if (widget.onChanged != null) {
          widget.onChanged!(value);
        }
        break;
    }
  }

  @override
  void didUpdateWidget(IOS26Switch oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update native side if properties changed
    if (oldWidget.value != widget.value) {
      _channel.invokeMethod('setValue', {'value': widget.value});
    }

    if (oldWidget.activeColor != widget.activeColor &&
        widget.activeColor != null) {
      _channel.invokeMethod('setActiveColor', {
        'color': _colorToARGB(widget.activeColor!),
      });
    }

    if (oldWidget.thumbColor != widget.thumbColor &&
        widget.thumbColor != null) {
      _channel.invokeMethod('setThumbColor', {
        'color': _colorToARGB(widget.thumbColor!),
      });
    }

    // Update enabled state
    if ((oldWidget.onChanged == null) != (widget.onChanged == null)) {
      _channel.invokeMethod('setEnabled', {
        'enabled': widget.onChanged != null,
      });
    }
  }

  Map<String, dynamic> _buildCreationParams() {
    return {
      'id': _id,
      'value': widget.value,
      'enabled': widget.onChanged != null,
      if (widget.activeColor != null)
        'activeColor': _colorToARGB(widget.activeColor!),
      if (widget.thumbColor != null)
        'thumbColor': _colorToARGB(widget.thumbColor!),
      'isDark': MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
  }

  int _colorToARGB(Color color) {
    return (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
  }

  @override
  Widget build(BuildContext context) {
    // Only use native implementation on iOS
    if (!kIsWeb && Platform.isIOS) {
      final platformView = UiKitView(
        viewType: 'adaptive_platform_ui/ios26_switch',
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<HorizontalDragGestureRecognizer>(
            () => HorizontalDragGestureRecognizer(),
          ),
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
        },
      );

      return SizedBox(
        width: 51, // Standard iOS switch width
        height: 31, // Standard iOS switch height
        child: platformView,
      );
    }

    // Fallback to CupertinoSwitch on other platforms
    return CupertinoSwitch(
      value: widget.value,
      onChanged: widget.onChanged,
      activeTrackColor: widget.activeColor,
      thumbColor: widget.thumbColor ?? CupertinoColors.white,
    );
  }
}

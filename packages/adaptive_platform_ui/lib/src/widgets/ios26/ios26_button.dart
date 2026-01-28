import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../../style/sf_symbol.dart';

/// iOS 26 native button styles (Liquid Glass design)
enum IOS26ButtonStyle {
  /// Filled button with solid background (primary action)
  filled,

  /// Tinted button with translucent background
  tinted,

  /// Gray button with subtle background
  gray,

  /// Bordered button with outline
  bordered,

  /// Plain text button without background
  plain,

  /// Glass effect button with translucent blur
  glass,

  /// Prominent glass button with enhanced blur effect
  prominentGlass,
}

/// iOS 26 button size presets matching native design
enum IOS26ButtonSize {
  /// Small button (height: 28)
  small,

  /// Medium button (height: 36) - default
  medium,

  /// Large button (height: 44)
  large,
}

/// Native iOS 26 button implementation using platform views
///
/// This button uses UIKit platform views to render native iOS 26 Liquid Glass
/// designs. It communicates with the native iOS side via platform channels.
///
/// Features:
/// - Native Liquid Glass visual effects
/// - iOS 26 button styles and animations
/// - Haptic feedback
/// - Native gesture handling
/// - Automatic light/dark mode support
///
/// Note: For complex layouts with custom widgets, use the AdaptiveButton.child() constructor
/// which will overlay the widget on top of the native iOS 26 button.
class IOS26Button extends StatefulWidget {
  /// Creates an iOS 26 style button with a text label
  const IOS26Button({
    super.key,
    required this.onPressed,
    required this.label,
    this.style = IOS26ButtonStyle.filled,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.textColor,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
  }) : child = null,
       isChildMode = false,
       sfSymbol = null;

  /// Creates an iOS 26 style button with a custom child widget
  /// The child will be overlaid on top of the native button background
  const IOS26Button.child({
    super.key,
    required this.onPressed,
    required this.child,
    this.style = IOS26ButtonStyle.filled,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
  }) : label = '',
       textColor = null,
       isChildMode = true,
       sfSymbol = null;

  /// Creates an iOS 26 style button with a native SF Symbol icon
  const IOS26Button.sfSymbol({
    super.key,
    required this.onPressed,
    required this.sfSymbol,
    this.style = IOS26ButtonStyle.glass,
    this.size = IOS26ButtonSize.medium,
    this.color,
    this.enabled = true,
    this.padding,
    this.borderRadius,
    this.minSize,
    this.useSmoothRectangleBorder = true,
  }) : label = '',
       textColor = null,
       child = null,
       isChildMode = false;

  /// The callback that is called when the button is tapped
  final VoidCallback? onPressed;

  /// The text label of the button
  final String label;

  /// The custom child widget (used in .child() constructor)
  final Widget? child;

  /// The SF Symbol to display (used in .sfSymbol() constructor)
  final SFSymbol? sfSymbol;

  /// Whether this is child mode
  final bool isChildMode;

  /// The visual style of the button
  final IOS26ButtonStyle style;

  /// The size preset for the button
  final IOS26ButtonSize size;

  /// The color of the button (uses system blue if not specified)
  final Color? color;

  /// The color of the button text
  final Color? textColor;

  /// Whether the button is enabled
  final bool enabled;

  /// The amount of space to surround the child inside the button
  final EdgeInsetsGeometry? padding;

  /// The border radius of the button
  final BorderRadius? borderRadius;

  /// The minimum size of the button
  final Size? minSize;

  /// Whether to use smooth rectangle border (iOS 26+ only)
  /// When false, uses perfectly circular/capsule shape
  /// Default is true for smooth rectangle, set to false for circular
  final bool useSmoothRectangleBorder;

  @override
  State<IOS26Button> createState() => _IOS26ButtonState();
}

class _IOS26ButtonState extends State<IOS26Button> {
  static int _nextId = 0;
  late final int _id;
  late final MethodChannel _channel;

  @override
  void initState() {
    super.initState();
    _id = _nextId++;
    _channel = MethodChannel('adaptive_platform_ui/ios26_button_$_id');
    _channel.setMethodCallHandler(_handleMethod);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleMethod(MethodCall call) async {
    switch (call.method) {
      case 'pressed':
        if (widget.enabled && widget.onPressed != null) {
          widget.onPressed!();
        }
        break;
    }
  }

  @override
  void didUpdateWidget(IOS26Button oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Update native side if properties changed
    if (oldWidget.style != widget.style) {
      _channel.invokeMethod('setStyle', {
        'style': _styleToString(widget.style),
      });
    }

    if (oldWidget.enabled != widget.enabled) {
      _channel.invokeMethod('setEnabled', {
        'enabled': widget.enabled && widget.onPressed != null,
      });
    }

    if (oldWidget.label != widget.label) {
      _channel.invokeMethod('setLabel', {'label': widget.label});
    }

    if (oldWidget.color != widget.color) {
      _channel.invokeMethod('setColor', {
        'color': widget.color != null ? _colorToHex(widget.color!) : null,
      });
    }

    if (oldWidget.useSmoothRectangleBorder != widget.useSmoothRectangleBorder) {
      _channel.invokeMethod('setUseSmoothRectangleBorder', {
        'useSmoothRectangleBorder': widget.useSmoothRectangleBorder,
      });
    }

    // Update SF Symbol if changed
    if (oldWidget.sfSymbol?.name != widget.sfSymbol?.name ||
        oldWidget.sfSymbol?.size != widget.sfSymbol?.size ||
        oldWidget.sfSymbol?.color != widget.sfSymbol?.color) {
      if (widget.sfSymbol != null) {
        _channel.invokeMethod('setIcon', {
          'iconName': widget.sfSymbol!.name,
          'iconSize': widget.sfSymbol!.size,
          if (widget.sfSymbol!.color != null)
            'iconColor': _colorToARGB(widget.sfSymbol!.color!),
        });
      }
    }
  }

  Map<String, dynamic> _buildCreationParams() {
    return {
      'id': _id,
      'label': widget.label,
      'style': _styleToString(widget.style),
      'size': _sizeToString(widget.size),
      'enabled': widget.enabled && widget.onPressed != null,
      'color': widget.color != null ? _colorToHex(widget.color!) : null,
      'textColor': widget.textColor != null
          ? _colorToHex(widget.textColor!)
          : null,
      'isDark': MediaQuery.platformBrightnessOf(context) == Brightness.dark,
      'useSmoothRectangleBorder': widget.useSmoothRectangleBorder,
      if (widget.sfSymbol != null) 'iconName': widget.sfSymbol!.name,
      if (widget.sfSymbol != null) 'iconSize': widget.sfSymbol!.size,
      if (widget.sfSymbol?.color != null)
        'iconColor': _colorToARGB(widget.sfSymbol!.color!),
    };
  }

  String _styleToString(IOS26ButtonStyle style) {
    switch (style) {
      case IOS26ButtonStyle.filled:
        return 'filled';
      case IOS26ButtonStyle.tinted:
        return 'tinted';
      case IOS26ButtonStyle.gray:
        return 'gray';
      case IOS26ButtonStyle.bordered:
        return 'bordered';
      case IOS26ButtonStyle.plain:
        return 'plain';
      case IOS26ButtonStyle.glass:
        return 'glass';
      case IOS26ButtonStyle.prominentGlass:
        return 'prominentGlass';
    }
  }

  String _sizeToString(IOS26ButtonSize size) {
    switch (size) {
      case IOS26ButtonSize.small:
        return 'small';
      case IOS26ButtonSize.medium:
        return 'medium';
      case IOS26ButtonSize.large:
        return 'large';
    }
  }

  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  }

  int _colorToARGB(Color color) {
    return (((color.a * 255.0).round() & 0xFF) << 24) |
        (((color.r * 255.0).round() & 0xFF) << 16) |
        (((color.g * 255.0).round() & 0xFF) << 8) |
        ((color.b * 255.0).round() & 0xFF);
  }

  double get _height {
    switch (widget.size) {
      case IOS26ButtonSize.small:
        return 28.0;
      case IOS26ButtonSize.medium:
        return 36.0;
      case IOS26ButtonSize.large:
        return 44.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only use native implementation on iOS
    if (!kIsWeb && Platform.isIOS) {
      final platformView = UiKitView(
        viewType: 'adaptive_platform_ui/ios26_button',
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
      );

      return SizedBox(
        height: _height,
        child: widget.isChildMode
            ? Stack(
                children: [
                  Positioned.fill(child: platformView),
                  Center(child: IgnorePointer(child: widget.child!)),
                ],
              )
            : platformView,
      );
    }

    // Fallback to CupertinoButton on other platforms
    return _buildFallbackButton();
  }

  Widget _buildFallbackButton() {
    final buttonColor = widget.color ?? CupertinoColors.systemBlue;
    final textStyle = TextStyle(
      color: widget.textColor ?? CupertinoColors.white,
    );

    // If child mode, use the child widget
    final buttonChild = widget.isChildMode
        ? widget.child!
        : Text(widget.label, style: textStyle);

    switch (widget.style) {
      case IOS26ButtonStyle.filled:
        return CupertinoButton.filled(
          onPressed: widget.enabled ? widget.onPressed : null,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: buttonChild,
        );

      case IOS26ButtonStyle.plain:
        return CupertinoButton(
          onPressed: widget.enabled ? widget.onPressed : null,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: widget.isChildMode
              ? widget.child!
              : Text(
                  widget.label,
                  style: TextStyle(color: widget.textColor ?? buttonColor),
                ),
        );

      default:
        return CupertinoButton(
          onPressed: widget.enabled ? widget.onPressed : null,
          color: buttonColor,
          padding:
              widget.padding ?? const EdgeInsets.symmetric(horizontal: 16.0),
          child: buttonChild,
        );
    }
  }
}

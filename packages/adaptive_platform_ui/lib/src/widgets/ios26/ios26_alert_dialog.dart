import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import '../adaptive_alert_dialog.dart';

/// Action types for alert dialog buttons
enum AlertActionStyle {
  /// Default style for standard actions
  defaultAction,

  /// Cancel style for dismissing actions
  cancel,

  /// Destructive style for dangerous actions
  destructive,

  /// Primary style for emphasized actions (bold)
  primary,

  /// Secondary style for less important actions
  secondary,

  /// Success style for positive confirmations
  success,

  /// Warning style for caution actions
  warning,

  /// Info style for informational actions
  info,

  /// Disabled style for non-interactive actions
  disabled,
}

/// A single action in an alert dialog
class AlertAction {
  /// Creates an alert action
  const AlertAction({
    required this.title,
    required this.onPressed,
    this.style = AlertActionStyle.defaultAction,
    this.enabled = true,
  });

  /// The text displayed in the action button
  final String title;

  /// Called when the action is pressed
  final VoidCallback onPressed;

  /// The visual style of the action
  final AlertActionStyle style;

  /// Whether the action can be pressed
  final bool enabled;
}

/// Native iOS 26 alert dialog implementation using platform views
class IOS26AlertDialog extends StatefulWidget {
  /// Creates an iOS 26 alert dialog
  const IOS26AlertDialog({
    super.key,
    required this.title,
    this.message,
    required this.actions,
    this.icon,
    this.iconSize,
    this.iconColor,
    this.oneTimeCode,
    this.input,
  });

  /// The title of the alert dialog
  final String title;

  /// Optional message text for additional context
  final String? message;

  /// List of actions for the alert
  final List<AlertAction> actions;

  /// Optional SF Symbol icon name to display in the alert
  final String? icon;

  /// Optional icon size
  final double? iconSize;

  /// Optional icon color
  final Color? iconColor;

  /// Optional 6-digit one-time code to display
  final String? oneTimeCode;

  /// Optional text input configuration
  final AdaptiveAlertDialogInput? input;

  @override
  State<IOS26AlertDialog> createState() => _IOS26AlertDialogState();
}

class _IOS26AlertDialogState extends State<IOS26AlertDialog> {
  MethodChannel? _channel;
  bool? _lastIsDark;
  int? _lastTint;

  bool get _isDark =>
      MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  Color? get _effectiveTint => CupertinoTheme.of(context).primaryColor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBrightnessIfNeeded();
  }

  @override
  void dispose() {
    _channel?.setMethodCallHandler(null);
    super.dispose();
  }

  int _colorToARGB(Color color) {
    return ((color.a * 255.0).round() & 0xff) << 24 |
        ((color.r * 255.0).round() & 0xff) << 16 |
        ((color.g * 255.0).round() & 0xff) << 8 |
        ((color.b * 255.0).round() & 0xff);
  }

  String _keyboardTypeToString(TextInputType type) {
    if (type == TextInputType.emailAddress) return 'emailAddress';
    if (type == TextInputType.number) return 'number';
    if (type == TextInputType.phone) return 'phone';
    if (type == TextInputType.url) return 'url';
    return 'default';
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb && Platform.isIOS) {
      final creationParams = <String, dynamic>{
        'title': widget.title,
        if (widget.message != null) 'message': widget.message,
        'actionTitles': widget.actions.map((a) => a.title).toList(),
        'actionStyles': widget.actions.map((a) => a.style.name).toList(),
        'actionEnabled': widget.actions.map((a) => a.enabled).toList(),
        if (widget.icon != null) 'iconName': widget.icon,
        if (widget.iconSize != null) 'iconSize': widget.iconSize,
        if (widget.iconColor != null)
          'iconColor': _colorToARGB(widget.iconColor!),
        if (widget.oneTimeCode != null) 'oneTimeCode': widget.oneTimeCode,
        if (widget.input != null) ...{
          'textFieldPlaceholder': widget.input!.placeholder,
          if (widget.input!.initialValue != null)
            'textFieldInitialValue': widget.input!.initialValue,
          'textFieldObscureText': widget.input!.obscureText,
          if (widget.input!.maxLength != null)
            'textFieldMaxLength': widget.input!.maxLength,
          if (widget.input!.keyboardType != null)
            'textFieldKeyboardType': _keyboardTypeToString(
              widget.input!.keyboardType!,
            ),
        },
        'alertStyle': 'glass',
        'isDark': _isDark,
        if (_effectiveTint != null) 'tint': _colorToARGB(_effectiveTint!),
      };

      final platformView = UiKitView(
        viewType: 'adaptive_platform_ui/ios26_alert_dialog',
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<TapGestureRecognizer>(() => TapGestureRecognizer()),
        },
      );

      // Alert dialogs are modal and should fill the screen
      return Container(
        color: const Color(0x42000000), // Semi-transparent overlay
        child: Center(
          child: SizedBox(
            width: 270, // Standard iOS alert width
            height: 200, // Approximate height, will be adjusted by native
            child: platformView,
          ),
        ),
      );
    }

    // Fallback to CupertinoAlertDialog
    return CupertinoAlertDialog(
      title: Text(widget.title),
      content: widget.message != null ? Text(widget.message!) : null,
      actions: widget.actions.map((action) {
        return CupertinoDialogAction(
          onPressed: () {
            Navigator.of(context).pop();
            action.onPressed();
          },
          isDefaultAction: action.style == AlertActionStyle.defaultAction,
          isDestructiveAction: action.style == AlertActionStyle.destructive,
          child: Text(action.title),
        );
      }).toList(),
    );
  }

  void _onCreated(int id) {
    final ch = MethodChannel('adaptive_platform_ui/ios26_alert_dialog_$id');
    _channel = ch;
    ch.setMethodCallHandler(_onMethodCall);
    _lastTint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;
    _lastIsDark = _isDark;
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == 'actionPressed') {
      final args = call.arguments as Map?;
      final idx = (args?['index'] as num?)?.toInt();
      final textFieldValue = args?['textFieldValue'] as String?;

      if (idx != null && idx >= 0 && idx < widget.actions.length) {
        final action = widget.actions[idx];

        // Dismiss the dialog with appropriate value
        if (mounted) {
          if (widget.input != null) {
            // Input dialog
            if (action.style == AlertActionStyle.cancel) {
              // Cancel button returns null for input dialogs
              Navigator.of(context).pop<String?>(null);
            } else {
              // Other buttons return the text field value
              Navigator.of(context).pop<String?>(textFieldValue);
            }
          } else {
            // Normal dialog - just close without returning a value
            Navigator.of(context).pop();
          }
        }

        // Then call the action
        action.onPressed();
      }
    }
    return null;
  }

  Future<void> _syncBrightnessIfNeeded() async {
    final ch = _channel;
    if (ch == null) return;

    final isDark = _isDark;
    final tint = _effectiveTint != null ? _colorToARGB(_effectiveTint!) : null;

    if (_lastIsDark != isDark) {
      try {
        await ch.invokeMethod('setBrightness', {'isDark': isDark});
        _lastIsDark = isDark;
      } catch (e) {
        // Ignore if method not implemented
      }
    }

    if (_lastTint != tint && tint != null) {
      try {
        await ch.invokeMethod('setStyle', {'tint': tint});
        _lastTint = tint;
      } catch (e) {
        // Ignore if method not implemented
      }
    }
  }
}

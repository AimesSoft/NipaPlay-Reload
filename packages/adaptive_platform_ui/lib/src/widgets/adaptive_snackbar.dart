import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../platform/platform_info.dart';

/// Snackbar type for different visual styles
enum AdaptiveSnackBarType {
  /// Default/neutral snackbar
  info,

  /// Success message (green)
  success,

  /// Warning message (orange/yellow)
  warning,

  /// Error message (red)
  error,
}

/// An adaptive snackbar that shows platform-appropriate notifications
///
/// - iOS: Shows a banner-style notification at the top
/// - Android: Shows a Material SnackBar at the bottom
class AdaptiveSnackBar {
  /// Shows an adaptive snackbar
  ///
  /// [context] - Build context
  /// [message] - Message to display
  /// [type] - Type of snackbar (info, success, warning, error)
  /// [duration] - How long to show the snackbar (default: 4 seconds)
  /// [action] - Optional action button
  /// [onActionPressed] - Callback for action button
  static void show(
    BuildContext context, {
    required String message,
    AdaptiveSnackBarType type = AdaptiveSnackBarType.info,
    Duration duration = const Duration(seconds: 4),
    String? action,
    VoidCallback? onActionPressed,
  }) {
    if (PlatformInfo.isIOS) {
      _showIOSSnackBar(
        context,
        message: message,
        type: type,
        duration: duration,
        action: action,
        onActionPressed: onActionPressed,
      );
    } else {
      _showAndroidSnackBar(
        context,
        message: message,
        type: type,
        duration: duration,
        action: action,
        onActionPressed: onActionPressed,
      );
    }
  }

  static void _showIOSSnackBar(
    BuildContext context, {
    required String message,
    required AdaptiveSnackBarType type,
    required Duration duration,
    String? action,
    VoidCallback? onActionPressed,
  }) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => _IOSSnackBar(
        message: message,
        type: type,
        duration: duration,
        action: action,
        onActionPressed: onActionPressed,
        onDismiss: () => overlayEntry.remove(),
      ),
    );

    overlay.insert(overlayEntry);
  }

  static void _showAndroidSnackBar(
    BuildContext context, {
    required String message,
    required AdaptiveSnackBarType type,
    required Duration duration,
    String? action,
    VoidCallback? onActionPressed,
  }) {
    final backgroundColor = _getAndroidBackgroundColor(context, type);
    final textColor = _getAndroidTextColor(type);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: textColor)),
        backgroundColor: backgroundColor,
        duration: duration,
        action: action != null
            ? SnackBarAction(
                label: action,
                textColor: textColor,
                onPressed: onActionPressed ?? () {},
              )
            : null,
      ),
    );
  }

  static Color _getAndroidBackgroundColor(
    BuildContext context,
    AdaptiveSnackBarType type,
  ) {
    switch (type) {
      case AdaptiveSnackBarType.success:
        return Colors.green.shade700;
      case AdaptiveSnackBarType.warning:
        return Colors.orange.shade700;
      case AdaptiveSnackBarType.error:
        return Colors.red.shade700;
      case AdaptiveSnackBarType.info:
        return Theme.of(context).snackBarTheme.backgroundColor ??
            const Color(0xFF323232);
    }
  }

  static Color _getAndroidTextColor(AdaptiveSnackBarType type) {
    return Colors.white;
  }
}

class _IOSSnackBar extends StatefulWidget {
  const _IOSSnackBar({
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.action,
    this.onActionPressed,
  });

  final String message;
  final AdaptiveSnackBarType type;
  final Duration duration;
  final String? action;
  final VoidCallback? onActionPressed;
  final VoidCallback onDismiss;

  @override
  State<_IOSSnackBar> createState() => _IOSSnackBarState();
}

class _IOSSnackBarState extends State<_IOSSnackBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();

    // Auto dismiss after duration
    Future.delayed(widget.duration, () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  Color _getBackgroundColor(BuildContext context) {
    final isDark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    switch (widget.type) {
      case AdaptiveSnackBarType.success:
        return isDark ? Colors.green.shade800 : Colors.green.shade600;
      case AdaptiveSnackBarType.warning:
        return isDark ? Colors.orange.shade800 : Colors.orange.shade600;
      case AdaptiveSnackBarType.error:
        return isDark ? Colors.red.shade800 : Colors.red.shade600;
      case AdaptiveSnackBarType.info:
        return isDark
            ? CupertinoColors.systemGrey.darkColor
            : CupertinoColors.systemGrey.color;
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case AdaptiveSnackBarType.success:
        return CupertinoIcons.check_mark_circled_solid;
      case AdaptiveSnackBarType.warning:
        return CupertinoIcons.exclamationmark_triangle_fill;
      case AdaptiveSnackBarType.error:
        return CupertinoIcons.xmark_circle_fill;
      case AdaptiveSnackBarType.info:
        return CupertinoIcons.info_circle_fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _opacityAnimation,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: GestureDetector(
                onTap: _dismiss,
                child: Container(
                  decoration: BoxDecoration(
                    color: _getBackgroundColor(context),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(_getIcon(), color: Colors.white, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      if (widget.action != null) ...[
                        const SizedBox(width: 12),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          onPressed: () {
                            widget.onActionPressed?.call();
                            _dismiss();
                          },
                          child: Text(
                            widget.action!,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

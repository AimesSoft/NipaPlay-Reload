import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';

class CupertinoAccountActionButton extends StatelessWidget {
  final String label;
  final IconData iosIcon;
  final VoidCallback? onPressed;
  final bool destructive;
  final bool isLoading;

  const CupertinoAccountActionButton({
    super.key,
    required this.label,
    required this.iosIcon,
    this.onPressed,
    this.destructive = false,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color resolvedColor = destructive
        ? CupertinoColors.systemRed
        : CupertinoTheme.of(context).primaryColor;

    return AdaptiveButton.child(
      onPressed: isLoading ? null : onPressed,
      style: destructive ? AdaptiveButtonStyle.bordered : AdaptiveButtonStyle.filled,
      color: destructive ? resolvedColor : null,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLoading)
            const CupertinoActivityIndicator(radius: 8)
          else
            Icon(
              iosIcon,
              size: 18,
              color: destructive ? resolvedColor : CupertinoColors.white,
            ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: destructive ? resolvedColor : CupertinoColors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

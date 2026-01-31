import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/main.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class BlurSnackBar {
  static OverlayEntry? _currentOverlayEntry;
  static AnimationController? _controller; // 防止泄漏：保存当前动画控制器

  static bool _shouldUseGlassBackground(BuildContext context) {
    if (kIsWeb) return false;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final mainPageState = MainPageState.of(context);
    final isOnVideoPage = mainPageState?.globalTabController?.index == 1;
    return videoState.status == PlayerStatus.playing && isOnVideoPage;
  }

  static void show(
    BuildContext context,
    String content, {
    String? actionText,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
    }

    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;
    late final Animation<double> animation;
    late final Animation<Offset> slideAnimation;
    late final Animation<double> scaleAnimation;
    final useGlassBackground = _shouldUseGlassBackground(context);

    void dismiss() {
      _controller?.reverse().then((_) {
        overlayEntry.remove();
        if (_currentOverlayEntry == overlayEntry) {
          _currentOverlayEntry = null;
          _controller?.dispose();
          _controller = null;
        }
      });
    }
    
    // 如有旧控制器，先释放
    _controller?.dispose();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: Navigator.of(context),
    );

    animation = CurvedAnimation(
      parent: _controller!,
      curve: Curves.easeInOut,
    );
    slideAnimation = Tween<Offset>(
      begin: const Offset(0.2, 0.2),
      end: Offset.zero,
    ).animate(animation);
    scaleAnimation = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(animation);
    
    overlayEntry = OverlayEntry(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final mediaQuery = MediaQuery.of(context);
        final safePadding = mediaQuery.padding;
        final size = mediaQuery.size;
        final maxWidth = math.min(
          360.0,
          (size.width - safePadding.left - safePadding.right - 32.0)
              .clamp(0.0, size.width)
              .toDouble(),
        );
        final maxHeight = math.min(
          160.0,
          (size.height - safePadding.top - safePadding.bottom - 32.0)
              .clamp(0.0, size.height)
              .toDouble(),
        );
        final baseSurface = Color.lerp(
          colorScheme.surface,
          colorScheme.onSurface,
          isDark ? 0.12 : 0.04,
        )!;
        final backgroundColor = useGlassBackground
            ? baseSurface.withOpacity(isDark ? 0.18 : 0.22)
            : baseSurface.withOpacity(isDark ? 0.92 : 0.97);
        final borderColor = colorScheme.onSurface.withOpacity(
          useGlassBackground ? (isDark ? 0.25 : 0.18) : (isDark ? 0.2 : 0.12),
        );
        final textColor = colorScheme.onSurface.withOpacity(isDark ? 0.92 : 0.88);
        final shadowColor = isDark
            ? Colors.black.withOpacity(0.45)
            : Colors.black.withOpacity(0.16);
        final radius = BorderRadius.circular(12);

        final body = Container(
          constraints: BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: radius,
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Text(
                  content,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                  ),
                ),
              ),
              if (actionText != null && onAction != null) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    dismiss();
                    onAction();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    minimumSize: const Size(0, 0),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(actionText),
                ),
              ],
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(
                  Icons.close,
                  color: textColor.withOpacity(0.75),
                  size: 20,
                ),
                onPressed: dismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        );

        final card = DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            boxShadow: [
              BoxShadow(
                color: shadowColor,
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: useGlassBackground
              ? ClipRRect(
                  borderRadius: radius,
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: body,
                  ),
                )
              : body,
        );

        return Positioned(
          bottom: 16 + safePadding.bottom,
          right: 16 + safePadding.right,
          child: FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slideAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                alignment: Alignment.bottomRight,
                child: Material(
                  type: MaterialType.transparency,
                  child: card,
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(overlayEntry);
    _currentOverlayEntry = overlayEntry;
    _controller!.forward();

    final resolvedDuration = duration ??
        (actionText != null && onAction != null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 2));

    Future.delayed(resolvedDuration, () {
      if (overlayEntry.mounted) {
        dismiss();
      }
    });
  }
}

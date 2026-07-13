import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/app/app_navigation_scope.dart';
import 'package:nipaplay/app/app_page_ids.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_no_ripple_theme.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class BlurSnackBar {
  static OverlayEntry? _currentOverlayEntry;
  static AnimationController? _controller; // 防止泄漏：保存当前动画控制器

  static bool _shouldUseGlassBackground(BuildContext context) {
    if (kIsWeb) return false;
    if (SettingsVisualScope.isBlurDisabled(context, listen: false)) {
      return false;
    }
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final isOnVideoPage =
        AppNavigationScope.maybeOf(context)?.selectedPageId == AppPageIds.video;
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

    // context 可能是 Navigator 自己的 context（无 Overlay 祖先，如 PlaybackService
    // 传入的 navigatorKey.currentContext），用 maybeOf + 回退到 Navigator 内部 Overlay。
    final overlay =
        Overlay.maybeOf(context) ?? globals.navigatorKey.currentState?.overlay;
    if (overlay == null) {
      debugPrint('[BlurSnackBar] 无可用 Overlay，放弃显示: $content');
      return;
    }
    late final OverlayEntry overlayEntry;
    late final Animation<double> animation;
    late final Animation<Offset> slideAnimation;
    late final Animation<double> scaleAnimation;
    bool useGlassBackground;
    final isPhoneSurface =
        AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone ||
            globals.isPhone;
    try {
      useGlassBackground = _shouldUseGlassBackground(context);
    } catch (_) {
      useGlassBackground = false;
    }

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
      vsync: globals.navigatorKey.currentState ?? Navigator.of(context),
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
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final mediaQuery = MediaQuery.of(context);
        final safePadding = mediaQuery.padding;
        final baseBottomOffset = 16 + safePadding.bottom;
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
        final backgroundColor = useGlassBackground
            ? (isDark
                ? Colors.black.withValues(alpha: 0.42)
                : Colors.white.withValues(alpha: 0.56))
            : (isDark ? const Color(0xF2252527) : const Color(0xFAF7F7F8));
        final borderColor = isDark
            ? Colors.white.withValues(alpha: useGlassBackground ? 0.2 : 0.14)
            : Colors.black.withValues(alpha: useGlassBackground ? 0.14 : 0.09);
        final textColor = isDark
            ? Colors.white.withValues(alpha: 0.92)
            : Colors.black.withValues(alpha: 0.86);
        final actionForeground = textColor;
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
                SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    dismiss();
                    onAction();
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: actionForeground,
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
              SizedBox(width: 4),
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
          bottom: isPhoneSurface ? baseBottomOffset * 2 : baseBottomOffset,
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

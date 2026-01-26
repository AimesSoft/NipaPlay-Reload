import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class SettingsMenuScope extends InheritedWidget {
  final double? width;
  final double? rightOffset;
  final bool useBackButton;
  final bool showHeader;
  final bool showBackItem;
  final bool lockControlsVisible;
  final Rect? anchorRect;
  final bool showPointer;
  final double pointerWidth;
  final double pointerHeight;

  const SettingsMenuScope({
    super.key,
    required super.child,
    this.width,
    this.rightOffset,
    this.useBackButton = false,
    this.showHeader = true,
    this.showBackItem = false,
    this.lockControlsVisible = false,
    this.anchorRect,
    this.showPointer = false,
    this.pointerWidth = 16,
    this.pointerHeight = 8,
  });

  static SettingsMenuScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<SettingsMenuScope>();
  }

  @override
  bool updateShouldNotify(SettingsMenuScope oldWidget) {
    return width != oldWidget.width ||
        rightOffset != oldWidget.rightOffset ||
        useBackButton != oldWidget.useBackButton ||
        showHeader != oldWidget.showHeader ||
        showBackItem != oldWidget.showBackItem ||
        lockControlsVisible != oldWidget.lockControlsVisible ||
        anchorRect != oldWidget.anchorRect ||
        showPointer != oldWidget.showPointer ||
        pointerWidth != oldWidget.pointerWidth ||
        pointerHeight != oldWidget.pointerHeight;
  }
}

class BaseSettingsMenu extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback? onClose;
  final Widget? extraButton;
  final double width;
  final double rightOffset;
  final ValueChanged<bool>? onHoverChanged;

  const BaseSettingsMenu({
    super.key,
    required this.title,
    required this.content,
    this.onClose,
    this.extraButton,
    this.width = 300,
    this.rightOffset = 240,
    this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scope = SettingsMenuScope.maybeOf(context);
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final backgroundColor = colorScheme.surface.withOpacity(0.15);
        final borderColor = colorScheme.onSurface.withOpacity(0.2);
        final resolvedWidth = scope?.width ?? width;
        final resolvedRightOffset = scope?.rightOffset ?? rightOffset;
        final bool useBackButton = scope?.useBackButton ?? false;
        final bool showHeader = scope?.showHeader ?? true;
        final bool showBackItem = scope?.showBackItem ?? false;
        final bool lockControlsVisible = scope?.lockControlsVisible ?? false;
        final Rect? anchorRect = scope?.anchorRect;
        final bool showPointer = scope?.showPointer ?? false;
        final double pointerWidth = scope?.pointerWidth ?? 16;
        final double pointerHeight = scope?.pointerHeight ?? 8;
        final Size screenSize = MediaQuery.of(context).size;
        const double horizontalMargin = 12;
        const double pointerPadding = 12;
        bool pointerOnTop = true;
        double? pointerX;
        double? left;
        double? top;
        double? bottom;

        if (anchorRect != null) {
          final spaceAbove = anchorRect.top;
          final spaceBelow = screenSize.height - anchorRect.bottom;
          final showAbove = spaceAbove >= spaceBelow;
          left = (anchorRect.right - resolvedWidth)
              .clamp(horizontalMargin, screenSize.width - resolvedWidth - horizontalMargin);
          pointerX = (anchorRect.center.dx - left)
              .clamp(pointerPadding, resolvedWidth - pointerPadding);
          if (showAbove) {
            bottom = (screenSize.height - anchorRect.top) + pointerHeight;
            pointerOnTop = false;
          } else {
            top = anchorRect.bottom + pointerHeight;
            pointerOnTop = true;
          }
        }

        return Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                Positioned(
                  right: anchorRect == null ? resolvedRightOffset : null,
                  left: anchorRect != null ? left : null,
                  top: anchorRect != null ? top : (globals.isPhone ? 10 : 80),
                  bottom: anchorRect != null ? bottom : null,
                  child: Container(
                    width: resolvedWidth,
                    constraints: BoxConstraints(
                      maxHeight: globals.isPhone
                          ? MediaQuery.of(context).size.height - 120
                          : MediaQuery.of(context).size.height - 200,
                    ),
                    child: MouseRegion(
                      onEnter: (_) {
                        videoState.setControlsHovered(true);
                        onHoverChanged?.call(true);
                      },
                      onExit: (_) {
                        if (!lockControlsVisible) {
                          videoState.setControlsHovered(false);
                        }
                        onHoverChanged?.call(false);
                      },
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: backgroundColor,
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: borderColor,
                                    width: 0.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                      spreadRadius: 0,
                                    ),
                                  ],
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: globals.isPhone
                                        ? MediaQuery.of(context).size.height - 120
                                        : MediaQuery.of(context).size.height - 200,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (showHeader)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 12,
                                          ),
                                          decoration: BoxDecoration(
                                            border: Border(
                                              bottom: BorderSide(
                                                color: borderColor,
                                                width: 0.5,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              if (useBackButton && onClose != null)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.arrow_back_ios_new_rounded,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                  onPressed: onClose,
                                                  iconSize: 18,
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                              if (useBackButton && onClose != null)
                                                const SizedBox(width: 8),
                                              Text(
                                                title,
                                                style: TextStyle(
                                                  color: colorScheme.onSurface,
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                              const Spacer(),
                                              if (extraButton != null) extraButton!,
                                              if (!useBackButton && onClose != null)
                                                IconButton(
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                  onPressed: onClose,
                                                  iconSize: 18,
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                            ],
                                          ),
                                        ),
                                      ListView(
                                        padding: EdgeInsets.zero,
                                        primary: false,
                                        shrinkWrap: true,
                                        physics: const ClampingScrollPhysics(),
                                        children: [
                                          if (!showHeader && showBackItem && onClose != null)
                                            _MenuBackItem(
                                              label: '返回',
                                              onTap: onClose!,
                                              textColor: colorScheme.onSurface,
                                              dividerColor: borderColor,
                                            ),
                                          content,
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (showPointer && pointerX != null)
                            Positioned(
                              left: pointerX - pointerWidth / 2,
                              top: pointerOnTop ? -pointerHeight : null,
                              bottom: pointerOnTop ? null : -pointerHeight,
                              child: CustomPaint(
                                size: Size(pointerWidth, pointerHeight),
                                painter: _MenuPointerPainter(
                                  color: backgroundColor,
                                  pointUp: pointerOnTop,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MenuBackItem extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color textColor;
  final Color dividerColor;

  const _MenuBackItem({
    required this.label,
    required this.onTap,
    required this.textColor,
    required this.dividerColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.arrow_back_ios_new_rounded,
                color: textColor,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MenuPointerPainter extends CustomPainter {
  final Color color;
  final bool pointUp;

  const _MenuPointerPainter({
    required this.color,
    required this.pointUp,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path();
    if (pointUp) {
      path.moveTo(0, size.height);
      path.lineTo(size.width / 2, 0);
      path.lineTo(size.width, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width / 2, size.height);
      path.lineTo(size.width, 0);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_MenuPointerPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.pointUp != pointUp;
  }
}

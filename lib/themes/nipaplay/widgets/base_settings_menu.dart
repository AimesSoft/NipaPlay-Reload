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
        bool pointUp = true;
        double? pointerX;
        double? left;
        double? top;
        double? bottom;
        double contentPaddingTop = 0;
        double contentPaddingBottom = 0;

        if (anchorRect != null) {
          final spaceAbove = anchorRect.top;
          final spaceBelow = screenSize.height - anchorRect.bottom;
          final showAbove = spaceAbove >= spaceBelow;
          left = (anchorRect.center.dx - resolvedWidth / 2)
              .clamp(horizontalMargin, screenSize.width - resolvedWidth - horizontalMargin);
          pointerX = (anchorRect.center.dx - left)
              .clamp(pointerPadding, resolvedWidth - pointerPadding);
          if (showAbove) {
            bottom = screenSize.height - anchorRect.top;
            pointUp = false;
            contentPaddingBottom = pointerHeight;
          } else {
            top = anchorRect.bottom;
            pointUp = true;
            contentPaddingTop = pointerHeight;
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
                      child: _MenuBubble(
                        backgroundColor: backgroundColor,
                        borderColor: borderColor,
                        blurValue: blurValue,
                        borderRadius: 15,
                        showPointer: showPointer && pointerX != null,
                        pointUp: pointUp,
                        pointerX: pointerX ?? resolvedWidth / 2,
                        pointerWidth: pointerWidth,
                        pointerHeight: pointerHeight,
                        contentPaddingTop: contentPaddingTop,
                        contentPaddingBottom: contentPaddingBottom,
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

class _MenuBubble extends StatelessWidget {
  final Color backgroundColor;
  final Color borderColor;
  final double blurValue;
  final double borderRadius;
  final bool showPointer;
  final bool pointUp;
  final double pointerX;
  final double pointerWidth;
  final double pointerHeight;
  final double contentPaddingTop;
  final double contentPaddingBottom;
  final Widget child;

  const _MenuBubble({
    required this.backgroundColor,
    required this.borderColor,
    required this.blurValue,
    required this.borderRadius,
    required this.showPointer,
    required this.pointUp,
    required this.pointerX,
    required this.pointerWidth,
    required this.pointerHeight,
    required this.contentPaddingTop,
    required this.contentPaddingBottom,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final shape = _MenuBubbleShape(
      radius: borderRadius,
      pointerWidth: showPointer ? pointerWidth : 0,
      pointerHeight: showPointer ? pointerHeight : 0,
      pointerX: pointerX,
      pointUp: pointUp,
      side: BorderSide(
        color: borderColor,
        width: 0.5,
      ),
    );

    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            color: backgroundColor,
            shadows: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: contentPaddingTop,
              bottom: contentPaddingBottom,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _MenuBubbleShape extends ShapeBorder {
  final double radius;
  final double pointerWidth;
  final double pointerHeight;
  final double pointerX;
  final bool pointUp;
  final BorderSide side;

  const _MenuBubbleShape({
    required this.radius,
    required this.pointerWidth,
    required this.pointerHeight,
    required this.pointerX,
    required this.pointUp,
    required this.side,
  });

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  ShapeBorder scale(double t) {
    return _MenuBubbleShape(
      radius: radius * t,
      pointerWidth: pointerWidth * t,
      pointerHeight: pointerHeight * t,
      pointerX: pointerX * t,
      pointUp: pointUp,
      side: side.scale(t),
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    if (side.width == 0) {
      return getOuterPath(rect, textDirection: textDirection);
    }
    return getOuterPath(rect.deflate(side.width), textDirection: textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final double clampedRadius = radius.clamp(0.0, rect.shortestSide / 2);
    final double arrowHalf = pointerWidth / 2;
    final double arrowX = pointerX
        .clamp(clampedRadius + arrowHalf, rect.width - clampedRadius - arrowHalf);
    final double top = rect.top + (pointUp ? pointerHeight : 0);
    final double bottom = rect.bottom - (pointUp ? 0 : pointerHeight);
    final Rect body = Rect.fromLTRB(rect.left, top, rect.right, bottom);
    final Radius r = Radius.circular(clampedRadius);
    final Path path = Path();

    if (pointUp) {
      path.moveTo(body.left + clampedRadius, body.top);
      path.lineTo(arrowX - arrowHalf, body.top);
      path.lineTo(arrowX, body.top - pointerHeight);
      path.lineTo(arrowX + arrowHalf, body.top);
      path.lineTo(body.right - clampedRadius, body.top);
      path.arcToPoint(Offset(body.right, body.top + clampedRadius), radius: r);
      path.lineTo(body.right, body.bottom - clampedRadius);
      path.arcToPoint(Offset(body.right - clampedRadius, body.bottom), radius: r);
      path.lineTo(body.left + clampedRadius, body.bottom);
      path.arcToPoint(Offset(body.left, body.bottom - clampedRadius), radius: r);
      path.lineTo(body.left, body.top + clampedRadius);
      path.arcToPoint(Offset(body.left + clampedRadius, body.top), radius: r);
    } else {
      path.moveTo(body.left + clampedRadius, body.top);
      path.lineTo(body.right - clampedRadius, body.top);
      path.arcToPoint(Offset(body.right, body.top + clampedRadius), radius: r);
      path.lineTo(body.right, body.bottom - clampedRadius);
      path.arcToPoint(Offset(body.right - clampedRadius, body.bottom), radius: r);
      path.lineTo(arrowX + arrowHalf, body.bottom);
      path.lineTo(arrowX, body.bottom + pointerHeight);
      path.lineTo(arrowX - arrowHalf, body.bottom);
      path.lineTo(body.left + clampedRadius, body.bottom);
      path.arcToPoint(Offset(body.left, body.bottom - clampedRadius), radius: r);
      path.lineTo(body.left, body.top + clampedRadius);
      path.arcToPoint(Offset(body.left + clampedRadius, body.top), radius: r);
    }

    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) {
      return;
    }
    final paint = Paint()
      ..color = side.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = side.width;
    final path = getOuterPath(rect, textDirection: textDirection);
    canvas.drawPath(path, paint);
  }
}

import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'arrow_menu_container.dart';

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
  final double? height;

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
    this.height,
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
        pointerHeight != oldWidget.pointerHeight ||
        height != oldWidget.height;
  }
}

class BaseSettingsMenu extends StatelessWidget {
  final String title;
  final Widget content;
  final VoidCallback? onClose;
  final Widget? extraButton;
  final double width;
  final double rightOffset;
  final double height;
  final ValueChanged<bool>? onHoverChanged;

  const BaseSettingsMenu({
    super.key,
    required this.title,
    required this.content,
    this.onClose,
    this.extraButton,
    this.width = 300,
    this.rightOffset = 240,
    this.height = 420,
    this.onHoverChanged,
  });

  @override
  Widget build(BuildContext context) {
    final scope = SettingsMenuScope.maybeOf(context);
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final baseTheme = Theme.of(context);
        final colorScheme = baseTheme.colorScheme;
        const menuTextColor = Colors.white;
        final backgroundColor = colorScheme.surface.withOpacity(0.15);
        final borderColor = colorScheme.onSurface.withOpacity(0.2);
        final menuTheme = baseTheme.copyWith(
          colorScheme: colorScheme.copyWith(
            onSurface: menuTextColor,
            onSurfaceVariant: menuTextColor.withOpacity(0.7),
          ),
          textTheme: baseTheme.textTheme.apply(
            bodyColor: menuTextColor,
            displayColor: menuTextColor,
          ),
          iconTheme: baseTheme.iconTheme.copyWith(color: menuTextColor),
        );
        final resolvedWidth = scope?.width ?? width;
        final resolvedRightOffset = scope?.rightOffset ?? rightOffset;
        final bool useBackButton = scope?.useBackButton ?? false;
        final bool showHeader = scope?.showHeader ?? true;
        final bool showBackItem = scope?.showBackItem ?? false;
        final bool lockControlsVisible = scope?.lockControlsVisible ?? false;
        final Rect? anchorRect = scope?.anchorRect;
        final bool showPointer =
            scope?.showPointer ?? (anchorRect != null);
        final double pointerWidth = scope?.pointerWidth ?? 16;
        final double pointerHeight = scope?.pointerHeight ?? 8;
        final Size screenSize = MediaQuery.of(context).size;
        final double screenMaxHeight = globals.isPhone
            ? screenSize.height - 120
            : screenSize.height - 200;
        final double resolvedHeight =
            math.min(scope?.height ?? height, screenMaxHeight);
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
                  child: SizedBox(
                    width: resolvedWidth,
                    height: resolvedHeight,
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
                      child: ArrowMenuContainer(
                        backgroundColor: backgroundColor,
                        borderColor: borderColor,
                        blurValue: blurValue,
                        borderRadius: 15,
                        showPointer: showPointer && pointerX != null,
                        pointUp: pointUp,
                        pointerX: pointerX ?? resolvedWidth / 2,
                        pointerWidth: pointerWidth,
                        pointerHeight: pointerHeight,
                        contentPadding: EdgeInsets.only(
                          top: contentPaddingTop,
                          bottom: contentPaddingBottom,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.max,
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
                                          color: menuTextColor,
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
                                        color: menuTextColor,
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
                                          color: menuTextColor,
                                        ),
                                        onPressed: onClose,
                                        iconSize: 18,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                      ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: Theme(
                                data: menuTheme,
                                child: _MenuContentList(
                                  showBackItem: showBackItem,
                                  onClose: onClose,
                                  textColor: menuTextColor,
                                  dividerColor: borderColor,
                                  content: content,
                                ),
                              ),
                            ),
                          ],
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

class _MenuContentList extends StatelessWidget {
  final bool showBackItem;
  final VoidCallback? onClose;
  final Color textColor;
  final Color dividerColor;
  final Widget content;

  const _MenuContentList({
    required this.showBackItem,
    required this.onClose,
    required this.textColor,
    required this.dividerColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    Widget listView = ListView(
      padding: EdgeInsets.zero,
      primary: false,
      shrinkWrap: false,
      physics: const ClampingScrollPhysics(),
      children: [
        if (showBackItem && onClose != null)
          _MenuBackItem(
            label: '返回',
            onTap: onClose!,
            textColor: textColor,
            dividerColor: dividerColor,
          ),
        content,
      ],
    );

    return listView;
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

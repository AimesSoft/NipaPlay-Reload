import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/providers/appearance_settings_provider.dart';

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
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;

    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final colorScheme = Theme.of(context).colorScheme;
        final backgroundColor = colorScheme.surface.withOpacity(0.15);
        final borderColor = colorScheme.onSurface.withOpacity(0.2);

        return Material(
          type: MaterialType.transparency,
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                Positioned(
                  right: rightOffset,
                  top: globals.isPhone ? 10 : 80,
                  child: Container(
                    width: width,
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
                        videoState.setControlsHovered(false);
                        onHoverChanged?.call(false);
                      },
                      child: ClipRRect(
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
                                children: [
                                  // 标题栏
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
                                        if (onClose != null)
                                          IconButton(
                                            icon: Icon(Icons.close, color: colorScheme.onSurface),
                                            onPressed: onClose,
                                            iconSize: 18,
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // 内容区域
                                  Expanded(
                                    child: SingleChildScrollView(
                                      child: content,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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

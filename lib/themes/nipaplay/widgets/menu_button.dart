// ignore: file_names
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class WindowControlButtons extends StatelessWidget {
  final bool isMaximized;
  final VoidCallback onMinimize;
  final VoidCallback onMaximizeRestore;
  final VoidCallback onClose;

  const WindowControlButtons({
    super.key,
    required this.isMaximized,
    required this.onMinimize,
    required this.onMaximizeRestore,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WindowCaptionButton.minimize(
          brightness: brightness,
          onPressed: onMinimize,
        ),
        isMaximized
            ? WindowCaptionButton.unmaximize(
                brightness: brightness,
                onPressed: onMaximizeRestore,
              )
            : WindowCaptionButton.maximize(
                brightness: brightness,
                onPressed: onMaximizeRestore,
              ),
        WindowCaptionButton.close(
          brightness: brightness,
          onPressed: onClose,
        ),
      ],
    );
  }
}

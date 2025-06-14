import 'dart:ui';
import 'package:flutter/material.dart';

class CountdownSnackBar {
  static OverlayEntry? _currentOverlayEntry;
  static Function()? _onCancel;
  static ValueNotifier<String>? _messageNotifier;

  static void show(
    BuildContext context, 
    String message, 
    {Function()? onCancel}
  ) {
    if (_currentOverlayEntry != null) {
      // 如果已经有显示的snackbar，只更新内容
      update(message);
      return;
    }

    _onCancel = onCancel;
    _messageNotifier = ValueNotifier<String>(message);
    
    final overlay = Overlay.of(context);
    late final OverlayEntry overlayEntry;
    late final AnimationController controller;
    late final Animation<double> animation;
    
    controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: Navigator.of(context),
    );

    animation = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOut,
    );
    
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 16,
        left: 16,
        right: 16,
        child: FadeTransition(
          opacity: animation,
          child: Material(
            type: MaterialType.transparency,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2),
                      width: 1,
                    ),
                  ),
                  child: ValueListenableBuilder<String>(
                    valueListenable: _messageNotifier!,
                    builder: (context, currentMessage, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.play_arrow,
                            color: Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              currentMessage,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          if (onCancel != null) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () {
                                onCancel();
                                _closeSnackBar(controller, overlayEntry);
                              },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                minimumSize: Size.zero,
                                backgroundColor: Colors.white.withOpacity(0.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              child: const Text(
                                '取消',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                            onPressed: () {
                              if (onCancel != null) {
                                onCancel();
                              }
                              _closeSnackBar(controller, overlayEntry);
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    _currentOverlayEntry = overlayEntry;
    controller.forward();
  }

  static void _closeSnackBar(AnimationController controller, OverlayEntry overlayEntry) {
    controller.reverse().then((_) {
      overlayEntry.remove();
      if (_currentOverlayEntry == overlayEntry) {
        _currentOverlayEntry = null;
        _messageNotifier?.dispose();
        _messageNotifier = null;
      }
    });
  }

  static void hide() {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
      _messageNotifier?.dispose();
      _messageNotifier = null;
    }
  }

  static void update(String message) {
    // 更新消息内容，不重新创建控件
    if (_messageNotifier != null) {
      _messageNotifier!.value = message;
    }
  }
} 
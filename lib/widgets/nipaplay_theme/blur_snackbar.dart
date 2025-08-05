import 'dart:ui';
import 'package:flutter/material.dart';

class BlurSnackBar {
  static OverlayEntry? _currentOverlayEntry;

  static void show(BuildContext context, String content) {
    if (_currentOverlayEntry != null) {
      _currentOverlayEntry!.remove();
      _currentOverlayEntry = null;
    }

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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          content,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                        onPressed: () {
                          controller.reverse().then((_) {
                            overlayEntry.remove();
                            if (_currentOverlayEntry == overlayEntry) {
                              _currentOverlayEntry = null;
                            }
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
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

    Future.delayed(const Duration(seconds: 2), () {
      if (overlayEntry.mounted) {
        controller.reverse().then((_) {
          overlayEntry.remove();
          if (_currentOverlayEntry == overlayEntry) {
            _currentOverlayEntry = null;
          }
        });
      }
    });
  }
} 
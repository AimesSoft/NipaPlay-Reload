import 'dart:ui';
import 'package:flutter/material.dart';

class BlurDialog extends StatelessWidget {
  final String title;
  final String content;
  final List<Widget> actions;
  final bool barrierDismissible;

  const BlurDialog({
    Key? key,
    required this.title,
    required this.content,
    required this.actions,
    this.barrierDismissible = true,
  }) : super(key: key);

  static Future<T?> show<T>({
    required BuildContext context,
    required String title,
    required String content,
    required List<Widget> actions,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (BuildContext context) {
        return BlurDialog(
          title: title,
          content: content,
          actions: actions,
          barrierDismissible: barrierDismissible,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Dialog(
        backgroundColor: Colors.transparent,
        child: IntrinsicWidth(
          child: IntrinsicHeight(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      content,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions.map((action) {
                        if (action is TextButton) {
                          return TextButton(
                            onPressed: action.onPressed,
                            child: Text(
                              (action.child as Text).data!,
                              style: TextStyle(
                                color: (action.child as Text).style?.color ?? Colors.white.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          );
                        }
                        return action;
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
} 
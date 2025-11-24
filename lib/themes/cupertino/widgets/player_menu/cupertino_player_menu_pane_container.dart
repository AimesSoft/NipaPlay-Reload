import 'dart:ui';

import 'package:flutter/cupertino.dart';

/// Cupertino Player 子菜单的通用容器，提供毛玻璃底部弹窗效果。
class CupertinoPlayerMenuPaneContainer extends StatelessWidget {
  const CupertinoPlayerMenuPaneContainer({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Color background = CupertinoTheme.of(context)
        .barBackgroundColor
        .withOpacity(0.92);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: CupertinoColors.black.withOpacity(0.35),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: SafeArea(
            bottom: true,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 440),
                    width: double.infinity,
                    color: background,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 5,
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: CupertinoColors.systemGrey4
                                .resolveFrom(context)
                                .withOpacity(0.6),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: CupertinoTheme.of(context)
                                      .textTheme
                                      .navTitleTextStyle,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              CupertinoButton(
                                padding: EdgeInsets.zero,
                                onPressed: onClose,
                                child:
                                    const Icon(CupertinoIcons.xmark_circle_fill),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 0.6,
                          color: CupertinoColors.separator.resolveFrom(context),
                        ),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

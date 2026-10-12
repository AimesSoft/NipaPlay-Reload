import 'package:flutter/material.dart';

/// TV/手机通用：带键盘适配的输入对话框。
///
/// 为什么需要它：Android 15+ 强制 edge-to-edge，`AlertDialog` 的 actions
/// 会被软键盘顶出屏幕或错位（用户实测截图）。这里做三件事：
/// 1. 内容区可滚动（键盘弹出时字段仍可达）；
/// 2. 用 [MediaQuery.viewInsets] 把键盘高度从可用高度里扣除；
/// 3. 对话框整体高度上限为可用高度的 85%，保证 actions 始终可见。
class TvInputDialog extends StatelessWidget {
  const TvInputDialog({
    super.key,
    required this.title,
    required this.children,
    this.actions = const [],
    this.maxWidth = 560,
  });

  final String title;
  final List<Widget> children;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.viewInsetsOf(context);
    final viewSize = MediaQuery.sizeOf(context);
    // 键盘占用的高度（edge-to-edge 下必须自行扣除）
    final keyboard = insets.bottom;
    final available = viewSize.height - keyboard - 48; // 留出上下边距

    return Dialog(
      backgroundColor: const Color(0xFF1A2026),
      insetPadding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        // 键盘弹出时把对话框整体上推，避免 actions 被遮
        bottom: 24 + keyboard,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: available > 240 ? available * 0.85 : available,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            // 内容可滚动：键盘弹出时仍可滚动到任意字段
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
            if (actions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      actions[i],
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

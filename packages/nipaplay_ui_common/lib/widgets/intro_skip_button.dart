import 'package:flutter/material.dart';

/// 播放器悬浮的「跳过片头 / 片尾」按钮。
///
/// 只在播放位置落入某个可跳过区间时出现（由 `VideoPlayerState.hasActiveSkipSegment`
/// 控制），点击后跳到区间结束点。样式保持与播放器浮层一致的深色半透明胶囊，
/// 不依赖具体主题皮肤，nipaplay / cupertino 两套皮肤下观感统一。
class IntroSkipButton extends StatelessWidget {
  /// 点击回调（通常调用 `VideoPlayerState.skipCurrentSegment`）。
  final VoidCallback onPressed;

  /// 按钮文案。调用方按当前区间类型传「跳过片头」或「跳过片尾」。
  final String label;

  const IntroSkipButton({
    super.key,
    required this.onPressed,
    this.label = '跳过片头',
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.fast_forward_rounded, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// 播放器悬浮的「跳过片头 / 片尾」按钮。
///
/// 只在播放位置落入某个可跳过区间时出现（由 `VideoPlayerState.hasActiveSkipSegment`
/// 控制），点击后跳到区间结束点。图标和文字带阴影，以便在视频画面上保持清晰。
class IntroSkipButton extends StatelessWidget {
  static const _contentShadows = [
    Shadow(color: Color(0xE6000000), blurRadius: 4),
    Shadow(color: Color(0xCC000000), blurRadius: 10, offset: Offset(0, 2)),
  ];

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
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        Icons.fast_forward_rounded,
        size: 18,
        shadows: _contentShadows,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          shadows: _contentShadows,
        ),
      ),
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return const Color(0xFFFFE0A0);
          }
          if (states.contains(WidgetState.pressed)) {
            return const Color(0xFFDADADA);
          }
          return Colors.white;
        }),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        shadowColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        side: const WidgetStatePropertyAll(BorderSide.none),
        splashFactory: NoSplash.splashFactory,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        ),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

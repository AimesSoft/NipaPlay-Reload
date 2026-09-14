import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/themes/nipaplay/widgets/player_menu_theme.dart';
import 'package:provider/provider.dart';

/// 两套播放器菜单共用的一级快捷操作。
class PlayerQuickControls extends StatelessWidget {
  const PlayerQuickControls({super.key, this.cupertino = false});

  final bool cupertino;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<VideoPlayerState>();
    if (!state.hasVideo) return const SizedBox.shrink();
    final colors = PlayerMenuTheme.colorsOf(context);
    final foreground = cupertino
        ? CupertinoColors.label.resolveFrom(context)
        : colors.foreground;
    final accent =
        cupertino ? CupertinoTheme.of(context).primaryColor : colors.accent;

    Widget choices(String title, List<double> values, double selected,
        Future<void> Function(double) onSelect, String Function(double) label) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: foreground, fontSize: 14)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: values.map((value) {
                final active = (selected - value).abs() < 0.001;
                final child = Text(label(value),
                    style: TextStyle(
                      color: active ? accent : foreground,
                      fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                    ));
                if (cupertino) {
                  return CupertinoButton(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    color:
                        CupertinoColors.tertiarySystemFill.resolveFrom(context),
                    onPressed: () => onSelect(value),
                    child: child,
                  );
                }
                return TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(44, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: active
                        ? colors.selectedBackground
                        : colors.controlBackground,
                  ),
                  onPressed: () => onSelect(value),
                  child: child,
                );
              }).toList(),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        choices('播放倍速 · ${state.playbackRate}×', const [0.5, 1, 1.5, 2],
            state.playbackRate, state.setPlaybackRate, (value) => '${value}×'),
        if (state.supportsVolumeBoost)
          choices('音量增强', const [1, 1.25, 1.5, 2], state.volumeBoost,
              state.setVolumeBoost, (value) => '${(value * 100).round()}%'),
      ],
    );
  }
}

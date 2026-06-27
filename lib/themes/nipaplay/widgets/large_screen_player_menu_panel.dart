import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_focusable_action.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

const double kNipaplayLargeScreenPlayerMenuPanelWidth = 430;

class NipaplayLargeScreenPlayerMenuPanel extends StatelessWidget {
  const NipaplayLargeScreenPlayerMenuPanel({
    super.key,
    required this.isDarkMode,
    required this.onRequestClose,
  });

  final bool isDarkMode;
  final VoidCallback onRequestClose;

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? Colors.white : const Color(0xFF161922);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          width: kNipaplayLargeScreenPlayerMenuPanelWidth,
          color: isDarkMode
              ? Colors.black.withValues(alpha: 0.62)
              : Colors.white.withValues(alpha: 0.82),
          padding: const EdgeInsets.fromLTRB(20, 72, 20, 72),
          child: Consumer<VideoPlayerState>(
            builder: (context, videoState, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '播放器菜单',
                              style: TextStyle(
                                color: textColor,
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '倍速、步长、弹幕和字幕',
                              style: TextStyle(
                                color: textColor.withValues(alpha: 0.62),
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _LargeScreenPlayerMenuIconButton(
                        icon: Icons.close_rounded,
                        label: '关闭',
                        onPressed: onRequestClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        _LargeScreenPlayerMenuSection(
                          title: '播放',
                          children: [
                            _LargeScreenPlayerMenuOptionGrid(
                              values: const [0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
                              labelFor: (value) =>
                                  '${value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2)}x',
                              selectedValue: videoState.playbackRate,
                              onSelected: (value) =>
                                  videoState.setPlaybackRate(value),
                            ),
                            const SizedBox(height: 12),
                            _LargeScreenPlayerMenuOptionGrid(
                              values: const [5, 10, 30, 60],
                              labelFor: (value) => '${value.toInt()}秒步长',
                              selectedValue: videoState.seekStepSeconds,
                              onSelected: (value) =>
                                  videoState.setSeekStepSeconds(value),
                            ),
                          ],
                        ),
                        _LargeScreenPlayerMenuSection(
                          title: '弹幕',
                          children: [
                            _LargeScreenPlayerMenuSwitchTile(
                              icon: Icons.chat_bubble_outline_rounded,
                              title: '显示弹幕',
                              value: videoState.danmakuVisible,
                              onPressed: videoState.toggleDanmakuVisible,
                            ),
                            _LargeScreenPlayerMenuStepperTile(
                              icon: Icons.opacity_rounded,
                              title: '弹幕不透明度',
                              valueLabel:
                                  '${(videoState.danmakuOpacity * 100).round()}%',
                              onDecrease: () => videoState.setDanmakuOpacity(
                                (videoState.danmakuOpacity - 0.1)
                                    .clamp(0.1, 1.0)
                                    .toDouble(),
                              ),
                              onIncrease: () => videoState.setDanmakuOpacity(
                                (videoState.danmakuOpacity + 0.1)
                                    .clamp(0.1, 1.0)
                                    .toDouble(),
                              ),
                            ),
                            _LargeScreenPlayerMenuStepperTile(
                              icon: Icons.format_size_rounded,
                              title: '弹幕字号',
                              valueLabel: videoState.danmakuFontSize <= 0
                                  ? '默认'
                                  : videoState.danmakuFontSize
                                      .toStringAsFixed(0),
                              onDecrease: () => videoState.setDanmakuFontSize(
                                (videoState.danmakuFontSize <= 0
                                        ? 24
                                        : videoState.danmakuFontSize - 2)
                                    .clamp(12, 72)
                                    .toDouble(),
                              ),
                              onIncrease: () => videoState.setDanmakuFontSize(
                                (videoState.danmakuFontSize <= 0
                                        ? 28
                                        : videoState.danmakuFontSize + 2)
                                    .clamp(12, 72)
                                    .toDouble(),
                              ),
                            ),
                          ],
                        ),
                        _LargeScreenPlayerMenuSection(
                          title: '字幕',
                          children: [
                            _LargeScreenPlayerMenuStepperTile(
                              icon: Icons.subtitles_rounded,
                              title: '字幕缩放',
                              valueLabel:
                                  '${(videoState.subtitleScale * 100).round()}%',
                              onDecrease: () => videoState.setSubtitleScale(
                                (videoState.subtitleScale - 0.05)
                                    .clamp(0.5, 2.0)
                                    .toDouble(),
                              ),
                              onIncrease: () => videoState.setSubtitleScale(
                                (videoState.subtitleScale + 0.05)
                                    .clamp(0.5, 2.0)
                                    .toDouble(),
                              ),
                            ),
                            _LargeScreenPlayerMenuStepperTile(
                              icon: Icons.timer_rounded,
                              title: '字幕延迟',
                              valueLabel:
                                  '${videoState.subtitleDelaySeconds.toStringAsFixed(1)}秒',
                              onDecrease: () =>
                                  videoState.setSubtitleDelaySeconds(
                                videoState.subtitleDelaySeconds - 0.1,
                              ),
                              onIncrease: () =>
                                  videoState.setSubtitleDelaySeconds(
                                videoState.subtitleDelaySeconds + 0.1,
                              ),
                            ),
                          ],
                        ),
                        _LargeScreenPlayerMenuSection(
                          title: '显示',
                          children: [
                            _LargeScreenPlayerMenuSwitchTile(
                              icon: Icons.fullscreen_rounded,
                              title: videoState.isFullscreen ? '退出全屏' : '进入全屏',
                              value: videoState.isFullscreen,
                              onPressed: () => videoState.toggleFullscreen(),
                            ),
                            _LargeScreenPlayerMenuSwitchTile(
                              icon: Icons.fit_screen_rounded,
                              title: '窗口适配视频',
                              value: false,
                              showSwitch: false,
                              onPressed: videoState.resizeWindowToVideoSize,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _LargeScreenPlayerMenuSection extends StatelessWidget {
  const _LargeScreenPlayerMenuSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF161922);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: textColor.withValues(alpha: 0.62),
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _LargeScreenPlayerMenuOptionGrid extends StatelessWidget {
  const _LargeScreenPlayerMenuOptionGrid({
    required this.values,
    required this.labelFor,
    required this.selectedValue,
    required this.onSelected,
  });

  final List<double> values;
  final String Function(double value) labelFor;
  final double selectedValue;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((value) {
        final selected = (selectedValue - value).abs() < 0.01;
        return _LargeScreenPlayerMenuChip(
          label: labelFor(value),
          selected: selected,
          onPressed: () => onSelected(value),
        );
      }).toList(),
    );
  }
}

class _LargeScreenPlayerMenuChip extends StatelessWidget {
  const _LargeScreenPlayerMenuChip({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return NipaplayLargeScreenFocusableAction(
      onActivate: onPressed,
      borderRadius: BorderRadius.circular(8),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      style: NipaplayLargeScreenFocusableStyle(
        idleBackgroundDark: selected
            ? AppAccentColors.current.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.08),
        idleBackgroundLight: selected
            ? AppAccentColors.current.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.78),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _LargeScreenPlayerMenuSwitchTile extends StatelessWidget {
  const _LargeScreenPlayerMenuSwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onPressed,
    this.showSwitch = true,
  });

  final IconData icon;
  final String title;
  final bool value;
  final VoidCallback onPressed;
  final bool showSwitch;

  @override
  Widget build(BuildContext context) {
    return _LargeScreenPlayerMenuTile(
      icon: icon,
      title: title,
      trailing: showSwitch
          ? Icon(
              value ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              color: value ? AppAccentColors.current : Colors.white54,
              size: 34,
            )
          : const Icon(Icons.chevron_right_rounded),
      onPressed: onPressed,
    );
  }
}

class _LargeScreenPlayerMenuStepperTile extends StatelessWidget {
  const _LargeScreenPlayerMenuStepperTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    return _LargeScreenPlayerMenuTile(
      icon: icon,
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LargeScreenPlayerMenuIconButton(
            icon: Icons.remove_rounded,
            label: '减少',
            onPressed: onDecrease,
          ),
          SizedBox(
            width: 74,
            child: Text(
              valueLabel,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _LargeScreenPlayerMenuIconButton(
            icon: Icons.add_rounded,
            label: '增加',
            onPressed: onIncrease,
          ),
        ],
      ),
      onPressed: onIncrease,
    );
  }
}

class _LargeScreenPlayerMenuTile extends StatelessWidget {
  const _LargeScreenPlayerMenuTile({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final Widget trailing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NipaplayLargeScreenFocusableAction(
        onActivate: onPressed,
        borderRadius: BorderRadius.circular(8),
        focusScale: 1.015,
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        style: NipaplayLargeScreenFocusableStyle(
          idleBackgroundDark: Colors.white.withValues(alpha: 0.08),
          idleBackgroundLight: Colors.white.withValues(alpha: 0.78),
        ),
        child: Row(
          children: [
            Icon(icon, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _LargeScreenPlayerMenuIconButton extends StatelessWidget {
  const _LargeScreenPlayerMenuIconButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: NipaplayLargeScreenFocusableAction(
        onActivate: onPressed,
        borderRadius: BorderRadius.circular(8),
        focusScale: 1.08,
        padding: const EdgeInsets.all(8),
        style: NipaplayLargeScreenFocusableStyle(
          idleBackgroundDark: Colors.white.withValues(alpha: 0.10),
          idleBackgroundLight: Colors.white.withValues(alpha: 0.70),
        ),
        child: Icon(icon, size: 20),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'player_menu_theme.dart';

/// 画面比例菜单（NipaPlay 样式）。
/// 与其余 NipaPlay 菜单一致：BaseSettingsMenu 深色圆角面板 +
/// SettingsMenuScope 锚定定位 + PlayerMenuTheme 配色/选中高亮/勾选，
/// 替代原先默认 PopupMenuButton（被评价为 PiLiPlus 风格）的列表。
class AspectRatioMenu extends StatelessWidget {
  const AspectRatioMenu({
    super.key,
    required this.onClose,
    this.anchorRect,
    this.standaloneWindow = false,
  });

  final VoidCallback onClose;
  final Rect? anchorRect;
  final bool standaloneWindow;

  static const double _menuWidth = 248;
  static const double _menuRightOffset = 14;
  static const double _menuHeight = 480;

  static const Map<VideoAspectMode, String> _labels = {
    VideoAspectMode.contain: '适应',
    VideoAspectMode.cover: '裁剪',
    VideoAspectMode.fill: '拉伸',
    VideoAspectMode.fitWidth: '等宽',
    VideoAspectMode.fitHeight: '等高',
    VideoAspectMode.none: '原始',
    VideoAspectMode.scaleDown: '限制',
    VideoAspectMode.ratio16x9: '16:9',
    VideoAspectMode.ratio4x3: '4:3',
  };

  @override
  Widget build(BuildContext context) {
    final menu = BaseSettingsMenu(
      title: '画面比例',
      onClose: onClose,
      width: _menuWidth,
      rightOffset: _menuRightOffset,
      height: _menuHeight,
      content: Consumer<VideoPlayerState>(
        builder: (context, videoState, _) {
          final menuColors = PlayerMenuTheme.colorsOf(context);
          final current = videoState.videoAspectMode;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in VideoAspectMode.values)
                _buildItem(
                  menuColors: menuColors,
                  label: _labels[mode] ?? mode.name,
                  selected: mode == current,
                  onTap: () {
                    unawaited(videoState.setVideoAspectMode(mode));
                    onClose();
                  },
                ),
            ],
          );
        },
      ),
    );

    return SettingsMenuScope(
      width: _menuWidth,
      rightOffset: _menuRightOffset,
      showHeader: true,
      lockControlsVisible: true,
      anchorRect: anchorRect,
      showPointer: anchorRect != null,
      height: _menuHeight,
      requestClose: () async => onClose(),
      standaloneWindow: standaloneWindow,
      child: menu,
    );
  }

  Widget _buildItem({
    required PlayerMenuColors menuColors,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? menuColors.selectedBackground : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: menuColors.divider, width: 0.5),
            ),
          ),
          child: Row(
            children: [
              if (selected)
                Icon(
                  Icons.check,
                  size: 18,
                  color: menuColors.selectedForeground,
                )
              else
                const SizedBox(width: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: selected
                      ? menuColors.selectedForeground
                      : menuColors.foreground,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
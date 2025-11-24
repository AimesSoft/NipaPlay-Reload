import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';

class FluentPlaybackRateMenu extends StatelessWidget {
  const FluentPlaybackRateMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackRatePaneController>();

    return Column(
      children: [
        // 当前倍速信息
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '当前倍速',
                    style: FluentTheme.of(context).typography.caption?.copyWith(
                      color: FluentTheme.of(context).resources.textFillColorSecondary,
                    ),
                  ),
                  Text(
                    '${controller.currentRate}x',
                    style: FluentTheme.of(context).typography.bodyStrong,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                controller.isSpeedBoostActive
                    ? '正在倍速播放'
                    : '点击下方选项或长按屏幕倍速播放',
                style: FluentTheme.of(context).typography.caption?.copyWith(
                  color: FluentTheme.of(context).resources.textFillColorTertiary,
                ),
              ),
            ],
          ),
        ),
        
        // 分隔线
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          color: FluentTheme.of(context).resources.controlStrokeColorDefault,
        ),
        
        // 倍速选项列表
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: controller.speedOptions.map((speed) {
              final isSelected = controller.currentRate == speed;
              final isNormalSpeed = speed == 1.0;
              
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: HoverButton(
                  onPressed: () {
                    controller.setPlaybackRate(speed);
                  },
                  builder: (context, states) {
                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? FluentTheme.of(context).accentColor.withValues(alpha: 0.2)
                            : states.isHovered
                                ? FluentTheme.of(context).resources.subtleFillColorSecondary
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: isSelected
                            ? Border.all(
                                color: FluentTheme.of(context).accentColor,
                                width: 1,
                              )
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _getSpeedIcon(speed, isNormalSpeed),
                            size: 16,
                            color: isSelected
                                ? FluentTheme.of(context).accentColor
                                : FluentTheme.of(context).resources.textFillColorPrimary,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${speed}x ${_getSpeedDescription(speed, isNormalSpeed)}',
                              style: FluentTheme.of(context).typography.body?.copyWith(
                                color: isSelected
                                    ? FluentTheme.of(context).accentColor
                                    : FluentTheme.of(context).resources.textFillColorPrimary,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isSelected)
                            Icon(
                              FluentIcons.check_mark,
                              size: 16,
                              color: FluentTheme.of(context).accentColor,
                            ),
                        ],
                      ),
                    );
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  IconData _getSpeedIcon(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return FluentIcons.play;
    } else if (speed < 1.0) {
      return FluentIcons.rewind;
    } else if (speed <= 2.0) {
      return FluentIcons.fast_forward;
    } else {
      return FluentIcons.fast_forward;
    }
  }

  String _getSpeedDescription(double speed, bool isNormalSpeed) {
    if (isNormalSpeed) {
      return '(正常速度)';
    } else if (speed < 1.0) {
      return '(慢速)';
    } else if (speed <= 2.0) {
      return '(快速)';
    } else {
      return '(极速)';
    }
  }
}

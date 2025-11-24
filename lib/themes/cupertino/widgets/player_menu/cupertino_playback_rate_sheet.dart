import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';

import 'cupertino_player_menu_pane_container.dart';

class CupertinoPlaybackRateSheet extends StatelessWidget {
  const CupertinoPlaybackRateSheet({
    super.key,
    required this.onClose,
  });

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackRatePaneController>();

    return CupertinoPlayerMenuPaneContainer(
      title: '播放速度',
      onClose: onClose,
      child: CupertinoScrollbar(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '当前倍速',
                    style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                          fontSize: 15,
                          color: CupertinoColors.systemGrey.resolveFrom(context),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${controller.currentRate}x',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navTitleTextStyle
                        .copyWith(fontSize: 24),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    controller.isSpeedBoostActive
                        ? '正在使用长按倍速'
                        : '点选下方倍速或长按方向键加速',
                    style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                          fontSize: 13,
                          color: CupertinoColors.systemGrey2
                              .resolveFrom(context),
                        ),
                  ),
                ],
              ),
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('选择倍速'),
              children: controller.speedOptions.map((speed) {
                final bool isSelected = controller.currentRate == speed;
                return CupertinoListTile(
                  title: Text('${speed}x'),
                  subtitle: Text(_speedDescription(speed)),
                  trailing: isSelected
                      ? Icon(
                          CupertinoIcons.check_mark,
                          color: CupertinoTheme.of(context).primaryColor,
                        )
                      : null,
                  onTap: () => controller.setPlaybackRate(speed),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  String _speedDescription(double speed) {
    if (speed == 1.0) {
      return '正常速度';
    } else if (speed < 1.0) {
      return '慢速播放';
    } else if (speed <= 2.0) {
      return '快速播放';
    } else {
      return '极速播放';
    }
  }
}

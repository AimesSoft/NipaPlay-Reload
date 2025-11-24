import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';

class CupertinoPlaybackRatePane extends StatelessWidget {
  const CupertinoPlaybackRatePane({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<PlaybackRatePaneController>();

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '当前倍速',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 15,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${controller.currentRate}x',
                  style: CupertinoTheme.of(context)
                      .textTheme
                      .navLargeTitleTextStyle
                      .copyWith(fontSize: 28),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.isSpeedBoostActive
                      ? '正在使用长按倍速'
                      : '点选下方倍速或长按方向键加速',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.systemGrey2.resolveFrom(context),
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
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
            ]),
          ),
        ),
      ],
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

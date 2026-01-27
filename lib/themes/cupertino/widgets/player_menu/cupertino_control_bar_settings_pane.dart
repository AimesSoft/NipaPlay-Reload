import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';

import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoControlBarSettingsPane extends StatelessWidget {
  const CupertinoControlBarSettingsPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  static const List<int> _colorOptions = [
    0xFFFF7274,
    0xFF40C7FF,
    0xFF6DFF69,
    0xFF4CFFB1,
    0xFFFFFFFF,
  ];

  @override
  Widget build(BuildContext context) {
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '控件设置',
                  style:
                      CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  '调整底部进度条及颜色',
                  style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel
                            .resolveFrom(context),
                      ),
                ),
              ],
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            CupertinoListSection.insetGrouped(
              header: const Text('附加控件'),
              children: [
                _buildSwitchTile(
                  context,
                  title: '底部进度条',
                  subtitle: '在屏幕底部显示简洁进度条',
                  value: videoState.minimalProgressBarEnabled,
                  onChanged: videoState.setMinimalProgressBarEnabled,
                ),
                _buildSwitchTile(
                  context,
                  title: '弹幕密度曲线',
                  subtitle: '在进度条上叠加弹幕密度',
                  value: videoState.showDanmakuDensityChart,
                  onChanged: videoState.setShowDanmakuDensityChart,
                ),
              ],
            ),
            if (videoState.minimalProgressBarEnabled)
              CupertinoListSection.insetGrouped(
                header: const Text('颜色选择'),
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Wrap(
                      spacing: 12,
                      children: _colorOptions.map((colorValue) {
                        final bool selected = colorValue ==
                            videoState.minimalProgressBarColor.value;
                        return GestureDetector(
                          onTap: () => videoState
                              .setMinimalProgressBarColor(colorValue),
                          child: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(colorValue),
                              border: Border.all(
                                color: selected
                                    ? CupertinoTheme.of(context).primaryColor
                                    : CupertinoColors.systemGrey,
                                width: selected ? 3 : 1,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 24),
          ]),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: onBack),
        ),
      ],
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CupertinoListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

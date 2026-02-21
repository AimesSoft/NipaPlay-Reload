import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';

class CupertinoSubtitleSettingsPane extends StatelessWidget {
  const CupertinoSubtitleSettingsPane({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SubtitleSettingsPaneController>();
    final double minScale = controller.minScale;
    final double maxScale = controller.maxScale;
    final double scale = controller.subtitleScale.clamp(minScale, maxScale);
    final int divisions = ((maxScale - minScale) / 0.05).round();
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final valueStyle = textTheme.copyWith(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '字幕设置',
              style: CupertinoTheme.of(context)
                  .textTheme
                  .navLargeTitleTextStyle
                  .copyWith(fontSize: 24),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 20),
          sliver: SliverToBoxAdapter(
            child: CupertinoListSection.insetGrouped(
              header: const Text('字幕大小'),
              children: [
                CupertinoListTile(
                  padding:
                      const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
                  title: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '当前大小',
                              style:
                                  textTheme.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${(scale * 100).round()}%',
                            style: valueStyle,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CupertinoPlayerSlider(
                        value: scale,
                        min: minScale,
                        max: maxScale,
                        divisions: divisions,
                        onChanged: controller.setSubtitleScale,
                      ),
                      const SizedBox(height: 6),
                      Text('仅对 Media Kit + libass 生效', style: valueStyle),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: onBack),
        ),
      ],
    );
  }
}

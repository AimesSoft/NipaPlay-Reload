import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';

class CupertinoDanmakuOffsetPane extends StatefulWidget {
  const CupertinoDanmakuOffsetPane({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<CupertinoDanmakuOffsetPane> createState() =>
      _CupertinoDanmakuOffsetPaneState();
}

class _CupertinoDanmakuOffsetPaneState
    extends State<CupertinoDanmakuOffsetPane> {
  static const List<double> _offsetOptions = [
    -10,
    -5,
    -2,
    -1,
    -0.5,
    0,
    0.5,
    1,
    2,
    5,
    10,
  ];

  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatOffset(double offset) {
    if (offset == 0) return '无偏移';
    return offset > 0 ? '+${offset}秒' : '${offset}秒';
  }

  void _applyCustomOffset(SettingsProvider provider) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final value = double.tryParse(text);
    if (value == null || value < -60 || value > 60) {
      BlurSnackBar.show(context, '请输入 -60 到 60 之间的数字');
      return;
    }
    provider.setDanmakuTimeOffset(value);
    _controller.clear();
    BlurSnackBar.show(context, '已设置弹幕偏移为 ${_formatOffset(value)}');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, provider, _) {
        final currentOffset = provider.danmakuTimeOffset;
        return CupertinoBottomSheetContentLayout(
          sliversBuilder: (context, topSpacing) => [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹幕时间偏移',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .navTitleTextStyle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '修正弹幕与视频之间的同步差异',
                      style: CupertinoTheme.of(context)
                          .textTheme
                          .textStyle
                          .copyWith(
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
                  header: const Text('当前偏移'),
                  children: [
                    CupertinoListTile(
                      title: Text(_formatOffset(currentOffset)),
                      subtitle: Text(
                        currentOffset == 0
                            ? '弹幕与视频同步显示'
                            : currentOffset > 0
                                ? '弹幕延迟 ${currentOffset} 秒'
                                : '弹幕提前 ${currentOffset.abs()} 秒',
                      ),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('快速选择'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _offsetOptions.map((value) {
                          final selected =
                              (value - currentOffset).abs() < 0.01;
                          return CupertinoButton(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            color: selected
                                ? CupertinoTheme.of(context).primaryColor
                                : CupertinoColors.systemGrey5,
                            onPressed: () =>
                                provider.setDanmakuTimeOffset(value),
                            child: Text(
                              _formatOffset(value),
                              style: TextStyle(
                                color: selected
                                    ? CupertinoColors.white
                                    : CupertinoColors.label.resolveFrom(
                                        context,
                                      ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('自定义'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CupertinoTextField(
                            controller: _controller,
                            placeholder: '输入 -60 ~ 60 之间的偏移值（秒）',
                            keyboardType: const TextInputType.numberWithOptions(
                              signed: true,
                              decimal: true,
                            ),
                            onSubmitted: (_) => _applyCustomOffset(provider),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: CupertinoButton(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 6),
                              onPressed: () => _applyCustomOffset(provider),
                              child: const Text('应用'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
            CupertinoListSection.insetGrouped(
              children: [
                CupertinoListTile(
                  title: const Text('重置偏移'),
                  subtitle: const Text('恢复为无偏移状态'),
                      trailing: const Icon(CupertinoIcons.refresh),
                      onTap: currentOffset == 0
                          ? null
                          : () {
                              provider.setDanmakuTimeOffset(0);
                              BlurSnackBar.show(context, '已重置弹幕偏移');
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
              ]),
            ),
            SliverToBoxAdapter(
              child: CupertinoPaneBackButton(onPressed: widget.onBack),
            ),
          ],
        );
      },
    );
  }
}

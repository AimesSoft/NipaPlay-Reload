import 'package:flutter/cupertino.dart';

import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/danmaku_history_sync.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoDanmakuSettingsPane extends StatefulWidget {
  const CupertinoDanmakuSettingsPane({
    super.key,
    required this.videoState,
    required this.onBack,
  });

  final VideoPlayerState videoState;
  final VoidCallback onBack;

  @override
  State<CupertinoDanmakuSettingsPane> createState() =>
      _CupertinoDanmakuSettingsPaneState();
}

class _CupertinoDanmakuSettingsPaneState
    extends State<CupertinoDanmakuSettingsPane> {
  final TextEditingController _blockWordController = TextEditingController();
  String? _blockWordError;

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  void _addBlockWord() {
    final word = _blockWordController.text.trim();
    if (word.isEmpty) {
      setState(() => _blockWordError = '屏蔽词不能为空');
      return;
    }

    if (widget.videoState.danmakuBlockWords.contains(word)) {
      setState(() => _blockWordError = '该屏蔽词已存在');
      return;
    }

    widget.videoState.addDanmakuBlockWord(word);
    setState(() {
      _blockWordController.clear();
      _blockWordError = null;
    });
  }

  Future<void> _handleManualMatch() async {
    final result =
        await ManualDanmakuMatcher.instance.showManualMatchDialog(context);
    if (result == null) return;

    final episodeId = result['episodeId']?.toString() ?? '';
    final animeId = result['animeId']?.toString() ?? '';

    if (episodeId.isEmpty || animeId.isEmpty) {
      BlurSnackBar.show(context, '未选择有效的弹幕记录');
      return;
    }

    try {
      final currentPath = widget.videoState.currentVideoPath;
      if (currentPath != null) {
        await DanmakuHistorySync.updateHistoryWithDanmakuInfo(
          videoPath: currentPath,
          episodeId: episodeId,
          animeId: animeId,
          animeTitle: result['animeTitle']?.toString(),
          episodeTitle: result['episodeTitle']?.toString(),
        );
        widget.videoState
            .setAnimeTitle(result['animeTitle']?.toString() ?? '');
        widget.videoState
            .setEpisodeTitle(result['episodeTitle']?.toString() ?? '');
      }
    } catch (_) {}

    widget.videoState.loadDanmaku(episodeId, animeId);
    BlurSnackBar.show(context, '已开始加载弹幕');
  }

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
                  '弹幕设置',
                  style:
                      CupertinoTheme.of(context).textTheme.navTitleTextStyle,
                ),
                const SizedBox(height: 4),
                Text(
                  '控制弹幕开关、透明度、字体大小以及屏蔽词',
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
              header: const Text('显示设置'),
              children: [
                _buildSwitchTile(
                  context,
                  title: '显示弹幕',
                  subtitle: '在画面上渲染实时弹幕',
                  value: widget.videoState.danmakuVisible,
                  onChanged: widget.videoState.setDanmakuVisible,
                ),
                _buildSwitchTile(
                  context,
                  title: '显示密度曲线',
                  subtitle: '在底部进度条显示弹幕密度',
                  value: widget.videoState.showDanmakuDensityChart,
                  onChanged: widget.videoState.setShowDanmakuDensityChart,
                ),
                CupertinoListTile(
                  title: const Text('手动匹配弹幕'),
                  subtitle: const Text('选择指定番剧/剧集的弹幕'),
                  trailing: const Icon(CupertinoIcons.right_chevron),
                  onTap: _handleManualMatch,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('弹幕样式'),
              children: [
                _buildSliderTile(
                  context,
                  title: '透明度',
                  description:
                      '${(widget.videoState.danmakuOpacity * 100).round()}%',
                  value: widget.videoState.danmakuOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  onChanged: widget.videoState.setDanmakuOpacity,
                ),
                _buildSliderTile(
                  context,
                  title: '字体大小',
                  description: '${widget.videoState.danmakuFontSize.round()}px',
                  value: widget.videoState.danmakuFontSize,
                  min: 12.0,
                  max: 36.0,
                  divisions: 24,
                  onChanged: widget.videoState.setDanmakuFontSize,
                ),
                _buildSliderTile(
                  context,
                  title: '滚动速度',
                  description:
                      '${widget.videoState.danmakuSpeedMultiplier.toStringAsFixed(2)}x',
                  value: widget.videoState.danmakuSpeedMultiplier,
                  min: 0.5,
                  max: 2.0,
                  divisions: 15,
                  onChanged: widget.videoState.setDanmakuSpeedMultiplier,
                ),
              ],
            ),
            CupertinoListSection.insetGrouped(
              header: const Text('屏蔽词管理'),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CupertinoTextField(
                        controller: _blockWordController,
                        placeholder: '输入要屏蔽的词语',
                        onSubmitted: (_) => _addBlockWord(),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: CupertinoButton(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          onPressed: _addBlockWord,
                          child: const Text('添加'),
                        ),
                      ),
                      if (_blockWordError != null)
                        Text(
                          _blockWordError!,
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.systemRed
                                .resolveFrom(context),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _buildBlockWordWrap(context),
                    ],
                  ),
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

  Widget _buildSliderTile(
    BuildContext context, {
    required String title,
    required String description,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final double safeValue = value.clamp(min, max);
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final valueStyle = textTheme.copyWith(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );

    return CupertinoListTile(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: textTheme.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(description, style: valueStyle),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoPlayerSlider(
            value: safeValue,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildBlockWordWrap(BuildContext context) {
    if (widget.videoState.danmakuBlockWords.isEmpty) {
      return Text(
        '尚未添加屏蔽词',
        style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: widget.videoState.danmakuBlockWords.map((word) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                CupertinoColors.systemGrey6.resolveFrom(context).withOpacity(0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(word),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => widget.videoState.removeDanmakuBlockWord(word),
                child: const Icon(
                  CupertinoIcons.clear_circled_solid,
                  size: 18,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

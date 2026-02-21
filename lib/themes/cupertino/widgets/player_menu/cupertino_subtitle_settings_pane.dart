import 'package:file_selector/file_selector.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_pane_back_button.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoSubtitleSettingsPane extends StatefulWidget {
  const CupertinoSubtitleSettingsPane({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<CupertinoSubtitleSettingsPane> createState() =>
      _CupertinoSubtitleSettingsPaneState();
}

class _CupertinoSubtitleSettingsPaneState
    extends State<CupertinoSubtitleSettingsPane> {
  final TextEditingController _fontNameController = TextEditingController();
  final TextEditingController _textColorController = TextEditingController();
  final TextEditingController _borderColorController = TextEditingController();
  final TextEditingController _shadowColorController = TextEditingController();
  final FocusNode _fontNameFocus = FocusNode();
  final FocusNode _textColorFocus = FocusNode();
  final FocusNode _borderColorFocus = FocusNode();
  final FocusNode _shadowColorFocus = FocusNode();

  @override
  void dispose() {
    _fontNameController.dispose();
    _textColorController.dispose();
    _borderColorController.dispose();
    _shadowColorController.dispose();
    _fontNameFocus.dispose();
    _textColorFocus.dispose();
    _borderColorFocus.dispose();
    _shadowColorFocus.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    final rgb = color.value & 0x00FFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  Color? _parseHexColor(String text) {
    final cleaned = text.trim().replaceAll('#', '');
    if (cleaned.length != 6) return null;
    final value = int.tryParse(cleaned, radix: 16);
    if (value == null) return null;
    return Color(0xFF000000 | value);
  }

  void _syncController({
    required TextEditingController controller,
    required FocusNode focus,
    required String value,
  }) {
    if (focus.hasFocus) return;
    if (controller.text != value) {
      controller.text = value;
    }
  }

  Future<void> _pickFontFile(VideoPlayerState videoState) async {
    final file = await openFile(
      acceptedTypeGroups: [
        const XTypeGroup(label: 'Font', extensions: ['ttf', 'otf', 'ttc']),
      ],
    );
    if (file == null) return;
    await videoState.importSubtitleFontFile(file.path);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SubtitleSettingsPaneController>();
    final videoState = controller.videoState;
    _syncController(
      controller: _fontNameController,
      focus: _fontNameFocus,
      value: videoState.subtitleFontName,
    );
    _syncController(
      controller: _textColorController,
      focus: _textColorFocus,
      value: _colorToHex(videoState.subtitleColor),
    );
    _syncController(
      controller: _borderColorController,
      focus: _borderColorFocus,
      value: _colorToHex(videoState.subtitleBorderColor),
    );
    _syncController(
      controller: _shadowColorController,
      focus: _shadowColorFocus,
      value: _colorToHex(videoState.subtitleShadowColor),
    );

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '字幕设置',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle
                        .copyWith(fontSize: 24),
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  onPressed: videoState.resetSubtitleSettings,
                  child: const Text('回到默认'),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 12),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed([
              CupertinoListSection.insetGrouped(
                header: const Text('基础设置'),
                children: [
                  _buildOverrideModeTile(context, videoState),
                  _buildSliderTile(
                    context,
                    title: '字幕大小',
                    description:
                        '${(controller.subtitleScale * 100).round()}%',
                    value: controller.subtitleScale,
                    min: controller.minScale,
                    max: controller.maxScale,
                    divisions: ((controller.maxScale - controller.minScale) /
                            0.05)
                        .round(),
                    onChanged: controller.setSubtitleScale,
                  ),
                  _buildSliderTile(
                    context,
                    title: '字幕延迟',
                    description:
                        '${videoState.subtitleDelaySeconds >= 0 ? '+' : ''}${videoState.subtitleDelaySeconds.toStringAsFixed(1)}s',
                    value: videoState.subtitleDelaySeconds,
                    min: -5.0,
                    max: 5.0,
                    divisions: 100,
                    onChanged: videoState.setSubtitleDelaySeconds,
                  ),
                  _buildSliderTile(
                    context,
                    title: '字幕位置',
                    description: '${videoState.subtitlePosition.toStringAsFixed(0)}%',
                    value: videoState.subtitlePosition,
                    min: VideoPlayerState.minSubtitlePosition,
                    max: VideoPlayerState.maxSubtitlePosition,
                    divisions: 100,
                    onChanged: videoState.setSubtitlePosition,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('对齐与边距'),
                children: [
                  _buildAlignXTile(context, videoState),
                  _buildAlignYTile(context, videoState),
                  _buildSliderTile(
                    context,
                    title: '水平边距',
                    description: '${videoState.subtitleMarginX.toStringAsFixed(0)}px',
                    value: videoState.subtitleMarginX,
                    min: 0,
                    max: 200,
                    divisions: 200,
                    onChanged: videoState.setSubtitleMarginX,
                  ),
                  _buildSliderTile(
                    context,
                    title: '垂直边距',
                    description: '${videoState.subtitleMarginY.toStringAsFixed(0)}px',
                    value: videoState.subtitleMarginY,
                    min: 0,
                    max: 200,
                    divisions: 200,
                    onChanged: videoState.setSubtitleMarginY,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('样式'),
                children: [
                  _buildSliderTile(
                    context,
                    title: '不透明度',
                    description: '${(videoState.subtitleOpacity * 100).round()}%',
                    value: videoState.subtitleOpacity,
                    min: 0,
                    max: 1,
                    divisions: 20,
                    onChanged: videoState.setSubtitleOpacity,
                  ),
                  _buildSliderTile(
                    context,
                    title: '描边大小',
                    description: videoState.subtitleBorderSize.toStringAsFixed(1),
                    value: videoState.subtitleBorderSize,
                    min: 0,
                    max: 10,
                    divisions: 100,
                    onChanged: videoState.setSubtitleBorderSize,
                  ),
                  _buildSliderTile(
                    context,
                    title: '阴影偏移',
                    description:
                        videoState.subtitleShadowOffset.toStringAsFixed(1),
                    value: videoState.subtitleShadowOffset,
                    min: 0,
                    max: 10,
                    divisions: 100,
                    onChanged: videoState.setSubtitleShadowOffset,
                  ),
                  _buildToggleTile(
                    context,
                    title: '粗体',
                    value: videoState.subtitleBold,
                    onChanged: videoState.setSubtitleBold,
                  ),
                  _buildToggleTile(
                    context,
                    title: '斜体',
                    value: videoState.subtitleItalic,
                    onChanged: videoState.setSubtitleItalic,
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('颜色'),
                children: [
                  _buildColorTile(
                    context,
                    label: '文字颜色',
                    controller: _textColorController,
                    focusNode: _textColorFocus,
                    color: videoState.subtitleColor,
                    onSubmit: (value) {
                      final parsed = _parseHexColor(value);
                      if (parsed != null) {
                        videoState.setSubtitleColor(parsed);
                      }
                    },
                  ),
                  _buildColorTile(
                    context,
                    label: '描边颜色',
                    controller: _borderColorController,
                    focusNode: _borderColorFocus,
                    color: videoState.subtitleBorderColor,
                    onSubmit: (value) {
                      final parsed = _parseHexColor(value);
                      if (parsed != null) {
                        videoState.setSubtitleBorderColor(parsed);
                      }
                    },
                  ),
                  _buildColorTile(
                    context,
                    label: '阴影颜色',
                    controller: _shadowColorController,
                    focusNode: _shadowColorFocus,
                    color: videoState.subtitleShadowColor,
                    onSubmit: (value) {
                      final parsed = _parseHexColor(value);
                      if (parsed != null) {
                        videoState.setSubtitleShadowColor(parsed);
                      }
                    },
                  ),
                ],
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('字体'),
                children: [
                  CupertinoListTile(
                    title: const Text('字体名称'),
                    subtitle: CupertinoTextField(
                      controller: _fontNameController,
                      focusNode: _fontNameFocus,
                      placeholder: '留空为默认',
                      onSubmitted: videoState.setSubtitleFontName,
                    ),
                  ),
                  CupertinoListTile(
                    title: const Text('导入字体文件'),
                    trailing: CupertinoButton(
                      padding: EdgeInsets.zero,
                      onPressed: () => _pickFontFile(videoState),
                      child: const Text('选择'),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: CupertinoPaneBackButton(onPressed: widget.onBack),
        ),
      ],
    );
  }

  Widget _buildOverrideModeTile(
      BuildContext context, VideoPlayerState videoState) {
    final Map<SubtitleStyleOverrideMode, String> labels = {
      SubtitleStyleOverrideMode.auto: '自动',
      SubtitleStyleOverrideMode.none: '保持原样',
      SubtitleStyleOverrideMode.scale: '仅缩放',
      SubtitleStyleOverrideMode.force: '自定义样式',
    };
    return CupertinoListTile(
      title: const Text('样式覆盖'),
      trailing: CupertinoSegmentedControl<SubtitleStyleOverrideMode>(
        groupValue: videoState.subtitleOverrideMode,
        onValueChanged: videoState.setSubtitleOverrideMode,
        children: {
          for (final entry in labels.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(entry.value),
            ),
        },
      ),
    );
  }

  Widget _buildAlignXTile(BuildContext context, VideoPlayerState videoState) {
    final Map<SubtitleAlignX, String> labels = {
      SubtitleAlignX.left: '左',
      SubtitleAlignX.center: '中',
      SubtitleAlignX.right: '右',
    };
    return CupertinoListTile(
      title: const Text('水平对齐'),
      trailing: CupertinoSegmentedControl<SubtitleAlignX>(
        groupValue: videoState.subtitleAlignX,
        onValueChanged: videoState.setSubtitleAlignX,
        children: {
          for (final entry in labels.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(entry.value),
            ),
        },
      ),
    );
  }

  Widget _buildAlignYTile(BuildContext context, VideoPlayerState videoState) {
    final Map<SubtitleAlignY, String> labels = {
      SubtitleAlignY.top: '上',
      SubtitleAlignY.center: '中',
      SubtitleAlignY.bottom: '下',
    };
    return CupertinoListTile(
      title: const Text('垂直对齐'),
      trailing: CupertinoSegmentedControl<SubtitleAlignY>(
        groupValue: videoState.subtitleAlignY,
        onValueChanged: videoState.setSubtitleAlignY,
        children: {
          for (final entry in labels.entries)
            entry.key: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(entry.value),
            ),
        },
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
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleTile(
    BuildContext context, {
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return CupertinoListTile(
      title: Text(title),
      trailing: CupertinoSwitch(
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildColorTile(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Color color,
    required ValueChanged<String> onSubmit,
  }) {
    return CupertinoListTile(
      title: Text(label),
      trailing: SizedBox(
        width: 120,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: CupertinoColors.systemGrey),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 80,
              child: CupertinoTextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: '#FFFFFF',
                onSubmitted: onSubmit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

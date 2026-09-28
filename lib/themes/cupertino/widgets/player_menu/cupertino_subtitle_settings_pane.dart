import 'package:file_selector/file_selector.dart';
import 'dart:io' as io;
import 'package:flutter/material.dart' show ActionChip;
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show
        AdaptiveButton,
        AdaptiveButtonSize,
        AdaptiveButtonStyle,
        AdaptiveSegmentedControl;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class CupertinoSubtitleSettingsPane extends StatefulWidget {
  const CupertinoSubtitleSettingsPane({super.key});

  @override
  State<CupertinoSubtitleSettingsPane> createState() =>
      _CupertinoSubtitleSettingsPaneState();
}

class _CupertinoSubtitleSettingsPaneState
    extends State<CupertinoSubtitleSettingsPane> {
  final TextEditingController _subtitleDelayController =
      TextEditingController();
  final TextEditingController _fontNameController = TextEditingController();
  final FocusNode _subtitleDelayFocus = FocusNode();
  final FocusNode _fontNameFocus = FocusNode();
  bool _subtitleDelayDirty = false;
  double? _subtitleDelayPreviewValue;
  // 字幕位置滑块预览值：onChanged 只更新本地状态（跟手不碰内核），
  // 松手 onChangeEnd 才提交 sub-pos，避免每帧 setProperty 卡顿。
  double? _subtitlePositionPreviewValue;
  String? _fontImportMessage;
  Future<List<String>>? _fontLibraryFuture;

  void _refreshFontLibrary() {
    setState(() {
      _fontLibraryFuture = null;
    });
  }

  @override
  void dispose() {
    _subtitleDelayController.dispose();
    _fontNameController.dispose();
    _subtitleDelayFocus.dispose();
    _fontNameFocus.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    final rgb = color.toARGB32() & 0x00FFFFFF;
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
    // 多选导入：导入后不自动套用字体名，由用户从字体库列表自由选择
    final files = await openFiles(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'Font',
          extensions: const ['ttf', 'otf', 'ttc'],
          uniformTypeIdentifiers: const [
            'public.truetype-font',
            'public.opentype-font',
            'public.font',
            'public.data',
            'public.item',
          ],
        ),
      ],
    );
    if (files.isEmpty) return;
    var count = 0;
    for (final f in files) {
      await videoState.importSubtitleFontFile(f.path, applyName: false);
      count++;
    }
    if (!mounted) return;
    setState(() {
      _fontImportMessage = '已导入 $count 个字体文件';
    });
    _refreshFontLibrary();
  }

  Future<void> _pickFontDirectory(VideoPlayerState videoState) async {
    // iOS 上 file_selector 的 getDirectoryPath 不受支持，改为多选字体文件
    if (io.Platform.isIOS) {
      final files = await openFiles(
        acceptedTypeGroups: [
          XTypeGroup(
            label: 'Font',
            extensions: const ['ttf', 'otf', 'ttc'],
            uniformTypeIdentifiers: const [
              'public.truetype-font',
              'public.opentype-font',
              'public.font',
              'public.data',
              'public.item'
            ],
          ),
        ],
      );
      if (files.isEmpty) return;
      var count = 0;
      for (final f in files) {
        // 多选导入：不自动套用当前字体名，让用户从字体库列表自由选择
        await videoState.importSubtitleFontFile(f.path, applyName: false);
        count++;
      }
      if (!mounted) return;
      setState(() {
        _fontImportMessage = '已导入 $count 个字体文件';
      });
      _refreshFontLibrary();
      return;
    }
    final directory = await getDirectoryPath();
    if (directory == null) return;
    final count = await videoState.importSubtitleFontDirectory(directory);
    if (!mounted) return;
    if (count > 0) {
      setState(() {
        _fontImportMessage = '已从该文件夹导入 $count 个字体文件';
      });
    } else if (count == 0) {
      setState(() {
        _fontImportMessage = '未在目录中找到字体文件';
      });
    }
    _refreshFontLibrary();
  }

  double _currentSubtitleDelayDisplayValue(VideoPlayerState videoState) {
    return _subtitleDelayPreviewValue ?? videoState.subtitleDelaySeconds;
  }

  String _getFontDirDisplayText(VideoPlayerState videoState) {
    final fontDir = videoState.subtitleFontDir;
    if (fontDir.isEmpty) return '未配置过字体库，使用默认设置';

    // 根据路径特征动态推断来源
    if (fontDir.contains('subtitle_fonts')) {
      return '$fontDir [字体库]';
    } else {
      return '$fontDir [本地fonts]';
    }
  }

  void _syncSubtitleDelayController(VideoPlayerState videoState) {
    if (_subtitleDelayFocus.hasFocus || _subtitleDelayDirty) return;
    final value =
        _formatDelayInput(_currentSubtitleDelayDisplayValue(videoState));
    if (_subtitleDelayController.text != value) {
      _subtitleDelayController.text = value;
    }
  }

  String _trimTrailingZeros(String value) {
    if (!value.contains('.')) return value;
    return value
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatDelayInput(double value) {
    if (value.abs() < 0.0001) return '0';
    return _trimTrailingZeros(value.toStringAsFixed(3));
  }

  String _formatDelayDisplay(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${value.toStringAsFixed(1)}s';
  }

  String _normalizeNumberInput(String value) {
    return value
        .trim()
        .replaceAll('，', '.')
        .replaceAll(',', '.')
        .replaceAll('＋', '+')
        .replaceAll('－', '-');
  }

  String _buildSubtitleDelayLimitHint(VideoPlayerState videoState) {
    final limit = _formatDelayInput(videoState.subtitleDelayCustomLimitSeconds);
    if (videoState.hasSubtitleDelayDurationLimit) {
      return '可输入 -$limit ~ +$limit 秒（按当前视频时长限制）';
    }
    return '可输入 -$limit ~ +$limit 秒（当前时长未就绪时先按默认范围处理）';
  }

  Future<void> _applyCustomSubtitleDelay(VideoPlayerState videoState) async {
    final input = _normalizeNumberInput(_subtitleDelayController.text);
    if (input.isEmpty) {
      BlurSnackBar.show(context, '请输入字幕延迟秒数');
      return;
    }

    final value = double.tryParse(input);
    if (value == null) {
      BlurSnackBar.show(context, '请输入有效数字');
      return;
    }
    if (!value.isFinite) {
      BlurSnackBar.show(context, '请输入有限数字');
      return;
    }

    final limit = videoState.subtitleDelayCustomLimitSeconds;
    if (value.abs() - limit > 0.0001) {
      final limitText = _formatDelayInput(limit);
      BlurSnackBar.show(context, '当前视频仅支持 -$limitText ~ +$limitText 秒');
      return;
    }

    await videoState.setSubtitleDelaySeconds(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _subtitleDelayDirty = false;
      _subtitleDelayPreviewValue = null;
    });
    BlurSnackBar.show(context, '已设置字幕延迟为 ${_formatDelayDisplay(value)}');
  }

  void _handleSubtitleDelayInputChanged(String _) {
    if (_subtitleDelayDirty) return;
    setState(() {
      _subtitleDelayDirty = true;
      _subtitleDelayPreviewValue = null;
    });
  }

  void _handleSubtitleDelaySliderStart(
    VideoPlayerState videoState,
    double _,
  ) {
    FocusScope.of(context).unfocus();
    setState(() {
      _subtitleDelayDirty = false;
      _subtitleDelayPreviewValue = videoState.subtitleDelaySeconds;
    });
  }

  void _handleSubtitleDelaySliderChanged(double value) {
    setState(() {
      _subtitleDelayPreviewValue = value;
    });
  }

  Future<void> _handleSubtitleDelaySliderEnd(
    VideoPlayerState videoState,
    double value,
  ) async {
    await videoState.setSubtitleDelaySeconds(value);
    if (!mounted) return;
    setState(() {
      _subtitleDelayDirty = false;
      _subtitleDelayPreviewValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SubtitleSettingsPaneController>();
    // 监听 VideoPlayerState：点选字体/颜色后芯片与输入框立即反映最新值
    // （此前只 watch PaneController，重开面板前看不到变化）。
    context.watch<VideoPlayerState>();
    final videoState = controller.videoState;
    _syncSubtitleDelayController(videoState);
    _syncController(
      controller: _fontNameController,
      focus: _fontNameFocus,
      value: videoState.subtitleFontName,
    );

    // 键盘弹出时把可滚动内容底部垫高一个键盘高度，否则面板底部的
    // 延迟/字体/hex 输入框会被键盘盖住无法查看与编辑。
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerRight,
              child: AdaptiveButton(
                label: '回到默认',
                style: AdaptiveButtonStyle.glass,
                size: AdaptiveButtonSize.small,
                onPressed: controller.supportsFullSubtitleStyle
                    ? videoState.resetSubtitleSettings
                    : controller.resetSubtitleScale,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.only(bottom: 12 + keyboardInset),
          sliver: SliverList(
            delegate: SliverChildListDelegate.fixed(
              controller.supportsFullSubtitleStyle
                  ? _buildFullSubtitleSections(
                      context,
                      controller,
                      videoState,
                    )
                  : _buildScaleOnlySubtitleSections(context, controller),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildScaleOnlySubtitleSections(
    BuildContext context,
    SubtitleSettingsPaneController controller,
  ) {
    return [
      AdaptivePlayerMenuSection(
        header: const Text('基础设置'),
        children: [
          _buildSubtitleScaleTile(context, controller),
        ],
      ),
    ];
  }

  List<Widget> _buildFullSubtitleSections(
    BuildContext context,
    SubtitleSettingsPaneController controller,
    VideoPlayerState videoState,
  ) {
    return [
      AdaptivePlayerMenuSection(
        header: const Text('基础设置'),
        children: [
          _buildOverrideModeTile(context, videoState),
          _buildSubtitleScaleTile(context, controller),
          _buildSliderTile(
            context,
            title: '字幕延迟',
            description: _formatDelayDisplay(
              _currentSubtitleDelayDisplayValue(videoState),
            ),
            value: _currentSubtitleDelayDisplayValue(videoState),
            min: videoState.subtitleDelaySliderMinSeconds,
            max: videoState.subtitleDelaySliderMaxSeconds,
            divisions: videoState.subtitleDelaySliderDivisions,
            onChangeStart: (value) =>
                _handleSubtitleDelaySliderStart(videoState, value),
            onChanged: _handleSubtitleDelaySliderChanged,
            onChangeEnd: (value) =>
                _handleSubtitleDelaySliderEnd(videoState, value),
          ),
          _buildSubtitleDelayInputTile(context, videoState),
          _buildSliderTile(
            context,
            title: '字幕位置',
            description:
                '${(_subtitlePositionPreviewValue ?? videoState.subtitlePosition).toStringAsFixed(0)}%',
            value: _subtitlePositionPreviewValue ?? videoState.subtitlePosition,
            min: VideoPlayerState.minSubtitlePosition,
            max: VideoPlayerState.maxSubtitlePosition,
            divisions: 100,
            // 拖动过程只更新本地预览值（滑块跟手、零内核调用）；
            // 松手才提交 sub-pos——内嵌 ASS 每帧 setProperty 会全量
            // 重排导致视频卡顿，这是此前「滑动卡顿」的根因。
            onChangeStart: (_) {
              setState(() {
                _subtitlePositionPreviewValue = videoState.subtitlePosition;
              });
            },
            onChanged: (value) {
              setState(() {
                _subtitlePositionPreviewValue = value;
              });
            },
            onChangeEnd: (value) async {
              await videoState.setSubtitlePosition(value);
              if (!mounted) return;
              setState(() {
                _subtitlePositionPreviewValue = null;
              });
            },
          ),
        ],
      ),
      AdaptivePlayerMenuSection(
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
      AdaptivePlayerMenuSection(
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
            description: videoState.subtitleShadowOffset.toStringAsFixed(1),
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
      AdaptivePlayerMenuSection(
        header: const Text('颜色'),
        children: [
          _buildColorTile(
            context,
            label: '文字颜色',
            color: videoState.subtitleColor,
            onPicked: (parsed) => videoState.setSubtitleColor(parsed),
          ),
          _buildColorTile(
            context,
            label: '描边颜色',
            color: videoState.subtitleBorderColor,
            onPicked: (parsed) => videoState.setSubtitleBorderColor(parsed),
          ),
          _buildColorTile(
            context,
            label: '阴影颜色',
            color: videoState.subtitleShadowColor,
            onPicked: (parsed) => videoState.setSubtitleShadowColor(parsed),
          ),
        ],
      ),
      AdaptivePlayerMenuSection(
        header: const Text('字体'),
        children: [
          AdaptivePlayerMenuTile(
            title: const Text('字体名称'),
            subtitle: AdaptivePlayerMenuTextField(
              controller: _fontNameController,
              focusNode: _fontNameFocus,
              placeholder: '留空为默认',
              onSubmitted: videoState.setSubtitleFontName,
            ),
          ),
          AdaptivePlayerMenuTile(
            title: const Text('导入字体文件'),
            trailing: AdaptiveButton(
              label: '选择',
              style: AdaptiveButtonStyle.glass,
              size: AdaptiveButtonSize.small,
              onPressed: () => _pickFontFile(videoState),
            ),
          ),
          AdaptivePlayerMenuTile(
            title: const Text('导入字体文件夹'),
            trailing: AdaptiveButton(
              label: '选择',
              style: AdaptiveButtonStyle.glass,
              size: AdaptiveButtonSize.small,
              onPressed: () => _pickFontDirectory(videoState),
            ),
          ),
          if (_fontImportMessage != null)
            AdaptivePlayerMenuTile(
              title: Text(
                _fontImportMessage!,
                style: const TextStyle(
                  color: CupertinoColors.activeBlue,
                  fontSize: 13,
                ),
              ),
            ),
          if (videoState.subtitleFontDir.isNotEmpty)
            AdaptivePlayerMenuTile(
              title: const Text('当前字体目录'),
              subtitle: Text(_getFontDirDisplayText(videoState)),
            ),
          FutureBuilder<List<String>>(
            future: _fontLibraryFuture ??= videoState.listSubtitleFonts(),
            builder: (context, snapshot) {
              final fonts = snapshot.data ?? const <String>[];
              if (fonts.isEmpty) {
                return const SizedBox.shrink();
              }
              // 多选感知：高亮按逗号分隔列表判断，点击为切换（与其他
              // 字幕面板的多选语义一致），不再是单值覆盖。
              final selectedFonts = videoState.subtitleFontName
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toSet();
              return AdaptivePlayerMenuTile(
                title: const Text('字体库（点击多选）'),
                subtitle: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final name in fonts)
                          ActionChip(
                            label: Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                color: selectedFonts.contains(name)
                                    ? CupertinoColors.activeBlue
                                    : CupertinoColors.label,
                              ),
                            ),
                            backgroundColor: CupertinoColors.systemGrey5,
                            side: BorderSide(
                              color: selectedFonts.contains(name)
                                  ? CupertinoColors.activeBlue
                                  : CupertinoColors.systemGrey4,
                            ),
                            onPressed: () {
                              final next = selectedFonts.contains(name)
                                  ? selectedFonts
                                      .where((e) => e != name)
                                      .join(',')
                                  : [...selectedFonts, name].join(',');
                              videoState.setSubtitleFontName(next);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          AdaptivePlayerMenuTile(
            title: const Text('清除字体设置'),
            trailing: AdaptiveButton(
              label: '清除',
              style: AdaptiveButtonStyle.glass,
              size: AdaptiveButtonSize.small,
              onPressed: () {
                videoState.setSubtitleFontName('');
                videoState.setSubtitleFontDir('');
              },
            ),
          ),
          AdaptivePlayerMenuTile(
            title: const Text('清理字体缓存'),
            trailing: AdaptiveButton(
              label: '清理',
              style: AdaptiveButtonStyle.glass,
              size: AdaptiveButtonSize.small,
              onPressed: () async {
                await videoState.clearSubtitleFontCache();
                if (!mounted) return;
                setState(() {
                  _fontImportMessage = '已清空字体库（subtitle_fonts 目录）';
                });
                _refreshFontLibrary();
              },
            ),
          ),
        ],
      ),
    ];
  }

  Widget _buildSubtitleScaleTile(
    BuildContext context,
    SubtitleSettingsPaneController controller,
  ) {
    return _buildSliderTile(
      context,
      title: '字幕大小',
      description: '${(controller.subtitleScale * 100).round()}%',
      value: controller.subtitleScale,
      min: controller.minScale,
      max: controller.maxScale,
      divisions: ((controller.maxScale - controller.minScale) / 0.05).round(),
      onChanged: controller.setSubtitleScale,
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
    return _buildSegmentedTile<SubtitleStyleOverrideMode>(
      context,
      title: '样式覆盖',
      groupValue: videoState.subtitleOverrideMode,
      labels: labels,
      onValueChanged: videoState.setSubtitleOverrideMode,
    );
  }

  Widget _buildAlignXTile(BuildContext context, VideoPlayerState videoState) {
    final Map<SubtitleAlignX, String> labels = {
      SubtitleAlignX.left: '左',
      SubtitleAlignX.center: '中',
      SubtitleAlignX.right: '右',
    };
    return _buildSegmentedTile<SubtitleAlignX>(
      context,
      title: '水平对齐',
      groupValue: videoState.subtitleAlignX,
      labels: labels,
      onValueChanged: videoState.setSubtitleAlignX,
    );
  }

  Widget _buildAlignYTile(BuildContext context, VideoPlayerState videoState) {
    final Map<SubtitleAlignY, String> labels = {
      SubtitleAlignY.top: '上',
      SubtitleAlignY.center: '中',
      SubtitleAlignY.bottom: '下',
    };
    return _buildSegmentedTile<SubtitleAlignY>(
      context,
      title: '垂直对齐',
      groupValue: videoState.subtitleAlignY,
      labels: labels,
      onValueChanged: videoState.setSubtitleAlignY,
    );
  }

  Widget _buildSegmentedTile<T extends Object>(
    BuildContext context, {
    required String title,
    required T groupValue,
    required Map<T, String> labels,
    required ValueChanged<T> onValueChanged,
  }) {
    final textStyle = CupertinoTheme.of(context).textTheme.textStyle;
    return AdaptivePlayerMenuTile(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 14),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textStyle.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: AdaptiveSegmentedControl(
              labels: labels.values.toList(growable: false),
              selectedIndex: labels.keys.toList(growable: false).indexOf(
                    groupValue,
                  ),
              onValueChanged: (index) =>
                  onValueChanged(labels.keys.elementAt(index)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitleDelayInputTile(
    BuildContext context,
    VideoPlayerState videoState,
  ) {
    final secondaryColor = CupertinoColors.secondaryLabel.resolveFrom(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '手动输入秒数',
            style: CupertinoTheme.of(context)
                .textTheme
                .textStyle
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            '滑块用于快速微调，正值延后，负值提前',
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 13,
                  color: secondaryColor,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            _buildSubtitleDelayLimitHint(videoState),
            style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                  fontSize: 13,
                  color: secondaryColor,
                ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AdaptivePlayerMenuTextField(
                  controller: _subtitleDelayController,
                  focusNode: _subtitleDelayFocus,
                  placeholder: '例如 -12.5 或 8',
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  suffix: const Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Text('秒'),
                  ),
                  onChanged: _handleSubtitleDelayInputChanged,
                  onSubmitted: (_) => _applyCustomSubtitleDelay(videoState),
                ),
              ),
              const SizedBox(width: 10),
              AdaptiveButton(
                label: '应用',
                style: AdaptiveButtonStyle.glass,
                onPressed: () => _applyCustomSubtitleDelay(videoState),
              ),
            ],
          ),
        ],
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
    ValueChanged<double>? onChangeStart,
    ValueChanged<double>? onChangeEnd,
  }) {
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final valueStyle = textTheme.copyWith(
      fontSize: 13,
      color: CupertinoColors.secondaryLabel.resolveFrom(context),
    );
    return AdaptivePlayerMenuTile(
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
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
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
    return AdaptivePlayerMenuTile(
      title: Text(title),
      trailing: AdaptivePlayerMenuSwitch(
        value: value,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  /// 颜色行：hex 文本按钮（点击弹出输入窗口）+ 色块按钮（HSV 调色板）。
  /// 之前 trailing 内嵌 110pt 输入框，在横屏播放器右下角的面板里键盘一顶
  /// 就被卡在画面角落；改为点击弹出独立对话框，Dialog/AppSheet 自带键盘
  /// 避让，输入框始终显示在键盘上方。
  Widget _buildColorTile(
    BuildContext context, {
    required String label,
    required Color color,
    required ValueChanged<Color> onPicked,
  }) {
    return AdaptivePlayerMenuTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AdaptiveButton.child(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            onPressed: () {
              _showHexInputDialog(context, label, color, onPicked);
            },
            child: Text(
              _colorToHex(color),
              key: const Key('subtitleColorValueButton'),
              style: const TextStyle(
                fontSize: 13,
                color: CupertinoColors.white,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 4),
          AdaptiveButton.child(
            padding: EdgeInsets.zero,
            minSize: const Size(44, 44),
            onPressed: () {
              // 点色块打开全色调色盘（HSV），选色后应用。
              _showColorPickerDialog(context, color, (picked) {
                debugPrint(
                  '[SubtitleColor] 色板选色: ${_colorToHex(picked)}',
                );
                onPicked(picked);
              });
            },
            child: Container(
              key: const Key('subtitleColorSwatch'),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: CupertinoColors.systemGrey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单行 hex 输入弹窗：实时解析（onChanged 输入即应用，与旧内嵌框
  /// 语义一致）。对话框自带键盘避让，不会卡在屏幕角落。
  Future<void> _showHexInputDialog(
    BuildContext context,
    String label,
    Color initial,
    ValueChanged<Color> onPicked,
  ) async {
    final controller = TextEditingController(text: _colorToHex(initial));
    await showCupertinoDialog<void>(
      context: context,
      builder: (dialogContext) {
        return CupertinoAlertDialog(
          title: Text(label),
          content: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: AdaptivePlayerMenuTextField(
              controller: controller,
              autofocus: true,
              maxLength: 7,
              placeholder: '#FFFFFF',
              onChanged: (value) {
                final parsed = _parseHexColor(value);
                if (parsed != null) {
                  onPicked(parsed);
                }
              },
              onSubmitted: (_) => Navigator.of(dialogContext).pop(),
            ),
          ),
          actions: [
            AdaptiveButton.child(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
    controller.dispose();
  }

  /// 全色调色板对话框（HSV 三滑块：色相/饱和度/亮度 + 实时预览）
  Future<void> _showColorPickerDialog(
    BuildContext context,
    Color initial,
    ValueChanged<Color> onPicked,
  ) async {
    var hsv = HSVColor.fromColor(initial);
    // 对话框内 hex 输入与 HSV 滑块双向同步：改滑块刷新文本框，
    // 输入合法 hex 反过来刷新滑块与预览。
    final hexController = TextEditingController(text: _colorToHex(initial));
    final picked = await showCupertinoDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return CupertinoAlertDialog(
              title: const Text('选择颜色'),
              content: SizedBox(
                width: 300,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hsv.toColor(),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: CupertinoColors.systemGrey),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildHsvSliderRow(
                      '色相',
                      hsv.hue,
                      0,
                      360,
                      (v) => setDialogState(() {
                        hsv = hsv.withHue(v);
                        hexController.text = _colorToHex(hsv.toColor());
                      }),
                    ),
                    _buildHsvSliderRow(
                      '饱和',
                      hsv.saturation,
                      0,
                      1,
                      (v) => setDialogState(() {
                        hsv = hsv.withSaturation(v);
                        hexController.text = _colorToHex(hsv.toColor());
                      }),
                    ),
                    _buildHsvSliderRow(
                      '亮度',
                      hsv.value,
                      0,
                      1,
                      (v) => setDialogState(() {
                        hsv = hsv.withValue(v);
                        hexController.text = _colorToHex(hsv.toColor());
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const SizedBox(
                          width: 60,
                          child: Text('十六进制', style: TextStyle(fontSize: 13)),
                        ),
                        Expanded(
                          child: AdaptivePlayerMenuTextField(
                            controller: hexController,
                            placeholder: '#FFFFFF',
                            onChanged: (text) {
                              final parsed = _parseHexColor(text);
                              if (parsed != null) {
                                setDialogState(
                                  () => hsv = HSVColor.fromColor(parsed),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                AdaptiveButton.child(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                AdaptiveButton.child(
                  onPressed: () {
                    // hex 输入合法时以 hex 为准（允许只改 hex 不动滑块）；
                    // 非法输入保持 HSV 当前值。
                    final fromHex = _parseHexColor(hexController.text);
                    Navigator.pop(dialogContext, fromHex ?? hsv.toColor());
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    hexController.dispose();
    if (picked != null) {
      onPicked(picked);
    }
  }

  Widget _buildHsvSliderRow(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
  ) {
    return Row(
      children: [
        SizedBox(
            width: 36,
            child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(
          child: CupertinoSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

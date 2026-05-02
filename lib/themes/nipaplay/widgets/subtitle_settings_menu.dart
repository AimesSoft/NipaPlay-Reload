import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/player_menu/player_menu_pane_controllers.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'blur_button.dart';
import 'blur_snackbar.dart';
import 'blur_dropdown.dart';
import 'fluent_settings_switch.dart';
import 'settings_hint_text.dart';
import 'settings_slider.dart';

class SubtitleSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final ValueChanged<bool>? onHoverChanged;

  const SubtitleSettingsMenu({
    super.key,
    required this.onClose,
    this.onHoverChanged,
  });

  @override
  State<SubtitleSettingsMenu> createState() => _SubtitleSettingsMenuState();
}

class _SubtitleSettingsMenuState extends State<SubtitleSettingsMenu> {
  final TextEditingController _subtitleDelayController =
      TextEditingController();
  final TextEditingController _fontNameController = TextEditingController();
  final TextEditingController _textColorController = TextEditingController();
  final TextEditingController _borderColorController = TextEditingController();
  final TextEditingController _shadowColorController = TextEditingController();
  final FocusNode _subtitleDelayFocus = FocusNode();
  final FocusNode _fontNameFocus = FocusNode();
  final FocusNode _textColorFocus = FocusNode();
  final FocusNode _borderColorFocus = FocusNode();
  final FocusNode _shadowColorFocus = FocusNode();
  String? _subtitleDelayError;
  bool _subtitleDelayDirty = false;
  double? _subtitleDelayPreviewValue;
  String? _fontImportMessage;

  @override
  void dispose() {
    _subtitleDelayController.dispose();
    _fontNameController.dispose();
    _textColorController.dispose();
    _borderColorController.dispose();
    _shadowColorController.dispose();
    _subtitleDelayFocus.dispose();
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
        const XTypeGroup(
          label: 'Font',
          extensions: ['ttf', 'otf', 'ttc'],
        ),
      ],
    );
    if (file == null) return;
    await videoState.importSubtitleFontFile(file.path);
  }

  Future<void> _pickFontDirectory(VideoPlayerState videoState) async {
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
  }

  double _currentSubtitleDelayDisplayValue(VideoPlayerState videoState) {
    return _subtitleDelayPreviewValue ?? videoState.subtitleDelaySeconds;
  }

  String _getFontDirDisplayText(VideoPlayerState videoState) {
    final source = videoState.subtitleFontDirSource;
    if (source == SubtitleFontDirSource.localFonts) {
      return '当前字体目录: ${videoState.subtitleFontDir} [本地fonts]';
    } else if (source == SubtitleFontDirSource.customLibrary) {
      return '当前字体目录: ${videoState.subtitleFontDir} [字体库]';
    }
    return '当前字体目录: ${videoState.subtitleFontDir}';
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
      return '手动输入范围：-$limit ~ +$limit 秒（按当前视频时长限制）';
    }
    return '手动输入范围：-$limit ~ +$limit 秒（当前时长未就绪时先按默认范围处理）';
  }

  Future<void> _applyCustomSubtitleDelay(VideoPlayerState videoState) async {
    final input = _normalizeNumberInput(_subtitleDelayController.text);
    if (input.isEmpty) {
      setState(() {
        _subtitleDelayError = '请输入字幕延迟秒数';
      });
      return;
    }

    final value = double.tryParse(input);
    if (value == null) {
      setState(() {
        _subtitleDelayError = '请输入有效的数字';
      });
      return;
    }

    final limit = videoState.subtitleDelayCustomLimitSeconds;
    if (value.abs() - limit > 0.0001) {
      final limitText = _formatDelayInput(limit);
      setState(() {
        _subtitleDelayError = '当前视频仅支持 -$limitText ~ +$limitText 秒';
      });
      return;
    }

    await videoState.setSubtitleDelaySeconds(value);
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _subtitleDelayError = null;
      _subtitleDelayDirty = false;
      _subtitleDelayPreviewValue = null;
    });
    BlurSnackBar.show(context, '已设置字幕延迟为 ${_formatDelayDisplay(value)}');
  }

  void _handleSubtitleDelayInputChanged(String _) {
    if (_subtitleDelayDirty && _subtitleDelayError == null) return;
    setState(() {
      _subtitleDelayDirty = true;
      _subtitleDelayError = null;
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
      _subtitleDelayError = null;
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
      _subtitleDelayError = null;
      _subtitleDelayPreviewValue = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SubtitleSettingsPaneController>(
      builder: (context, controller, child) {
        final videoState = controller.videoState;
        _syncSubtitleDelayController(videoState);
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

        return BaseSettingsMenu(
          title: '字幕设置',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          extraButton: TextButton(
            onPressed: () => videoState.resetSubtitleSettings(),
            child: const Text(
              '回到默认',
              locale: Locale('zh', 'CN'),
              style: TextStyle(color: Colors.white),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildOverrideModeSection(videoState),
              _buildScaleSection(controller),
              _buildDelaySection(videoState),
              _buildPositionSection(videoState),
              _buildAlignSection(videoState),
              _buildMarginSection(videoState),
              _buildOpacitySection(videoState),
              _buildBorderShadowSection(videoState),
              _buildStyleSwitches(videoState),
              _buildColorSection(videoState),
              _buildFontSection(videoState),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverrideModeSection(VideoPlayerState videoState) {
    final items = SubtitleStyleOverrideMode.values
        .map<DropdownMenuItemData<SubtitleStyleOverrideMode>>((mode) {
      final String label;
      switch (mode) {
        case SubtitleStyleOverrideMode.auto:
          label = '自动';
          break;
        case SubtitleStyleOverrideMode.none:
          label = '保持原样';
          break;
        case SubtitleStyleOverrideMode.scale:
          label = '仅缩放';
          break;
        case SubtitleStyleOverrideMode.force:
          label = '自定义样式';
          break;
      }
      return DropdownMenuItemData<SubtitleStyleOverrideMode>(
        value: mode,
        title: label,
        isSelected: videoState.subtitleOverrideMode == mode,
      );
    }).toList();

    return _buildOptionButtonsSection(
      title: '样式覆盖',
      description: 'ASS 字幕样式覆盖策略',
      items: items,
      onSelected: videoState.setSubtitleOverrideMode,
    );
  }

  Widget _buildScaleSection(SubtitleSettingsPaneController controller) {
    return _buildSliderSection(
      label: '字幕大小',
      value: controller.subtitleScale,
      min: controller.minScale,
      max: controller.maxScale,
      step: 0.05,
      displayTextBuilder: (v) => '${(v * 100).round()}%',
      onChanged: controller.setSubtitleScale,
      hint: '缩放 libass 字幕大小',
    );
  }

  Widget _buildDelaySection(VideoPlayerState videoState) {
    final displayValue = _currentSubtitleDelayDisplayValue(videoState);
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSlider(
            value: displayValue,
            onChangeStart: (value) =>
                _handleSubtitleDelaySliderStart(videoState, value),
            onChanged: _handleSubtitleDelaySliderChanged,
            onChangeEnd: (value) =>
                _handleSubtitleDelaySliderEnd(videoState, value),
            label: '字幕延迟',
            displayTextBuilder: _formatDelayDisplay,
            min: videoState.subtitleDelaySliderMinSeconds,
            max: videoState.subtitleDelaySliderMaxSeconds,
            step: VideoPlayerState.subtitleDelayStep,
          ),
          const SizedBox(height: 8),
          Text(
            '手动输入秒数',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _subtitleDelayController,
                  focusNode: _subtitleDelayFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9+\-.,，＋－]'),
                    ),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: '例如 -12.5 或 8',
                    hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                    filled: true,
                    fillColor: Colors.white.withOpacity(0.08),
                    suffixText: '秒',
                    suffixStyle: const TextStyle(color: Colors.white70),
                    errorText: _subtitleDelayError,
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.6)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.redAccent),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedErrorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Colors.redAccent),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) => _applyCustomSubtitleDelay(videoState),
                  onChanged: _handleSubtitleDelayInputChanged,
                ),
              ),
              const SizedBox(width: 12),
              BlurButton(
                text: '应用',
                icon: Icons.check,
                onTap: () => _applyCustomSubtitleDelay(videoState),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const SettingsHintText('滑块用于快速微调，正值延后，负值提前'),
          SettingsHintText(_buildSubtitleDelayLimitHint(videoState)),
        ],
      ),
    );
  }

  Widget _buildPositionSection(VideoPlayerState videoState) {
    return _buildSliderSection(
      label: '字幕位置',
      value: videoState.subtitlePosition,
      min: VideoPlayerState.minSubtitlePosition,
      max: VideoPlayerState.maxSubtitlePosition,
      step: 1.0,
      displayTextBuilder: (v) => '${v.toStringAsFixed(0)}%',
      onChanged: videoState.setSubtitlePosition,
      hint: '0=顶部，100=底部',
    );
  }

  Widget _buildAlignSection(VideoPlayerState videoState) {
    final alignXItems = SubtitleAlignX.values
        .map<DropdownMenuItemData<SubtitleAlignX>>((align) {
      final label = switch (align) {
        SubtitleAlignX.left => '左对齐',
        SubtitleAlignX.center => '居中',
        SubtitleAlignX.right => '右对齐',
      };
      return DropdownMenuItemData<SubtitleAlignX>(
        value: align,
        title: label,
        isSelected: videoState.subtitleAlignX == align,
      );
    }).toList();
    final alignYItems = SubtitleAlignY.values
        .map<DropdownMenuItemData<SubtitleAlignY>>((align) {
      final label = switch (align) {
        SubtitleAlignY.top => '顶部',
        SubtitleAlignY.center => '垂直居中',
        SubtitleAlignY.bottom => '底部',
      };
      return DropdownMenuItemData<SubtitleAlignY>(
        value: align,
        title: label,
        isSelected: videoState.subtitleAlignY == align,
      );
    }).toList();

    return Column(
      children: [
        _buildOptionButtonsSection(
          title: '水平对齐',
          description: '字幕水平位置',
          items: alignXItems,
          onSelected: videoState.setSubtitleAlignX,
        ),
        _buildOptionButtonsSection(
          title: '垂直对齐',
          description: '字幕垂直位置',
          items: alignYItems,
          onSelected: videoState.setSubtitleAlignY,
        ),
      ],
    );
  }

  Widget _buildMarginSection(VideoPlayerState videoState) {
    return Column(
      children: [
        _buildSliderSection(
          label: '水平边距',
          value: videoState.subtitleMarginX,
          min: 0,
          max: 200,
          step: 1.0,
          displayTextBuilder: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: videoState.setSubtitleMarginX,
          hint: '字幕与左右边缘距离',
        ),
        _buildSliderSection(
          label: '垂直边距',
          value: videoState.subtitleMarginY,
          min: 0,
          max: 200,
          step: 1.0,
          displayTextBuilder: (v) => '${v.toStringAsFixed(0)}px',
          onChanged: videoState.setSubtitleMarginY,
          hint: '字幕与上下边缘距离',
        ),
      ],
    );
  }

  Widget _buildOpacitySection(VideoPlayerState videoState) {
    return _buildSliderSection(
      label: '字幕不透明度',
      value: videoState.subtitleOpacity,
      min: 0,
      max: 1,
      step: 0.05,
      displayTextBuilder: (v) => '${(v * 100).round()}%',
      onChanged: videoState.setSubtitleOpacity,
      hint: '整体字幕透明度',
    );
  }

  Widget _buildBorderShadowSection(VideoPlayerState videoState) {
    return Column(
      children: [
        _buildSliderSection(
          label: '描边大小',
          value: videoState.subtitleBorderSize,
          min: 0,
          max: 10,
          step: 0.1,
          displayTextBuilder: (v) => '${v.toStringAsFixed(1)}',
          onChanged: videoState.setSubtitleBorderSize,
          hint: '描边越大越清晰',
        ),
        _buildSliderSection(
          label: '阴影偏移',
          value: videoState.subtitleShadowOffset,
          min: 0,
          max: 10,
          step: 0.1,
          displayTextBuilder: (v) => '${v.toStringAsFixed(1)}',
          onChanged: videoState.setSubtitleShadowOffset,
          hint: '阴影偏移大小',
        ),
      ],
    );
  }

  Widget _buildStyleSwitches(VideoPlayerState videoState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          _buildSwitchRow(
            label: '粗体',
            value: videoState.subtitleBold,
            onChanged: videoState.setSubtitleBold,
          ),
          const SizedBox(height: 8),
          _buildSwitchRow(
            label: '斜体',
            value: videoState.subtitleItalic,
            onChanged: videoState.setSubtitleItalic,
          ),
        ],
      ),
    );
  }

  Widget _buildColorSection(VideoPlayerState videoState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildColorInputRow(
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
          const SizedBox(height: 8),
          _buildColorInputRow(
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
          const SizedBox(height: 8),
          _buildColorInputRow(
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
          const SizedBox(height: 4),
          const SettingsHintText('输入颜色十六进制，例如 #FFFFFF'),
        ],
      ),
    );
  }

  Widget _buildFontSection(VideoPlayerState videoState) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '字幕字体',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fontNameController,
            focusNode: _fontNameFocus,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '输入字体名称（留空为默认）',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onSubmitted: (value) => videoState.setSubtitleFontName(value),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BlurButton(
                  text: '选择字体文件',
                  icon: Icons.font_download_outlined,
                  onTap: () => _pickFontFile(videoState),
                  expandHorizontally: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BlurButton(
                  text: '导入字体文件夹',
                  icon: Icons.folder_outlined,
                  onTap: () => _pickFontDirectory(videoState),
                  expandHorizontally: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BlurButton(
                  text: '清除字体设置',
                  icon: Icons.clear,
                  onTap: () {
                    videoState.setSubtitleFontName('');
                    videoState.setSubtitleFontDir('');
                  },
                  expandHorizontally: true,
                ),
              ),
            ],
          ),
          if (_fontImportMessage != null) ...[
            const SizedBox(height: 4),
            SettingsHintText(_fontImportMessage!),
          ],
          if (videoState.subtitleFontDir.isNotEmpty) ...[
            const SizedBox(height: 4),
            SettingsHintText(
              _getFontDirDisplayText(videoState),
            ),
          ],
          const SizedBox(height: 4),
          const SettingsHintText('字体名称需与系统或导入字体匹配'),
        ],
      ),
    );
  }

  Widget _buildSliderSection({
    required String label,
    required double value,
    required double min,
    required double max,
    double? step,
    required String Function(double) displayTextBuilder,
    required ValueChanged<double> onChanged,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSlider(
            value: value,
            onChanged: onChanged,
            label: label,
            displayTextBuilder: displayTextBuilder,
            min: min,
            max: max,
            step: step,
          ),
          const SizedBox(height: 4),
          SettingsHintText(hint),
        ],
      ),
    );
  }

  Widget _buildOptionButtonsSection<T>({
    required String title,
    required String description,
    required List<DropdownMenuItemData<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items
                .map((item) => _buildOptionButton(item, onSelected))
                .toList(),
          ),
          const SizedBox(height: 4),
          SettingsHintText(description),
        ],
      ),
    );
  }

  Widget _buildOptionButton<T>(
    DropdownMenuItemData<T> item,
    ValueChanged<T> onSelected,
  ) {
    final isSelected = item.isSelected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(item.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(isSelected ? 0.15 : 0.05),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withOpacity(isSelected ? 0.5 : 0.2),
              width: 1,
            ),
          ),
          child: Text(
            item.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
        FluentSettingsSwitch(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildColorInputRow({
    required String label,
    required TextEditingController controller,
    required FocusNode focusNode,
    required Color color,
    required ValueChanged<String> onSubmit,
  }) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white24),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        SizedBox(
          width: 110,
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              filled: true,
              fillColor: Colors.white.withOpacity(0.08),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(6),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.6)),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onSubmitted: onSubmit,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'base_settings_menu.dart';
import 'player_menu_theme.dart';
import 'settings_hint_text.dart';
import 'dart:convert';
import 'dart:io';
import 'blur_button.dart';
import 'blur_dropdown.dart';
import 'fluent_settings_switch.dart';
import 'settings_slider.dart';
import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/utils/danmaku_history_sync.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/providers/ui_theme_provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/text_input_dialog.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

enum _DanmakuExportFormat { json, xml }

class DanmakuSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;
  final VideoPlayerState videoState;
  final ValueChanged<bool>? onHoverChanged;

  const DanmakuSettingsMenu({
    super.key,
    required this.onClose,
    required this.videoState,
    this.onHoverChanged,
  });

  @override
  State<DanmakuSettingsMenu> createState() => _DanmakuSettingsMenuState();
}

class _DanmakuSettingsMenuState extends State<DanmakuSettingsMenu> {
  static const List<double> _danmakuDisplayAreaOptions = <double>[
    0.0,
    0.125,
    0.25,
    0.33,
    0.67,
    1.0,
  ];
  static final Map<double, String> _danmakuDisplayAreaLabels = <double, String>{
    0.0: '单行显示',
    0.125: '1/8 屏幕',
    0.25: '1/4 屏幕',
    0.33: '1/3 屏幕',
    0.67: '2/3 屏幕',
    1.0: '全屏',
  };

  final TextEditingController _blockWordController = TextEditingController();
  bool _hasBlockWordError = false;
  String? _blockWordErrorMessage;
  bool _isSavingDanmaku = false;

  @override
  void dispose() {
    _blockWordController.dispose();
    super.dispose();
  }

  List<String> _splitBlockWords(String input) {
    final result = <String>[];
    final current = StringBuffer();
    bool inRegex = false;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];

      if (char == '/' && !inRegex) {
        final prev = current.toString();
        if (prev.isNotEmpty && RegExp(r'\S$').hasMatch(prev)) {
          inRegex = true;
        }
        current.write(char);
      } else if (char == '/' && inRegex) {
        inRegex = false;
        current.write(char);
      } else if (char == ',' && !inRegex) {
        final word = current.toString().trim();
        if (word.isNotEmpty) {
          result.add(word);
        }
        current.clear();
      } else {
        current.write(char);
      }
    }

    final lastWord = current.toString().trim();
    if (lastWord.isNotEmpty) {
      result.add(lastWord);
    }

    return result;
  }

  void _addBlockWordFromInput(String input) {
    final trimmed = input.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }

    final rawWords = _splitBlockWords(trimmed);
    final validWords = <String>[];
    final duplicateWords = <String>[];
    final emptyWords = <String>[];

    for (final w in rawWords) {
      final word = w.trim();
      if (word.isEmpty) {
        emptyWords.add(w);
        continue;
      }
      if (widget.videoState.danmakuBlockWords.contains(word)) {
        duplicateWords.add(word);
      } else {
        validWords.add(word);
      }
    }

    for (final word in validWords) {
      widget.videoState.addDanmakuBlockWord(word);
    }

    String? errorMessage;
    if (validWords.isEmpty && duplicateWords.isEmpty && emptyWords.isNotEmpty) {
      errorMessage = '所有输入的词都是空的';
    } else if (validWords.isEmpty && duplicateWords.isNotEmpty) {
      errorMessage = duplicateWords.length == 1
          ? '该屏蔽词已存在'
          : '这些屏蔽词已存在：${duplicateWords.join('、')}';
    } else if (validWords.isNotEmpty) {
      final successMessage = validWords.length == 1
          ? '已添加屏蔽词：${validWords.first}'
          : '已添加 ${validWords.length} 个屏蔽词';
      BlurSnackBar.show(context, successMessage);
      _blockWordController.clear();
      setState(() {
        _hasBlockWordError = false;
        _blockWordErrorMessage = '';
      });
      return;
    }

    if (errorMessage != null) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = errorMessage;
      });
    }
  }

  Future<void> _showBlockWordInputDialog() async {
    final result = await TextInputDialog.show(
      context,
      title: '添加屏蔽词',
      subtitle: '输入要屏蔽的关键词，批量添加请用逗号隔开（支持正则，以"规则名称/表达式/"形式输入）',
      hintText: '请输入文本',
      minLines: 4,
    );

    if (result != null && result.isNotEmpty) {
      _addBlockWordFromInput(result);
    }
  }

  void _addBlockWord() {
    if (globals.isMobilePlatform) {
      _showBlockWordInputDialog();
      return;
    }

    final input = _blockWordController.text.trim();

    if (input.isEmpty) {
      setState(() {
        _hasBlockWordError = true;
        _blockWordErrorMessage = '屏蔽词不能为空';
      });
      return;
    }

    _addBlockWordFromInput(input);
  }

  Future<void> _saveDanmaku(_DanmakuExportFormat format) async {
    if (_isSavingDanmaku) return;

    final exportList = widget.videoState.collectDanmakuForExport();
    if (exportList.isEmpty) {
      if (mounted) {
        BlurSnackBar.show(context, '当前没有可保存的弹幕');
      }
      return;
    }

    if (mounted) {
      setState(() => _isSavingDanmaku = true);
    } else {
      _isSavingDanmaku = true;
    }

    try {
      final extension = format == _DanmakuExportFormat.xml ? 'xml' : 'json';
      final fileName =
          _buildDanmakuExportFileName(widget.videoState, extension);
      final savePath = await getSaveLocation(
        suggestedName: fileName,
        acceptedTypeGroups: [
          XTypeGroup(
            label: extension.toUpperCase(),
            extensions: [extension],
          ),
        ],
      );

      if (savePath == null) {
        return;
      }

      final content = format == _DanmakuExportFormat.xml
          ? widget.videoState.buildDanmakuXmlExport(exportList)
          : widget.videoState.buildDanmakuJsonExport(exportList);
      final file = File(savePath.path);
      await file.writeAsString(content, encoding: utf8);

      if (mounted) {
        BlurSnackBar.show(context, '弹幕已保存到: ${savePath.path}');
      }
    } catch (e) {
      if (mounted) {
        BlurSnackBar.show(context, '保存弹幕失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingDanmaku = false);
      } else {
        _isSavingDanmaku = false;
      }
    }
  }

  String _buildDanmakuExportFileName(
    VideoPlayerState videoState,
    String extension,
  ) {
    final title = videoState.animeTitle?.trim();
    final fallback = videoState.currentVideoPath == null
        ? 'danmaku'
        : p.basenameWithoutExtension(videoState.currentVideoPath!);
    final baseName = (title == null || title.isEmpty) ? fallback : title;
    final timestamp = _formatTimestamp(DateTime.now());
    return '${baseName}_danmaku_$timestamp.$extension';
  }

  String _formatTimestamp(DateTime time) {
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${time.year}'
        '${twoDigits(time.month)}'
        '${twoDigits(time.day)}_'
        '${twoDigits(time.hour)}'
        '${twoDigits(time.minute)}'
        '${twoDigits(time.second)}';
  }

  bool get _isNext2Kernel =>
      DanmakuKernelFactory.getKernelType() == DanmakuRenderEngine.next2;

  bool get _isDfmPlusKernel =>
      DanmakuKernelFactory.getKernelType() == DanmakuRenderEngine.dfmPlus;

  bool get _usesBinaryDanmakuEffectToggles =>
      _isNext2Kernel || _isDfmPlusKernel;

  String get _binaryDanmakuEffectKernelName =>
      _isDfmPlusKernel ? 'DFM+' : 'Next2';

  Future<void> _pickDanmakuFontFile(VideoPlayerState videoState) async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Font',
          extensions: ['ttf', 'otf', 'ttc', 'otc'],
        ),
      ],
    );
    if (selected == null) return;

    final success = await videoState.importDanmakuFontFile(selected.path);
    if (!mounted) return;
    if (success) {
      BlurSnackBar.show(context, '已应用字体: ${p.basename(selected.path)}');
    } else {
      BlurSnackBar.show(context, '字体加载失败，请选择有效的字体文件');
    }
  }

  Future<void> _resetDanmakuFont(VideoPlayerState videoState) async {
    await videoState.resetDanmakuFont();
    if (!mounted) return;
    BlurSnackBar.show(context, '已恢复为系统默认字体');
  }

  String _danmakuFontLabel(VideoPlayerState videoState) {
    final fontPath = videoState.danmakuFontFilePath.trim();
    if (fontPath.isEmpty) return '系统默认字体';
    return p.basename(fontPath);
  }

  String _shadowStyleLabel(DanmakuShadowStyle style) {
    switch (style) {
      case DanmakuShadowStyle.none:
        return '无阴影';
      case DanmakuShadowStyle.soft:
        return '柔和阴影';
      case DanmakuShadowStyle.medium:
        return '标准阴影';
      case DanmakuShadowStyle.strong:
        return '增强阴影';
    }
  }

  String _outlineStyleLabel(DanmakuOutlineStyle style) {
    switch (style) {
      case DanmakuOutlineStyle.none:
        return '无描边';
      case DanmakuOutlineStyle.stroke:
        return '标准描边';
      case DanmakuOutlineStyle.uniform:
        return '均匀描边';
    }
  }

  double _snapDanmakuDisplayArea(double value) {
    double best = _danmakuDisplayAreaOptions.first;
    double bestDiff = (value - best).abs();
    for (final option in _danmakuDisplayAreaOptions.skip(1)) {
      final diff = (value - option).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = option;
      }
    }
    return best;
  }

  String _danmakuDisplayAreaText(double value) {
    final snapped = _snapDanmakuDisplayArea(value);
    return _danmakuDisplayAreaLabels[snapped] ?? '全屏';
  }

  // 检查是否是正则表达式规则格式: 规则名称/表达式/
  bool _isRegexRule(String word) {
    if (!word.contains('/')) return false;
    final parts = word.split('/');
    return parts.length >= 3 && parts.first.isNotEmpty && parts.last.isEmpty;
  }

  // 获取屏蔽词的显示文本
  String _getDisplayText(String word) {
    if (_isRegexRule(word)) {
      final firstSlash = word.indexOf('/');
      final name = word.substring(0, firstSlash);
      return '规则：$name';
    }
    return word;
  }

  // 构建屏蔽词展示UI
  Widget _buildBlockWordsList() {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        if (videoState.danmakuBlockWords.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            child: Text(
              '暂无屏蔽词',
              style:
                  TextStyle(color: menuColors.disabledForeground, fontSize: 14),
            ),
          );
        }

        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: videoState.danmakuBlockWords.map((word) {
            return Container(
              decoration: BoxDecoration(
                color: menuColors.controlBackground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: menuColors.controlBorder,
                  width: 0.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getDisplayText(word),
                      style: TextStyle(
                        color: menuColors.foreground,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => videoState.removeDanmakuBlockWord(word),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: menuColors.secondaryForeground,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildDanmakuStyleSection(VideoPlayerState videoState) {
    final isErikaPlayerKernel =
        PlayerFactory.getKernelType() == PlayerKernelType.erika;
    final showBinaryDanmakuEffectToggles =
        isErikaPlayerKernel || _usesBinaryDanmakuEffectToggles;
    final binaryDanmakuEffectKernelName =
        isErikaPlayerKernel ? 'Erika' : _binaryDanmakuEffectKernelName;
    final showMergeToggle = isErikaPlayerKernel ||
        DanmakuKernelFactory.getKernelType() != DanmakuRenderEngine.canvas;

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '弹幕样式',
            style: TextStyle(
              color: PlayerMenuTheme.colorsOf(context).foreground,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildSliderSection(
            label: '弹幕不透明度',
            value: videoState.danmakuOpacity,
            min: 0,
            max: 1,
            step: 0.01,
            displayTextBuilder: (value) => '${(value * 100).round()}%',
            onChanged: videoState.setDanmakuOpacity,
            hint: '调整弹幕文字透明度',
          ),
          _buildSliderSection(
            label: '弹幕字体大小',
            value: videoState.danmakuFontSize <= 0
                ? videoState.actualDanmakuFontSize
                : videoState.danmakuFontSize,
            min: 12,
            max: 60,
            step: 0.5,
            displayTextBuilder: (value) => '${value.toStringAsFixed(1)}px',
            onChanged: videoState.setDanmakuFontSize,
            onChangeEnd: (value) =>
                videoState.setDanmakuFontSize(value, commit: true),
            hint: '调整弹幕文字大小，轨道间距会自动适配',
          ),
          _buildFontSection(videoState),
          _buildOutlineSection(
            videoState,
            useBinaryToggle: showBinaryDanmakuEffectToggles,
            kernelName: binaryDanmakuEffectKernelName,
          ),
          if (!isErikaPlayerKernel) _buildShadowSection(videoState),
          _buildSliderSection(
            label: '滚动弹幕速度',
            value: videoState.danmakuSpeedMultiplier,
            min: 0.5,
            max: 2,
            step: 0.05,
            displayTextBuilder: (value) => '${value.toStringAsFixed(2)}x',
            onChanged: videoState.setDanmakuSpeedMultiplier,
            hint: '向左减慢滚动弹幕速度，向右加快',
          ),
          _buildDisplayAreaSection(videoState),
          if (showMergeToggle)
            _buildSwitchSection(
              label: '合并相同弹幕',
              value: videoState.mergeDanmaku,
              onChanged: videoState.setMergeDanmaku,
              hint: '将内容相同的弹幕合并为一条显示',
            ),
        ],
      ),
    );
  }

  Widget _buildDanmakuBlockModeSection(VideoPlayerState videoState) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '弹幕屏蔽',
            style: TextStyle(
              color: PlayerMenuTheme.colorsOf(context).foreground,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          _buildSwitchSection(
            label: '屏蔽顶部弹幕',
            value: videoState.blockTopDanmaku,
            onChanged: videoState.setBlockTopDanmaku,
            hint: '不显示顶部固定弹幕',
          ),
          _buildSwitchSection(
            label: '屏蔽底部弹幕',
            value: videoState.blockBottomDanmaku,
            onChanged: videoState.setBlockBottomDanmaku,
            hint: '不显示底部固定弹幕',
          ),
          _buildSwitchSection(
            label: '屏蔽滚动弹幕',
            value: videoState.blockScrollDanmaku,
            onChanged: videoState.setBlockScrollDanmaku,
            hint: '不显示从右向左滚动的弹幕',
          ),
        ],
      ),
    );
  }

  Widget _buildSliderSection({
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required String Function(double) displayTextBuilder,
    required ValueChanged<double> onChanged,
    ValueChanged<double>? onChangeEnd,
    required String hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSlider(
            value: value,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
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

  Widget _buildFontSection(VideoPlayerState videoState) {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '字体选择',
            style: TextStyle(
              color: menuColors.foreground,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '当前字体：${_danmakuFontLabel(videoState)}',
            style: TextStyle(
              color: menuColors.secondaryForeground,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: BlurButton(
                  text: '选择字体文件',
                  icon: Icons.folder_open,
                  onTap: () => _pickDanmakuFontFile(videoState),
                  expandHorizontally: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: BlurButton(
                  text: '恢复默认',
                  icon: Icons.restart_alt,
                  onTap: () => _resetDanmakuFont(videoState),
                  expandHorizontally: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const SettingsHintText('支持 ttf、otf、ttc、otc 字体文件'),
        ],
      ),
    );
  }

  Widget _buildOutlineSection(
    VideoPlayerState videoState, {
    required bool useBinaryToggle,
    required String kernelName,
  }) {
    if (useBinaryToggle) {
      return _buildSwitchSection(
        label: '弹幕描边',
        value: videoState.next2DanmakuOutlineWidth > 0.0,
        onChanged: (value) {
          videoState.setNext2DanmakuOutlineWidth(value ? 1.0 : 0.0);
        },
        hint: '开启后为 $kernelName 弹幕添加描边',
      );
    }

    final items = DanmakuOutlineStyle.values
        .map(
          (style) => DropdownMenuItemData<DanmakuOutlineStyle>(
            title: _outlineStyleLabel(style),
            value: style,
            isSelected: videoState.danmakuOutlineStyle == style,
          ),
        )
        .toList();

    return _buildOptionButtonsSection(
      title: '弹幕描边',
      description: '选择弹幕文字外缘的描边方式',
      items: items,
      onSelected: videoState.setDanmakuOutlineStyle,
    );
  }

  Widget _buildShadowSection(VideoPlayerState videoState) {
    if (_usesBinaryDanmakuEffectToggles) {
      return _buildSwitchSection(
        label: '弹幕阴影',
        value: videoState.danmakuShadowStyle != DanmakuShadowStyle.none,
        onChanged: (value) {
          videoState.setDanmakuShadowStyle(
            value ? DanmakuShadowStyle.strong : DanmakuShadowStyle.none,
          );
        },
        hint: '开启后为 $_binaryDanmakuEffectKernelName 弹幕添加阴影',
      );
    }

    final items = DanmakuShadowStyle.values
        .map(
          (style) => DropdownMenuItemData<DanmakuShadowStyle>(
            title: _shadowStyleLabel(style),
            value: style,
            isSelected: videoState.danmakuShadowStyle == style,
          ),
        )
        .toList();

    return _buildOptionButtonsSection(
      title: '弹幕阴影',
      description: '选择弹幕文字的阴影强度',
      items: items,
      onSelected: videoState.setDanmakuShadowStyle,
    );
  }

  Widget _buildDisplayAreaSection(VideoPlayerState videoState) {
    final selectedArea = _snapDanmakuDisplayArea(videoState.danmakuDisplayArea);
    final items = _danmakuDisplayAreaOptions
        .map(
          (area) => DropdownMenuItemData<double>(
            title: _danmakuDisplayAreaText(area),
            value: area,
            isSelected: selectedArea == area,
          ),
        )
        .toList();

    return _buildOptionButtonsSection(
      title: '轨道显示区域',
      description: '设置弹幕轨道在屏幕上的显示范围',
      items: items,
      onSelected: (value) {
        videoState.setDanmakuDisplayArea(_snapDanmakuDisplayArea(value));
      },
    );
  }

  Widget _buildOptionButtonsSection<T>({
    required String title,
    required String description,
    required List<DropdownMenuItemData<T>> items,
    required ValueChanged<T> onSelected,
  }) {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: menuColors.foreground,
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
    final menuColors = PlayerMenuTheme.colorsOf(context);
    final isSelected = item.isSelected;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => onSelected(item.value),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? menuColors.selectedBackground
                : menuColors.controlBackground,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? menuColors.selectedBorder
                  : menuColors.controlBorder,
              width: 1,
            ),
          ),
          child: Text(
            item.title,
            style: TextStyle(
              color: isSelected
                  ? menuColors.selectedForeground
                  : menuColors.foreground,
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchSection({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String hint,
  }) {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: menuColors.foreground,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FluentSettingsSwitch(value: value, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 4),
          SettingsHintText(hint),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final menuColors = PlayerMenuTheme.colorsOf(context);
        return BaseSettingsMenu(
          title: '弹幕设置',
          onClose: widget.onClose,
          onHoverChanged: widget.onHoverChanged,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 弹幕开关
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '显示弹幕',
                          style: TextStyle(
                            color: menuColors.foreground,
                            fontSize: 14,
                          ),
                        ),
                        FluentSettingsSwitch(
                          value: videoState.danmakuVisible,
                          onChanged: (value) {
                            videoState.setDanmakuVisible(value);
                          },
                        ),
                      ],
                    ),
                    const SettingsHintText('开启后在视频上显示弹幕内容'),
                  ],
                ),
              ),
              _buildDanmakuStyleSection(videoState),
              _buildDanmakuBlockModeSection(videoState),
              // 手动匹配弹幕
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BlurButton(
                      text: '手动匹配弹幕',
                      icon: Icons.search,
                      onTap: () async {
                        debugPrint('=== 弹幕设置菜单：点击手动匹配弹幕按钮 ===');
                        print('=== 强制输出：手动匹配弹幕按钮被点击！ ===');
                        final rootContext =
                            Navigator.of(context, rootNavigator: true).context;
                        final uiThemeProvider = Provider.of<UIThemeProvider>(
                          context,
                          listen: false,
                        );
                        if (uiThemeProvider.isCupertinoTheme) {
                          final menuScope = SettingsMenuScope.maybeOf(context);
                          if (menuScope?.requestClose != null) {
                            await menuScope!.requestClose!();
                          }
                        }
                        final videoState = widget.videoState;
                        final initialVideoPath = videoState.currentVideoPath;
                        final String? initialSearchKeyword = initialVideoPath ==
                                null
                            ? null
                            : (initialVideoPath.startsWith('jellyfin://') ||
                                    initialVideoPath.startsWith('emby://'))
                                ? (videoState.animeTitle?.trim().isNotEmpty ==
                                        true
                                    ? videoState.animeTitle!.trim()
                                    : null)
                                : p.basenameWithoutExtension(initialVideoPath);
                        final result = await ManualDanmakuMatcher.instance
                            .showManualMatchDialog(
                          uiThemeProvider.isCupertinoTheme
                              ? rootContext
                              : context,
                          initialVideoTitle: initialSearchKeyword,
                        );

                        if (result != null) {
                          if (videoState.isDisposed ||
                              videoState.currentVideoPath != initialVideoPath) {
                            debugPrint('视频已切换或播放器已销毁，取消加载弹幕');
                            return;
                          }

                          // 如果用户选择了弹幕，重新加载弹幕
                          final episodeId =
                              result['episodeId']?.toString() ?? '';
                          final animeId = result['animeId']?.toString() ?? '';

                          if (episodeId.isNotEmpty && animeId.isNotEmpty) {
                            // 调用新的弹幕历史同步方法来更新历史记录
                            try {
                              final currentVideoPath =
                                  videoState.currentVideoPath;
                              if (currentVideoPath != null) {
                                await DanmakuHistorySync
                                    .updateHistoryWithDanmakuInfo(
                                  videoPath: currentVideoPath,
                                  episodeId: episodeId,
                                  animeId: animeId,
                                  animeTitle: result['animeTitle']?.toString(),
                                  episodeTitle:
                                      result['episodeTitle']?.toString(),
                                );

                                // 立即更新视频播放器状态中的动漫和剧集标题
                                videoState.setAnimeTitle(
                                    result['animeTitle']?.toString());
                                videoState.setEpisodeTitle(
                                    result['episodeTitle']?.toString());
                              }
                            } catch (e) {}
                            videoState.loadDanmaku(episodeId, animeId);
                          }
                        }
                      },
                      expandHorizontally: true,
                    ),
                    const SettingsHintText('手动搜索并选择匹配的弹幕文件'),
                  ],
                ),
              ),
              // 保存弹幕
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '保存弹幕',
                      style: TextStyle(
                        color: menuColors.foreground,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: BlurButton(
                            text: '保存为 JSON',
                            icon: Icons.save_alt,
                            onTap: () =>
                                _saveDanmaku(_DanmakuExportFormat.json),
                            expandHorizontally: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: BlurButton(
                            text: '保存为 XML',
                            icon: Icons.save_alt,
                            onTap: () => _saveDanmaku(_DanmakuExportFormat.xml),
                            expandHorizontally: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const SettingsHintText('保存当前启用轨道的弹幕到本地文件'),
                  ],
                ),
              ),
              // 弹幕屏蔽词
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
                child: Consumer<VideoPlayerState>(
                    builder: (context, videoState, child) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '弹幕屏蔽词',
                            style: TextStyle(
                              color: menuColors.foreground,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          // 毛玻璃效果的白色添加按钮
                          BlurButton(
                            icon: Icons.add,
                            text: '添加',
                            onTap: () => _addBlockWord(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (globals.isMobilePlatform)
                        _buildMobileBlockWordInput()
                      else
                        _buildDesktopBlockWordInput(),
                      if (_hasBlockWordError && _blockWordErrorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 12),
                          child: Text(
                            _blockWordErrorMessage!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      const SizedBox(height: 8),
                      _buildBlockWordsList(),
                      const SettingsHintText('包含屏蔽词或被正则表达式命中的弹幕将被过滤'),
                    ],
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDesktopBlockWordInput() {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    final borderColor = _hasBlockWordError
        ? Colors.redAccent.withOpacity(0.8)
        : menuColors.controlBorder;

    return SizedBox(
      height: 80,
      child: TextField(
        controller: _blockWordController,
        style: TextStyle(color: menuColors.foreground, fontSize: 13),
        textAlignVertical: TextAlignVertical.center,
        maxLines: 3,
        decoration: InputDecoration(
          hintText: '输入要屏蔽的关键词\n（支持正则，以"规则名称/表达式/"形式输入；支持逗号分隔批量添加）',
          hintStyle: TextStyle(
            color: menuColors.disabledForeground,
            fontSize: 13,
          ),
          filled: true,
          fillColor: menuColors.controlBackground,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          isDense: true,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: menuColors.accent, width: 1),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor, width: 1),
          ),
          suffixIcon: IconButton(
            icon: Icon(
              Icons.clear,
              color: menuColors.secondaryForeground,
              size: 18,
            ),
            onPressed: () => _blockWordController.clear(),
            tooltip: '',
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(),
          ),
        ),
        onSubmitted: (_) => _addBlockWord(),
      ),
    );
  }

  Widget _buildMobileBlockWordInput() {
    final menuColors = PlayerMenuTheme.colorsOf(context);
    return GestureDetector(
      onTap: _showBlockWordInputDialog,
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: menuColors.controlBackground,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _hasBlockWordError
                ? Colors.redAccent.withOpacity(0.8)
                : menuColors.controlBorder,
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            '点击输入屏蔽词',
            style: TextStyle(
              color: menuColors.disabledForeground,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

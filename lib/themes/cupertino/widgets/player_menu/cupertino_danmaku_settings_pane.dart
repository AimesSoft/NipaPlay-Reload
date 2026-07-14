import 'dart:convert';
import 'dart:io' as io;

import 'package:file_selector/file_selector.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveButton, AdaptiveButtonStyle, AdaptiveSwitch;

import 'package:nipaplay/services/manual_danmaku_matcher.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/adaptive_player_menu_primitives.dart';
import 'package:nipaplay/themes/cupertino/widgets/player_menu/cupertino_player_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/danmaku/style.dart';
import 'package:nipaplay/utils/danmaku_history_sync.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:path/path.dart' as p;

enum _DanmakuExportFormat { json, xml }

class CupertinoDanmakuSettingsPane extends StatefulWidget {
  const CupertinoDanmakuSettingsPane({
    super.key,
    required this.videoState,
  });

  final VideoPlayerState videoState;

  @override
  State<CupertinoDanmakuSettingsPane> createState() =>
      _CupertinoDanmakuSettingsPaneState();
}

class _CupertinoDanmakuSettingsPaneState
    extends State<CupertinoDanmakuSettingsPane> {
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
  String? _blockWordError;
  bool _isSavingDanmaku = false;

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
    final videoState = widget.videoState;
    final initialVideoPath = videoState.currentVideoPath;
    final String? initialSearchKeyword = initialVideoPath == null
        ? null
        : (initialVideoPath.startsWith('jellyfin://') ||
                initialVideoPath.startsWith('emby://'))
            ? (videoState.animeTitle?.trim().isNotEmpty == true
                ? videoState.animeTitle!.trim()
                : null)
            : p.basenameWithoutExtension(initialVideoPath);
    final result = await ManualDanmakuMatcher.instance.showManualMatchDialog(
      context,
      initialVideoTitle: initialSearchKeyword,
    );
    if (result == null) return;

    if (videoState.isDisposed ||
        videoState.currentVideoPath != initialVideoPath) {
      debugPrint('视频已切换或播放器已销毁，取消加载弹幕');
      return;
    }

    final episodeId = result['episodeId']?.toString() ?? '';
    final animeId = result['animeId']?.toString() ?? '';

    if (episodeId.isEmpty || animeId.isEmpty) {
      if (mounted) {
        BlurSnackBar.show(context, '未选择有效的弹幕记录');
      }
      return;
    }

    try {
      final currentPath = videoState.currentVideoPath;
      if (currentPath != null) {
        await DanmakuHistorySync.updateHistoryWithDanmakuInfo(
          videoPath: currentPath,
          episodeId: episodeId,
          animeId: animeId,
          animeTitle: result['animeTitle']?.toString(),
          episodeTitle: result['episodeTitle']?.toString(),
        );
        videoState.setAnimeTitle(result['animeTitle']?.toString() ?? '');
        videoState.setEpisodeTitle(result['episodeTitle']?.toString() ?? '');
      }
    } catch (_) {}

    videoState.loadDanmaku(episodeId, animeId);
    if (mounted) {
      BlurSnackBar.show(context, '已开始加载弹幕');
    }
  }

  Future<void> _saveDanmaku(_DanmakuExportFormat format) async {
    if (_isSavingDanmaku) return;

    final exportList = widget.videoState.collectDanmakuForExport();
    if (exportList.isEmpty) {
      _showMessage('当前没有可保存的弹幕');
      return;
    }

    setState(() => _isSavingDanmaku = true);
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

      if (savePath == null) return;

      final content = format == _DanmakuExportFormat.xml
          ? widget.videoState.buildDanmakuXmlExport(exportList)
          : widget.videoState.buildDanmakuJsonExport(exportList);
      final file = io.File(savePath.path);
      await file.writeAsString(content, encoding: utf8);

      _showMessage('弹幕已保存到: ${savePath.path}');
    } catch (e) {
      _showMessage('保存弹幕失败: $e');
    } finally {
      if (mounted) {
        setState(() => _isSavingDanmaku = false);
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

  void _showMessage(String message) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
  }

  Future<void> _pickDanmakuFontFile() async {
    final selected = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Font',
          extensions: ['ttf', 'otf', 'ttc', 'otc'],
        ),
      ],
    );
    if (selected == null) return;

    final success =
        await widget.videoState.importDanmakuFontFile(selected.path);
    if (!mounted) return;
    _showMessage(
      success ? '已应用字体: ${p.basename(selected.path)}' : '字体加载失败，请选择有效的字体文件',
    );
  }

  Future<void> _resetDanmakuFont() async {
    await widget.videoState.resetDanmakuFont();
    if (!mounted) return;
    _showMessage('已恢复为系统默认字体');
  }

  String _danmakuFontLabel() {
    final fontPath = widget.videoState.danmakuFontFilePath.trim();
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

  bool get _isNext2Kernel =>
      DanmakuKernelFactory.getKernelType() == DanmakuRenderEngine.next2;

  bool get _isDfmPlusKernel =>
      DanmakuKernelFactory.getKernelType() == DanmakuRenderEngine.dfmPlus;

  bool get _usesBinaryDanmakuEffectToggles =>
      _isNext2Kernel || _isDfmPlusKernel;

  String get _binaryDanmakuEffectKernelName =>
      _isDfmPlusKernel ? 'DFM+' : 'Next2';

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

  @override
  Widget build(BuildContext context) {
    final isErikaPlayerKernel =
        PlayerFactory.getKernelType() == PlayerKernelType.erika;
    final showBinaryDanmakuEffectToggles =
        isErikaPlayerKernel || _usesBinaryDanmakuEffectToggles;
    final binaryDanmakuEffectKernelName =
        isErikaPlayerKernel ? 'Erika' : _binaryDanmakuEffectKernelName;

    return CupertinoBottomSheetContentLayout(
      sliversBuilder: (context, topSpacing) => [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 12),
          sliver: SliverToBoxAdapter(
            child: Text(
              '控制弹幕开关、透明度、字体大小以及屏蔽词',
              style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                    fontSize: 13,
                    color: CupertinoColors.secondaryLabel.resolveFrom(context),
                  ),
            ),
          ),
        ),
        SliverList(
          delegate: SliverChildListDelegate([
            AdaptivePlayerMenuSection(
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
                _buildSwitchTile(
                  context,
                  title: '随机染色',
                  subtitle: '忽略原始颜色，按预设彩色随机分配',
                  value: widget.videoState.danmakuRandomColorEnabled,
                  onChanged: widget.videoState.setDanmakuRandomColorEnabled,
                ),
                AdaptivePlayerMenuTile(
                  title: const Text('手动匹配弹幕'),
                  subtitle: const Text('选择指定番剧/剧集的弹幕'),
                  trailing: const Icon(CupertinoIcons.right_chevron),
                  onTap: _handleManualMatch,
                ),
              ],
            ),
            AdaptivePlayerMenuSection(
              header: const Text('保存弹幕'),
              children: [
                AdaptivePlayerMenuTile(
                  title: const Text('保存为 JSON'),
                  subtitle: const Text('通用格式，便于再次导入'),
                  trailing: const Icon(CupertinoIcons.right_chevron),
                  onTap: () => _saveDanmaku(_DanmakuExportFormat.json),
                ),
                AdaptivePlayerMenuTile(
                  title: const Text('保存为 XML'),
                  subtitle: const Text('Bilibili XML 格式'),
                  trailing: const Icon(CupertinoIcons.right_chevron),
                  onTap: () => _saveDanmaku(_DanmakuExportFormat.xml),
                ),
              ],
            ),
            AdaptivePlayerMenuSection(
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
                  description:
                      '${(widget.videoState.danmakuFontSize <= 0 ? widget.videoState.actualDanmakuFontSize : widget.videoState.danmakuFontSize).round()}px',
                  value: widget.videoState.danmakuFontSize <= 0
                      ? widget.videoState.actualDanmakuFontSize
                      : widget.videoState.danmakuFontSize,
                  min: 12.0,
                  max: 60.0,
                  divisions: 96,
                  onChanged: widget.videoState.setDanmakuFontSize,
                ),
                AdaptivePlayerMenuTile(
                  title: const Text('字体选择'),
                  subtitle: Text('当前字体：${_danmakuFontLabel()}'),
                  trailing: const Icon(CupertinoIcons.right_chevron),
                  onTap: _pickDanmakuFontFile,
                ),
                AdaptivePlayerMenuTile(
                  title: const Text('恢复默认字体'),
                  subtitle: const Text('使用系统默认弹幕字体'),
                  trailing: const Icon(CupertinoIcons.refresh),
                  onTap: _resetDanmakuFont,
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
                if (showBinaryDanmakuEffectToggles)
                  _buildSwitchTile(
                    context,
                    title: '弹幕描边',
                    subtitle: '开启后为 $binaryDanmakuEffectKernelName 弹幕添加描边',
                    value: widget.videoState.next2DanmakuOutlineWidth > 0.0,
                    onChanged: (value) {
                      widget.videoState
                          .setNext2DanmakuOutlineWidth(value ? 1.0 : 0.0);
                    },
                  )
                else
                  _buildOptionButtonsTile<DanmakuOutlineStyle>(
                    context,
                    title: '弹幕描边',
                    subtitle: '选择弹幕文字外缘的描边方式',
                    values: DanmakuOutlineStyle.values,
                    selectedValue: widget.videoState.danmakuOutlineStyle,
                    labelBuilder: _outlineStyleLabel,
                    onSelected: widget.videoState.setDanmakuOutlineStyle,
                  ),
                _buildOptionButtonsTile<DanmakuShadowStyle>(
                  context,
                  title: '弹幕阴影',
                  subtitle: '选择弹幕文字的阴影强度',
                  values: DanmakuShadowStyle.values,
                  selectedValue: widget.videoState.danmakuShadowStyle,
                  labelBuilder: _shadowStyleLabel,
                  onSelected: widget.videoState.setDanmakuShadowStyle,
                ),
                _buildOptionButtonsTile<double>(
                  context,
                  title: '轨道显示区域',
                  subtitle: '设置弹幕轨道在屏幕上的显示范围',
                  values: _danmakuDisplayAreaOptions,
                  selectedValue: _snapDanmakuDisplayArea(
                    widget.videoState.danmakuDisplayArea,
                  ),
                  labelBuilder: _danmakuDisplayAreaText,
                  onSelected: (value) {
                    widget.videoState.setDanmakuDisplayArea(
                      _snapDanmakuDisplayArea(value),
                    );
                  },
                ),
                if (DanmakuKernelFactory.getKernelType() !=
                    DanmakuRenderEngine.canvas)
                  _buildSwitchTile(
                    context,
                    title: '合并相同弹幕',
                    subtitle: '将内容相同的弹幕合并为一条显示',
                    value: widget.videoState.mergeDanmaku,
                    onChanged: widget.videoState.setMergeDanmaku,
                  ),
                if (DanmakuKernelFactory.getKernelType() ==
                    DanmakuRenderEngine.dfmPlus)
                  _buildSliderTile(
                    context,
                    title: '轨道间距',
                    description:
                        '${(widget.videoState.danmakuDfmPlusTrackGap * 100).round()}%',
                    value: widget.videoState.danmakuDfmPlusTrackGap,
                    min: 0.0,
                    max: 0.5,
                    divisions: 50,
                    onChanged: widget.videoState.setDanmakuDfmPlusTrackGap,
                  ),
              ],
            ),
            AdaptivePlayerMenuSection(
              header: const Text('弹幕屏蔽'),
              children: [
                _buildSwitchTile(
                  context,
                  title: '屏蔽顶部弹幕',
                  subtitle: '不显示顶部固定弹幕',
                  value: widget.videoState.blockTopDanmaku,
                  onChanged: widget.videoState.setBlockTopDanmaku,
                ),
                _buildSwitchTile(
                  context,
                  title: '屏蔽底部弹幕',
                  subtitle: '不显示底部固定弹幕',
                  value: widget.videoState.blockBottomDanmaku,
                  onChanged: widget.videoState.setBlockBottomDanmaku,
                ),
                _buildSwitchTile(
                  context,
                  title: '屏蔽滚动弹幕',
                  subtitle: '不显示从右向左滚动的弹幕',
                  value: widget.videoState.blockScrollDanmaku,
                  onChanged: widget.videoState.setBlockScrollDanmaku,
                ),
              ],
            ),
            AdaptivePlayerMenuSection(
              header: const Text('屏蔽词管理'),
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AdaptivePlayerMenuTextField(
                        controller: _blockWordController,
                        placeholder: '输入要屏蔽的词语',
                        onSubmitted: (_) => _addBlockWord(),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: AdaptiveButton(
                          label: '添加',
                          style: AdaptiveButtonStyle.glass,
                          onPressed: _addBlockWord,
                        ),
                      ),
                      if (_blockWordError != null)
                        Text(
                          _blockWordError!,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                CupertinoColors.systemRed.resolveFrom(context),
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
    return AdaptivePlayerMenuTile(
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: AdaptiveSwitch(
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

  Widget _buildOptionButtonsTile<T>(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<T> values,
    required T selectedValue,
    required String Function(T value) labelBuilder,
    required ValueChanged<T> onSelected,
  }) {
    final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
    final selectedColor = CupertinoTheme.of(context).primaryColor;
    final borderColor = CupertinoColors.separator.resolveFrom(context);
    final selectedTextColor = CupertinoDynamicColor.resolve(
      CupertinoColors.white,
      context,
    );
    final normalTextColor = CupertinoColors.label.resolveFrom(context);

    return AdaptivePlayerMenuTile(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 12, 20, 16),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: textTheme.copyWith(
              fontSize: 13,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: values.map((value) {
              final selected = value == selectedValue;
              return GestureDetector(
                onTap: () => onSelected(value),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected
                        ? selectedColor
                        : CupertinoColors.systemGrey6.resolveFrom(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? selectedColor : borderColor,
                    ),
                  ),
                  child: Text(
                    labelBuilder(value),
                    style: textTheme.copyWith(
                      fontSize: 13,
                      color: selected ? selectedTextColor : normalTextColor,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
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
            color: CupertinoColors.systemGrey6
                .resolveFrom(context)
                .withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_getDisplayText(word)),
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

  bool _isRegexRule(String word) {
    if (!word.contains('/')) return false;
    final parts = word.split('/');
    return parts.length >= 3 && parts.first.isNotEmpty && parts.last.isEmpty;
  }

  String _getDisplayText(String word) {
    if (_isRegexRule(word)) {
      final firstSlash = word.indexOf('/');
      final name = word.substring(0, firstSlash);
      return '规则：$name';
    }
    return word;
  }
}

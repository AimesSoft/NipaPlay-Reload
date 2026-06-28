import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/app_accent_color.dart';

class DanmakuSettingsPage extends StatefulWidget {
  const DanmakuSettingsPage({super.key});

  @override
  State<DanmakuSettingsPage> createState() => _DanmakuSettingsPageState();
}

class _DanmakuSettingsPageState extends State<DanmakuSettingsPage> {
  static Color get _fluentAccentColor => AppAccentColors.current;
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

  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;

  final GlobalKey _danmakuRenderEngineDropdownKey = GlobalKey();
  final GlobalKey _spoilerAiApiFormatDropdownKey = GlobalKey();
  final GlobalKey _danmakuDisplayAreaDropdownKey = GlobalKey();
  final GlobalKey _danmakuOutlineStyleDropdownKey = GlobalKey();
  final GlobalKey _danmakuShadowStyleDropdownKey = GlobalKey();
  final GlobalKey _danmakuAutoLoadStrategyDropdownKey = GlobalKey();

  final TextEditingController _spoilerAiUrlController = TextEditingController();
  final TextEditingController _spoilerAiModelController =
      TextEditingController();
  final TextEditingController _spoilerAiApiKeyController =
      TextEditingController();
  bool _spoilerAiControllersInitialized = false;
  bool _isSavingSpoilerAiSettings = false;
  SpoilerAiApiFormat _spoilerAiApiFormatDraft = SpoilerAiApiFormat.openai;
  double _spoilerAiTemperatureDraft = 0.5;

  @override
  void initState() {
    super.initState();
    _loadDanmakuRenderEngineSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_spoilerAiControllersInitialized) return;

    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _spoilerAiApiFormatDraft = videoState.spoilerAiApiFormat;
    _spoilerAiTemperatureDraft = videoState.spoilerAiTemperature;
    _spoilerAiUrlController.text = videoState.spoilerAiApiUrl;
    _spoilerAiModelController.text = videoState.spoilerAiModel;
    _spoilerAiApiKeyController.text = videoState.spoilerAiApiKey;
    _spoilerAiControllersInitialized = true;
  }

  @override
  void dispose() {
    _spoilerAiUrlController.dispose();
    _spoilerAiModelController.dispose();
    _spoilerAiApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadDanmakuRenderEngineSettings() async {
    if (!mounted) return;
    setState(() {
      _selectedDanmakuRenderEngine = DanmakuKernelFactory.getKernelType();
    });
  }

  Future<void> _saveDanmakuRenderEngineSettings(
      DanmakuRenderEngine engine) async {
    await DanmakuKernelFactory.saveKernelType(engine);

    if (!mounted) return;
    BlurSnackBar.show(context, '弹幕渲染引擎已切换');

    setState(() {
      _selectedDanmakuRenderEngine = DanmakuKernelFactory.getKernelType();
    });
  }

  Future<void> _saveSpoilerAiSettings(VideoPlayerState videoState) async {
    if (_isSavingSpoilerAiSettings) return;

    final url = _spoilerAiUrlController.text.trim();
    final model = _spoilerAiModelController.text.trim();
    final apiKeyInput = _spoilerAiApiKeyController.text.trim();

    if (url.isEmpty) {
      BlurSnackBar.show(context, '请输入 AI 接口 URL');
      return;
    }
    if (model.isEmpty) {
      BlurSnackBar.show(context, '请输入模型名称');
      return;
    }
    if (apiKeyInput.isEmpty) {
      BlurSnackBar.show(context, '请输入 API Key');
      return;
    }

    setState(() {
      _isSavingSpoilerAiSettings = true;
    });

    try {
      await videoState.updateSpoilerAiSettings(
        apiFormat: _spoilerAiApiFormatDraft,
        apiUrl: url,
        model: model,
        temperature: _spoilerAiTemperatureDraft,
        apiKey: apiKeyInput,
      );
      _spoilerAiApiKeyController.text = apiKeyInput;
      if (!mounted) return;
      BlurSnackBar.show(context, '防剧透 AI 设置已保存');
    } catch (e) {
      if (!mounted) return;
      BlurSnackBar.show(context, '保存失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSavingSpoilerAiSettings = false;
        });
      }
    }
  }

  String _getDanmakuRenderEngineDescription(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return 'CPU 渲染引擎\n使用 Flutter Widget 进行绘制，兼容性好，但在低端设备上弹幕量大时可能卡顿。';
      case DanmakuRenderEngine.gpu:
        return 'GPU 渲染引擎 (实验性)\n使用自定义着色器和字体图集，性能更高，功耗更低，但目前仍在开发中。';
      case DanmakuRenderEngine.canvas:
        return 'Canvas 弹幕渲染引擎\n来自软件kazumi的开发者\n使用Canvas绘制弹幕，高性能，低功耗，支持大量弹幕同时显示。';
      case DanmakuRenderEngine.nipaplayNext:
        return '${DanmakuKernelFactory.nipaplayNextDisplayName}\n是CPU弹幕和Canvas弹幕优点的集合体，包含两边的全部优点。';
      case DanmakuRenderEngine.next2:
        return Next2PlatformSupport.description;
      case DanmakuRenderEngine.dfmPlus:
        return 'DFM+ 弹幕引擎\n移植自 B 站的 DanmakuFlameMaster「烈焰弹幕使」，结合 Rust 计算层和 GPU 渲染。';
    }
  }

  List<DropdownMenuItemData<DanmakuRenderEngine>>
      _buildDanmakuRenderEngineItems({
    required bool showNext2,
    required bool next2Supported,
  }) {
    final items = <DropdownMenuItemData<DanmakuRenderEngine>>[
      DropdownMenuItemData(
        title: 'CPU 渲染',
        value: DanmakuRenderEngine.cpu,
        isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.cpu,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.cpu),
      ),
      DropdownMenuItemData(
        title: 'GPU 渲染 (实验性)',
        value: DanmakuRenderEngine.gpu,
        isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.gpu,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.gpu),
      ),
      DropdownMenuItemData(
        title: 'Canvas 弹幕 (实验性)',
        value: DanmakuRenderEngine.canvas,
        isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.canvas,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.canvas),
      ),
      DropdownMenuItemData(
        title: DanmakuKernelFactory.nipaplayNextDisplayName,
        value: DanmakuRenderEngine.nipaplayNext,
        isSelected:
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.nipaplayNext,
        description: _getDanmakuRenderEngineDescription(
            DanmakuRenderEngine.nipaplayNext),
      ),
    ];

    if (showNext2) {
      items.add(
        DropdownMenuItemData(
          title: 'NipaPlay Next2',
          value: DanmakuRenderEngine.next2,
          isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.next2,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.next2),
        ),
      );
      items.add(
        DropdownMenuItemData(
          title: 'DFM+',
          value: DanmakuRenderEngine.dfmPlus,
          isSelected:
              _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.dfmPlus),
        ),
      );
    } else if (_selectedDanmakuRenderEngine == DanmakuRenderEngine.next2) {
      items.add(
        DropdownMenuItemData(
          title: next2Supported
              ? 'NipaPlay Next2 (实验室关闭)'
              : 'NipaPlay Next2 (当前平台不支持)',
          value: DanmakuRenderEngine.next2,
          isSelected: true,
          enabled: false,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.next2),
        ),
      );
    } else if (_selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus) {
      items.add(
        DropdownMenuItemData(
          title: next2Supported ? 'DFM+ (实验室关闭)' : 'DFM+ (当前平台不支持)',
          value: DanmakuRenderEngine.dfmPlus,
          isSelected: true,
          enabled: false,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.dfmPlus),
        ),
      );
    }

    return items;
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

  String _danmakuAutoLoadStrategyLabel(DanmakuAutoLoadStrategy strategy) {
    switch (strategy) {
      case DanmakuAutoLoadStrategy.remoteAndLocal:
        return context.l10n.danmakuAutoLoadStrategyRemoteAndLocal;
      case DanmakuAutoLoadStrategy.remote:
        return context.l10n.danmakuAutoLoadStrategyRemote;
      case DanmakuAutoLoadStrategy.local:
        return context.l10n.danmakuAutoLoadStrategyLocal;
      case DanmakuAutoLoadStrategy.manual:
        return context.l10n.danmakuAutoLoadStrategyManual;
    }
  }

  String _danmakuAutoLoadStrategyDescription(DanmakuAutoLoadStrategy strategy) {
    switch (strategy) {
      case DanmakuAutoLoadStrategy.remoteAndLocal:
        return context.l10n.danmakuAutoLoadStrategyRemoteAndLocalDescription;
      case DanmakuAutoLoadStrategy.remote:
        return context.l10n.danmakuAutoLoadStrategyRemoteDescription;
      case DanmakuAutoLoadStrategy.local:
        return context.l10n.danmakuAutoLoadStrategyLocalDescription;
      case DanmakuAutoLoadStrategy.manual:
        return context.l10n.danmakuAutoLoadStrategyManualDescription;
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final next2Supported = Next2PlatformSupport.isKernelSupported;
    final showNext2 = next2Supported &&
        context.watch<LabsSettingsProvider>().enableNext2DanmakuKernel;
    final renderEngineItems = _buildDanmakuRenderEngineItems(
      showNext2: showNext2,
      next2Supported: next2Supported,
    );

    return ListView(
      children: [
        SettingsItem.dropdown(
          title: '弹幕渲染引擎',
          subtitle: '选择弹幕的渲染方式',
          icon: Ionicons.hardware_chip_outline,
          items: renderEngineItems,
          onChanged: (dynamic value) {
            if (value is! DanmakuRenderEngine) return;
            if ((!showNext2 || !next2Supported) &&
                value == DanmakuRenderEngine.next2) {
              return;
            }
            _saveDanmakuRenderEngineSettings(value);
          },
          dropdownKey: _danmakuRenderEngineDropdownKey,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        if (_selectedDanmakuRenderEngine == DanmakuRenderEngine.next2 ||
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus)
          Consumer<SettingsProvider>(
            builder: (context, settingsProvider, child) {
              final currentValue = settingsProvider.danmakuSupersample;
              final items = <DropdownMenuItemData<double>>[
                DropdownMenuItemData(
                  title: '关闭',
                  value: 0.0,
                  isSelected: currentValue == 0.0,
                  description: '原始分辨率渲染，GPU 负担最低',
                ),
                DropdownMenuItemData(
                  title: '1.5x',
                  value: 1.5,
                  isSelected: currentValue == 1.5,
                  description: '1.5 倍像素密度，平衡清晰度与性能',
                ),
                DropdownMenuItemData(
                  title: '2x',
                  value: 2.0,
                  isSelected: currentValue == 2.0,
                  description: '2 倍像素密度，文字最清晰，GPU 负担较高',
                ),
              ];
              return SettingsItem.dropdown(
                title: '弹幕超采样渲染',
                subtitle: '以更高像素密度渲染弹幕，使文字更清晰',
                icon: Ionicons.expand_outline,
                items: items,
                onChanged: (dynamic value) {
                  if (value is! double) return;
                  settingsProvider.setDanmakuSupersample(value);
                  if (context.mounted) {
                    final label = value == 0.0 ? '关闭' : '${value}x';
                    BlurSnackBar.show(
                      context,
                      '弹幕超采样已设为 $label',
                    );
                  }
                },
              );
            },
          ),
        if (_selectedDanmakuRenderEngine == DanmakuRenderEngine.next2 ||
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus)
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return SettingsItem.toggle(
              title: context.l10n.rememberDanmakuOffset,
              subtitle: context.l10n.rememberDanmakuOffsetSubtitle,
              icon: Icons.av_timer,
              value: videoState.rememberDanmakuOffset,
              onChanged: (bool value) async {
                await videoState.setRememberDanmakuOffset(value);
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  value
                      ? context.l10n.rememberDanmakuOffsetEnabled
                      : context.l10n.rememberDanmakuOffsetDisabled,
                );
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: context.l10n.danmakuConvertToSimplified,
              subtitle: context.l10n.danmakuConvertToSimplifiedSubtitle,
              icon: Ionicons.language_outline,
              value: settingsProvider.danmakuConvertToSimplified,
              onChanged: (bool value) {
                settingsProvider.setDanmakuConvertToSimplified(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    value
                        ? context.l10n.danmakuConvertToSimplifiedEnabled
                        : context.l10n.danmakuConvertToSimplifiedDisabled,
                  );
                }
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final outlineItems = DanmakuOutlineStyle.values
                .map(
                  (style) => DropdownMenuItemData<DanmakuOutlineStyle>(
                    title: _outlineStyleLabel(style),
                    value: style,
                    isSelected: videoState.danmakuOutlineStyle == style,
                  ),
                )
                .toList();
            final shadowItems = DanmakuShadowStyle.values
                .map(
                  (style) => DropdownMenuItemData<DanmakuShadowStyle>(
                    title: _shadowStyleLabel(style),
                    value: style,
                    isSelected: videoState.danmakuShadowStyle == style,
                  ),
                )
                .toList();
            final displayAreaItems = _danmakuDisplayAreaOptions
                .map(
                  (area) => DropdownMenuItemData<double>(
                    title: _danmakuDisplayAreaText(area),
                    value: area,
                    isSelected: _snapDanmakuDisplayArea(
                          videoState.danmakuDisplayArea,
                        ) ==
                        area,
                  ),
                )
                .toList();

            return Column(
              children: [
                SettingsItem.toggle(
                  title: '随机染色',
                  subtitle: '忽略弹幕原始颜色，按发送弹幕预设色随机分配',
                  icon: Ionicons.color_palette_outline,
                  value: videoState.danmakuRandomColorEnabled,
                  onChanged: (value) {
                    videoState.setDanmakuRandomColorEnabled(value);
                  },
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.toggle(
                  title: '时间轴告知',
                  subtitle: '在视频特定进度(25%/50%/75%/90%)显示弹幕提示',
                  icon: Ionicons.notifications_outline,
                  value: videoState.isTimelineDanmakuEnabled,
                  onChanged: (value) {
                    videoState.toggleTimelineDanmaku(value);
                  },
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.slider(
                  title: '弹幕不透明度',
                  subtitle: '调整弹幕文字透明度',
                  icon: Ionicons.contrast_outline,
                  value: videoState.danmakuOpacity,
                  min: 0.0,
                  max: 1.0,
                  divisions: 100,
                  onChanged: (value) {
                    videoState.setDanmakuOpacity(value);
                  },
                  labelFormatter: (value) => '${(value * 100).round()}%',
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.slider(
                  title: '弹幕字体大小',
                  subtitle: '调整弹幕文字大小，轨道间距会自动适配',
                  icon: Ionicons.text_outline,
                  value: videoState.danmakuFontSize <= 0
                      ? videoState.actualDanmakuFontSize
                      : videoState.danmakuFontSize,
                  min: 12.0,
                  max: 60.0,
                  divisions: 96,
                  onChanged: (value) {
                    videoState.setDanmakuFontSize(value, commit: true);
                  },
                  labelFormatter: (value) => '${value.toStringAsFixed(1)}px',
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 12.0,
                  ),
                  child: SettingsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Ionicons.text_outline,
                              color: colorScheme.onSurface,
                              size: 18,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '弹幕字体',
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前字体：${_danmakuFontLabel(videoState)}',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: BlurButton(
                                icon: Ionicons.folder_open_outline,
                                text: '选择字体文件',
                                onTap: () => _pickDanmakuFontFile(videoState),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                fontSize: 13,
                                iconSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: BlurButton(
                                icon: Ionicons.refresh_outline,
                                text: '恢复默认',
                                onTap: () => _resetDanmakuFont(videoState),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                fontSize: 13,
                                iconSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                if (_usesBinaryDanmakuEffectToggles)
                  SettingsItem.toggle(
                    title: '弹幕描边',
                    subtitle: '开启后为 $_binaryDanmakuEffectKernelName 弹幕添加描边',
                    icon: Ionicons.text_outline,
                    value: videoState.next2DanmakuOutlineWidth > 0.0,
                    onChanged: (value) {
                      videoState.setNext2DanmakuOutlineWidth(
                        value ? 1.0 : 0.0,
                      );
                    },
                  )
                else
                  SettingsItem.dropdown(
                    title: '弹幕描边样式',
                    subtitle: '选择弹幕文字外缘的描边方式',
                    icon: Ionicons.text_outline,
                    items: outlineItems,
                    onChanged: (dynamic value) {
                      if (value is! DanmakuOutlineStyle) return;
                      videoState.setDanmakuOutlineStyle(value);
                    },
                    dropdownKey: _danmakuOutlineStyleDropdownKey,
                  ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                if (_usesBinaryDanmakuEffectToggles)
                  SettingsItem.toggle(
                    title: '弹幕阴影',
                    subtitle: '开启后为 $_binaryDanmakuEffectKernelName 弹幕添加阴影',
                    icon: Ionicons.color_wand_outline,
                    value: videoState.danmakuShadowStyle !=
                        DanmakuShadowStyle.none,
                    onChanged: (value) {
                      videoState.setDanmakuShadowStyle(
                        value
                            ? DanmakuShadowStyle.strong
                            : DanmakuShadowStyle.none,
                      );
                    },
                  )
                else
                  SettingsItem.dropdown(
                    title: '弹幕阴影样式',
                    subtitle: '选择弹幕文字的阴影强度',
                    icon: Ionicons.color_wand_outline,
                    items: shadowItems,
                    onChanged: (dynamic value) {
                      if (value is! DanmakuShadowStyle) return;
                      videoState.setDanmakuShadowStyle(value);
                    },
                    dropdownKey: _danmakuShadowStyleDropdownKey,
                  ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.slider(
                  title: '滚动弹幕速度',
                  subtitle: '向左减慢滚动弹幕速度，向右加快',
                  icon: Ionicons.speedometer_outline,
                  value: videoState.danmakuSpeedMultiplier,
                  min: 0.5,
                  max: 2.0,
                  divisions: 30,
                  onChanged: (value) {
                    videoState.setDanmakuSpeedMultiplier(value);
                  },
                  labelFormatter: (value) => '${value.toStringAsFixed(2)}x',
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.dropdown(
                  title: '轨道显示区域',
                  subtitle: '设置弹幕轨道在屏幕上的显示范围',
                  icon: Ionicons.resize_outline,
                  items: displayAreaItems,
                  onChanged: (dynamic value) {
                    if (value is! double) return;
                    videoState.setDanmakuDisplayArea(
                      _snapDanmakuDisplayArea(value),
                    );
                  },
                  dropdownKey: _danmakuDisplayAreaDropdownKey,
                ),
                if (_isDfmPlusKernel) ...[
                  Divider(
                      color: colorScheme.onSurface.withOpacity(0.12),
                      height: 1),
                  SettingsItem.slider(
                    title: '弹幕轨道间距',
                    subtitle: '增大间距可减少重叠，减小间距可显示更多弹幕',
                    icon: Ionicons.reorder_three_outline,
                    value: videoState.danmakuDfmPlusTrackGap,
                    min: 0.0,
                    max: 0.5,
                    divisions: 50,
                    onChanged: (value) {
                      videoState.setDanmakuDfmPlusTrackGap(value);
                    },
                    labelFormatter: (value) => '${(value * 100).round()}%',
                  ),
                ],
                if (DanmakuKernelFactory.getKernelType() !=
                    DanmakuRenderEngine.canvas) ...[
                  Divider(
                      color: colorScheme.onSurface.withOpacity(0.12),
                      height: 1),
                  SettingsItem.toggle(
                    title: '合并相同弹幕',
                    subtitle: '将内容相同的弹幕合并为一条显示',
                    icon: Ionicons.git_merge_outline,
                    value: videoState.mergeDanmaku,
                    onChanged: (value) {
                      videoState.setMergeDanmaku(value);
                    },
                  ),
                ],
                if (DanmakuKernelFactory.getKernelType() !=
                        DanmakuRenderEngine.canvas &&
                    DanmakuKernelFactory.getKernelType() !=
                        DanmakuRenderEngine.nipaplayNext &&
                    DanmakuKernelFactory.getKernelType() !=
                        DanmakuRenderEngine.next2 &&
                    DanmakuKernelFactory.getKernelType() !=
                        DanmakuRenderEngine.dfmPlus) ...[
                  Divider(
                      color: colorScheme.onSurface.withOpacity(0.12),
                      height: 1),
                  SettingsItem.toggle(
                    title: '弹幕堆叠',
                    subtitle: '允许多条弹幕重叠显示，适合弹幕密集场景',
                    icon: Ionicons.layers_outline,
                    value: videoState.danmakuStacking,
                    onChanged: (value) {
                      videoState.setDanmakuStacking(value);
                    },
                  ),
                ],
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.toggle(
                  title: '屏蔽顶部弹幕',
                  subtitle: '不显示顶部固定弹幕',
                  icon: Ionicons.arrow_up_outline,
                  value: videoState.blockTopDanmaku,
                  onChanged: (value) {
                    videoState.setBlockTopDanmaku(value);
                  },
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.toggle(
                  title: '屏蔽底部弹幕',
                  subtitle: '不显示底部固定弹幕',
                  icon: Ionicons.arrow_down_outline,
                  value: videoState.blockBottomDanmaku,
                  onChanged: (value) {
                    videoState.setBlockBottomDanmaku(value);
                  },
                ),
                Divider(
                    color: colorScheme.onSurface.withOpacity(0.12), height: 1),
                SettingsItem.toggle(
                  title: '屏蔽滚动弹幕',
                  subtitle: '不显示从右向左滚动的弹幕',
                  icon: Ionicons.swap_horizontal_outline,
                  value: videoState.blockScrollDanmaku,
                  onChanged: (value) {
                    videoState.setBlockScrollDanmaku(value);
                  },
                ),
              ],
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final widgets = <Widget>[
              SettingsItem.toggle(
                title: '防剧透模式',
                subtitle: '开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕',
                icon: Ionicons.shield_outline,
                value: videoState.spoilerPreventionEnabled,
                onChanged: (bool value) async {
                  if (value && !videoState.spoilerAiConfigReady) {
                    BlurSnackBar.show(context, '请先填写并保存 AI 接口配置');
                    return;
                  }
                  await videoState.setSpoilerPreventionEnabled(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '已开启防剧透模式' : '已关闭防剧透模式',
                  );
                },
              ),
            ];

            widgets.add(
              Divider(
                color: colorScheme.onSurface.withOpacity(0.12),
                height: 1,
              ),
            );

            final bool isGemini =
                _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
            final urlHint = isGemini
                ? 'https://generativelanguage.googleapis.com/v1beta/models'
                : 'https://api.openai.com/v1/chat/completions';
            final modelHint = isGemini ? 'gemini-1.5-flash' : 'gpt-5';

            widgets.add(
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 12.0,
                ),
                child: SettingsCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Ionicons.settings_outline,
                            color: colorScheme.onSurface,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            '防剧透 AI 设置',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        isGemini
                            ? 'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。'
                            : 'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                      SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            '接口格式',
                            style: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 12),
                          BlurDropdown<SpoilerAiApiFormat>(
                            dropdownKey: _spoilerAiApiFormatDropdownKey,
                            items: [
                              DropdownMenuItemData(
                                title: 'OpenAI 兼容',
                                value: SpoilerAiApiFormat.openai,
                                isSelected: _spoilerAiApiFormatDraft ==
                                    SpoilerAiApiFormat.openai,
                              ),
                              DropdownMenuItemData(
                                title: 'Gemini',
                                value: SpoilerAiApiFormat.gemini,
                                isSelected: _spoilerAiApiFormatDraft ==
                                    SpoilerAiApiFormat.gemini,
                              ),
                            ],
                            onItemSelected: (format) {
                              setState(() {
                                _spoilerAiApiFormatDraft = format;
                              });
                            },
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiUrlController,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: '接口 URL',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: urlHint,
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiModelController,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: '模型',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: modelHint,
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: _spoilerAiApiKeyController,
                        autocorrect: false,
                        enableSuggestions: false,
                        cursorColor: _fluentAccentColor,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          labelStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                          hintText: '请输入你的 API Key',
                          hintStyle: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.38),
                          ),
                          filled: true,
                          fillColor: colorScheme.onSurface.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderSide: BorderSide.none,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderSide:
                                BorderSide(color: _fluentAccentColor, width: 2),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '温度：${_spoilerAiTemperatureDraft.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 13,
                        ),
                      ),
                      fluent.FluentTheme(
                        data: fluent.FluentThemeData(
                          brightness: Theme.of(context).brightness,
                          accentColor: fluent.AccentColor.swatch({
                            'normal': _fluentAccentColor,
                            'default': _fluentAccentColor,
                          }),
                        ),
                        child: NipaplayLargeScreenEditableSlider(
                          min: 0.0,
                          max: 2.0,
                          divisions: 40,
                          value: _spoilerAiTemperatureDraft.clamp(0.0, 2.0),
                          onChanged: (value) {
                            setState(() {
                              _spoilerAiTemperatureDraft = value;
                            });
                          },
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: BlurButton(
                          icon: _isSavingSpoilerAiSettings
                              ? null
                              : Ionicons.checkmark_outline,
                          text: _isSavingSpoilerAiSettings ? '保存中...' : '保存配置',
                          onTap: _isSavingSpoilerAiSettings
                              ? () {}
                              : () => _saveSpoilerAiSettings(videoState),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          fontSize: 13,
                          iconSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widgets,
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            final currentStrategy = settingsProvider.danmakuAutoLoadStrategy;
            final items = DanmakuAutoLoadStrategy.values
                .map(
                  (strategy) => DropdownMenuItemData<DanmakuAutoLoadStrategy>(
                    title: _danmakuAutoLoadStrategyLabel(strategy),
                    value: strategy,
                    isSelected: currentStrategy == strategy,
                    description: _danmakuAutoLoadStrategyDescription(strategy),
                  ),
                )
                .toList();
            return SettingsItem.dropdown(
              title: context.l10n.danmakuAutoLoadStrategyTitle,
              subtitle: _danmakuAutoLoadStrategyDescription(currentStrategy),
              icon: Ionicons.sync_outline,
              items: items,
              onChanged: (dynamic value) {
                if (value is! DanmakuAutoLoadStrategy) return;
                settingsProvider.setDanmakuAutoLoadStrategy(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    context.l10n.danmakuAutoLoadStrategyUpdated,
                  );
                }
              },
              dropdownKey: _danmakuAutoLoadStrategyDropdownKey,
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: '哈希匹配失败自动匹配弹幕',
              subtitle: '哈希匹配失败时，默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单',
              icon: Ionicons.search_outline,
              value:
                  settingsProvider.autoMatchDanmakuFirstSearchResultOnHashFail,
              onChanged: (bool value) {
                settingsProvider
                    .setAutoMatchDanmakuFirstSearchResultOnHashFail(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                    context,
                    value ? '已开启匹配失败自动匹配' : '已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）',
                  );
                }
              },
            );
          },
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
      ],
    );
  }
}

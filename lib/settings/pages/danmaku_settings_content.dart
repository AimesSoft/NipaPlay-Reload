import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveSlider, PlatformInfo;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class DanmakuSettingsContent extends StatefulWidget {
  const DanmakuSettingsContent({super.key});

  @override
  State<DanmakuSettingsContent> createState() => _DanmakuSettingsContentState();
}

class _DanmakuSettingsContentState extends State<DanmakuSettingsContent> {
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;

  final GlobalKey _danmakuRenderEngineDropdownKey = GlobalKey();
  final GlobalKey _danmakuAutoLoadStrategyDropdownKey = GlobalKey();
  final GlobalKey _spoilerAiApiFormatDropdownKey = GlobalKey();

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

  Future<void> _saveNextPlusPlusEngineSetting(bool enabled) async {
    await DanmakuKernelFactory.saveEnableNextPlusPlus(enabled);

    if (!mounted) return;
    BlurSnackBar.show(context, enabled ? 'Next++ 已开启' : 'Next++ 已关闭');
    setState(() {});
  }

  Future<bool> _saveSpoilerAiSettings(VideoPlayerState videoState) async {
    if (_isSavingSpoilerAiSettings) return false;

    final url = _spoilerAiUrlController.text.trim();
    final model = _spoilerAiModelController.text.trim();
    final apiKeyInput = _spoilerAiApiKeyController.text.trim();

    if (url.isEmpty) {
      BlurSnackBar.show(context, '请输入 AI 接口 URL');
      return false;
    }
    if (model.isEmpty) {
      BlurSnackBar.show(context, '请输入模型名称');
      return false;
    }
    if (apiKeyInput.isEmpty) {
      BlurSnackBar.show(context, '请输入 API Key');
      return false;
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
      if (!mounted) return false;
      BlurSnackBar.show(context, '防剧透 AI 设置已保存');
      return true;
    } catch (e) {
      if (!mounted) return false;
      BlurSnackBar.show(context, '保存失败: $e');
      return false;
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

    if (next2Supported) {
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
          title: 'NipaPlay Next2 (当前平台不支持)',
          value: DanmakuRenderEngine.next2,
          isSelected: true,
          enabled: false,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.next2),
        ),
      );
    }

    if (!next2Supported &&
        _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus) {
      items.add(
        DropdownMenuItemData(
          title: 'DFM+ (当前平台不支持)',
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

  bool get _isDfmPlusKernel =>
      DanmakuKernelFactory.getKernelType() == DanmakuRenderEngine.dfmPlus;

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

  Future<void> _showSpoilerAiSettingsDialog(
    VideoPlayerState videoState,
  ) async {
    if (AdaptiveSettingsScope.isPhoneLayout(context)) {
      await CupertinoBottomSheet.show<void>(
        context: context,
        title: '防剧透 AI 设置',
        floatingTitle: true,
        child: StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            void updateDialog(VoidCallback change) {
              setState(change);
              sheetSetState(() {});
            }

            return CupertinoBottomSheetContentLayout(
              sliversBuilder: (contentContext, topSpacing) => [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(20, topSpacing, 20, 20),
                  sliver: SliverToBoxAdapter(
                    child: _buildSpoilerAiSettingsForm(
                      contentContext,
                      isPhoneLayout: true,
                      updateDialog: updateDialog,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: _buildSpoilerAiSettingsActions(
                        sheetContext,
                        videoState: videoState,
                        isPhoneLayout: true,
                        updateDialog: updateDialog,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
      return;
    }

    final enableAnimation =
        context.read<AppearanceSettingsProvider>().enablePageAnimation;

    await NipaplayWindow.show<void>(
      context: context,
      enableAnimation: enableAnimation,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      child: Builder(
        builder: (windowContext) {
          final screenSize = MediaQuery.of(windowContext).size;
          final maxWidth =
              (screenSize.width * 0.92).clamp(360.0, 640.0).toDouble();

          return StatefulBuilder(
            builder: (dialogContext, dialogSetState) {
              void updateDialog(VoidCallback change) {
                setState(change);
                dialogSetState(() {});
              }

              final colorScheme = Theme.of(dialogContext).colorScheme;
              return NipaplayWindowScaffold(
                maxWidth: maxWidth,
                maxHeightFactor: 0.84,
                onClose: () => Navigator.of(dialogContext).maybePop(),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '防剧透 AI 设置',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                        child: _buildSpoilerAiSettingsForm(
                          dialogContext,
                          isPhoneLayout: false,
                          updateDialog: updateDialog,
                        ),
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 18),
                      child: _buildSpoilerAiSettingsActions(
                        dialogContext,
                        videoState: videoState,
                        isPhoneLayout: false,
                        updateDialog: updateDialog,
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildSpoilerAiSettingsForm(
    BuildContext context, {
    required bool isPhoneLayout,
    required void Function(VoidCallback change) updateDialog,
  }) {
    final isGemini = _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
    final urlHint = isGemini
        ? 'https://generativelanguage.googleapis.com/v1beta/models'
        : 'https://api.openai.com/v1/chat/completions';
    final modelHint = isGemini ? 'gemini-1.5-flash' : 'gpt-5';

    if (isPhoneLayout) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。',
            style: TextStyle(
              color: cupertino.CupertinoDynamicColor.resolve(
                cupertino.CupertinoColors.secondaryLabel,
                context,
              ),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          _buildPhoneSpoilerLabel(context, '接口格式'),
          cupertino.CupertinoSlidingSegmentedControl<SpoilerAiApiFormat>(
            groupValue: _spoilerAiApiFormatDraft,
            children: const {
              SpoilerAiApiFormat.openai: Text('OpenAI 兼容'),
              SpoilerAiApiFormat.gemini: Text('Gemini'),
            },
            onValueChanged: (format) {
              if (format == null) return;
              updateDialog(() {
                _spoilerAiApiFormatDraft = format;
              });
            },
          ),
          const SizedBox(height: 14),
          _buildPhoneSpoilerLabel(context, '接口 URL'),
          _buildPhoneSpoilerTextField(
            controller: _spoilerAiUrlController,
            placeholder: urlHint,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 14),
          _buildPhoneSpoilerLabel(context, '模型'),
          _buildPhoneSpoilerTextField(
            controller: _spoilerAiModelController,
            placeholder: modelHint,
          ),
          const SizedBox(height: 14),
          _buildPhoneSpoilerLabel(context, 'API Key'),
          _buildPhoneSpoilerTextField(
            controller: _spoilerAiApiKeyController,
            placeholder: '请输入你的 API Key',
          ),
          const SizedBox(height: 16),
          Text(
            '温度：${_spoilerAiTemperatureDraft.toStringAsFixed(2)}',
            style: TextStyle(
              color: cupertino.CupertinoDynamicColor.resolve(
                cupertino.CupertinoColors.label,
                context,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
          _buildPhoneSpoilerTemperatureSlider(context, updateDialog),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '开启防剧透前请先填写并保存配置（必须提供接口 URL / Key / 模型）。',
        ),
        const SizedBox(height: 12),
        Text(
          '接口格式',
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: BlurDropdown<SpoilerAiApiFormat>(
              dropdownKey: _spoilerAiApiFormatDropdownKey,
              items: [
                DropdownMenuItemData<SpoilerAiApiFormat>(
                  title: 'OpenAI 兼容',
                  value: SpoilerAiApiFormat.openai,
                  isSelected:
                      _spoilerAiApiFormatDraft == SpoilerAiApiFormat.openai,
                ),
                DropdownMenuItemData<SpoilerAiApiFormat>(
                  title: 'Gemini',
                  value: SpoilerAiApiFormat.gemini,
                  isSelected:
                      _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini,
                ),
              ],
              onItemSelected: (format) {
                updateDialog(() {
                  _spoilerAiApiFormatDraft = format;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _spoilerAiUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '接口 URL',
            hintText: urlHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _spoilerAiModelController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: '模型',
            hintText: modelHint,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _spoilerAiApiKeyController,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'API Key',
            hintText: '请输入你的 API Key',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '温度：${_spoilerAiTemperatureDraft.toStringAsFixed(2)}',
        ),
        fluent.FluentTheme(
          data: fluent.FluentThemeData(
            brightness: Theme.of(context).brightness,
            accentColor: fluent.AccentColor.swatch({
              'normal': AppAccentColors.current,
              'default': AppAccentColors.current,
            }),
          ),
          child: NipaplayLargeScreenEditableSlider(
            min: 0.0,
            max: 2.0,
            divisions: 40,
            value: _spoilerAiTemperatureDraft.clamp(0.0, 2.0),
            label: _spoilerAiTemperatureDraft.toStringAsFixed(2),
            onChanged: (value) {
              updateDialog(() {
                _spoilerAiTemperatureDraft = value;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneSpoilerLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          color: cupertino.CupertinoDynamicColor.resolve(
            cupertino.CupertinoColors.secondaryLabel,
            context,
          ),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildPhoneSpoilerTemperatureSlider(
    BuildContext context,
    void Function(VoidCallback change) updateDialog,
  ) {
    final value = _spoilerAiTemperatureDraft.clamp(0.0, 2.0).toDouble();
    void onChanged(double next) {
      updateDialog(() {
        _spoilerAiTemperatureDraft = next;
      });
    }

    if (PlatformInfo.isIOS26OrHigher()) {
      return AdaptiveSlider(
        min: 0.0,
        max: 2.0,
        divisions: 40,
        label: value.toStringAsFixed(2),
        value: value,
        activeColor: AppAccentColors.current,
        onChanged: onChanged,
      );
    }

    return fluent.FluentTheme(
      data: fluent.FluentThemeData(
        brightness: Theme.of(context).brightness,
        accentColor: fluent.AccentColor.swatch({
          'normal': AppAccentColors.current,
          'default': AppAccentColors.current,
        }),
      ),
      child: fluent.Slider(
        min: 0.0,
        max: 2.0,
        divisions: 40,
        label: value.toStringAsFixed(2),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildPhoneSpoilerTextField({
    required TextEditingController controller,
    required String placeholder,
    TextInputType? keyboardType,
  }) {
    return cupertino.CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      keyboardType: keyboardType,
      autocorrect: false,
      enableSuggestions: false,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: cupertino.CupertinoColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _buildSpoilerAiSettingsActions(
    BuildContext dialogContext, {
    required VideoPlayerState videoState,
    required bool isPhoneLayout,
    required void Function(VoidCallback change) updateDialog,
  }) {
    Future<void> save() async {
      updateDialog(() {});
      final saved = await _saveSpoilerAiSettings(videoState);
      if (!dialogContext.mounted) return;
      updateDialog(() {});
      if (saved) {
        Navigator.of(dialogContext).maybePop();
      }
    }

    if (isPhoneLayout) {
      return Row(
        children: [
          Expanded(
            child: AdaptiveSettingsActionButton(
              label: context.l10n.cancel,
              onPressed: () => Navigator.of(dialogContext).maybePop(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: AdaptiveSettingsActionButton(
              label: _isSavingSpoilerAiSettings ? '保存中...' : '保存配置',
              primary: true,
              onPressed: _isSavingSpoilerAiSettings ? null : save,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AdaptiveSettingsActionButton(
          label: context.l10n.cancel,
          onPressed: () => Navigator.of(dialogContext).maybePop(),
        ),
        const SizedBox(width: 8),
        AdaptiveSettingsActionButton(
          label: _isSavingSpoilerAiSettings ? '保存中...' : '保存配置',
          primary: true,
          onPressed: _isSavingSpoilerAiSettings ? null : save,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isErikaPlayerKernel =
        PlayerFactory.getKernelType() == PlayerKernelType.erika;
    final next2Supported = Next2PlatformSupport.isKernelSupported;
    final showNextPlusPlusToggle =
        _selectedDanmakuRenderEngine == DanmakuRenderEngine.nipaplayNext;
    final showRendererSupersample = !isErikaPlayerKernel &&
        (_selectedDanmakuRenderEngine == DanmakuRenderEngine.next2 ||
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus);
    final renderEngineItems = _buildDanmakuRenderEngineItems(
      next2Supported: next2Supported,
    );

    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          addDividers: false,
          children: [
            if (!isErikaPlayerKernel) ...[
              AdaptiveSettingsTile.dropdown(
                title: '弹幕渲染引擎',
                subtitle: '选择弹幕的渲染方式',
                icon: Ionicons.hardware_chip_outline,
                items: renderEngineItems,
                onChanged: (dynamic value) {
                  if (value is! DanmakuRenderEngine) return;
                  if (!next2Supported &&
                      (value == DanmakuRenderEngine.next2 ||
                          value == DanmakuRenderEngine.dfmPlus)) {
                    return;
                  }
                  _saveDanmakuRenderEngineSettings(value);
                },
                dropdownKey: _danmakuRenderEngineDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (showNextPlusPlusToggle) ...[
              AdaptiveSettingsTile.toggle(
                title: 'Next++ 激进优化引擎',
                subtitle: '开启后使用 Next++ 优化路径，关闭则回退至 Next 原始引擎路径',
                icon: Ionicons.rocket_outline,
                value: DanmakuKernelFactory.isNextPlusPlusEnabled,
                onChanged: _saveNextPlusPlusEngineSetting,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (showRendererSupersample)
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
                  return AdaptiveSettingsTile.dropdown(
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
            if (showRendererSupersample)
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                return AdaptiveSettingsTile.toggle(
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
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile.toggle(
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
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final showTrackGapSlider =
                    isErikaPlayerKernel || _isDfmPlusKernel;
                final showStackingToggle = isErikaPlayerKernel ||
                    (DanmakuKernelFactory.getKernelType() !=
                            DanmakuRenderEngine.canvas &&
                        DanmakuKernelFactory.getKernelType() !=
                            DanmakuRenderEngine.nipaplayNext &&
                        DanmakuKernelFactory.getKernelType() !=
                            DanmakuRenderEngine.next2 &&
                        DanmakuKernelFactory.getKernelType() !=
                            DanmakuRenderEngine.dfmPlus);

                return Column(
                  children: [
                    AdaptiveSettingsTile.toggle(
                      title: '随机染色',
                      subtitle: '忽略弹幕原始颜色，按发送弹幕预设色随机分配',
                      icon: Ionicons.color_palette_outline,
                      value: videoState.danmakuRandomColorEnabled,
                      onChanged: (value) {
                        videoState.setDanmakuRandomColorEnabled(value);
                      },
                    ),
                    Divider(
                        color: colorScheme.onSurface.withValues(alpha: 0.12),
                        height: 1),
                    AdaptiveSettingsTile.toggle(
                      title: '时间轴告知',
                      subtitle: '在视频特定进度(25%/50%/75%/90%)显示弹幕提示',
                      icon: Ionicons.notifications_outline,
                      value: videoState.isTimelineDanmakuEnabled,
                      onChanged: (value) {
                        videoState.toggleTimelineDanmaku(value);
                      },
                    ),
                    if (showTrackGapSlider) ...[
                      Divider(
                          color: colorScheme.onSurface.withValues(alpha: 0.12),
                          height: 1),
                      AdaptiveSettingsTile.slider(
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
                    if (showStackingToggle) ...[
                      Divider(
                          color: colorScheme.onSurface.withValues(alpha: 0.12),
                          height: 1),
                      AdaptiveSettingsTile.toggle(
                        title: '弹幕堆叠',
                        subtitle: '允许多条弹幕重叠显示，适合弹幕密集场景',
                        icon: Ionicons.layers_outline,
                        value: videoState.danmakuStacking,
                        onChanged: (value) {
                          videoState.setDanmakuStacking(value);
                        },
                      ),
                    ],
                  ],
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AdaptiveSettingsTile.toggle(
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
                    Divider(
                      color: colorScheme.onSurface.withValues(alpha: 0.12),
                      height: 1,
                    ),
                    AdaptiveSettingsTile.card(
                      title: '防剧透 AI 设置',
                      subtitle: videoState.spoilerAiConfigReady
                          ? '已配置：${_spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini ? 'Gemini' : 'OpenAI 兼容'} / ${_spoilerAiModelController.text.trim()}'
                          : '未配置，开启防剧透前需要填写接口 URL / Key / 模型',
                      icon: Ionicons.settings_outline,
                      onTap: () => _showSpoilerAiSettingsDialog(videoState),
                    ),
                  ],
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                final currentStrategy =
                    settingsProvider.danmakuAutoLoadStrategy;
                final items = DanmakuAutoLoadStrategy.values
                    .map(
                      (strategy) =>
                          DropdownMenuItemData<DanmakuAutoLoadStrategy>(
                        title: _danmakuAutoLoadStrategyLabel(strategy),
                        value: strategy,
                        isSelected: currentStrategy == strategy,
                        description:
                            _danmakuAutoLoadStrategyDescription(strategy),
                      ),
                    )
                    .toList();
                return AdaptiveSettingsTile.dropdown(
                  title: context.l10n.danmakuAutoLoadStrategyTitle,
                  subtitle:
                      _danmakuAutoLoadStrategyDescription(currentStrategy),
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
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile.toggle(
                  title: '哈希匹配失败自动匹配弹幕',
                  subtitle: '哈希匹配失败时，默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单',
                  icon: Ionicons.search_outline,
                  value: settingsProvider
                      .autoMatchDanmakuFirstSearchResultOnHashFail,
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
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
          ],
        ),
      ],
    );
  }
}

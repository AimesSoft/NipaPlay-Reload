import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/danmaku_next/next2_platform_support.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/models/danmaku/style.dart';
import 'package:nipaplay/models/danmaku_auto_load_strategy.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart'
    show AdaptiveSlider;
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_editable_slider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/nipaplay_window.dart';
import 'package:nipaplay/themes/nipaplay/widgets/tvos_remote_text_input_scope.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/plugins/plugin_service.dart';
import 'package:nipaplay/plugins/models/plugin_danmaku_renderer.dart';
import 'package:nipaplay/plugins/danmaku/titan_danmaku_settings.dart';

class DanmakuSettingsContent extends StatefulWidget {
  const DanmakuSettingsContent({super.key});

  @override
  State<DanmakuSettingsContent> createState() => _DanmakuSettingsContentState();
}

class _DanmakuSettingsContentState extends State<DanmakuSettingsContent> {
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;
  String? _selectedPluginDanmakuRendererId;

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
  bool _isSpoilerAiSettingsSheetVisible = false;
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
      _selectedPluginDanmakuRendererId =
          DanmakuKernelFactory.activePluginRenderer?.selectionId;
    });
  }

  Future<void> _saveDanmakuRenderEngineSettings(
      DanmakuRenderEngine engine) async {
    await DanmakuKernelFactory.saveKernelType(engine);

    if (!mounted) return;
    BlurSnackBar.show(context, '弹幕渲染引擎已切换');

    setState(() {
      _selectedDanmakuRenderEngine = DanmakuKernelFactory.getKernelType();
      _selectedPluginDanmakuRendererId = null;
    });
  }

  Future<void> _savePluginDanmakuRendererSettings(
    PluginDanmakuRenderer renderer,
  ) async {
    await DanmakuKernelFactory.savePluginRenderer(renderer.selectionId);
    if (!mounted) return;
    BlurSnackBar.show(context, '弹幕渲染引擎已切换');
    setState(() {
      _selectedPluginDanmakuRendererId = renderer.selectionId;
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

  List<DropdownMenuItemData<Object>> _buildDanmakuRenderEngineItems({
    required bool next2Supported,
    required List<PluginDanmakuRenderer> pluginRenderers,
  }) {
    final hasPluginSelection = _selectedPluginDanmakuRendererId != null;
    final items = <DropdownMenuItemData<Object>>[
      DropdownMenuItemData(
        title: 'CPU 渲染',
        value: DanmakuRenderEngine.cpu,
        isSelected: !hasPluginSelection &&
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.cpu,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.cpu),
      ),
      DropdownMenuItemData(
        title: 'GPU 渲染 (实验性)',
        value: DanmakuRenderEngine.gpu,
        isSelected: !hasPluginSelection &&
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.gpu,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.gpu),
      ),
      DropdownMenuItemData(
        title: 'Canvas 弹幕 (实验性)',
        value: DanmakuRenderEngine.canvas,
        isSelected: !hasPluginSelection &&
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.canvas,
        description:
            _getDanmakuRenderEngineDescription(DanmakuRenderEngine.canvas),
      ),
      DropdownMenuItemData(
        title: DanmakuKernelFactory.nipaplayNextDisplayName,
        value: DanmakuRenderEngine.nipaplayNext,
        isSelected: !hasPluginSelection &&
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
          isSelected: !hasPluginSelection &&
              _selectedDanmakuRenderEngine == DanmakuRenderEngine.next2,
          description:
              _getDanmakuRenderEngineDescription(DanmakuRenderEngine.next2),
        ),
      );
      items.add(
        DropdownMenuItemData(
          title: 'DFM+',
          value: DanmakuRenderEngine.dfmPlus,
          isSelected: !hasPluginSelection &&
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

    for (final renderer in pluginRenderers) {
      items.add(
        DropdownMenuItemData<Object>(
          title: renderer.name,
          value: renderer,
          isSelected: renderer.selectionId == _selectedPluginDanmakuRendererId,
          description: renderer.description.isEmpty
              ? '由插件 ${renderer.pluginId} 提供的 WebView 弹幕渲染器'
              : renderer.description,
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
      final hideNativeIOS26Switches = usesNativeIOS26SettingsControls;
      if (hideNativeIOS26Switches) {
        // UIKit platform views sit above Flutter overlays. Remove the switches
        // for a complete frame before presenting the nested bottom sheet.
        setState(() {
          _isSpoilerAiSettingsSheetVisible = true;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }

      try {
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
      } finally {
        if (hideNativeIOS26Switches && mounted) {
          setState(() {
            _isSpoilerAiSettingsSheetVisible = false;
          });
        }
      }
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
        TvOSRemoteTextInputControl(
          title: '接口 URL',
          child: TextField(
            controller: _spoilerAiUrlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '接口 URL',
              hintText: urlHint,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TvOSRemoteTextInputControl(
          title: '模型',
          child: TextField(
            controller: _spoilerAiModelController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: '模型',
              hintText: modelHint,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TvOSRemoteTextInputControl(
          title: 'API Key',
          child: TextField(
            controller: _spoilerAiApiKeyController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'API Key',
              hintText: '请输入你的 API Key',
            ),
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
    context.watch<PluginService>();
    final videoState = context.watch<VideoPlayerState>();
    final colorScheme = Theme.of(context).colorScheme;
    final isErikaPlayerKernel = globals.isTvOS ||
        PlayerFactory.getKernelType() == PlayerKernelType.erika;
    final next2Supported = Next2PlatformSupport.isKernelSupported;
    final selectedPluginRenderer = DanmakuKernelFactory.activePluginRenderer;
    final effectivePluginRenderer = PluginDanmakuRenderer.resolveForPlayback(
      selectedRenderer: selectedPluginRenderer,
      nativeDanmakuActive: isErikaPlayerKernel,
    );
    final hasPluginRenderer = effectivePluginRenderer != null;
    final usesTitanSettings =
        effectivePluginRenderer?.usesTitanSettings ?? false;
    _selectedPluginDanmakuRendererId = selectedPluginRenderer?.selectionId;
    final showNextPlusPlusToggle = !hasPluginRenderer &&
        !globals.isTvOS &&
        _selectedDanmakuRenderEngine == DanmakuRenderEngine.nipaplayNext;
    final showRendererSupersample = !hasPluginRenderer &&
        !isErikaPlayerKernel &&
        (_selectedDanmakuRenderEngine == DanmakuRenderEngine.next2 ||
            _selectedDanmakuRenderEngine == DanmakuRenderEngine.dfmPlus);
    final renderEngineItems = _buildDanmakuRenderEngineItems(
      next2Supported: next2Supported,
      pluginRenderers: DanmakuKernelFactory.availablePluginRenderers,
    );
    final canSelectRenderer = !isErikaPlayerKernel;

    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          addDividers: false,
          children: [
            if (canSelectRenderer) ...[
              AdaptiveSettingsTile.dropdown(
                title: '弹幕渲染引擎',
                subtitle: '选择弹幕的渲染方式',
                icon: Ionicons.hardware_chip_outline,
                items: renderEngineItems,
                onChanged: (dynamic value) {
                  if (value is PluginDanmakuRenderer) {
                    _savePluginDanmakuRendererSettings(value);
                    return;
                  }
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
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
            if (usesTitanSettings)
              AdaptiveSettingsTile.slider(
                title: 'Titan 弹幕不透明度',
                subtitle: '使用 Titan 原生透明度，默认 85%',
                icon: Icons.opacity,
                value: videoState.titanDanmakuSettings.opacity,
                min: 0.2,
                max: 1.0,
                divisions: 16,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(opacity: value),
                  );
                },
                labelFormatter: (value) => '${(value * 100).round()}%',
              )
            else
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.slider(
                    title: context.l10n.danmakuOpacityTitle,
                    subtitle: context.l10n.danmakuOpacitySubtitle,
                    icon: Icons.opacity,
                    value: videoState.danmakuOpacity,
                    min: 0,
                    max: 1,
                    divisions: 100,
                    onChanged: videoState.setDanmakuOpacity,
                    labelFormatter: (value) => '${(value * 100).round()}%',
                  );
                },
              ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            if (usesTitanSettings)
              AdaptiveSettingsTile.slider(
                title: 'Titan 字号倍率',
                subtitle: '使用 Titan 原生字号倍率，不改变其他弹幕引擎的像素字号',
                icon: Icons.format_size,
                value: videoState.titanDanmakuSettings.fontSize,
                min: 0.5,
                max: 2.0,
                divisions: 30,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(fontSize: value),
                  );
                },
                labelFormatter: (value) => '${value.toStringAsFixed(2)}×',
              )
            else
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  final currentFontSize = videoState.danmakuFontSize <= 0
                      ? videoState.actualDanmakuFontSize
                      : videoState.danmakuFontSize;
                  return AdaptiveSettingsTile.slider(
                    title: context.l10n.danmakuFontSizeTitle,
                    subtitle: '调整弹幕文字大小，轨道间距会自动适配',
                    icon: Icons.format_size,
                    value: currentFontSize.clamp(
                      DanmakuStyle.minDanmakuFontSize,
                      DanmakuStyle.maxDanmakuFontSize,
                    ),
                    min: DanmakuStyle.minDanmakuFontSize,
                    max: DanmakuStyle.maxDanmakuFontSize,
                    divisions: 96,
                    onChanged: (value) {
                      videoState.setDanmakuFontSize(value, commit: true);
                    },
                    labelFormatter: (value) => '${value.toStringAsFixed(1)}px',
                  );
                },
              ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            if (usesTitanSettings) ...[
              AdaptiveSettingsTile.toggle(
                title: 'Titan 弹幕加粗',
                subtitle: '使用 Titan 原生粗体样式',
                icon: Icons.format_bold,
                value: videoState.titanDanmakuSettings.bold,
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(bold: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.dropdown(
                title: 'Titan 描边类型',
                subtitle: '选择重墨、描边或 45° 投影',
                icon: Icons.border_color,
                items: <DropdownMenuItemData<int>>[
                  for (final entry in const <int, String>{
                    0: '重墨',
                    1: '描边',
                    2: '45° 投影',
                  }.entries)
                    DropdownMenuItemData<int>(
                      title: entry.value,
                      value: entry.key,
                      isSelected: videoState.titanDanmakuSettings.fontBorder ==
                          entry.key,
                    ),
                ],
                onChanged: (dynamic value) {
                  if (value is! int) return;
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(fontBorder: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.dropdown(
                title: 'Titan 弹幕字体',
                subtitle: '字体未安装时 WebView 会自动回退到简体中文系统字体',
                icon: Icons.font_download_outlined,
                items: <DropdownMenuItemData<String>>[
                  for (final option in TitanDanmakuSettings.fontOptions)
                    DropdownMenuItemData<String>(
                      title: option.label,
                      value: option.value,
                      isSelected: videoState.titanDanmakuSettings.fontFamily ==
                          option.value,
                    ),
                ],
                onChanged: (dynamic value) {
                  if (value is! String) return;
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(fontFamily: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 滚动速度',
                subtitle: 'Titan 原生 speedPlus；不改变其他引擎速度',
                icon: Icons.speed,
                value: videoState.titanDanmakuSettings.speedPlus,
                min: 0.25,
                max: 3.0,
                divisions: 11,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(speedPlus: value),
                  );
                },
                labelFormatter: (value) => '${value.toStringAsFixed(2)}×',
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 弹幕密度',
                subtitle: '限制同屏轨道占用密度',
                icon: Icons.density_medium,
                value: videoState.titanDanmakuSettings.density,
                min: 0.1,
                max: 1.0,
                divisions: 9,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(density: value),
                  );
                },
                labelFormatter: (value) => value.toStringAsFixed(1),
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 基准时长',
                subtitle: '设置滚动弹幕的基础存活时间',
                icon: Icons.timer_outlined,
                value: videoState.titanDanmakuSettings.duration,
                min: 2.0,
                max: 12.0,
                divisions: 20,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings.copyWith(duration: value),
                  );
                },
                labelFormatter: (value) => '${value.toStringAsFixed(1)}s',
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 同屏上限',
                subtitle: '0 表示由引擎决定；最高可设置为 1000',
                icon: Icons.format_list_numbered,
                value: videoState.titanDanmakuSettings.limit
                    .clamp(0, 1000)
                    .toDouble(),
                min: 0,
                max: 1000,
                divisions: 20,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(limit: value.round()),
                  );
                },
                labelFormatter: (value) => value.round().toString(),
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.toggle(
                title: 'Titan 防挡字幕',
                subtitle: '避免弹幕覆盖画面底部的字幕区域',
                icon: Icons.layers_clear_outlined,
                value: videoState.titanDanmakuSettings.preventShade,
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(preventShade: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 顶部偏移',
                subtitle: '调整顶部弹幕轨道的像素偏移',
                icon: Icons.vertical_align_top,
                value: videoState.titanDanmakuSettings.offsetTop.toDouble(),
                min: -100,
                max: 100,
                divisions: 200,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(offsetTop: value.round()),
                  );
                },
                labelFormatter: (value) => '${value.round()}px',
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 底部偏移',
                subtitle: '调整底部弹幕轨道的像素偏移',
                icon: Icons.vertical_align_bottom,
                value: videoState.titanDanmakuSettings.offsetBottom.toDouble(),
                min: -100,
                max: 100,
                divisions: 200,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(offsetBottom: value.round()),
                  );
                },
                labelFormatter: (value) => '${value.round()}px',
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.slider(
                title: 'Titan 最大长度',
                subtitle: '限制单条弹幕文字长度；0 表示不限制',
                icon: Icons.straighten,
                value: videoState.titanDanmakuSettings.maxLength
                    .clamp(0, 200)
                    .toDouble(),
                min: 0,
                max: 200,
                divisions: 20,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(maxLength: value.round()),
                  );
                },
                labelFormatter: (value) => value.round().toString(),
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.toggle(
                title: 'Titan DOM 回收',
                subtitle: '复用已经离屏的弹幕 DOM 节点',
                icon: Icons.recycling,
                value: videoState.titanDanmakuSettings.isRecyclingDom,
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(isRecyclingDom: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.toggle(
                title: 'Titan 模型回收',
                subtitle: '复用引擎内部弹幕模型；默认关闭',
                icon: Icons.memory,
                value: videoState.titanDanmakuSettings.isRecyclingModel,
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(isRecyclingModel: value),
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              AdaptiveSettingsTile.toggle(
                title: 'Titan 禁止缩小',
                subtitle: '轨道拥挤时不自动缩小弹幕文字',
                icon: Icons.text_decrease,
                value: videoState.titanDanmakuSettings.forbidShrinkState,
                hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                onChanged: (value) {
                  videoState.setTitanDanmakuSettings(
                    videoState.titanDanmakuSettings
                        .copyWith(forbidShrinkState: value),
                  );
                },
              ),
            ] else
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.slider(
                    title: context.l10n.danmakuOutlineWidthTitle,
                    subtitle: context.l10n.danmakuOutlineEnabledSubtitle,
                    icon: Icons.border_color,
                    value: videoState.next2DanmakuOutlineWidth,
                    min: 0.0,
                    max: 2.0,
                    divisions: 2,
                    onChanged: videoState.setNext2DanmakuOutlineWidth,
                    labelFormatter: (value) => value.round().toString(),
                  );
                },
              ),
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
                  hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                return AdaptiveSettingsTile.slider(
                  title: '手动弹幕偏移',
                  subtitle: '调整弹幕与视频时间的对齐，负值提前，正值延后',
                  icon: Icons.schedule,
                  value: videoState.manualDanmakuOffset.clamp(-10.0, 10.0),
                  min: -10.0,
                  max: 10.0,
                  divisions: 200,
                  onChanged: (value) {
                    videoState.setManualDanmakuOffset(value);
                  },
                  labelFormatter: (value) {
                    if (value.abs() < 0.0001) return '0s';
                    final sign = value > 0 ? '+' : '';
                    return '${sign}${value.toStringAsFixed(1)}s';
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
                  hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
                      hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
                      hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
                        hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
                      hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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
                return AdaptiveSettingsTile.toggle(
                  title: context.l10n.skipDanmakuMatchingTitle,
                  subtitle: context.l10n.skipDanmakuMatchingDescription,
                  icon: Ionicons.hand_left_outline,
                  value: settingsProvider.skipDanmakuMatching,
                  hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
                  onChanged: (bool value) async {
                    await settingsProvider.setSkipDanmakuMatching(value);
                    if (context.mounted) {
                      BlurSnackBar.show(
                        context,
                        value
                            ? context.l10n.skipDanmakuMatchingEnabled
                            : context.l10n.skipDanmakuMatchingDisabled,
                      );
                    }
                  },
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
                    .where(
                      (strategy) => strategy != DanmakuAutoLoadStrategy.manual,
                    )
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
                  hideNativeIOS26Switch: _isSpoilerAiSettingsSheetVisible,
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

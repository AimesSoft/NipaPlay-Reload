import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:provider/provider.dart';

import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoDanmakuSettingsPage extends StatefulWidget {
  const CupertinoDanmakuSettingsPage({super.key});

  @override
  State<CupertinoDanmakuSettingsPage> createState() =>
      _CupertinoDanmakuSettingsPageState();
}

class _CupertinoDanmakuSettingsPageState
    extends State<CupertinoDanmakuSettingsPage> {
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;

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
    AdaptiveSnackBar.show(
      context,
      message: context.l10n.danmakuRenderEngineSwitched,
      type: AdaptiveSnackBarType.success,
    );
    setState(() {
      _selectedDanmakuRenderEngine = engine;
    });
  }

  Future<void> _saveSpoilerAiSettings(VideoPlayerState videoState) async {
    if (_isSavingSpoilerAiSettings) return;

    final url = _spoilerAiUrlController.text.trim();
    final model = _spoilerAiModelController.text.trim();
    final apiKeyInput = _spoilerAiApiKeyController.text.trim();

    if (url.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.enterAiApiUrl,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (model.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.enterModelName,
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (apiKeyInput.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.enterApiKey,
        type: AdaptiveSnackBarType.error,
      );
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
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.spoilerAiSettingsSaved,
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: context.l10n.saveFailedWithError('$e'),
        type: AdaptiveSnackBarType.error,
      );
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
        return context.l10n.danmakuRenderEngineDescriptionCpu;
      case DanmakuRenderEngine.gpu:
        return context.l10n.danmakuRenderEngineDescriptionGpuExperimental;
      case DanmakuRenderEngine.canvas:
        return context.l10n.danmakuRenderEngineDescriptionCanvasExperimental;
      case DanmakuRenderEngine.nipaplayNext:
        return context.l10n.danmakuRenderEngineDescriptionNipaplayNext;
    }
  }

  String _danmakuTitle(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return context.l10n.danmakuRenderEngineTitleCpu;
      case DanmakuRenderEngine.gpu:
        return context.l10n.danmakuRenderEngineTitleGpuExperimental;
      case DanmakuRenderEngine.canvas:
        return context.l10n.danmakuRenderEngineTitleCanvasExperimental;
      case DanmakuRenderEngine.nipaplayNext:
        return context.l10n.danmakuRenderEngineTitleNipaplayNext;
    }
  }

  List<AdaptivePopupMenuEntry> _danmakuMenuItems() {
    return DanmakuRenderEngine.values
        .map(
          (engine) => AdaptivePopupMenuItem<DanmakuRenderEngine>(
            label: _danmakuTitle(engine),
            value: engine,
          ),
        )
        .toList();
  }

  String _spoilerAiFormatTitle(
    BuildContext context,
    SpoilerAiApiFormat format,
  ) {
    switch (format) {
      case SpoilerAiApiFormat.openai:
        return context.l10n.openAiCompatible;
      case SpoilerAiApiFormat.gemini:
        return 'Gemini';
    }
  }

  List<AdaptivePopupMenuEntry> _spoilerAiFormatMenuItems(BuildContext context) {
    return [
      AdaptivePopupMenuItem<SpoilerAiApiFormat>(
        label: context.l10n.openAiCompatible,
        value: SpoilerAiApiFormat.openai,
      ),
      const AdaptivePopupMenuItem<SpoilerAiApiFormat>(
        label: 'Gemini',
        value: SpoilerAiApiFormat.gemini,
      ),
    ];
  }

  Widget _buildMenuChip(BuildContext context, String label) {
    final Color background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGrey5,
      context,
    );

    final Color textColor = CupertinoDynamicColor.resolve(
      CupertinoColors.label,
      context,
    );

    return Container(
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final Color sectionBackground = resolveSettingsSectionBackground(context);
    final Color tileBackground = resolveSettingsTileBackground(context);
    final double topPadding = MediaQuery.of(context).padding.top + 64;

    final sections = <Widget>[
      CupertinoSettingsGroupCard(
        margin: EdgeInsets.zero,
        backgroundColor: sectionBackground,
        addDividers: true,
        dividerIndent: 16,
        children: [
          CupertinoSettingsTile(
            leading: Icon(
              CupertinoIcons.bubble_left_bubble_right,
              color: resolveSettingsIconColor(context),
            ),
            title: Text(context.l10n.danmakuRenderEngine),
            subtitle: Text(
              _getDanmakuRenderEngineDescription(_selectedDanmakuRenderEngine),
            ),
            trailing: AdaptivePopupMenuButton.widget<DanmakuRenderEngine>(
              items: _danmakuMenuItems(),
              buttonStyle: PopupButtonStyle.gray,
              child: _buildMenuChip(
                context,
                _danmakuTitle(_selectedDanmakuRenderEngine),
              ),
              onSelected: (index, entry) {
                final engine = entry.value ?? DanmakuRenderEngine.values[index];
                if (engine != _selectedDanmakuRenderEngine) {
                  _saveDanmakuRenderEngineSettings(engine);
                }
              },
            ),
            backgroundColor: tileBackground,
          ),
        ],
      ),
      const SizedBox(height: 16),
      Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          return CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            backgroundColor: sectionBackground,
            addDividers: true,
            dividerIndent: 16,
            children: [
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.timer,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(context.l10n.rememberDanmakuOffset),
                    subtitle: Text(context.l10n.rememberDanmakuOffsetSubtitle),
                    trailing: AdaptiveSwitch(
                      value: videoState.rememberDanmakuOffset,
                      onChanged: (value) async {
                        await videoState.setRememberDanmakuOffset(value);
                        if (!mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: value
                              ? context.l10n.rememberDanmakuOffsetEnabled
                              : context.l10n.rememberDanmakuOffsetDisabled,
                          type: AdaptiveSnackBarType.success,
                        );
                      },
                    ),
                    onTap: () async {
                      final bool newValue = !videoState.rememberDanmakuOffset;
                      await videoState.setRememberDanmakuOffset(newValue);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: newValue
                            ? context.l10n.rememberDanmakuOffsetEnabled
                            : context.l10n.rememberDanmakuOffsetDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                    backgroundColor: tileBackground,
                  );
                },
              ),
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.textformat_abc,
                  color: resolveSettingsIconColor(context),
                ),
                title: Text(context.l10n.danmakuConvertToSimplified),
                subtitle: Text(context.l10n.danmakuConvertToSimplifiedSubtitle),
                trailing: AdaptiveSwitch(
                  value: settingsProvider.danmakuConvertToSimplified,
                  onChanged: (value) {
                    settingsProvider.setDanmakuConvertToSimplified(value);
                    if (mounted) {
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.danmakuConvertToSimplifiedEnabled
                            : context.l10n.danmakuConvertToSimplifiedDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    }
                  },
                ),
                onTap: () {
                  final bool newValue =
                      !settingsProvider.danmakuConvertToSimplified;
                  settingsProvider.setDanmakuConvertToSimplified(newValue);
                  if (mounted) {
                    AdaptiveSnackBar.show(
                      context,
                      message: newValue
                          ? context.l10n.danmakuConvertToSimplifiedEnabled
                          : context.l10n.danmakuConvertToSimplifiedDisabled,
                      type: AdaptiveSnackBarType.success,
                    );
                  }
                },
                backgroundColor: tileBackground,
              ),
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.eye_slash,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(context.l10n.spoilerPreventionMode),
                    subtitle: Text(
                      context.l10n.spoilerPreventionModeSubtitle,
                    ),
                    trailing: AdaptiveSwitch(
                      value: videoState.spoilerPreventionEnabled,
                      onChanged: (value) async {
                        if (value && !videoState.spoilerAiConfigReady) {
                          AdaptiveSnackBar.show(
                            context,
                            message: context.l10n.fillAndSaveAiConfigFirst,
                            type: AdaptiveSnackBarType.error,
                          );
                          return;
                        }
                        await videoState.setSpoilerPreventionEnabled(value);
                        if (!mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: value
                              ? context.l10n.spoilerPreventionModeEnabled
                              : context.l10n.spoilerPreventionModeDisabled,
                          type: AdaptiveSnackBarType.success,
                        );
                      },
                    ),
                    onTap: () async {
                      final bool newValue =
                          !videoState.spoilerPreventionEnabled;
                      if (newValue && !videoState.spoilerAiConfigReady) {
                        AdaptiveSnackBar.show(
                          context,
                          message: context.l10n.fillAndSaveAiConfigFirst,
                          type: AdaptiveSnackBarType.error,
                        );
                        return;
                      }
                      await videoState.setSpoilerPreventionEnabled(newValue);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: newValue
                            ? context.l10n.spoilerPreventionModeEnabled
                            : context.l10n.spoilerPreventionModeDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                    backgroundColor: tileBackground,
                  );
                },
              ),
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.refresh,
                  color: resolveSettingsIconColor(context),
                ),
                title: Text(context.l10n.autoMatchDanmakuOnPlayTitle),
                subtitle: Text(context.l10n.autoMatchDanmakuOnPlaySubtitle),
                trailing: AdaptiveSwitch(
                  value: settingsProvider.autoMatchDanmakuOnPlay,
                  onChanged: (value) {
                    settingsProvider.setAutoMatchDanmakuOnPlay(value);
                    if (mounted) {
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.autoMatchDanmakuOnPlayEnabled
                            : context.l10n.autoMatchDanmakuOnPlayDisabledManual,
                        type: AdaptiveSnackBarType.success,
                      );
                    }
                  },
                ),
                onTap: () {
                  final bool newValue =
                      !settingsProvider.autoMatchDanmakuOnPlay;
                  settingsProvider.setAutoMatchDanmakuOnPlay(newValue);
                  if (mounted) {
                    AdaptiveSnackBar.show(
                      context,
                      message: newValue
                          ? context.l10n.autoMatchDanmakuOnPlayEnabled
                          : context.l10n.autoMatchDanmakuOnPlayDisabledManual,
                      type: AdaptiveSnackBarType.success,
                    );
                  }
                },
                backgroundColor: tileBackground,
              ),
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.search,
                  color: resolveSettingsIconColor(context),
                ),
                title: Text(context.l10n.autoMatchOnHashFailTitle),
                subtitle: Text(context.l10n.autoMatchOnHashFailSubtitle),
                trailing: AdaptiveSwitch(
                  value: settingsProvider
                      .autoMatchDanmakuFirstSearchResultOnHashFail,
                  onChanged: (value) {
                    settingsProvider
                        .setAutoMatchDanmakuFirstSearchResultOnHashFail(value);
                    if (mounted) {
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.autoMatchOnHashFailEnabled
                            : context
                                .l10n.autoMatchOnHashFailDisabledShowSearch,
                        type: AdaptiveSnackBarType.success,
                      );
                    }
                  },
                ),
                onTap: () {
                  final bool newValue = !settingsProvider
                      .autoMatchDanmakuFirstSearchResultOnHashFail;
                  settingsProvider
                      .setAutoMatchDanmakuFirstSearchResultOnHashFail(newValue);
                  if (mounted) {
                    AdaptiveSnackBar.show(
                      context,
                      message: newValue
                          ? context.l10n.autoMatchOnHashFailEnabled
                          : context.l10n.autoMatchOnHashFailDisabledShowSearch,
                      type: AdaptiveSnackBarType.success,
                    );
                  }
                },
                backgroundColor: tileBackground,
              ),
            ],
          );
        },
      ),
      Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          final bool isGemini =
              _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
          final urlHint = isGemini
              ? 'https://generativelanguage.googleapis.com/v1beta/models'
              : 'https://api.openai.com/v1/chat/completions';
          final modelHint = isGemini ? 'gemini-1.5-flash' : 'gpt-5';

          final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
          final Color subtitleColor =
              resolveSettingsSecondaryTextColor(context);
          final Color iconColor = resolveSettingsIconColor(context);

          return Column(
            children: [
              const SizedBox(height: 16),
              CupertinoSettingsGroupCard(
                margin: EdgeInsets.zero,
                backgroundColor: sectionBackground,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(CupertinoIcons.settings,
                                size: 18, color: iconColor),
                            const SizedBox(width: 8),
                            Text(
                              context.l10n.spoilerAiSettingsTitle,
                              style: textTheme.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.l10n.spoilerAiSettingsDescription,
                          style: textTheme.copyWith(
                            fontSize: 13,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isGemini
                              ? context.l10n.spoilerAiGeminiUrlNote
                              : context.l10n.spoilerAiOpenAiUrlNote,
                          style: textTheme.copyWith(
                            fontSize: 13,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              context.l10n.apiFormatLabel,
                              style: textTheme.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            AdaptivePopupMenuButton.widget<SpoilerAiApiFormat>(
                              items: _spoilerAiFormatMenuItems(context),
                              buttonStyle: PopupButtonStyle.gray,
                              child: _buildMenuChip(
                                context,
                                _spoilerAiFormatTitle(
                                  context,
                                  _spoilerAiApiFormatDraft,
                                ),
                              ),
                              onSelected: (index, entry) {
                                final format = entry.value ??
                                    SpoilerAiApiFormat.values[index];
                                setState(() {
                                  _spoilerAiApiFormatDraft = format;
                                });
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        CupertinoTextField(
                          controller: _spoilerAiUrlController,
                          placeholder: urlHint,
                          keyboardType: TextInputType.url,
                          autocorrect: false,
                          enableSuggestions: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.tertiarySystemFill,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CupertinoTextField(
                          controller: _spoilerAiModelController,
                          placeholder: modelHint,
                          autocorrect: false,
                          enableSuggestions: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.tertiarySystemFill,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        CupertinoTextField(
                          controller: _spoilerAiApiKeyController,
                          placeholder: context.l10n.enterYourApiKey,
                          autocorrect: false,
                          enableSuggestions: false,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.tertiarySystemFill,
                              context,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.l10n.temperatureLabel(
                            _spoilerAiTemperatureDraft.toStringAsFixed(2),
                          ),
                          style: textTheme.copyWith(
                            fontSize: 13,
                            color: subtitleColor,
                          ),
                        ),
                        CupertinoSlider(
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
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: SizedBox(
                            height: 36,
                            child: CupertinoButton.filled(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 0),
                              onPressed: _isSavingSpoilerAiSettings
                                  ? null
                                  : () => _saveSpoilerAiSettings(videoState),
                              child: _isSavingSpoilerAiSettings
                                  ? const CupertinoActivityIndicator(radius: 8)
                                  : Text(context.l10n.saveConfiguration),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ];

    return AdaptiveScaffold(
      appBar: AdaptiveAppBar(
        title: '弹幕',
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: ListView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: EdgeInsets.fromLTRB(16, topPadding, 16, 32),
            children: sections,
          ),
        ),
      ),
    );
  }
}

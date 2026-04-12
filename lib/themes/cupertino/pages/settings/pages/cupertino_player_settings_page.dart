import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:nipaplay/themes/cupertino/cupertino_imports.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/anime4k_shader_manager.dart';
import 'package:nipaplay/utils/crt_shader_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';
import 'package:nipaplay/services/file_picker_service.dart';

import 'package:nipaplay/utils/cupertino_settings_colors.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_group_card.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_settings_tile.dart';

class CupertinoPlayerSettingsPage extends StatefulWidget {
  const CupertinoPlayerSettingsPage({super.key});

  @override
  State<CupertinoPlayerSettingsPage> createState() =>
      _CupertinoPlayerSettingsPageState();
}

class _CupertinoPlayerSettingsPageState
    extends State<CupertinoPlayerSettingsPage> {
  static const String _selectedDecodersKey = 'selected_decoders';

  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;
  bool _initialized = false;
  bool _initializing = false;

  final TextEditingController _spoilerAiUrlController = TextEditingController();
  final TextEditingController _spoilerAiModelController =
      TextEditingController();
  final TextEditingController _spoilerAiApiKeyController =
      TextEditingController();
  bool _spoilerAiControllersInitialized = false;
  bool _isSavingSpoilerAiSettings = false;
  SpoilerAiApiFormat _spoilerAiApiFormatDraft = SpoilerAiApiFormat.openai;
  double _spoilerAiTemperatureDraft = 0.5;
  Anime4KProfile? _anime4kSelectionOverride;
  CrtProfile? _crtSelectionOverride;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized || kIsWeb) return;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _decoderManager = videoState.decoderManager;
    _initializing = true;
    _loadSettings();

    if (!_spoilerAiControllersInitialized) {
      _spoilerAiApiFormatDraft = videoState.spoilerAiApiFormat;
      _spoilerAiTemperatureDraft = videoState.spoilerAiTemperature;
      _spoilerAiUrlController.text = videoState.spoilerAiApiUrl;
      _spoilerAiModelController.text = videoState.spoilerAiModel;
      _spoilerAiApiKeyController.text = videoState.spoilerAiApiKey;
      _spoilerAiControllersInitialized = true;
    }

    _initialized = true;
  }

  @override
  void dispose() {
    _spoilerAiUrlController.dispose();
    _spoilerAiModelController.dispose();
    _spoilerAiApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    if (!kIsWeb) {
      _getAvailableDecoders();
      await _loadDecoderSettings();
    }
    await _loadPlayerKernelSettings();
    await _loadDanmakuRenderEngineSettings();

    if (mounted) {
      setState(() {
        _initializing = false;
      });
    }
  }

  Future<void> _loadPlayerKernelSettings() async {
    setState(() {
      _selectedKernelType = PlayerFactory.getKernelType();
    });
  }

  Future<void> _savePlayerKernelSettings(PlayerKernelType kernelType) async {
    await PlayerFactory.saveKernelType(kernelType);
    if (!mounted) return;
    AdaptiveSnackBar.show(
      context,
      message: context.l10n.playerKernelSwitched,
      type: AdaptiveSnackBarType.success,
    );
    setState(() {
      _selectedKernelType = kernelType;
    });
  }

  Future<void> _loadDecoderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedDecoders = prefs.getStringList(_selectedDecodersKey);
      if (savedDecoders != null && savedDecoders.isNotEmpty) {
        _selectedDecoders = savedDecoders;
      } else {
        _initializeSelectedDecodersWithPlatformDefaults();
      }
    });
  }

  void _initializeSelectedDecodersWithPlatformDefaults() {
    final allDecoders = _decoderManager.getAllSupportedDecoders();
    if (Platform.isMacOS) {
      _selectedDecoders = List.from(allDecoders['macos']!);
    } else if (Platform.isIOS) {
      _selectedDecoders = List.from(allDecoders['ios']!);
    } else if (Platform.isWindows) {
      _selectedDecoders = List.from(allDecoders['windows']!);
    } else if (Platform.isLinux) {
      _selectedDecoders = List.from(allDecoders['linux']!);
    } else if (Platform.isAndroid) {
      _selectedDecoders = List.from(allDecoders['android']!);
    } else {
      _selectedDecoders = ['FFmpeg'];
    }
  }

  void _getAvailableDecoders() {
    final allDecoders = _decoderManager.getAllSupportedDecoders();

    if (Platform.isMacOS) {
      _availableDecoders = allDecoders['macos']!;
    } else if (Platform.isIOS) {
      _availableDecoders = allDecoders['ios']!;
    } else if (Platform.isWindows) {
      _availableDecoders = allDecoders['windows']!;
    } else if (Platform.isLinux) {
      _availableDecoders = allDecoders['linux']!;
    } else if (Platform.isAndroid) {
      _availableDecoders = allDecoders['android']!;
    } else {
      _availableDecoders = ['FFmpeg'];
    }

    _selectedDecoders
        .retainWhere((decoder) => _availableDecoders.contains(decoder));
    if (_selectedDecoders.isEmpty && _availableDecoders.isNotEmpty) {
      _initializeSelectedDecodersWithPlatformDefaults();
    }
  }

  Future<void> _loadDanmakuRenderEngineSettings() async {
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

  String _kernelDisplayName(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return 'MDK';
      case PlayerKernelType.videoPlayer:
        return 'Video Player';
      case PlayerKernelType.mediaKit:
        return 'Libmpv';
    }
  }

  String _getPlayerKernelDescription(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return context.l10n.playerKernelDescriptionMdk;
      case PlayerKernelType.videoPlayer:
        return context.l10n.playerKernelDescriptionVideoPlayer;
      case PlayerKernelType.mediaKit:
        return context.l10n.playerKernelDescriptionLibmpv;
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

  String _getAnime4KProfileTitle(Anime4KProfile profile) {
    switch (profile) {
      case Anime4KProfile.off:
        return context.l10n.qualityProfileOff;
      case Anime4KProfile.lite:
        return context.l10n.qualityProfileLite;
      case Anime4KProfile.standard:
        return context.l10n.qualityProfileStandard;
      case Anime4KProfile.high:
        return context.l10n.qualityProfileHigh;
    }
  }

  String _getAnime4KProfileDescription(Anime4KProfile profile) {
    switch (profile) {
      case Anime4KProfile.off:
        return context.l10n.anime4kProfileDescriptionOff;
      case Anime4KProfile.lite:
        return context.l10n.anime4kProfileDescriptionLite;
      case Anime4KProfile.standard:
        return context.l10n.anime4kProfileDescriptionStandard;
      case Anime4KProfile.high:
        return context.l10n.anime4kProfileDescriptionHigh;
    }
  }

  String _getCrtProfileTitle(CrtProfile profile) {
    switch (profile) {
      case CrtProfile.off:
        return context.l10n.qualityProfileOff;
      case CrtProfile.lite:
        return context.l10n.qualityProfileLite;
      case CrtProfile.standard:
        return context.l10n.qualityProfileStandard;
      case CrtProfile.high:
        return context.l10n.qualityProfileHigh;
    }
  }

  String _getCrtProfileDescription(CrtProfile profile) {
    switch (profile) {
      case CrtProfile.off:
        return context.l10n.crtProfileDescriptionOff;
      case CrtProfile.lite:
        return context.l10n.crtProfileDescriptionLite;
      case CrtProfile.standard:
        return context.l10n.crtProfileDescriptionStandard;
      case CrtProfile.high:
        return context.l10n.crtProfileDescriptionHigh;
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

  List<AdaptivePopupMenuEntry> _kernelMenuItems() {
    return PlayerKernelType.values
        .map(
          (kernel) => AdaptivePopupMenuItem<PlayerKernelType>(
            label: _kernelDisplayName(kernel),
            value: kernel,
          ),
        )
        .toList();
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

  List<AdaptivePopupMenuEntry> _anime4kMenuItems() {
    return Anime4KProfile.values
        .map(
          (profile) => AdaptivePopupMenuItem<Anime4KProfile>(
            label: _getAnime4KProfileTitle(profile),
            value: profile,
          ),
        )
        .toList();
  }

  List<AdaptivePopupMenuEntry> _playbackEndActionMenuItems() {
    return PlaybackEndAction.values
        .map(
          (action) => AdaptivePopupMenuItem<PlaybackEndAction>(
            label: action.label,
            value: action,
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

  Widget _buildAutoNextCountdownSlider(
    BuildContext context,
    VideoPlayerState videoState,
    bool isAutoNext,
  ) {
    final double value = videoState.autoNextCountdownSeconds.toDouble();
    final double minValue =
        AutoNextEpisodeService.minCountdownSeconds.toDouble();
    final double maxValue =
        AutoNextEpisodeService.maxCountdownSeconds.toDouble();
    final ValueChanged<double>? onChanged = isAutoNext
        ? (value) {
            videoState.setAutoNextCountdownSeconds(value.round());
          }
        : null;
    final Color accentColor = CupertinoTheme.of(context).primaryColor;

    final Widget slider = PlatformInfo.isIOS26OrHigher()
        ? AdaptiveSlider(
            value: value,
            min: minValue,
            max: maxValue,
            onChanged: onChanged,
            activeColor: accentColor,
          )
        : fluent.FluentTheme(
            data: fluent.FluentThemeData(
              brightness: CupertinoTheme.brightnessOf(context),
              accentColor: fluent.AccentColor.swatch({
                'normal': accentColor,
                'default': accentColor,
              }),
            ),
            child: fluent.Slider(
              value: value,
              min: minValue,
              max: maxValue,
              onChanged: onChanged,
            ),
          );

    return SizedBox(width: double.infinity, child: slider);
  }

  Widget _buildPrecacheBufferSizeSlider(
    BuildContext context,
    VideoPlayerState videoState,
    bool enabled,
  ) {
    final double value = videoState.precacheBufferSizeMb.toDouble();
    final double minValue = PlayerFactory.minPrecacheBufferSizeMb.toDouble();
    final double maxValue = PlayerFactory.maxPrecacheBufferSizeMb.toDouble();
    final ValueChanged<double>? onChanged = enabled
        ? (value) {
            videoState.setPrecacheBufferSizeMb(value.round());
          }
        : null;
    final Color accentColor = CupertinoTheme.of(context).primaryColor;

    final Widget slider = PlatformInfo.isIOS26OrHigher()
        ? AdaptiveSlider(
            value: value,
            min: minValue,
            max: maxValue,
            onChanged: onChanged,
            activeColor: accentColor,
          )
        : fluent.FluentTheme(
            data: fluent.FluentThemeData(
              brightness: CupertinoTheme.brightnessOf(context),
              accentColor: fluent.AccentColor.swatch({
                'normal': accentColor,
                'default': accentColor,
              }),
            ),
            child: fluent.Slider(
              value: value,
              min: minValue,
              max: maxValue,
              onChanged: onChanged,
            ),
          );

    return SizedBox(width: double.infinity, child: slider);
  }

  Widget _buildPrecacheBufferDurationSlider(
    BuildContext context,
    VideoPlayerState videoState,
    bool enabled,
  ) {
    final double value = videoState.precacheBufferDurationSeconds.toDouble();
    const double minValue = 1;
    const double maxValue = 120;
    final ValueChanged<double>? onChanged = enabled
        ? (value) {
            videoState.setPrecacheBufferDurationSeconds(value.round());
          }
        : null;
    final Color accentColor = CupertinoTheme.of(context).primaryColor;

    final Widget slider = PlatformInfo.isIOS26OrHigher()
        ? AdaptiveSlider(
            value: value,
            min: minValue,
            max: maxValue,
            onChanged: onChanged,
            activeColor: accentColor,
          )
        : fluent.FluentTheme(
            data: fluent.FluentThemeData(
              brightness: CupertinoTheme.brightnessOf(context),
              accentColor: fluent.AccentColor.swatch({
                'normal': accentColor,
                'default': accentColor,
              }),
            ),
            child: fluent.Slider(
              value: value,
              min: minValue,
              max: maxValue,
              onChanged: onChanged,
            ),
          );

    return SizedBox(width: double.infinity, child: slider);
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return AdaptiveScaffold(
        appBar: AdaptiveAppBar(
          title: context.l10n.player,
          useNativeToolbar: true,
        ),
        body: Center(
          child: Text(context.l10n.playerUnavailableOnWeb),
        ),
      );
    }

    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final sectionBackground = resolveSettingsSectionBackground(context);

    final double topPadding = MediaQuery.of(context).padding.top + 64;

    final Color tileBackground = resolveSettingsTileBackground(context);
    final bool externalSupported = globals.isDesktop;

    final List<Widget> sections = [
      CupertinoSettingsGroupCard(
        margin: EdgeInsets.zero,
        backgroundColor: sectionBackground,
        addDividers: true,
        dividerIndent: 16,
        children: [
          CupertinoSettingsTile(
            leading: Icon(
              CupertinoIcons.play_rectangle,
              color: resolveSettingsIconColor(context),
            ),
            title: Text(context.l10n.playerKernel),
            subtitle: Text(_getPlayerKernelDescription(_selectedKernelType)),
            trailing: AdaptivePopupMenuButton.widget<PlayerKernelType>(
              items: _kernelMenuItems(),
              buttonStyle: PopupButtonStyle.gray,
              child: _buildMenuChip(
                  context, _kernelDisplayName(_selectedKernelType)),
              onSelected: (index, entry) {
                final kernel = entry.value ?? PlayerKernelType.values[index];
                if (kernel != _selectedKernelType) {
                  _savePlayerKernelSettings(kernel);
                }
              },
            ),
            backgroundColor: tileBackground,
          ),
        ],
      ),
      const SizedBox(height: 16),
      if (externalSupported)
        CupertinoSettingsGroupCard(
          margin: EdgeInsets.zero,
          backgroundColor: sectionBackground,
          addDividers: true,
          dividerIndent: 16,
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                Future<void> toggleExternal(bool value) async {
                  if (!externalSupported) {
                    return;
                  }
                  if (value) {
                    if (settingsProvider.externalPlayerPath.trim().isEmpty) {
                      final picked = await FilePickerService()
                          .pickExternalPlayerExecutable();
                      if (picked == null || picked.trim().isEmpty) {
                        if (!mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: context.l10n.externalPlayerSelectionCanceled,
                          type: AdaptiveSnackBarType.info,
                        );
                        await settingsProvider.setUseExternalPlayer(false);
                        return;
                      }
                      await settingsProvider.setExternalPlayerPath(picked);
                    }
                    await settingsProvider.setUseExternalPlayer(true);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: context.l10n.externalPlayerEnabled,
                      type: AdaptiveSnackBarType.success,
                    );
                  } else {
                    await settingsProvider.setUseExternalPlayer(false);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: context.l10n.externalPlayerDisabled,
                      type: AdaptiveSnackBarType.success,
                    );
                  }
                }

                return CupertinoSettingsTile(
                  leading: Icon(
                    CupertinoIcons.square_arrow_up,
                    color: resolveSettingsIconColor(context),
                  ),
                  title: Text(context.l10n.externalPlayerEnableTitle),
                  subtitle: Text(context.l10n.externalPlayerEnableSubtitle),
                  trailing: AdaptiveSwitch(
                    value: settingsProvider.useExternalPlayer,
                    onChanged: toggleExternal,
                  ),
                  onTap: () =>
                      toggleExternal(!settingsProvider.useExternalPlayer),
                  backgroundColor: tileBackground,
                );
              },
            ),
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                final path = settingsProvider.externalPlayerPath.trim();
                final subtitle = path.isEmpty
                    ? context.l10n.externalPlayerNotSelected
                    : path;
                return CupertinoSettingsTile(
                  leading: Icon(
                    CupertinoIcons.folder,
                    color: resolveSettingsIconColor(context),
                  ),
                  title: Text(context.l10n.externalPlayerSelectTitle),
                  subtitle: Text(subtitle),
                  showChevron: true,
                  onTap: () async {
                    final picked = await FilePickerService()
                        .pickExternalPlayerExecutable();
                    if (picked == null || picked.trim().isEmpty) {
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: context.l10n.externalPlayerSelectionCanceled,
                        type: AdaptiveSnackBarType.info,
                      );
                      return;
                    }
                    await settingsProvider.setExternalPlayerPath(picked);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: context.l10n.externalPlayerUpdated,
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                  backgroundColor: tileBackground,
                );
              },
            ),
          ],
        ),
      if (_selectedKernelType == PlayerKernelType.mdk ||
          _selectedKernelType == PlayerKernelType.mediaKit) ...[
        const SizedBox(height: 16),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return CupertinoSettingsGroupCard(
              margin: EdgeInsets.zero,
              backgroundColor: sectionBackground,
              addDividers: true,
              dividerIndent: 16,
              children: [
                CupertinoSettingsTile(
                  leading: Icon(
                    CupertinoIcons.bolt,
                    color: resolveSettingsIconColor(context),
                  ),
                  title: Text(context.l10n.hardwareDecoding),
                  subtitle: Text(context.l10n.hardwareDecodingSubtitle),
                  trailing: AdaptiveSwitch(
                    value: videoState.useHardwareDecoder,
                    onChanged: (value) async {
                      await videoState.setHardwareDecoderEnabled(value);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.hardwareDecodingEnabled
                            : context.l10n.hardwareDecodingDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                  ),
                  onTap: () async {
                    final bool newValue = !videoState.useHardwareDecoder;
                    await videoState.setHardwareDecoderEnabled(newValue);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: newValue
                          ? context.l10n.hardwareDecodingEnabled
                          : context.l10n.hardwareDecodingDisabled,
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                  backgroundColor: tileBackground,
                ),
              ],
            );
          },
        ),
      ],
      if (globals.isPhone) ...[
        const SizedBox(height: 16),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return CupertinoSettingsGroupCard(
              margin: EdgeInsets.zero,
              backgroundColor: sectionBackground,
              addDividers: true,
              dividerIndent: 16,
              children: [
                CupertinoSettingsTile(
                  leading: Icon(
                    CupertinoIcons.pause_circle,
                    color: resolveSettingsIconColor(context),
                  ),
                  title: Text(context.l10n.pauseOnBackgroundTitle),
                  subtitle: Text(context.l10n.pauseOnBackgroundSubtitle),
                  trailing: AdaptiveSwitch(
                    value: videoState.pauseOnBackground,
                    onChanged: (value) async {
                      await videoState.setPauseOnBackground(value);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.pauseOnBackgroundEnabled
                            : context.l10n.pauseOnBackgroundDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                  ),
                  backgroundColor: tileBackground,
                ),
              ],
            );
          },
        ),
      ],
      const SizedBox(height: 16),
      Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          final bool isAutoNext =
              videoState.playbackEndAction == PlaybackEndAction.autoNext;
          return CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            backgroundColor: sectionBackground,
            addDividers: true,
            dividerIndent: 16,
            children: [
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.play_circle,
                  color: resolveSettingsIconColor(context),
                ),
                title: Text(context.l10n.playbackEndActionTitle),
                subtitle: Text(videoState.playbackEndAction.description),
                trailing: AdaptivePopupMenuButton.widget<PlaybackEndAction>(
                  items: _playbackEndActionMenuItems(),
                  buttonStyle: PopupButtonStyle.gray,
                  child: _buildMenuChip(
                    context,
                    videoState.playbackEndAction.label,
                  ),
                  onSelected: (index, entry) async {
                    final action =
                        entry.value ?? PlaybackEndAction.values[index];
                    if (action == videoState.playbackEndAction) return;
                    await videoState.setPlaybackEndAction(action);
                    if (!mounted) return;
                    String message;
                    switch (action) {
                      case PlaybackEndAction.autoNext:
                        message = context.l10n.playbackEndActionAutoNextMessage;
                        break;
                      case PlaybackEndAction.loop:
                        message = context.l10n.playbackEndActionLoopMessage;
                        break;
                      case PlaybackEndAction.pause:
                        message = context.l10n.playbackEndActionPauseMessage;
                        break;
                      case PlaybackEndAction.exitPlayer:
                        message = context.l10n.playbackEndActionExitMessage;
                        break;
                    }
                    AdaptiveSnackBar.show(
                      context,
                      message: message,
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                ),
                backgroundColor: tileBackground,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.timer,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(context.l10n.autoNextCountdownTitle),
                    subtitle: Text(
                      isAutoNext
                          ? context.l10n.autoNextCountdownWaitSeconds(
                              videoState.autoNextCountdownSeconds,
                            )
                          : context.l10n.autoNextCountdownNeedAutoNext,
                    ),
                    backgroundColor: tileBackground,
                    contentPadding:
                        const EdgeInsetsDirectional.fromSTEB(20, 12, 16, 8),
                  ),
                  Container(
                    color: tileBackground,
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 0, 16, 12),
                    child: _buildAutoNextCountdownSlider(
                      context,
                      videoState,
                      isAutoNext,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      if (_selectedKernelType == PlayerKernelType.mdk) ...[
        const SizedBox(height: 16),
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return CupertinoSettingsGroupCard(
              margin: EdgeInsets.zero,
              backgroundColor: sectionBackground,
              addDividers: true,
              dividerIndent: 16,
              children: [
                CupertinoSettingsTile(
                  leading: Icon(
                    CupertinoIcons.photo_on_rectangle,
                    color: resolveSettingsIconColor(context),
                  ),
                  title: Text(context.l10n.timelinePreviewTitle),
                  subtitle: Text(context.l10n.timelinePreviewSubtitle),
                  trailing: AdaptiveSwitch(
                    value: videoState.timelinePreviewEnabled,
                    onChanged: (value) async {
                      if (value) {
                        final bool? confirm = await showCupertinoDialog<bool>(
                          context: context,
                          builder: (context) => CupertinoAlertDialog(
                            title: Text(context.l10n.enableWarning),
                            content: Text(
                              context.l10n.timelinePreviewEnableWarningContent,
                            ),
                            actions: [
                              CupertinoDialogAction(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: Text(context.l10n.cancel),
                              ),
                              CupertinoDialogAction(
                                isDestructiveAction: true,
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(context.l10n.confirm),
                              ),
                            ],
                          ),
                        );
                        if (confirm != true) return;
                      }
                      await videoState.setTimelinePreviewEnabled(value);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: value
                            ? context.l10n.timelinePreviewEnabled
                            : context.l10n.timelinePreviewDisabled,
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                  ),
                  backgroundColor: tileBackground,
                ),
              ],
            );
          },
        ),
      ],
      const SizedBox(height: 16),
      Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          final bool isMdk = _selectedKernelType == PlayerKernelType.mdk;
          final bool enableSetting =
              isMdk || _selectedKernelType == PlayerKernelType.mediaKit;
          return CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            backgroundColor: sectionBackground,
            addDividers: true,
            dividerIndent: 16,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.tray_full,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: Text(
                      isMdk
                          ? context.l10n.playPrecacheDuration
                          : context.l10n.playPrecacheSize,
                    ),
                    subtitle: Text(
                      isMdk
                          ? context.l10n.currentPrecacheDurationSeconds(
                              videoState.precacheBufferDurationSeconds,
                            )
                          : (enableSetting
                              ? context.l10n.currentPrecacheSizeMb(
                                  videoState.precacheBufferSizeMb,
                                )
                              : context.l10n.libmpvKernelOnly),
                    ),
                    backgroundColor: tileBackground,
                    contentPadding:
                        const EdgeInsetsDirectional.fromSTEB(20, 12, 16, 8),
                  ),
                  Container(
                    color: tileBackground,
                    padding:
                        const EdgeInsetsDirectional.fromSTEB(20, 0, 16, 12),
                    child: isMdk
                        ? _buildPrecacheBufferDurationSlider(
                            context,
                            videoState,
                            enableSetting,
                          )
                        : _buildPrecacheBufferSizeSlider(
                            context,
                            videoState,
                            enableSetting,
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      if (_selectedKernelType == PlayerKernelType.mediaKit)
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool supportsUpscale = videoState.isDoubleResolutionSupported;
            if (!supportsUpscale) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                const SizedBox(height: 16),
                CupertinoSettingsGroupCard(
                  margin: EdgeInsets.zero,
                  backgroundColor: sectionBackground,
                  addDividers: true,
                  dividerIndent: 16,
                  children: [
                    CupertinoSettingsTile(
                      leading: Icon(
                        CupertinoIcons.textformat_abc,
                        color: resolveSettingsIconColor(context),
                      ),
                      title: Text(context.l10n.doubleResolutionPlaybackTitle),
                      subtitle:
                          Text(context.l10n.doubleResolutionPlaybackSubtitle),
                      trailing: AdaptiveSwitch(
                        value: videoState.doubleResolutionPlaybackEnabled,
                        onChanged: (value) async {
                          await videoState
                              .setDoubleResolutionPlaybackEnabled(value);
                          if (!mounted) return;
                          final bool deferApply = videoState.hasVideo;
                          final String message = deferApply
                              ? context.l10n.settingSavedReopenVideoToApply
                              : (value
                                  ? context.l10n.doubleResolutionPlaybackEnabled
                                  : context
                                      .l10n.doubleResolutionPlaybackDisabled);
                          AdaptiveSnackBar.show(
                            context,
                            message: message,
                            type: AdaptiveSnackBarType.success,
                          );
                        },
                      ),
                      onTap: () async {
                        final bool newValue =
                            !videoState.doubleResolutionPlaybackEnabled;
                        await videoState
                            .setDoubleResolutionPlaybackEnabled(newValue);
                        if (!mounted) return;
                        final bool deferApply = videoState.hasVideo;
                        final String message = deferApply
                            ? context.l10n.settingSavedReopenVideoToApply
                            : (newValue
                                ? context.l10n.doubleResolutionPlaybackEnabled
                                : context.l10n.doubleResolutionPlaybackDisabled);
                        AdaptiveSnackBar.show(
                          context,
                          message: message,
                          type: AdaptiveSnackBarType.success,
                        );
                      },
                      backgroundColor: tileBackground,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      if (_selectedKernelType == PlayerKernelType.mediaKit)
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool supportsAnime4K = videoState.isAnime4KSupported;
            if (!supportsAnime4K) {
              return const SizedBox.shrink();
            }
            final Anime4KProfile providerProfile = videoState.anime4kProfile;
            if (_anime4kSelectionOverride != null &&
                _anime4kSelectionOverride == providerProfile) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _anime4kSelectionOverride = null;
                });
              });
            }
            final Anime4KProfile currentProfile =
                _anime4kSelectionOverride ?? providerProfile;
            return Column(
              children: [
                const SizedBox(height: 16),
                CupertinoSettingsGroupCard(
                  margin: EdgeInsets.zero,
                  backgroundColor: sectionBackground,
                  addDividers: true,
                  dividerIndent: 16,
                  children: [
                    CupertinoSettingsTile(
                      leading: Icon(
                        CupertinoIcons.tv,
                        color: resolveSettingsIconColor(context),
                      ),
                      title: Text(context.l10n.anime4kSuperResolutionTitle),
                      subtitle: Text(
                        _getAnime4KProfileDescription(currentProfile),
                      ),
                      trailing: AdaptivePopupMenuButton.widget<Anime4KProfile>(
                        items: _anime4kMenuItems(),
                        buttonStyle: PopupButtonStyle.gray,
                        child: _buildMenuChip(
                          context,
                          _getAnime4KProfileTitle(currentProfile),
                        ),
                        onSelected: (index, entry) {
                          final profile =
                              entry.value ?? Anime4KProfile.values[index];
                          if (profile == currentProfile) return;
                          setState(() {
                            _anime4kSelectionOverride = profile;
                          });
                          videoState.setAnime4KProfile(profile).then((_) {
                            if (!mounted) return;
                            final bool deferApply = videoState.hasVideo;
                            final option = _getAnime4KProfileTitle(profile);
                            final message = deferApply
                                ? context.l10n.settingSavedReopenVideoToApply
                                : (profile == Anime4KProfile.off
                                    ? context.l10n.anime4kDisabled
                                    : context.l10n.anime4kSwitchedTo(option));
                            AdaptiveSnackBar.show(
                              context,
                              message: message,
                              type: AdaptiveSnackBarType.success,
                            );
                          });
                        },
                      ),
                      backgroundColor: tileBackground,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      if (_selectedKernelType == PlayerKernelType.mediaKit)
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool supportsCrt = videoState.isCrtSupported;
            if (!supportsCrt) {
              return const SizedBox.shrink();
            }
            final CrtProfile providerProfile = videoState.crtProfile;
            if (_crtSelectionOverride != null &&
                _crtSelectionOverride == providerProfile) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() {
                  _crtSelectionOverride = null;
                });
              });
            }
            final CrtProfile currentProfile =
                _crtSelectionOverride ?? providerProfile;
            return Column(
              children: [
                const SizedBox(height: 16),
                CupertinoSettingsGroupCard(
                  margin: EdgeInsets.zero,
                  backgroundColor: sectionBackground,
                  addDividers: true,
                  dividerIndent: 16,
                  children: [
                    CupertinoSettingsTile(
                      leading: Icon(
                        CupertinoIcons.tv,
                        color: resolveSettingsIconColor(context),
                      ),
                      title: Text(context.l10n.crtDisplayEffectTitle),
                      subtitle: Text(
                        _getCrtProfileDescription(currentProfile),
                      ),
                      trailing: AdaptivePopupMenuButton.widget<CrtProfile>(
                        items: CrtProfile.values
                            .map(
                              (profile) => AdaptivePopupMenuItem<CrtProfile>(
                                label: _getCrtProfileTitle(profile),
                                value: profile,
                              ),
                            )
                            .toList(),
                        buttonStyle: PopupButtonStyle.gray,
                        child: _buildMenuChip(
                          context,
                          _getCrtProfileTitle(currentProfile),
                        ),
                        onSelected: (index, entry) {
                          final profile =
                              entry.value ?? CrtProfile.values[index];
                          if (profile == currentProfile) return;
                          setState(() {
                            _crtSelectionOverride = profile;
                          });
                          videoState.setCrtProfile(profile).then((_) {
                            if (!mounted) return;
                            final option = _getCrtProfileTitle(profile);
                            final message = profile == CrtProfile.off
                                ? context.l10n.crtDisabled
                                : context.l10n.crtSwitchedTo(option);
                            AdaptiveSnackBar.show(
                              context,
                              message: message,
                              type: AdaptiveSnackBarType.success,
                            );
                          });
                        },
                      ),
                      backgroundColor: tileBackground,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      const SizedBox(height: 16),
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
        title: context.l10n.player,
        useNativeToolbar: true,
      ),
      body: ColoredBox(
        color: backgroundColor,
        child: SafeArea(
          top: false,
          bottom: false,
          child: _initializing
              ? const Center(child: CupertinoActivityIndicator())
              : ListView(
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

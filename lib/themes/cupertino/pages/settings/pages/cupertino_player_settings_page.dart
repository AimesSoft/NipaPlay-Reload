import 'dart:io' if (dart.library.io) 'dart:io';

import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
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
import 'package:nipaplay/services/file_picker_service.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';

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
      message: '播放器内核已切换',
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
      message: '弹幕渲染引擎已切换',
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
        message: '请输入 AI 接口 URL',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (model.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '请输入模型名称',
        type: AdaptiveSnackBarType.error,
      );
      return;
    }
    if (!videoState.spoilerAiHasApiKey && apiKeyInput.isEmpty) {
      AdaptiveSnackBar.show(
        context,
        message: '请输入 API Key',
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
        apiKey: apiKeyInput.isEmpty ? null : apiKeyInput,
      );
      _spoilerAiApiKeyController.clear();
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '防剧透 AI 设置已保存',
        type: AdaptiveSnackBarType.success,
      );
    } catch (e) {
      if (!mounted) return;
      AdaptiveSnackBar.show(
        context,
        message: '保存失败: $e',
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
        return 'MDK 多媒体开发套件，支持硬件解码（默认优先；不支持时回落软件解码）。';
      case PlayerKernelType.videoPlayer:
        return 'Flutter 官方 Video Player，兼容性好。';
      case PlayerKernelType.mediaKit:
        return 'MediaKit (Libmpv) 播放器，支持硬件解码与高级特性。';
    }
  }

  String _getDanmakuRenderEngineDescription(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return 'CPU 渲染：兼容性最佳，适合大多数场景。';
      case DanmakuRenderEngine.gpu:
        return 'GPU 渲染（实验性）：性能更高，但仍在开发中。';
      case DanmakuRenderEngine.canvas:
        return 'Canvas 弹幕（实验性）：高性能，低功耗。';
    }
  }

  String _getAnime4KProfileTitle(Anime4KProfile profile) {
    switch (profile) {
      case Anime4KProfile.off:
        return '关闭';
      case Anime4KProfile.lite:
        return '轻量';
      case Anime4KProfile.standard:
        return '标准';
      case Anime4KProfile.high:
        return '高质量';
    }
  }

  String _getAnime4KProfileDescription(Anime4KProfile profile) {
    switch (profile) {
      case Anime4KProfile.off:
        return '保持原始画面，不进行超分辨率处理。';
      case Anime4KProfile.lite:
        return '适度超分辨率与降噪，性能消耗较低。';
      case Anime4KProfile.standard:
        return '画质与性能平衡的标准方案。';
      case Anime4KProfile.high:
        return '追求最佳画质，性能需求最高。';
    }
  }

  String _getCrtProfileTitle(CrtProfile profile) {
    switch (profile) {
      case CrtProfile.off:
        return '关闭';
      case CrtProfile.lite:
        return '轻量';
      case CrtProfile.standard:
        return '标准';
      case CrtProfile.high:
        return '高质量';
    }
  }

  String _getCrtProfileDescription(CrtProfile profile) {
    switch (profile) {
      case CrtProfile.off:
        return '保持原始画面，不启用 CRT 效果。';
      case CrtProfile.lite:
        return '扫描线 + 暗角，性能开销较小。';
      case CrtProfile.standard:
        return '增加曲面与栅格，画面更接近 CRT。';
      case CrtProfile.high:
        return '加入辉光与色散，效果最佳但性能开销更高。';
    }
  }

  String _danmakuTitle(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return 'CPU 渲染';
      case DanmakuRenderEngine.gpu:
        return 'GPU 渲染 (实验性)';
      case DanmakuRenderEngine.canvas:
        return 'Canvas 弹幕 (实验性)';
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

  String _spoilerAiFormatTitle(SpoilerAiApiFormat format) {
    switch (format) {
      case SpoilerAiApiFormat.openai:
        return 'OpenAI 兼容';
      case SpoilerAiApiFormat.gemini:
        return 'Gemini';
    }
  }

  List<AdaptivePopupMenuEntry> _spoilerAiFormatMenuItems() {
    return const [
      AdaptivePopupMenuItem<SpoilerAiApiFormat>(
        label: 'OpenAI 兼容',
        value: SpoilerAiApiFormat.openai,
      ),
      AdaptivePopupMenuItem<SpoilerAiApiFormat>(
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
    if (kIsWeb) {
      return AdaptiveScaffold(
        appBar: const AdaptiveAppBar(
          title: '播放器',
          useNativeToolbar: true,
        ),
        body: const Center(
          child: Text('播放器设置在 Web 平台不可用'),
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
            title: const Text('播放器内核'),
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
                  title: const Text('后台自动暂停'),
                  subtitle: const Text('切到后台或锁屏时自动暂停播放'),
                  trailing: AdaptiveSwitch(
                    value: videoState.pauseOnBackground,
                    onChanged: (value) async {
                      await videoState.setPauseOnBackground(value);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: value ? '后台自动暂停已开启' : '后台自动暂停已关闭',
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
                title: const Text('播放结束操作'),
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
                    final message = action == PlaybackEndAction.autoNext
                        ? '播放结束后将自动进入下一话'
                        : action == PlaybackEndAction.pause
                            ? '播放结束后将停留在当前页面'
                            : '播放结束后将返回上一页';
                    AdaptiveSnackBar.show(
                      context,
                      message: message,
                      type: AdaptiveSnackBarType.success,
                    );
                  },
                ),
                backgroundColor: tileBackground,
              ),
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.timer,
                  color: resolveSettingsIconColor(context),
                ),
                title: const Text('自动连播倒计时'),
                subtitle: Text(
                  isAutoNext
                      ? '自动跳转下一话前等待 ${videoState.autoNextCountdownSeconds} 秒'
                      : '需先启用自动播放下一话',
                ),
                trailing: SizedBox(
                  width: 220,
                  child: CupertinoSlider(
                    value: videoState.autoNextCountdownSeconds.toDouble(),
                    min: AutoNextEpisodeService.minCountdownSeconds.toDouble(),
                    max: AutoNextEpisodeService.maxCountdownSeconds.toDouble(),
                    onChanged: isAutoNext
                        ? (value) {
                            videoState
                                .setAutoNextCountdownSeconds(value.round());
                          }
                        : null,
                  ),
                ),
                backgroundColor: tileBackground,
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 16),
      Consumer<VideoPlayerState>(
        builder: (context, videoState, child) {
          final currentPath = (videoState.screenshotSaveDirectory ?? '').trim();
          return CupertinoSettingsGroupCard(
            margin: EdgeInsets.zero,
            backgroundColor: sectionBackground,
            addDividers: true,
            dividerIndent: 16,
            children: [
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.camera,
                  color: resolveSettingsIconColor(context),
                ),
                title: const Text('截图保存位置'),
                subtitle: Text(currentPath.isEmpty ? '默认：下载目录' : currentPath),
                showChevron: true,
                onTap: () async {
                  final selected = await FilePickerService().pickDirectory(
                    initialDirectory: currentPath.isEmpty ? null : currentPath,
                  );
                  if (selected == null || selected.trim().isEmpty) return;
                  await videoState.setScreenshotSaveDirectory(selected);
                  if (!mounted) return;
                  AdaptiveSnackBar.show(
                    context,
                    message: '截图保存位置已更新',
                    type: AdaptiveSnackBarType.success,
                  );
                },
                backgroundColor: tileBackground,
              ),
            ],
          );
        },
      ),
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
                title: const Text('时间轴截图预览'),
                subtitle:
                    const Text('悬停进度条时显示缩略图（本地/WebDAV/SMB/共享媒体库生效）'),
                trailing: AdaptiveSwitch(
                  value: videoState.timelinePreviewEnabled,
                  onChanged: (value) async {
                    await videoState.setTimelinePreviewEnabled(value);
                    if (!mounted) return;
                    AdaptiveSnackBar.show(
                      context,
                      message: value ? '已开启时间轴截图预览' : '已关闭时间轴截图预览',
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
                      title: const Text('Anime4K 超分辨率（实验性）'),
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
                            final option = _getAnime4KProfileTitle(profile);
                            final message = profile == Anime4KProfile.off
                                ? '已关闭 Anime4K'
                                : 'Anime4K 已切换为$option';
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
                      title: const Text('CRT 显示效果'),
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
                                ? '已关闭 CRT'
                                : 'CRT 已切换为$option';
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
            title: const Text('弹幕渲染引擎'),
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
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.textformat_abc,
                  color: resolveSettingsIconColor(context),
                ),
                title: const Text('弹幕转换简体中文'),
                subtitle: const Text('开启后，将繁体中文弹幕转换为简体显示。'),
                trailing: AdaptiveSwitch(
                  value: settingsProvider.danmakuConvertToSimplified,
                  onChanged: (value) {
                    settingsProvider.setDanmakuConvertToSimplified(value);
                    if (mounted) {
                      AdaptiveSnackBar.show(
                        context,
                        message: value ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文',
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
                      message: newValue ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文',
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
                    title: const Text('防剧透模式'),
                    subtitle: const Text('开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕。'),
                    trailing: AdaptiveSwitch(
                      value: videoState.spoilerPreventionEnabled,
                      onChanged: (value) async {
                        await videoState.setSpoilerPreventionEnabled(value);
                        if (!mounted) return;
                        AdaptiveSnackBar.show(
                          context,
                          message: value ? '已开启防剧透模式' : '已关闭防剧透模式',
                          type: AdaptiveSnackBarType.success,
                        );
                      },
                    ),
                    onTap: () async {
                      final bool newValue = !videoState.spoilerPreventionEnabled;
                      await videoState.setSpoilerPreventionEnabled(newValue);
                      if (!mounted) return;
                      AdaptiveSnackBar.show(
                        context,
                        message: newValue ? '已开启防剧透模式' : '已关闭防剧透模式',
                        type: AdaptiveSnackBarType.success,
                      );
                    },
                    backgroundColor: tileBackground,
                  );
                },
              ),
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  final enabled = videoState.spoilerPreventionEnabled;
                  return CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.lock,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('使用自定义 AI Key'),
                    subtitle:
                        const Text('开启后将使用你填写的 URL/Key（支持 OpenAI 兼容 / Gemini）。'),
                    trailing: AdaptiveSwitch(
                      value: videoState.spoilerAiUseCustomKey,
                      onChanged: enabled
                          ? (value) async {
                              await videoState.setSpoilerAiUseCustomKey(value);
                              if (!mounted) return;
                              AdaptiveSnackBar.show(
                                context,
                                message:
                                    value ? '已开启自定义 AI Key' : '已关闭自定义 AI Key',
                                type: AdaptiveSnackBarType.success,
                              );
                            }
                          : null,
                    ),
                    onTap: enabled
                        ? () async {
                            final bool newValue =
                                !videoState.spoilerAiUseCustomKey;
                            await videoState.setSpoilerAiUseCustomKey(newValue);
                            if (!mounted) return;
                            AdaptiveSnackBar.show(
                              context,
                              message: newValue
                                  ? '已开启自定义 AI Key'
                                  : '已关闭自定义 AI Key',
                              type: AdaptiveSnackBarType.success,
                            );
                          }
                        : null,
                    backgroundColor: tileBackground,
                  );
                },
              ),
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  final enabled = videoState.spoilerPreventionEnabled;
                  return CupertinoSettingsTile(
                    leading: Icon(
                      CupertinoIcons.info_circle,
                      color: resolveSettingsIconColor(context),
                    ),
                    title: const Text('调试：打印 AI 返回内容'),
                    subtitle: const Text('开启后会在日志里打印 AI 返回的原始文本与命中弹幕。'),
                    trailing: AdaptiveSwitch(
                      value: videoState.spoilerAiDebugPrintResponse,
                      onChanged: enabled
                          ? (value) async {
                              await videoState.setSpoilerAiDebugPrintResponse(
                                  value);
                              if (!mounted) return;
                              AdaptiveSnackBar.show(
                                context,
                                message: value
                                    ? '已开启 AI 调试打印'
                                    : '已关闭 AI 调试打印',
                                type: AdaptiveSnackBarType.success,
                              );
                            }
                          : null,
                    ),
                    onTap: enabled
                        ? () async {
                            final bool newValue =
                                !videoState.spoilerAiDebugPrintResponse;
                            await videoState
                                .setSpoilerAiDebugPrintResponse(newValue);
                            if (!mounted) return;
                            AdaptiveSnackBar.show(
                              context,
                              message: newValue
                                  ? '已开启 AI 调试打印'
                                  : '已关闭 AI 调试打印',
                              type: AdaptiveSnackBarType.success,
                            );
                          }
                        : null,
                    backgroundColor: tileBackground,
                  );
                },
              ),
              CupertinoSettingsTile(
                leading: Icon(
                  CupertinoIcons.search,
                  color: resolveSettingsIconColor(context),
                ),
                title: const Text('哈希匹配失败自动匹配弹幕'),
                subtitle: const Text('哈希匹配失败时默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单。'),
                trailing: AdaptiveSwitch(
                  value:
                      settingsProvider.autoMatchDanmakuFirstSearchResultOnHashFail,
                  onChanged: (value) {
                    settingsProvider
                        .setAutoMatchDanmakuFirstSearchResultOnHashFail(value);
                    if (mounted) {
                      AdaptiveSnackBar.show(
                        context,
                        message:
                            value ? '已开启匹配失败自动匹配' : '已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）',
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
                      message:
                          newValue ? '已开启匹配失败自动匹配' : '已关闭匹配失败自动匹配（将弹出搜索弹幕菜单）',
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
          if (!videoState.spoilerPreventionEnabled ||
              !videoState.spoilerAiUseCustomKey) {
            return const SizedBox.shrink();
          }

          final bool isGemini =
              _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
          final urlHint = isGemini
              ? 'https://generativelanguage.googleapis.com/v1beta/models'
              : 'https://api.openai.com/v1/chat/completions';
          final modelHint = isGemini ? 'gemini-1.5-flash' : 'gpt-5';

          final textTheme = CupertinoTheme.of(context).textTheme.textStyle;
          final Color subtitleColor = resolveSettingsSecondaryTextColor(context);
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
                              '防剧透 AI 设置',
                              style: textTheme.copyWith(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isGemini
                              ? 'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。'
                              : 'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。',
                          style: textTheme.copyWith(
                            fontSize: 13,
                            color: subtitleColor,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              '接口格式',
                              style: textTheme.copyWith(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Spacer(),
                            AdaptivePopupMenuButton.widget<SpoilerAiApiFormat>(
                              items: _spoilerAiFormatMenuItems(),
                              buttonStyle: PopupButtonStyle.gray,
                              child: _buildMenuChip(
                                context,
                                _spoilerAiFormatTitle(_spoilerAiApiFormatDraft),
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
                          placeholder: videoState.spoilerAiHasApiKey
                              ? '已保存，留空表示不修改'
                              : '请输入你的 API Key',
                          obscureText: true,
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
                          '温度：${_spoilerAiTemperatureDraft.toStringAsFixed(2)}',
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
                                  : const Text('保存配置'),
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
      appBar: const AdaptiveAppBar(
        title: '播放器',
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

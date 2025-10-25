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
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/utils/anime4k_shader_manager.dart';

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
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.cpu;
  bool _initialized = false;
  bool _initializing = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized || kIsWeb) return;
    _decoderManager =
        Provider.of<VideoPlayerState>(context, listen: false).decoderManager;
    _initializing = true;
    _loadSettings();
    _initialized = true;
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
    BlurSnackBar.show(context, '播放器内核已切换');
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
    BlurSnackBar.show(context, '弹幕渲染引擎已切换');
    setState(() {
      _selectedDanmakuRenderEngine = engine;
    });
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
        return 'MDK 多媒体开发套件，基于 FFmpeg，性能优秀。';
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

  Future<void> _showKernelPicker() async {
    final PlayerKernelType? result = await showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择播放器内核'),
        actions: PlayerKernelType.values.map((kernel) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(kernel),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _kernelDisplayName(kernel),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _getPlayerKernelDescription(kernel),
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (result != null && result != _selectedKernelType) {
      await _savePlayerKernelSettings(result);
    }
  }

  Future<void> _showDanmakuPicker() async {
    final DanmakuRenderEngine? result = await showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择弹幕渲染方式'),
        actions: DanmakuRenderEngine.values.map((engine) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(engine),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _danmakuTitle(engine),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _getDanmakuRenderEngineDescription(engine),
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (result != null && result != _selectedDanmakuRenderEngine) {
      await _saveDanmakuRenderEngineSettings(result);
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

  Future<void> _showAnime4KPicker(VideoPlayerState videoState) async {
    final Anime4KProfile? result = await showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        title: const Text('选择 Anime4K 档位'),
        actions: Anime4KProfile.values.map((profile) {
          return CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(profile),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _getAnime4KProfileTitle(profile),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _getAnime4KProfileDescription(profile),
                  style: const TextStyle(
                    fontSize: 12,
                    color: CupertinoColors.systemGrey,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
      ),
    );

    if (result != null) {
      await videoState.setAnime4KProfile(result);
      if (!mounted) return;
      final String option = _getAnime4KProfileTitle(result);
      final String message = result == Anime4KProfile.off
          ? '已关闭 Anime4K'
          : 'Anime4K 已切换为$option';
      BlurSnackBar.show(context, message);
    }
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

    final double topPadding = MediaQuery.of(context).padding.top + 48;

    final List<Widget> sections = [
      AdaptiveFormSection.insetGrouped(
        children: [
          AdaptiveListTile(
            leading: const Icon(CupertinoIcons.play_rectangle),
            title: const Text('播放器内核'),
            subtitle: Text(_getPlayerKernelDescription(_selectedKernelType)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _kernelDisplayName(_selectedKernelType),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chevron_forward
                      : CupertinoIcons.forward,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey2,
                    context,
                  ),
                ),
              ],
            ),
            onTap: _showKernelPicker,
          ),
        ],
      ),
      if (_selectedKernelType == PlayerKernelType.mediaKit)
        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool supportsAnime4K = videoState.isAnime4KSupported;
            if (!supportsAnime4K) {
              return const SizedBox.shrink();
            }
            final Anime4KProfile currentProfile = videoState.anime4kProfile;
            return Column(
              children: [
                const SizedBox(height: 16),
                AdaptiveFormSection.insetGrouped(
                  children: [
                    AdaptiveListTile(
                      leading: const Icon(CupertinoIcons.sparkles,
                          color: CupertinoColors.systemYellow),
                      title: const Text('Anime4K 超分辨率（实验性）'),
                      subtitle: Text(
                        _getAnime4KProfileDescription(currentProfile),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getAnime4KProfileTitle(currentProfile),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            PlatformInfo.isIOS
                                ? CupertinoIcons.chevron_forward
                                : CupertinoIcons.forward,
                            color: CupertinoDynamicColor.resolve(
                              CupertinoColors.systemGrey2,
                              context,
                            ),
                          ),
                        ],
                      ),
                      onTap: () => _showAnime4KPicker(videoState),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      const SizedBox(height: 16),
      AdaptiveFormSection.insetGrouped(
        children: [
          AdaptiveListTile(
            leading: const Icon(CupertinoIcons.bubble_left_bubble_right),
            title: const Text('弹幕渲染引擎'),
            subtitle: Text(
              _getDanmakuRenderEngineDescription(_selectedDanmakuRenderEngine),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _danmakuTitle(_selectedDanmakuRenderEngine),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Icon(
                  PlatformInfo.isIOS
                      ? CupertinoIcons.chevron_forward
                      : CupertinoIcons.forward,
                  color: CupertinoDynamicColor.resolve(
                    CupertinoColors.systemGrey2,
                    context,
                  ),
                ),
              ],
            ),
            onTap: _showDanmakuPicker,
          ),
        ],
      ),
      const SizedBox(height: 16),
      Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          return AdaptiveFormSection.insetGrouped(
            children: [
              AdaptiveListTile(
                leading: const Icon(CupertinoIcons.textformat_abc),
                title: const Text('弹幕转换简体中文'),
                subtitle: const Text('开启后，将繁体中文弹幕转换为简体显示。'),
                trailing: AdaptiveSwitch(
                  value: settingsProvider.danmakuConvertToSimplified,
                  onChanged: (value) {
                    settingsProvider.setDanmakuConvertToSimplified(value);
                    if (mounted) {
                      BlurSnackBar.show(
                        context,
                        value ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文',
                      );
                    }
                  },
                ),
                onTap: () {
                  final bool newValue =
                      !settingsProvider.danmakuConvertToSimplified;
                  settingsProvider.setDanmakuConvertToSimplified(newValue);
                  if (mounted) {
                    BlurSnackBar.show(
                      context,
                      newValue ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文',
                    );
                  }
                },
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

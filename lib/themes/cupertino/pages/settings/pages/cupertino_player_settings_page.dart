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
            subtitle:
                Text(_getPlayerKernelDescription(_selectedKernelType)),
            trailing: AdaptivePopupMenuButton.widget<PlayerKernelType>(
              items: _kernelMenuItems(),
              buttonStyle: PopupButtonStyle.gray,
              child:
                  _buildMenuChip(context, _kernelDisplayName(_selectedKernelType)),
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
                CupertinoSettingsGroupCard(
                  margin: EdgeInsets.zero,
                  backgroundColor: sectionBackground,
                  addDividers: true,
                  dividerIndent: 16,
                  children: [
                    CupertinoSettingsTile(
                      leading: Icon(
                        CupertinoIcons.sparkles,
                        color: CupertinoDynamicColor.resolve(
                          CupertinoColors.systemYellow,
                          context,
                        ),
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
                final engine = entry.value ??
                    DanmakuRenderEngine.values[index];
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
                        message: value
                            ? '已开启弹幕转换简体中文'
                            : '已关闭弹幕转换简体中文',
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
                          ? '已开启弹幕转换简体中文'
                          : '已关闭弹幕转换简体中文',
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

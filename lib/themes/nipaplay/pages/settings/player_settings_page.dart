import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_card.dart';
import 'package:nipaplay/themes/nipaplay/widgets/settings_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/hover_scale_text_button.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/utils/player_kernel_manager.dart';
import 'package:nipaplay/utils/anime4k_shader_manager.dart';
import 'package:nipaplay/utils/crt_shader_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/services/auto_next_episode_service.dart';
import 'package:nipaplay/services/danmaku_spoiler_filter_service.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  _PlayerSettingsPageState createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  static const String _selectedDecodersKey = 'selected_decoders';
  static const String _playerKernelTypeKey = 'player_kernel_type';
  static const String _danmakuRenderEngineKey = 'danmaku_render_engine';
  static const Color _fluentAccentColor = Color(0xFFFF2E55);

  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;
  String _playerCoreName = "MDK";
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.canvas;

  // 为BlurDropdown添加GlobalKey
  final GlobalKey _playerKernelDropdownKey = GlobalKey();
  final GlobalKey _danmakuRenderEngineDropdownKey = GlobalKey();
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
  }

  @override
  void dispose() {
    _spoilerAiUrlController.dispose();
    _spoilerAiModelController.dispose();
    _spoilerAiApiKeyController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final playerState = Provider.of<VideoPlayerState>(context, listen: false);
    _decoderManager = playerState.decoderManager;
    // 异步获取内核名称
    _loadCurrentPlayerKernelName();

    if (!kIsWeb) {
      _getAvailableDecoders();
    }
    _loadDecoderSettings();
    _loadPlayerKernelSettings();
    _loadDanmakuRenderEngineSettings();

    if (!_spoilerAiControllersInitialized) {
      _spoilerAiApiFormatDraft = playerState.spoilerAiApiFormat;
      _spoilerAiTemperatureDraft = playerState.spoilerAiTemperature;
      _spoilerAiUrlController.text = playerState.spoilerAiApiUrl;
      _spoilerAiModelController.text = playerState.spoilerAiModel;
      _spoilerAiControllersInitialized = true;
    }
  }

  Future<void> _loadCurrentPlayerKernelName() async {
    final kernelName = await PlayerKernelManager.getCurrentPlayerKernel();
    setState(() {
      _playerCoreName = kernelName;
    });
  }

  Future<void> _loadPlayerKernelSettings() async {
    // 直接从PlayerFactory获取当前内核类型
    setState(() {
      _selectedKernelType = PlayerFactory.getKernelType();
      _updatePlayerCoreName();
    });
  }

  void _updatePlayerCoreName() {
    // 从当前选定的内核类型决定显示名称
    switch (_selectedKernelType) {
      case PlayerKernelType.mdk:
        _playerCoreName = "MDK";
        break;
      case PlayerKernelType.videoPlayer:
        _playerCoreName = "Video Player";
        break;
      case PlayerKernelType.mediaKit:
        _playerCoreName = "Libmpv";
        break;
      default:
        _playerCoreName = "MDK";
    }
  }

  Future<void> _savePlayerKernelSettings(PlayerKernelType kernelType) async {
    // 使用新的静态方法保存设置
    await PlayerFactory.saveKernelType(kernelType);

    if (context.mounted) {
      BlurSnackBar.show(context, '播放器内核已切换');
    }

    setState(() {
      _selectedKernelType = kernelType;
      _updatePlayerCoreName();
    });
  }

  void _showRestartDialog() {
    BlurDialog.show(
      context: context,
      title: '需要重启应用',
      content: '更改播放器内核需要重启应用才能生效。点击确定退出应用。',
      barrierDismissible: false,
      actions: [
        HoverScaleTextButton(
          onPressed: () {
            // 直接退出应用
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              exit(0);
            } else if (!kIsWeb) {
              // 桌面平台
              windowManager.close();
            } else {
              // Web 平台可以提示用户手动刷新
              Navigator.of(context).pop();
            }
          },
          child: const Text('确定',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Future<void> _loadDecoderSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      final savedDecoders = prefs.getStringList(_selectedDecodersKey);
      if (savedDecoders != null && savedDecoders.isNotEmpty) {
        _selectedDecoders = savedDecoders;
      } else if (!kIsWeb) {
        _initializeSelectedDecodersWithPlatformDefaults();
      }
    });
  }

  void _initializeSelectedDecodersWithPlatformDefaults() {
    if (kIsWeb) return;
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
      _selectedDecoders = ["FFmpeg"];
    }
  }

  void _getAvailableDecoders() {
    if (kIsWeb) return;
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
      _availableDecoders = ["FFmpeg"];
    }
    _selectedDecoders
        .retainWhere((decoder) => _availableDecoders.contains(decoder));
    if (_selectedDecoders.isEmpty && _availableDecoders.isNotEmpty) {
      _initializeSelectedDecodersWithPlatformDefaults();
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedDecodersKey, _selectedDecoders);

    if (context.mounted) {
      await _decoderManager.updateDecoders(_selectedDecoders);

      if (!kIsWeb) {
        final playerState =
            Provider.of<VideoPlayerState>(context, listen: false);
        if (playerState.hasVideo &&
            playerState.player.mediaInfo.video != null &&
            playerState.player.mediaInfo.video!.isNotEmpty) {
          final videoTrack = playerState.player.mediaInfo.video![0];
          final codecString = videoTrack.toString().toLowerCase();
          if (codecString.contains('hevc') || codecString.contains('h265')) {
            debugPrint('检测到设置变更时正在播放HEVC视频，应用特殊优化...');

            if (Platform.isMacOS) {
              if (_selectedDecoders.isNotEmpty &&
                  _selectedDecoders[0] != "VT") {
                _selectedDecoders.remove("VT");
                _selectedDecoders.insert(0, "VT");

                await prefs.setStringList(
                    _selectedDecodersKey, _selectedDecoders);
                await _decoderManager.updateDecoders(_selectedDecoders);

                BlurSnackBar.show(context, '已优化解码器设置以支持HEVC硬件解码');
              }

              await playerState.forceEnableHardwareDecoder();
            }
          }
        }
      }
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

    if (context.mounted) {
      BlurSnackBar.show(context, '弹幕渲染引擎已切换');
    }

    setState(() {
      _selectedDanmakuRenderEngine = engine;
    });
  }

  void _showRestartDanmakuDialog() {
    BlurDialog.show(
      context: context,
      title: '需要重启应用',
      content: '更改弹幕内核需要重启应用才能完全生效。点击确定退出应用，点击取消保留当前设置。',
      barrierDismissible: true,
      actions: [
        HoverScaleTextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.grey)),
        ),
        HoverScaleTextButton(
          onPressed: () {
            // 直接退出应用
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              exit(0);
            } else if (!kIsWeb) {
              // 桌面平台
              windowManager.close();
            }
          },
          child: const Text('确定',
              locale: Locale("zh-Hans", "zh"),
              style: TextStyle(color: Colors.white)),
        ),
      ],
    );
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
    if (!videoState.spoilerAiHasApiKey && apiKeyInput.isEmpty) {
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
        apiKey: apiKeyInput.isEmpty ? null : apiKeyInput,
      );
      _spoilerAiApiKeyController.clear();
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

  String _getPlayerKernelDescription(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return 'MDK 多媒体开发套件\n支持硬件解码（默认优先；不支持时回落软件解码）';
      case PlayerKernelType.videoPlayer:
        return 'Video Player 官方播放器\n适用于简单视频播放，兼容性良好';
      case PlayerKernelType.mediaKit:
        return 'MediaKit (Libmpv) 播放器\n基于MPV，功能强大，支持硬件解码，支持复杂媒体格式';
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
        return '关闭 Anime4K 着色器，保持原始视频画面';
      case Anime4KProfile.lite:
        return '启用 x2 超分辨率和轻度降噪，性能开销较小';
      case Anime4KProfile.standard:
        return '恢复纹理 + 超分辨率的平衡方案，画质与性能兼顾';
      case Anime4KProfile.high:
        return '高光抑制 + 恢复 + 超分辨率，画质最佳，对性能要求最高';
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
        return '关闭 CRT 着色器，保持原始画面';
      case CrtProfile.lite:
        return '扫描线 + 暗角，性能开销较小';
      case CrtProfile.standard:
        return '增加曲面与栅格，画面更接近 CRT';
      case CrtProfile.high:
        return '加入辉光与色散，效果最佳但性能开销更高';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Web 平台现在允许访问此页面，但部分功能受限
    return ListView(
      children: [
        if (!kIsWeb) ...[
          SettingsItem.dropdown(
            title: "播放器内核",
            subtitle: "选择播放器使用的核心引擎",
            icon: Ionicons.play_circle_outline,
            items: [
              DropdownMenuItemData(
                title: "MDK",
                value: PlayerKernelType.mdk,
                isSelected: _selectedKernelType == PlayerKernelType.mdk,
                description: _getPlayerKernelDescription(PlayerKernelType.mdk),
              ),
              DropdownMenuItemData(
                title: "Video Player",
                value: PlayerKernelType.videoPlayer,
                isSelected: _selectedKernelType == PlayerKernelType.videoPlayer,
                description:
                    _getPlayerKernelDescription(PlayerKernelType.videoPlayer),
              ),
              DropdownMenuItemData(
                title: "Libmpv",
                value: PlayerKernelType.mediaKit,
                isSelected: _selectedKernelType == PlayerKernelType.mediaKit,
                description:
                    _getPlayerKernelDescription(PlayerKernelType.mediaKit),
              ),
            ],
            onChanged: (kernelType) {
              _savePlayerKernelSettings(kernelType);
            },
            dropdownKey: _playerKernelDropdownKey,
          ),

          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        ],

        if (_selectedKernelType == PlayerKernelType.mdk ||
            _selectedKernelType == PlayerKernelType.mediaKit) ...[
          Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              return SettingsItem.toggle(
                title: '硬件解码',
                subtitle: '仅对 MDK / Libmpv 生效',
                icon: Ionicons.hardware_chip_outline,
                value: videoState.useHardwareDecoder,
                onChanged: (bool value) async {
                  await videoState.setHardwareDecoderEnabled(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '已开启硬件解码' : '已关闭硬件解码',
                  );
                },
              );
            },
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        ],

        SettingsItem.dropdown(
          title: "弹幕渲染引擎",
          subtitle: "选择弹幕的渲染方式",
          icon: Ionicons.hardware_chip_outline,
          items: [
            DropdownMenuItemData(
              title: "CPU 渲染",
              value: DanmakuRenderEngine.cpu,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.cpu,
              description:
                  _getDanmakuRenderEngineDescription(DanmakuRenderEngine.cpu),
            ),
            DropdownMenuItemData(
              title: "GPU 渲染 (实验性)",
              value: DanmakuRenderEngine.gpu,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.gpu,
              description:
                  _getDanmakuRenderEngineDescription(DanmakuRenderEngine.gpu),
            ),
            DropdownMenuItemData(
              title: "Canvas 弹幕 (实验性)",
              value: DanmakuRenderEngine.canvas,
              isSelected:
                  _selectedDanmakuRenderEngine == DanmakuRenderEngine.canvas,
              description: _getDanmakuRenderEngineDescription(
                  DanmakuRenderEngine.canvas),
            ),
          ],
          onChanged: (engine) {
            _saveDanmakuRenderEngineSettings(engine);
          },
          dropdownKey: _danmakuRenderEngineDropdownKey,
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        if (globals.isPhone) ...[
          Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              return SettingsItem.toggle(
                title: '后台自动暂停',
                subtitle: '切到后台或锁屏时自动暂停播放（仅移动端）',
                icon: Ionicons.pause_circle_outline,
                value: videoState.pauseOnBackground,
                onChanged: (bool value) async {
                  await videoState.setPauseOnBackground(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '后台自动暂停已开启' : '后台自动暂停已关闭',
                  );
                },
              );
            },
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        ],

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final currentAction = videoState.playbackEndAction;
            final items = PlaybackEndAction.values
                .map(
                  (action) => DropdownMenuItemData(
                    title: action.label,
                    value: action,
                    isSelected: action == currentAction,
                    description: action.description,
                  ),
                )
                .toList();

            return SettingsItem.dropdown(
              title: '播放结束操作',
              subtitle: '控制本集播放完毕后的默认行为',
              icon: Ionicons.stop_circle_outline,
              items: items,
              onChanged: (dynamic value) async {
                if (value is! PlaybackEndAction) return;
                await videoState.setPlaybackEndAction(value);
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  value == PlaybackEndAction.autoNext
                      ? '播放结束后将自动进入下一话'
                      : value == PlaybackEndAction.pause
                          ? '播放结束后将停留在当前页面'
                          : '播放结束后将返回上一页',
                );
              },
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final bool isAutoNext =
                videoState.playbackEndAction == PlaybackEndAction.autoNext;
            final double minSeconds =
                AutoNextEpisodeService.minCountdownSeconds.toDouble();
            final double maxSeconds =
                AutoNextEpisodeService.maxCountdownSeconds.toDouble();
            final divisions = AutoNextEpisodeService.maxCountdownSeconds -
                AutoNextEpisodeService.minCountdownSeconds;
            return SettingsItem.slider(
              title: '自动连播倒计时',
              subtitle: isAutoNext
                  ? '播放结束后等待多久再自动播放下一话'
                  : '该设置在“播放结束操作”选择“自动播放下一话”时才会生效',
              icon: Ionicons.timer_outline,
              enabled: isAutoNext,
              value: videoState.autoNextCountdownSeconds.toDouble(),
              min: minSeconds,
              max: maxSeconds,
              divisions: divisions,
              onChanged: (value) {
                videoState.setAutoNextCountdownSeconds(value.round());
              },
              labelFormatter: (value) => '${value.round()} 秒',
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            return SettingsItem.toggle(
              title: '时间轴截图预览',
              subtitle: '进度条悬停时显示缩略图（仅本地/WebDAV/SMB/共享媒体库生效）',
              icon: Icons.photo_size_select_small_outlined,
              value: videoState.timelinePreviewEnabled,
              onChanged: (bool value) async {
                await videoState.setTimelinePreviewEnabled(value);
                if (!context.mounted) return;
                BlurSnackBar.show(
                  context,
                  value ? '已开启时间轴截图预览' : '已关闭时间轴截图预览',
                );
              },
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        if (globals.isDesktop) ...[
          Consumer<VideoPlayerState>(
            builder: (context, videoState, child) {
              return SettingsItem.toggle(
                title: '右侧悬浮设置菜单',
                subtitle: '鼠标移到播放器最右侧显示设置菜单（桌面端）',
                icon: Ionicons.settings_outline,
                value: videoState.desktopHoverSettingsMenuEnabled,
                onChanged: (bool value) async {
                  await videoState.setDesktopHoverSettingsMenuEnabled(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '已开启右侧悬浮设置菜单' : '已关闭右侧悬浮设置菜单',
                  );
                },
              );
            },
          ),
          Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        ],

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final Anime4KProfile currentProfile = videoState.anime4kProfile;
            final bool supportsAnime4K = videoState.isAnime4KSupported;

            final items = Anime4KProfile.values
                .map(
                  (profile) => DropdownMenuItemData(
                    title: _getAnime4KProfileTitle(profile),
                    value: profile,
                    isSelected: profile == currentProfile,
                    description: _getAnime4KProfileDescription(profile),
                  ),
                )
                .toList();

            if (_selectedKernelType != PlayerKernelType.mediaKit) {
              return const SizedBox.shrink();
            }

            if (!supportsAnime4K) {
              return const SizedBox.shrink();
            }

            return SettingsItem.dropdown(
              title: 'Anime4K 超分辨率（实验性）',
              subtitle: '使用 Anime4K GLSL 着色器提升二次元画面清晰度',
              icon: Ionicons.color_wand_outline,
              items: items,
              onChanged: (dynamic value) async {
                if (value is! Anime4KProfile) return;
                await videoState.setAnime4KProfile(value);
                if (!context.mounted) return;
                final String option = _getAnime4KProfileTitle(value);
                final String message = value == Anime4KProfile.off
                    ? '已关闭 Anime4K'
                    : 'Anime4K 已切换为$option';
                BlurSnackBar.show(context, message);
              },
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final CrtProfile currentProfile = videoState.crtProfile;
            final bool supportsCrt = videoState.isCrtSupported;

            if (_selectedKernelType != PlayerKernelType.mediaKit) {
              return const SizedBox.shrink();
            }

            if (!supportsCrt) {
              return const SizedBox.shrink();
            }

            final items = CrtProfile.values
                .map(
                  (profile) => DropdownMenuItemData(
                    title: _getCrtProfileTitle(profile),
                    value: profile,
                    isSelected: profile == currentProfile,
                    description: _getCrtProfileDescription(profile),
                  ),
                )
                .toList();

            return SettingsItem.dropdown(
              title: 'CRT 显示效果',
              subtitle: '使用 CRT GLSL 着色器模拟显示器质感（可与 Anime4K 叠加）',
              icon: Ionicons.tv_outline,
              items: items,
              onChanged: (dynamic value) async {
                if (value is! CrtProfile) return;
                await videoState.setCrtProfile(value);
                if (!context.mounted) return;
                final String option = _getCrtProfileTitle(value);
                final String message =
                    value == CrtProfile.off ? '已关闭 CRT' : 'CRT 已切换为$option';
                BlurSnackBar.show(context, message);
              },
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        // 弹幕转换简体中文开关
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SettingsItem.toggle(
              title: "弹幕转换简体中文",
              subtitle: "开启后，繁体中文弹幕将转换为简体中文显示",
              icon: Ionicons.language_outline,
              value: settingsProvider.danmakuConvertToSimplified,
              onChanged: (bool value) {
                settingsProvider.setDanmakuConvertToSimplified(value);
                if (context.mounted) {
                  BlurSnackBar.show(
                      context, value ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文');
                }
              },
            );
          },
        ),

        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),

        Consumer<VideoPlayerState>(
          builder: (context, videoState, child) {
            final widgets = <Widget>[
              SettingsItem.toggle(
                title: "防剧透模式",
                subtitle: "开启后，加载弹幕后将通过 AI 识别并屏蔽疑似剧透弹幕",
                icon: Ionicons.shield_outline,
                value: videoState.spoilerPreventionEnabled,
                onChanged: (bool value) async {
                  await videoState.setSpoilerPreventionEnabled(value);
                  if (!context.mounted) return;
                  BlurSnackBar.show(
                    context,
                    value ? '已开启防剧透模式' : '已关闭防剧透模式',
                  );
                },
              ),
            ];

            if (videoState.spoilerPreventionEnabled) {
              widgets.add(
                Divider(
                  color: colorScheme.onSurface.withOpacity(0.12),
                  height: 1,
                ),
              );
              widgets.add(
                SettingsItem.toggle(
                  title: "使用自定义 AI Key",
                  subtitle: "开启后将使用你填写的 URL/Key（支持 OpenAI 兼容 / Gemini）",
                  icon: Ionicons.key_outline,
                  value: videoState.spoilerAiUseCustomKey,
                  onChanged: (bool value) async {
                    await videoState.setSpoilerAiUseCustomKey(value);
                    if (!context.mounted) return;
                    BlurSnackBar.show(
                      context,
                      value ? '已开启自定义 AI Key' : '已关闭自定义 AI Key',
                    );
                  },
                ),
              );
            }

            if (videoState.spoilerPreventionEnabled &&
                videoState.spoilerAiUseCustomKey) {
              final bool isGemini =
                  _spoilerAiApiFormatDraft == SpoilerAiApiFormat.gemini;
              final urlHint = isGemini
                  ? 'https://generativelanguage.googleapis.com/v1beta/models'
                  : 'https://api.openai.com/v1/chat/completions';
              final modelHint =
                  isGemini ? 'gemini-1.5-flash' : 'gpt-5';

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
                            Icon(Ionicons.settings_outline,
                                color: colorScheme.onSurface, size: 18),
                            const SizedBox(width: 8),
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
                        const SizedBox(height: 8),
                        Text(
                          isGemini
                              ? 'Gemini：URL 可填到 /v1beta/models，实际请求会自动拼接 /<模型>:generateContent。'
                              : 'OpenAI：URL 建议填写 /v1/chat/completions（兼容接口亦可）。',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
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
                            const SizedBox(width: 12),
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
                        const SizedBox(height: 12),
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
                            border: const OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: _fluentAccentColor, width: 2),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                          ),
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 12),
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
                            border: const OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: _fluentAccentColor, width: 2),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                          ),
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _spoilerAiApiKeyController,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          cursorColor: _fluentAccentColor,
                          decoration: InputDecoration(
                            labelText: 'API Key',
                            labelStyle: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                            hintText: videoState.spoilerAiHasApiKey
                                ? '已保存，留空表示不修改'
                                : '请输入你的 API Key',
                            hintStyle: TextStyle(
                              color: colorScheme.onSurface.withOpacity(0.38),
                            ),
                            filled: true,
                            fillColor: colorScheme.onSurface.withOpacity(0.1),
                            border: const OutlineInputBorder(
                              borderSide: BorderSide.none,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: _fluentAccentColor, width: 2),
                              borderRadius:
                                  BorderRadius.all(Radius.circular(8)),
                            ),
                          ),
                          style: TextStyle(color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 12),
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
                          child: fluent.Slider(
                            min: 0.0,
                            max: 2.0,
                            divisions: 40,
                            value:
                                _spoilerAiTemperatureDraft.clamp(0.0, 2.0),
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
                                horizontal: 16, vertical: 10),
                            fontSize: 13,
                            iconSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

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
            return SettingsItem.toggle(
              title: "哈希匹配失败自动匹配弹幕",
              subtitle: "哈希匹配失败时，默认使用文件名搜索的第一个结果自动匹配；关闭后将弹出搜索弹幕菜单",
              icon: Ionicons.search_outline,
              value: settingsProvider.autoMatchDanmakuFirstSearchResultOnHashFail,
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

        if (_selectedKernelType == PlayerKernelType.mdk) ...[
          // 这里可以添加解码器相关设置
        ],
      ],
    );
  }

  String _getDecoderDescription() {
    if (kIsWeb) return 'Web平台使用浏览器内置解码器';
    if (Platform.isMacOS || Platform.isIOS) {
      return 'VT: macOS/iOS 视频工具箱硬件加速\n'
          'hap: HAP 视频格式解码\n'
          'FFmpeg: 软件解码，支持绝大多数格式\n'
          'dav1d: 高效AV1解码器';
    } else if (Platform.isWindows) {
      return 'MFT:d3d=11: 媒体基础转换D3D11加速\n'
          'D3D11: 直接3D 11硬件加速\n'
          'DXVA: DirectX视频加速\n'
          'CUDA: NVIDIA GPU加速\n'
          'hap: HAP 视频格式解码\n'
          'FFmpeg: 软件解码，支持绝大多数格式\n'
          'dav1d: 高效AV1解码器';
    } else if (Platform.isLinux) {
      return 'VAAPI: 视频加速API\n'
          'VDPAU: 视频解码和演示API\n'
          'CUDA: NVIDIA GPU加速\n'
          'hap: HAP 视频格式解码\n'
          'FFmpeg: 软件解码，支持绝大多数格式\n'
          'dav1d: 高效AV1解码器';
    } else if (Platform.isAndroid) {
      return 'AMediaCodec: Android媒体编解码器\n'
          'FFmpeg: 软件解码，支持绝大多数格式\n'
          'dav1d: 高效AV1解码器';
    } else {
      return 'FFmpeg: 软件解码，支持绝大多数格式';
    }
  }
}

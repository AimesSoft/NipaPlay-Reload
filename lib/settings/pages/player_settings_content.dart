import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/l10n/l10n.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/settings/adaptive_settings_widgets.dart';
import 'package:nipaplay/settings/adaptive_settings_scope.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/player_abstraction/player_data_models.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/utils/anime4k_shader_manager.dart';
import 'package:nipaplay/utils/crt_shader_manager.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:nipaplay/services/auto_next_episode_service.dart';

class PlayerSettingsContent extends StatefulWidget {
  const PlayerSettingsContent({super.key});

  @override
  State<PlayerSettingsContent> createState() => _PlayerSettingsContentState();
}

class _PlayerSettingsContentState extends State<PlayerSettingsContent> {
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  bool _macOSNativeVideoEnabled = false;
  String _androidAudioOutput = 'opensles';

  // 为BlurDropdown添加GlobalKey
  final GlobalKey _playerKernelDropdownKey = GlobalKey();
  final GlobalKey _androidAudioOutputDropdownKey = GlobalKey();
  final GlobalKey _erikaUpscalerDropdownKey = GlobalKey();
  final GlobalKey _seekStepDropdownKey = GlobalKey();
  final GlobalKey _speedBoostDropdownKey = GlobalKey();

  static const List<double> _seekStepPresetOptions = [
    0.5,
    1.0,
    5.0,
    10.0,
    15.0,
    30.0,
    60.0,
  ];
  static const List<double> _speedBoostOptions = [
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
  ];
  static const int _minSkipSeconds = 10;
  static const int _maxSkipSeconds = 600;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadPlayerKernelSettings();
    _loadMacOSNativeVideoSettings();
    _loadAndroidAudioOutputSettings();
  }

  Future<void> _loadPlayerKernelSettings() async {
    // 直接从PlayerFactory获取当前内核类型
    setState(() {
      _selectedKernelType = PlayerFactory.getKernelType();
    });
  }

  Future<void> _loadMacOSNativeVideoSettings() async {
    final enabled = PlayerFactory.getMacOSNativeVideoEnabled();
    if (!mounted) return;
    setState(() {
      _macOSNativeVideoEnabled = enabled;
    });
  }

  Future<void> _savePlayerKernelSettings(PlayerKernelType kernelType) async {
    // 使用新的静态方法保存设置
    await PlayerFactory.saveKernelType(kernelType);

    if (!mounted) return;
    BlurSnackBar.show(context, '播放器内核已切换');

    setState(() {
      _selectedKernelType = kernelType;
    });
  }

  Future<void> _saveMacOSNativeVideoSetting(bool enabled) async {
    await PlayerFactory.saveMacOSNativeVideoEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _macOSNativeVideoEnabled = enabled;
    });
    BlurSnackBar.show(
      context,
      enabled ? '已开启实验性 HDR 原生视频输出' : '已切回 Flutter 纹理视频输出',
    );
  }

  Future<void> _loadAndroidAudioOutputSettings() async {
    final output = PlayerFactory.getAndroidAudioOutput();
    if (!mounted) return;
    setState(() {
      _androidAudioOutput = output;
    });
  }

  Future<void> _saveAndroidAudioOutputSettings(String output) async {
    await PlayerFactory.saveAndroidAudioOutput(output);
    if (!mounted) return;
    setState(() {
      _androidAudioOutput = output;
    });
    final displayName = output == 'audiotrack' ? 'AudioTrack' : 'OpenSL ES';
    BlurSnackBar.show(context, 'Android 音频后端已切换为 $displayName，需重启APP生效');
  }

  String _getPlayerKernelDescription(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return 'MDK 多媒体开发套件\n支持硬件解码（默认优先；不支持时回落软件解码）';
      case PlayerKernelType.videoPlayer:
        return 'Video Player 官方播放器\n适用于简单视频播放，兼容性良好';
      case PlayerKernelType.mediaKit:
        return 'MediaKit (Libmpv) 播放器\n基于MPV，功能强大，支持硬件解码，支持复杂媒体格式';
      case PlayerKernelType.erika:
        return 'Erika Rust 播放器（实验性）\niOS/macOS 原生 Metal 输出，Windows 原生 D3D11 输出，播放、渲染和音频由 Rust 内核负责';
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

  String _getErikaUpscalerTitle(PlayerUpscalerMode mode) {
    switch (mode) {
      case PlayerUpscalerMode.off:
        return '关闭';
      case PlayerUpscalerMode.erikaArtCnnC4F16:
        return 'ART-CNN C4F16';
      case PlayerUpscalerMode.erikaArtCnnC4F32:
        return 'ART-CNN C4F32';
    }
  }

  String _getErikaUpscalerDescription(PlayerUpscalerMode mode) {
    switch (mode) {
      case PlayerUpscalerMode.off:
        return '不启用 Erika 内核超分辨率';
      case PlayerUpscalerMode.erikaArtCnnC4F16:
        return '半精度 ART-CNN，速度优先，推荐日常播放';
      case PlayerUpscalerMode.erikaArtCnnC4F32:
        return '单精度 ART-CNN，画质优先，对 GPU 压力更高';
    }
  }

  List<double> _buildSeekStepOptions(VideoPlayerState videoState) {
    final min = videoState.seekStepMinSeconds;
    final max = videoState.seekStepMaxSeconds;
    final values = <double>[
      min,
      ..._seekStepPresetOptions,
      videoState.seekStepSeconds
    ];
    final result = <double>[];
    for (final raw in values) {
      final clamped = raw.clamp(min, max).toDouble();
      final exists = result.any(
        (value) =>
            (value - clamped).abs() <
            VideoPlayerState.seekStepComparisonEpsilon,
      );
      if (!exists) {
        result.add(clamped);
      }
    }
    result.sort();
    return result;
  }

  List<double> _buildSpeedBoostOptions(VideoPlayerState videoState) {
    final values = <double>[..._speedBoostOptions, videoState.speedBoostRate];
    final result = <double>[];
    for (final raw in values) {
      final clamped = raw
          .clamp(
            VideoPlayerState.minPlaybackRate,
            VideoPlayerState.maxPlaybackRate,
          )
          .toDouble();
      final exists = result.any((value) => (value - clamped).abs() < 0.0005);
      if (!exists) {
        result.add(clamped);
      }
    }
    result.sort();
    return result;
  }

  String _formatRateLabel(double value) {
    if ((value - value.roundToDouble()).abs() < 0.0005) {
      return '${value.round()}x';
    }
    return '${value.toStringAsFixed(2)}x';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showErikaKernel = PlayerFactory.isErikaKernelSupported &&
        context.watch<LabsSettingsProvider>().enableErikaPlayerKernel;
    final visibleKernelType =
        _selectedKernelType == PlayerKernelType.erika && !showErikaKernel
            ? PlayerKernelType.mdk
            : _selectedKernelType;
    // Web 平台现在允许访问此页面，但部分功能受限
    return AdaptiveSettingsPage(
      children: [
        AdaptiveSettingsSection(
          addDividers: false,
          children: [
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return AdaptiveSettingsTile<bool>.toggle(
                  title: _text(
                    context,
                    '快速开始播放',
                    '快速開始播放',
                    'Start Playback Immediately',
                  ),
                  subtitle: _text(
                    context,
                    '跳过视频就绪后的识别加载界面，开始播放后在后台识别番剧并加载弹幕',
                    '跳過影片就緒後的識別載入畫面，開始播放後在後台識別番劇並載入彈幕',
                    'Start as soon as the video is ready, then identify it and load danmaku in the background.',
                  ),
                  icon: Ionicons.flash_outline,
                  phoneIcon: cupertino.CupertinoIcons.bolt,
                  value: settingsProvider.fastPlaybackStartup,
                  onChanged: settingsProvider.setFastPlaybackStartup,
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            if (!kIsWeb) ...[
              AdaptiveSettingsTile.dropdown(
                title: "播放器内核",
                subtitle: "选择播放器使用的核心引擎",
                icon: Ionicons.play_circle_outline,
                items: [
                  DropdownMenuItemData(
                    title: "MDK",
                    value: PlayerKernelType.mdk,
                    isSelected: visibleKernelType == PlayerKernelType.mdk,
                    description:
                        _getPlayerKernelDescription(PlayerKernelType.mdk),
                  ),
                  DropdownMenuItemData(
                    title: "Video Player",
                    value: PlayerKernelType.videoPlayer,
                    isSelected:
                        visibleKernelType == PlayerKernelType.videoPlayer,
                    description: _getPlayerKernelDescription(
                        PlayerKernelType.videoPlayer),
                  ),
                  DropdownMenuItemData(
                    title: "Libmpv",
                    value: PlayerKernelType.mediaKit,
                    isSelected: visibleKernelType == PlayerKernelType.mediaKit,
                    description:
                        _getPlayerKernelDescription(PlayerKernelType.mediaKit),
                  ),
                  if (showErikaKernel)
                    DropdownMenuItemData(
                      title: "Erika",
                      value: PlayerKernelType.erika,
                      isSelected: visibleKernelType == PlayerKernelType.erika,
                      description:
                          _getPlayerKernelDescription(PlayerKernelType.erika),
                    ),
                ],
                onChanged: (kernelType) {
                  _savePlayerKernelSettings(kernelType);
                },
                dropdownKey: _playerKernelDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (visibleKernelType == PlayerKernelType.erika) ...[
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  final currentMode = videoState.erikaUpscalerMode;
                  final items = PlayerUpscalerMode.values
                      .map(
                        (mode) => DropdownMenuItemData(
                          title: _getErikaUpscalerTitle(mode),
                          value: mode,
                          isSelected: mode == currentMode,
                          description: _getErikaUpscalerDescription(mode),
                        ),
                      )
                      .toList();
                  return AdaptiveSettingsTile.dropdown(
                    title: 'Erika 超分辨率',
                    subtitle: '使用 Erika ART-CNN 对视频帧做实时超分',
                    icon: Ionicons.sparkles_outline,
                    items: items,
                    onChanged: (dynamic value) async {
                      if (value is! PlayerUpscalerMode) return;
                      await videoState.setErikaUpscalerMode(value);
                      if (!context.mounted) return;
                      final option = _getErikaUpscalerTitle(value);
                      BlurSnackBar.show(
                        context,
                        value == PlayerUpscalerMode.off
                            ? '已关闭 Erika 超分辨率'
                            : 'Erika 超分辨率已切换为$option',
                      );
                    },
                    dropdownKey: _erikaUpscalerDropdownKey,
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (visibleKernelType == PlayerKernelType.mdk ||
                visibleKernelType == PlayerKernelType.mediaKit) ...[
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.toggle(
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
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (!kIsWeb &&
                Platform.isAndroid &&
                visibleKernelType == PlayerKernelType.mediaKit) ...[
              AdaptiveSettingsTile.dropdown(
                title: 'Android 音频后端',
                subtitle:
                    '音频后端切换为 AudioTrack 可支持某些Android机型杜比全景声等系统音效（实验性，需重启APP生效）',
                icon: Ionicons.musical_notes_outline,
                items: [
                  DropdownMenuItemData(
                    title: 'OpenSL ES',
                    value: 'opensles',
                    isSelected: _androidAudioOutput == 'opensles',
                    description: '默认，兼容性较好',
                  ),
                  DropdownMenuItemData(
                    title: 'AudioTrack',
                    value: 'audiotrack',
                    isSelected: _androidAudioOutput == 'audiotrack',
                    description: '支持系统音效（如杜比全景声）',
                  ),
                ],
                onChanged: _saveAndroidAudioOutputSettings,
                dropdownKey: _androidAudioOutputDropdownKey,
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (!kIsWeb &&
                (Platform.isMacOS || Platform.isWindows) &&
                visibleKernelType == PlayerKernelType.mediaKit) ...[
              AdaptiveSettingsTile.toggle(
                title: '实验性 HDR 原生视频输出',
                subtitle: Platform.isWindows
                    ? '开启后使用 Windows 原生视频窗口；关闭后回退到 Flutter 纹理路径'
                    : '开启后使用 macOS 原生视频层；关闭后回退到 Flutter 纹理路径',
                icon: Ionicons.color_filter_outline,
                value: _macOSNativeVideoEnabled,
                onChanged: (bool value) async {
                  await _saveMacOSNativeVideoSetting(value);
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            if (globals.isPhone) ...[
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.toggle(
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
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
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

                return AdaptiveSettingsTile.dropdown(
                  title: '播放结束操作',
                  subtitle: '控制本集播放完毕后的默认行为',
                  icon: Ionicons.stop_circle_outline,
                  items: items,
                  onChanged: (dynamic value) async {
                    if (value is! PlaybackEndAction) return;
                    await videoState.setPlaybackEndAction(value);
                    if (!context.mounted) return;
                    String message;
                    switch (value) {
                      case PlaybackEndAction.autoNext:
                        message = '播放结束后将自动进入下一话';
                        break;
                      case PlaybackEndAction.loop:
                        message = '播放结束后将从头循环播放';
                        break;
                      case PlaybackEndAction.pause:
                        message = '播放结束后将停留在当前页面';
                        break;
                      case PlaybackEndAction.exitPlayer:
                        message = '播放结束后将返回上一页';
                        break;
                    }
                    BlurSnackBar.show(context, message);
                  },
                );
              },
            ),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final bool isAutoNext =
                    videoState.playbackEndAction == PlaybackEndAction.autoNext;
                if (!isAutoNext) {
                  return const SizedBox.shrink();
                }
                final double minSeconds =
                    AutoNextEpisodeService.minCountdownSeconds.toDouble();
                final double maxSeconds =
                    AutoNextEpisodeService.maxCountdownSeconds.toDouble();
                const divisions = AutoNextEpisodeService.maxCountdownSeconds -
                    AutoNextEpisodeService.minCountdownSeconds;
                return Column(
                  children: [
                    Divider(
                        color: colorScheme.onSurface.withValues(alpha: 0.12),
                        height: 1),
                    AdaptiveSettingsTile.slider(
                      title: '自动连播倒计时',
                      subtitle: '播放结束后等待多久再自动播放下一话',
                      icon: Ionicons.timer_outline,
                      value: videoState.autoNextCountdownSeconds.toDouble(),
                      min: minSeconds,
                      max: maxSeconds,
                      divisions: divisions,
                      onChanged: (value) {
                        videoState.setAutoNextCountdownSeconds(value.round());
                      },
                      labelFormatter: (value) => '${value.round()} 秒',
                    ),
                  ],
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final items = _buildSeekStepOptions(videoState)
                    .map(
                      (seconds) => DropdownMenuItemData<double>(
                        title: videoState.formatSeekStepLabel(
                          seconds,
                          preferFrameLabel: true,
                          includeFrameApproximation: true,
                        ),
                        value: seconds,
                        isSelected:
                            (videoState.seekStepSeconds - seconds).abs() <
                                VideoPlayerState.seekStepComparisonEpsilon,
                      ),
                    )
                    .toList();
                return AdaptiveSettingsTile.dropdown(
                  title: '快进快退步长',
                  subtitle: '控制快进、快退按钮和方向键每次跳转的时间',
                  icon: Ionicons.play_skip_forward_outline,
                  items: items,
                  onChanged: (dynamic value) async {
                    if (value is! double) return;
                    await videoState.setSeekStepSeconds(value);
                    if (!context.mounted) return;
                    BlurSnackBar.show(
                      context,
                      '快进快退步长已设为 ${videoState.formatSeekStepLabel(value, preferFrameLabel: true)}',
                    );
                  },
                  dropdownKey: _seekStepDropdownKey,
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final items = _buildSpeedBoostOptions(videoState)
                    .map(
                      (rate) => DropdownMenuItemData<double>(
                        title: _formatRateLabel(rate),
                        value: rate,
                        isSelected:
                            (videoState.speedBoostRate - rate).abs() < 0.0005,
                      ),
                    )
                    .toList();
                return AdaptiveSettingsTile.dropdown(
                  title: '长按倍速倍率',
                  subtitle: '长按快进手势时临时切换到该播放速度',
                  icon: Ionicons.flash_outline,
                  items: items,
                  onChanged: (dynamic value) async {
                    if (value is! double) return;
                    await videoState.setSpeedBoostRate(value);
                    if (!context.mounted) return;
                    BlurSnackBar.show(
                        context, '长按倍速倍率已设为 ${_formatRateLabel(value)}');
                  },
                  dropdownKey: _speedBoostDropdownKey,
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                return AdaptiveSettingsTile.slider(
                  title: '跳过时间',
                  subtitle: '控制播放器左上角和快捷键的跳过按钮前进秒数',
                  icon: Ionicons.play_skip_forward_outline,
                  value: videoState.skipSeconds
                      .clamp(_minSkipSeconds, _maxSkipSeconds)
                      .toDouble(),
                  min: _minSkipSeconds.toDouble(),
                  max: _maxSkipSeconds.toDouble(),
                  divisions: (_maxSkipSeconds - _minSkipSeconds) ~/ 10,
                  onChanged: (value) {
                    videoState.setSkipSeconds((value / 10).round() * 10);
                  },
                  labelFormatter: (value) => '${((value / 10).round() * 10)} 秒',
                );
              },
            ),
            if (visibleKernelType == PlayerKernelType.mdk) ...[
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.toggle(
                    title: '时间轴截图预览',
                    subtitle: '进度条悬停时显示缩略图（仅本地/WebDAV/SMB/共享媒体库生效）',
                    icon: Icons.photo_size_select_small_outlined,
                    value: videoState.timelinePreviewEnabled,
                    onChanged: (bool value) async {
                      if (value) {
                        final bool? confirm = AdaptiveSettingsScope
                                .isPhoneLayout(context)
                            ? await cupertino.showCupertinoDialog<bool>(
                                context: context,
                                builder: (dialogContext) =>
                                    cupertino.CupertinoAlertDialog(
                                  title: const Text('开启警告'),
                                  content: const Text(
                                      '开启时间轴截图预览会在后台实时生成截图，可能导致播放卡顿或性能下降。是否确认开启？'),
                                  actions: [
                                    cupertino.CupertinoDialogAction(
                                      onPressed: () =>
                                          Navigator.of(dialogContext)
                                              .pop(false),
                                      child: const Text('取消'),
                                    ),
                                    cupertino.CupertinoDialogAction(
                                      isDefaultAction: true,
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                      child: const Text('确认'),
                                    ),
                                  ],
                                ),
                              )
                            : await showDialog<bool>(
                                context: context,
                                builder: (dialogContext) => AlertDialog(
                                  title: const Text('开启警告'),
                                  content: const Text(
                                      '开启时间轴截图预览会在后台实时生成截图，可能导致播放卡顿或性能下降。是否确认开启？'),
                                  actions: [
                                    AdaptiveSettingsActionButton(
                                      label: '取消',
                                      onPressed: () =>
                                          Navigator.of(dialogContext)
                                              .pop(false),
                                    ),
                                    AdaptiveSettingsActionButton(
                                      label: '确认',
                                      primary: true,
                                      onPressed: () =>
                                          Navigator.of(dialogContext).pop(true),
                                    ),
                                  ],
                                ),
                              );
                        if (confirm != true) return;
                      }
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
            ],
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                return AdaptiveSettingsTile.toggle(
                  title: 'MKV 章节标记',
                  subtitle: '在进度条上显示 MKV 自带章节分割线，悬停高亮后点击可跳转章节（仅 libmpv 内核）',
                  icon: Ionicons.bookmark_outline,
                  value: videoState.chapterMarkersEnabled,
                  onChanged: (bool value) async {
                    await videoState.setChapterMarkersEnabled(value);
                    if (!context.mounted) return;
                    BlurSnackBar.show(
                      context,
                      value ? '已开启 MKV 章节标记' : '已关闭 MKV 章节标记',
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
                if (visibleKernelType == PlayerKernelType.mdk) {
                  const int minSeconds = 1;
                  const int maxSeconds = 120;
                  return AdaptiveSettingsTile.slider(
                    title: '播放预缓存时长',
                    subtitle:
                        '当前 ${videoState.precacheBufferDurationSeconds} 秒，修改后立即生效',
                    icon: Ionicons.cloud_download_outline,
                    value: videoState.precacheBufferDurationSeconds.toDouble(),
                    min: minSeconds.toDouble(),
                    max: maxSeconds.toDouble(),
                    divisions: maxSeconds - minSeconds,
                    onChanged: (value) {
                      videoState
                          .setPrecacheBufferDurationSeconds(value.round());
                    },
                    labelFormatter: (value) => '${value.round()} 秒',
                  );
                }
                final bool enableSetting =
                    visibleKernelType == PlayerKernelType.mediaKit;
                const int stepSize = 4;
                const int minValue = PlayerFactory.minPrecacheBufferSizeMb;
                const int maxValue = PlayerFactory.maxPrecacheBufferSizeMb;
                final int divisions =
                    ((maxValue - minValue) / stepSize).round();
                return AdaptiveSettingsTile.slider(
                  title: '播放预缓存大小',
                  subtitle: enableSetting
                      ? '当前 ${videoState.precacheBufferSizeMb} MB，修改后重新打开视频生效'
                      : '仅 Libmpv 内核生效',
                  icon: Ionicons.cloud_download_outline,
                  enabled: enableSetting,
                  value: videoState.precacheBufferSizeMb.toDouble(),
                  min: minValue.toDouble(),
                  max: maxValue.toDouble(),
                  divisions: divisions,
                  onChanged: (value) {
                    videoState.setPrecacheBufferSizeMb(value.round());
                  },
                  labelFormatter: (value) => '${value.round()} MB',
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            if (globals.isDesktop) ...[
              Consumer<VideoPlayerState>(
                builder: (context, videoState, child) {
                  return AdaptiveSettingsTile.toggle(
                    title: '立即隐藏播放器UI',
                    subtitle: '鼠标移开后立即隐藏播放控制（桌面端）',
                    icon: Ionicons.eye_off_outline,
                    value: videoState.instantHidePlayerUiEnabled,
                    onChanged: (bool value) async {
                      await videoState.setInstantHidePlayerUiEnabled(value);
                      if (!context.mounted) return;
                      BlurSnackBar.show(
                        context,
                        value ? '已开启立即隐藏播放器UI' : '已关闭立即隐藏播放器UI',
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
                  return AdaptiveSettingsTile.toggle(
                    title: '右侧悬浮设置菜单',
                    subtitle: '鼠标移到播放器最右侧显示设置菜单（桌面端）',
                    icon: Ionicons.settings_outline,
                    value: videoState.desktopHoverSettingsMenuEnabled,
                    onChanged: (bool value) async {
                      await videoState
                          .setDesktopHoverSettingsMenuEnabled(value);
                      if (!context.mounted) return;
                      BlurSnackBar.show(
                        context,
                        value ? '已开启右侧悬浮设置菜单' : '已关闭右侧悬浮设置菜单',
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
                  // notice: 不清楚移动端是否需要该功能，选项暂时只向桌面端开放
                  return AdaptiveSettingsTile.toggle(
                    title: '自动全屏',
                    subtitle: '在加载视频后自动全屏',
                    icon: Icons.fullscreen_rounded,
                    value: videoState.autoFullscreenEnabled,
                    onChanged: (bool value) async {
                      await videoState.setAutoFullscreenEnabled(value);
                      if (!context.mounted) return;
                      BlurSnackBar.show(
                        context,
                        value ? '已开启自动全屏' : '已关闭自动全屏',
                      );
                    },
                  );
                },
              ),
              Divider(
                  color: colorScheme.onSurface.withValues(alpha: 0.12),
                  height: 1),
            ],
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                if (visibleKernelType != PlayerKernelType.mediaKit) {
                  return const SizedBox.shrink();
                }
                final bool supportsUpscale =
                    videoState.isDoubleResolutionSupported;
                if (!supportsUpscale) {
                  return const SizedBox.shrink();
                }
                return AdaptiveSettingsTile.toggle(
                  title: '双倍分辨率播放视频',
                  subtitle: '以 2x 分辨率渲染画面，改善内嵌字幕清晰度（仅 Libmpv，不与 Anime4K 叠加）',
                  icon: Ionicons.resize_outline,
                  value: videoState.doubleResolutionPlaybackEnabled,
                  onChanged: (bool value) async {
                    await videoState.setDoubleResolutionPlaybackEnabled(value);
                    if (!context.mounted) return;
                    final bool deferApply = videoState.hasVideo;
                    final String message = deferApply
                        ? '已保存，重新打开视频生效'
                        : (value ? '已开启双倍分辨率播放' : '已关闭双倍分辨率播放');
                    BlurSnackBar.show(
                      context,
                      message,
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

                if (visibleKernelType != PlayerKernelType.mediaKit) {
                  return const SizedBox.shrink();
                }

                if (!supportsAnime4K) {
                  return const SizedBox.shrink();
                }

                return AdaptiveSettingsTile.dropdown(
                  title: 'Anime4K 超分辨率（实验性）',
                  subtitle: '使用 Anime4K GLSL 着色器提升二次元画面清晰度',
                  icon: Ionicons.color_wand_outline,
                  items: items,
                  onChanged: (dynamic value) async {
                    if (value is! Anime4KProfile) return;
                    await videoState.setAnime4KProfile(value);
                    if (!context.mounted) return;
                    final bool deferApply = videoState.hasVideo;
                    final String option = _getAnime4KProfileTitle(value);
                    final String message = deferApply
                        ? '已保存，重新打开视频生效'
                        : (value == Anime4KProfile.off
                            ? '已关闭 Anime4K'
                            : 'Anime4K 已切换为$option');
                    BlurSnackBar.show(context, message);
                  },
                );
              },
            ),
            Divider(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
                height: 1),
            Consumer<VideoPlayerState>(
              builder: (context, videoState, child) {
                final CrtProfile currentProfile = videoState.crtProfile;
                final bool supportsCrt = videoState.isCrtSupported;

                if (visibleKernelType != PlayerKernelType.mediaKit) {
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

                return AdaptiveSettingsTile.dropdown(
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
            if (visibleKernelType == PlayerKernelType.mdk) ...[
              // 这里可以添加解码器相关设置
            ],
          ],
        ),
      ],
    );
  }

  String _text(
    BuildContext context,
    String simplified,
    String traditional,
    String english,
  ) {
    final locale = context.l10n.localeName;
    if (locale == 'en') return english;
    if (locale == 'zh_Hant') return traditional;
    return simplified;
  }
}

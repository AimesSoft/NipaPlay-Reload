import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'package:nipaplay/providers/settings_provider.dart';

class FluentPlayerSettingsPage extends StatefulWidget {
  const FluentPlayerSettingsPage({super.key});

  @override
  State<FluentPlayerSettingsPage> createState() => _FluentPlayerSettingsPageState();
}

class _FluentPlayerSettingsPageState extends State<FluentPlayerSettingsPage> {
  static const String _selectedDecodersKey = 'selected_decoders';
  
  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.cpu;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeSettings();
  }

  Future<void> _initializeSettings() async {
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      final playerState = Provider.of<VideoPlayerState>(context, listen: false);
      _decoderManager = playerState.decoderManager;
      
      _getAvailableDecoders();
      await _loadDecoderSettings();
      await _loadPlayerKernelSettings();
      await _loadDanmakuRenderEngineSettings();
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
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

    if (context.mounted) {
      _showSuccessInfoBar('播放器内核已切换');
    }

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
    _selectedDecoders.retainWhere((decoder) => _availableDecoders.contains(decoder));
    if (_selectedDecoders.isEmpty && _availableDecoders.isNotEmpty) {
        _initializeSelectedDecodersWithPlatformDefaults();
    }
  }



  Future<void> _loadDanmakuRenderEngineSettings() async {
    setState(() {
      _selectedDanmakuRenderEngine = DanmakuKernelFactory.getKernelType();
    });
  }

  Future<void> _saveDanmakuRenderEngineSettings(DanmakuRenderEngine engine) async {
    await DanmakuKernelFactory.saveKernelType(engine);
    
    if (context.mounted) {
      _showSuccessInfoBar('弹幕渲染引擎已切换');
    }
    
    setState(() {
      _selectedDanmakuRenderEngine = engine;
    });
  }
  


  String _getPlayerKernelDescription(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return 'MDK 多媒体开发套件，基于FFmpeg，CPU解码视频，性能优秀';
      case PlayerKernelType.videoPlayer:
        return 'Video Player 官方播放器，适用于简单视频播放，兼容性良好';
      case PlayerKernelType.mediaKit:
        return 'MediaKit (Libmpv) 播放器，基于MPV，功能强大，支持硬件解码，支持复杂媒体格式';
    }
  }

  String _getDanmakuRenderEngineDescription(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return '使用 Flutter Widget 进行绘制，兼容性好，但在低端设备上弹幕量大时可能卡顿';
      case DanmakuRenderEngine.gpu:
        return '使用自定义着色器和字体图集，性能更高，功耗更低，但目前仍在开发中';
    }
  }

  void _showSuccessInfoBar(String message) {
    FluentInfoBar.show(
      context,
      message,
      severity: InfoBarSeverity.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const ScaffoldPage(
        content: Center(
          child: ProgressRing(),
        ),
      );
    }

    // Web 平台显示提示信息
    if (kIsWeb) {
      return ScaffoldPage(
        header: const PageHeader(
          title: Text('播放器设置'),
        ),
        content: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              InfoBar(
                title: const Text('Web平台提示'),
                content: const Text('播放器设置在Web平台不可用，Web平台使用浏览器内置播放器。'),
                severity: InfoBarSeverity.info,
              ),
            ],
          ),
        ),
      );
    }

    return ScaffoldPage(
      header: const PageHeader(
        title: Text('播放器设置'),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
          children: [
            // 播放器内核设置
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '播放器内核',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择播放器使用的核心引擎',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    const SizedBox(height: 16),
                    
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('当前内核'),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ComboBox<PlayerKernelType>(
                            value: _selectedKernelType,
                            items: [
                              ComboBoxItem<PlayerKernelType>(
                                value: PlayerKernelType.mdk,
                                child: const Text('MDK'),
                              ),
                              ComboBoxItem<PlayerKernelType>(
                                value: PlayerKernelType.videoPlayer,
                                child: const Text('Video Player'),
                              ),
                              ComboBoxItem<PlayerKernelType>(
                                value: PlayerKernelType.mediaKit,
                                child: const Text('Libmpv'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _savePlayerKernelSettings(value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getPlayerKernelDescription(_selectedKernelType),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 弹幕渲染引擎设置
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '弹幕渲染引擎',
                      style: FluentTheme.of(context).typography.subtitle,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '选择弹幕的渲染方式',
                      style: FluentTheme.of(context).typography.caption,
                    ),
                    const SizedBox(height: 16),
                    
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('渲染引擎'),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: ComboBox<DanmakuRenderEngine>(
                            value: _selectedDanmakuRenderEngine,
                            items: [
                              ComboBoxItem<DanmakuRenderEngine>(
                                value: DanmakuRenderEngine.cpu,
                                child: const Text('CPU 渲染'),
                              ),
                              ComboBoxItem<DanmakuRenderEngine>(
                                value: DanmakuRenderEngine.gpu,
                                child: const Text('GPU 渲染 (实验性)'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                _saveDanmakuRenderEngineSettings(value);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _getDanmakuRenderEngineDescription(_selectedDanmakuRenderEngine),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // 弹幕设置
            Consumer<SettingsProvider>(
              builder: (context, settingsProvider, child) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '弹幕设置',
                          style: FluentTheme.of(context).typography.subtitle,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '配置弹幕显示选项',
                          style: FluentTheme.of(context).typography.caption,
                        ),
                        const SizedBox(height: 16),
                        
                        // 弹幕转换简体中文开关
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('弹幕转换简体中文'),
                                  const SizedBox(height: 4),
                                  Text(
                                    '开启后，繁体中文弹幕将转换为简体中文显示',
                                    style: FluentTheme.of(context).typography.caption,
                                  ),
                                ],
                              ),
                            ),
                            ToggleSwitch(
                              checked: settingsProvider.danmakuConvertToSimplified,
                              onChanged: (value) {
                                settingsProvider.setDanmakuConvertToSimplified(value);
                                // 使用Fluent UI的消息提示
                                if (context.mounted) {
                                  displayInfoBar(
                                    context,
                                    builder: (context, close) {
                                      return InfoBar(
                                        title: Text(value ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文'),
                                        severity: InfoBarSeverity.success,
                                      );
                                    },
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // MDK内核特有设置可以在这里添加
            if (_selectedKernelType == PlayerKernelType.mdk) ...[
              const SizedBox(height: 16),
              // 可以添加解码器相关设置
            ],
          ],
          ),
        ),
      ),
    );
  }
}
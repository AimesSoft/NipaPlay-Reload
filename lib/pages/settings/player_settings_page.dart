import 'dart:io' if (dart.library.io) 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dropdown.dart';
import 'package:nipaplay/providers/settings_provider.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  _PlayerSettingsPageState createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  static const String _selectedDecodersKey = 'selected_decoders';
  static const String _playerKernelTypeKey = 'player_kernel_type';
  static const String _danmakuRenderEngineKey = 'danmaku_render_engine';
  
  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;
  String _playerCoreName = "MDK";
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  DanmakuRenderEngine _selectedDanmakuRenderEngine = DanmakuRenderEngine.cpu;
  
  // 为BlurDropdown添加GlobalKey
  final GlobalKey _playerKernelDropdownKey = GlobalKey();
  final GlobalKey _danmakuRenderEngineDropdownKey = GlobalKey();

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final playerState = Provider.of<VideoPlayerState>(context, listen: false);
    _decoderManager = playerState.decoderManager;
    _playerCoreName = playerState.playerCoreName;
    
    if (!kIsWeb) {
      _getAvailableDecoders();
    }
    _loadDecoderSettings();
    _loadPlayerKernelSettings();
    _loadDanmakuRenderEngineSettings();
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
        TextButton(
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
          child: const Text('确定', style: TextStyle(color: Colors.white)),
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
    _selectedDecoders.retainWhere((decoder) => _availableDecoders.contains(decoder));
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
        final playerState = Provider.of<VideoPlayerState>(context, listen: false);
        if (playerState.hasVideo && 
            playerState.player.mediaInfo.video != null && 
            playerState.player.mediaInfo.video!.isNotEmpty) {
          
          final videoTrack = playerState.player.mediaInfo.video![0];
          final codecString = videoTrack.toString().toLowerCase();
          if (codecString.contains('hevc') || codecString.contains('h265')) {
            debugPrint('检测到设置变更时正在播放HEVC视频，应用特殊优化...');
            
            if (Platform.isMacOS) {
              if (_selectedDecoders.isNotEmpty && _selectedDecoders[0] != "VT") {
                _selectedDecoders.remove("VT");
                _selectedDecoders.insert(0, "VT");
                
                await prefs.setStringList(_selectedDecodersKey, _selectedDecoders);
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

  Future<void> _saveDanmakuRenderEngineSettings(DanmakuRenderEngine engine) async {
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
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('取消', style: TextStyle(color: Colors.grey)),
        ),
        TextButton(
          onPressed: () {
            // 直接退出应用
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              exit(0);
            } else if (!kIsWeb) {
              // 桌面平台
              windowManager.close();
            }
          },
          child: const Text('确定', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  String _getPlayerKernelDescription(PlayerKernelType type) {
    switch (type) {
      case PlayerKernelType.mdk:
        return 'MDK 多媒体开发套件\n基于FFmpeg，支持硬件加速，性能优秀';
      case PlayerKernelType.videoPlayer:
        return 'Video Player 官方播放器\n适用于简单视频播放，兼容性良好';
      case PlayerKernelType.mediaKit:
        return 'MediaKit (Libmpv) 播放器\n基于MPV，功能强大，支持复杂媒体格式';
    }
  }

  String _getDanmakuRenderEngineDescription(DanmakuRenderEngine engine) {
    switch (engine) {
      case DanmakuRenderEngine.cpu:
        return 'CPU 渲染引擎\n使用 Flutter Widget 进行绘制，兼容性好，但在低端设备上弹幕量大时可能卡顿。';
      case DanmakuRenderEngine.gpu:
        return 'GPU 渲染引擎 (实验性)\n使用自定义着色器和字体图集，性能更高，功耗更低，但目前仍在开发中。';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Web 平台不显示此页面内容，或者显示一个提示信息
    if (kIsWeb) {
      return const Center(
        child: Text(
          '播放器设置在Web平台不可用',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    return ListView(
      children: [
        ListTile(
          title: const Text("播放器内核", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text(
            "选择播放器使用的核心引擎",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: BlurDropdown<PlayerKernelType>(
            dropdownKey: _playerKernelDropdownKey,
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
                description: _getPlayerKernelDescription(PlayerKernelType.videoPlayer),
              ),
              DropdownMenuItemData(
                title: "Libmpv",
                value: PlayerKernelType.mediaKit,
                isSelected: _selectedKernelType == PlayerKernelType.mediaKit,
                description: _getPlayerKernelDescription(PlayerKernelType.mediaKit),
              ),
            ],
            onItemSelected: (kernelType) {
              _savePlayerKernelSettings(kernelType);
            },
          ),
        ),
        
        const Divider(color: Colors.white12, height: 1),
        
        ListTile(
          title: const Text("弹幕渲染引擎", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          subtitle: const Text(
            "选择弹幕的渲染方式",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: BlurDropdown<DanmakuRenderEngine>(
            dropdownKey: _danmakuRenderEngineDropdownKey,
            items: [
              DropdownMenuItemData(
                title: "CPU 渲染",
                value: DanmakuRenderEngine.cpu,
                isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.cpu,
                description: _getDanmakuRenderEngineDescription(DanmakuRenderEngine.cpu),
              ),
              DropdownMenuItemData(
                title: "GPU 渲染 (实验性)",
                value: DanmakuRenderEngine.gpu,
                isSelected: _selectedDanmakuRenderEngine == DanmakuRenderEngine.gpu,
                description: _getDanmakuRenderEngineDescription(DanmakuRenderEngine.gpu),
              ),
            ],
            onItemSelected: (engine) {
              _saveDanmakuRenderEngineSettings(engine);
            },
          ),
        ),
        
        const Divider(color: Colors.white12, height: 1),
        
        // 弹幕转换简体中文开关
        Consumer<SettingsProvider>(
          builder: (context, settingsProvider, child) {
            return SwitchListTile(
              title: const Text(
                "弹幕转换简体中文",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                "开启后，繁体中文弹幕将转换为简体中文显示",
                style: TextStyle(color: Colors.white70),
              ),
              value: settingsProvider.danmakuConvertToSimplified,
              onChanged: (bool value) {
                settingsProvider.setDanmakuConvertToSimplified(value);
                if (context.mounted) {
                  BlurSnackBar.show(context, value ? '已开启弹幕转换简体中文' : '已关闭弹幕转换简体中文');
                }
              },
              activeColor: Colors.white,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color.fromARGB(255, 0, 0, 0),
            );
          },
        ),
        
        const Divider(color: Colors.white12, height: 1),
        
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
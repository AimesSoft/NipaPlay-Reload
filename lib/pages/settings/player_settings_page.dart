import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/danmaku_abstraction/danmaku_kernel_factory.dart';
import 'package:window_manager/window_manager.dart';
import 'package:nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/blur_dropdown.dart';
import 'package:nipaplay/utils/theme_utils.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({super.key});

  @override
  _PlayerSettingsPageState createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  static const String _selectedDecodersKey = 'selected_decoders';
  static const String _playerKernelTypeKey = 'player_kernel_type';
  
  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;
  String _playerCoreName = "MDK";
  PlayerKernelType _selectedKernelType = PlayerKernelType.mdk;
  DanmakuKernelType _selectedDanmakuKernelType = DanmakuKernelType.nipaPlay;
  
  // 为BlurDropdown添加GlobalKey
  final GlobalKey _playerKernelDropdownKey = GlobalKey();
  final GlobalKey _danmakuKernelDropdownKey = GlobalKey();

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
    
    _getAvailableDecoders();
    _loadDecoderSettings();
    _loadPlayerKernelSettings();
    _loadDanmakuKernelSettings();
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
    
    if (_selectedKernelType != kernelType && context.mounted) {
      _showRestartDialog();
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
            if (Platform.isAndroid || Platform.isIOS) {
              exit(0);
            } else {
              // 桌面平台
              windowManager.close();
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
      _selectedDecoders = ["FFmpeg"];
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

  Future<void> _loadDanmakuKernelSettings() async {
    setState(() {
      _selectedDanmakuKernelType = DanmakuKernelFactory.getKernelType();
    });
  }

  Future<void> _saveDanmakuKernelSettings(DanmakuKernelType kernelType) async {
    await DanmakuKernelFactory.saveKernelType(kernelType);
    
    setState(() {
      _selectedDanmakuKernelType = kernelType;
    });
    
    if (context.mounted) {
      String kernelName = kernelType == DanmakuKernelType.nipaPlay ? 'NipaPlay' : 'Canvas_Danmaku';
      BlurSnackBar.show(context, '弹幕内核已切换为: $kernelName');
    }
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

  String _getDanmakuKernelDescription(DanmakuKernelType type) {
    switch (type) {
      case DanmakuKernelType.nipaPlay:
        return 'NipaPlay 内置弹幕渲染器\n支持轨道分配、弹幕合并、防重叠等高级功能';
      case DanmakuKernelType.canvasDanmaku:
        return 'Canvas_Danmaku 渲染器\n基于CustomPainter，性能更佳，功耗更低';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        ListTile(
          title: Text("播放器内核", style: getTitleTextStyle(context)),
          subtitle: Text(
            _getPlayerKernelDescription(_selectedKernelType),
            style: TextStyle(
              color: Colors.grey[200],
              fontSize: 12,
            ),
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
        
        const Divider(),
        
        ListTile(
          title: Text("弹幕内核", style: getTitleTextStyle(context)),
          subtitle: Text(
            _getDanmakuKernelDescription(_selectedDanmakuKernelType),
            style: TextStyle(
              color: Colors.grey[200],
              fontSize: 12,
            ),
          ),
          trailing: BlurDropdown<DanmakuKernelType>(
            dropdownKey: _danmakuKernelDropdownKey,
            items: [
              DropdownMenuItemData(
                title: "NipaPlay",
                value: DanmakuKernelType.nipaPlay,
                isSelected: _selectedDanmakuKernelType == DanmakuKernelType.nipaPlay,
                description: _getDanmakuKernelDescription(DanmakuKernelType.nipaPlay),
              ),
              DropdownMenuItemData(
                title: "Canvas_Danmaku",
                value: DanmakuKernelType.canvasDanmaku,
                isSelected: _selectedDanmakuKernelType == DanmakuKernelType.canvasDanmaku,
                description: _getDanmakuKernelDescription(DanmakuKernelType.canvasDanmaku),
              ),
            ],
            onItemSelected: (kernelType) {
              _saveDanmakuKernelSettings(kernelType);
            },
          ),
        ),
        
        const Divider(),
        
        if (_selectedKernelType == PlayerKernelType.mdk) ...[
          // 这里可以添加解码器相关设置
        ],
      ],
    );
  }
  
  String _getDecoderDescription() {
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
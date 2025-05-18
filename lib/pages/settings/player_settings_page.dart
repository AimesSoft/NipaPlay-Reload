import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fvp/mdk.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/utils/decoder_manager.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/widgets/blur_snackbar.dart';

class PlayerSettingsPage extends StatefulWidget {
  const PlayerSettingsPage({Key? key}) : super(key: key);

  @override
  _PlayerSettingsPageState createState() => _PlayerSettingsPageState();
}

class _PlayerSettingsPageState extends State<PlayerSettingsPage> {
  static const String _useHardwareDecoderKey = 'use_hardware_decoder';
  static const String _selectedDecodersKey = 'selected_decoders';
  
  bool _useHardwareDecoder = true;
  List<String> _availableDecoders = [];
  List<String> _selectedDecoders = [];
  late DecoderManager _decoderManager;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final playerState = Provider.of<VideoPlayerState>(context, listen: false);
    _decoderManager = playerState.decoderManager;
    
    _getAvailableDecoders();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
      
      final savedDecoders = prefs.getStringList(_selectedDecodersKey);
      if (savedDecoders != null && savedDecoders.isNotEmpty) {
        _selectedDecoders = savedDecoders;
      } else {
        _selectedDecoders = ["FFmpeg"];
      }
    });
  }

  void _getAvailableDecoders() {
    final allDecoders = _decoderManager.getAllSupportedDecoders();
    
    if (Platform.isMacOS) {
      _availableDecoders = allDecoders['macos']!;
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = List.from(allDecoders['macos']!);
      }
    } else if (Platform.isIOS) {
      _availableDecoders = allDecoders['ios']!;
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = List.from(allDecoders['ios']!);
      }
    } else if (Platform.isWindows) {
      _availableDecoders = allDecoders['windows']!;
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = List.from(allDecoders['windows']!);
      }
    } else if (Platform.isLinux) {
      _availableDecoders = allDecoders['linux']!;
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = List.from(allDecoders['linux']!);
      }
    } else if (Platform.isAndroid) {
      _availableDecoders = allDecoders['android']!;
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = List.from(allDecoders['android']!);
      }
    } else {
      _availableDecoders = ["FFmpeg"];
      if (_selectedDecoders.length <= 1) {
        _selectedDecoders = ["FFmpeg"];
      }
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useHardwareDecoderKey, _useHardwareDecoder);
    await prefs.setStringList(_selectedDecodersKey, _selectedDecoders);
    
    if (context.mounted) {
      if (_useHardwareDecoder) {
        // 应用新的解码器设置
        await _decoderManager.updateDecoders(_selectedDecoders);
        
        // HEVC视频格式的特殊处理
        final playerState = Provider.of<VideoPlayerState>(context, listen: false);
        if (playerState.hasVideo && 
            playerState.player.mediaInfo.video != null && 
            playerState.player.mediaInfo.video!.isNotEmpty) {
          
          final videoTrack = playerState.player.mediaInfo.video![0];
          final codecString = videoTrack.toString().toLowerCase();
          if (codecString.contains('hevc') || codecString.contains('h265')) {
            debugPrint('检测到设置变更时正在播放HEVC视频，应用特殊优化...');
            
            if (Platform.isMacOS) {
              // 确保VideoToolbox优先
              if (_selectedDecoders.isNotEmpty && _selectedDecoders[0] != "VT") {
                _selectedDecoders.remove("VT");
                _selectedDecoders.insert(0, "VT");
                
                await prefs.setStringList(_selectedDecodersKey, _selectedDecoders);
                await _decoderManager.updateDecoders(_selectedDecoders);
                
                // 提示用户
                BlurSnackBar.show(context, '已优化解码器设置以支持HEVC硬件解码');
              }
              
              // 强制启用硬件解码
              await playerState.forceEnableHardwareDecoder();
            }
          }
        }
      } else {
        await _decoderManager.updateDecoders(["FFmpeg"]);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SwitchListTile(
          title: const Text('启用硬件解码', style: TextStyle(fontSize: 18)),
          subtitle: const Text('提高视频播放性能，建议保持开启'),
          value: _useHardwareDecoder,
          onChanged: (value) {
            setState(() {
              _useHardwareDecoder = value;
            });
            _saveSettings();
          },
        ),
        const Divider(),
        if (_useHardwareDecoder) ...[
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('解码器优先级', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0),
            child: Text('拖动调整解码器的使用优先级，上面的优先使用', 
              style: TextStyle(fontSize: 14, color: Colors.grey)),
          ),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _selectedDecoders.length,
            itemBuilder: (context, index) {
              return ListTile(
                key: Key('decoder_$index'),
                title: Text(_selectedDecoders[index]),
                trailing: const Icon(Icons.drag_handle),
              );
            },
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (oldIndex < newIndex) {
                  newIndex -= 1;
                }
                final item = _selectedDecoders.removeAt(oldIndex);
                _selectedDecoders.insert(newIndex, item);
              });
              _saveSettings();
            },
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('解码器说明', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _getDecoderDescription(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
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
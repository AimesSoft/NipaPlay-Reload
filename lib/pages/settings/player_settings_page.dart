import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fvp/mdk.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

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

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _getAvailableDecoders();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useHardwareDecoder = prefs.getBool(_useHardwareDecoderKey) ?? true;
      
      // 获取保存的解码器列表
      final savedDecoders = prefs.getStringList(_selectedDecodersKey);
      if (savedDecoders != null && savedDecoders.isNotEmpty) {
        _selectedDecoders = savedDecoders;
      } else {
        // 默认解码器设置
        if (Platform.isMacOS || Platform.isIOS) {
          _selectedDecoders = ["VT", "hap", "FFmpeg", "dav1d"];
        } else if (Platform.isWindows) {
          _selectedDecoders = ["MFT:d3d=11", "D3D11", "DXVA", "CUDA", "hap", "FFmpeg", "dav1d"];
        } else if (Platform.isLinux) {
          _selectedDecoders = ["VAAPI", "VDPAU", "CUDA", "hap", "FFmpeg", "dav1d"];
        } else if (Platform.isAndroid) {
          _selectedDecoders = ["AMediaCodec", "FFmpeg", "dav1d"];
        } else {
          _selectedDecoders = ["FFmpeg"];
        }
      }
    });
  }

  void _getAvailableDecoders() {
    // 根据平台设置可用的解码器
    if (Platform.isMacOS || Platform.isIOS) {
      _availableDecoders = ["VT", "hap", "FFmpeg", "dav1d"];
    } else if (Platform.isWindows) {
      _availableDecoders = ["MFT:d3d=11", "D3D11", "DXVA", "CUDA", "hap", "FFmpeg", "dav1d"];
    } else if (Platform.isLinux) {
      _availableDecoders = ["VAAPI", "VDPAU", "CUDA", "hap", "FFmpeg", "dav1d"];
    } else if (Platform.isAndroid) {
      _availableDecoders = ["AMediaCodec", "FFmpeg", "dav1d"];
    } else {
      _availableDecoders = ["FFmpeg"];
    }
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_useHardwareDecoderKey, _useHardwareDecoder);
    await prefs.setStringList(_selectedDecodersKey, _selectedDecoders);
    
    // 更新视频播放器的解码器设置
    if (context.mounted) {
      final playerState = Provider.of<VideoPlayerState>(context, listen: false);
      
      if (_useHardwareDecoder) {
        playerState.updateDecoders(_selectedDecoders);
      } else {
        playerState.updateDecoders(["FFmpeg"]);
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
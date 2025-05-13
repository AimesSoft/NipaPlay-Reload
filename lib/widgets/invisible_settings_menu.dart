import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:provider/provider.dart';
import '../utils/video_player_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 不可见设置菜单组件，用于修复SteamDeck/Linux上的渲染问题
/// 这个组件使用与普通设置菜单相同的渲染方式，但完全透明，对用户不可见
class InvisibleSettingsMenu extends StatefulWidget {
  const InvisibleSettingsMenu({super.key});

  @override
  State<InvisibleSettingsMenu> createState() => _InvisibleSettingsMenuState();
}

class _InvisibleSettingsMenuState extends State<InvisibleSettingsMenu> {
  static const String _linuxRenderFixEnabledKey = 'linux_render_fix_enabled';
  static const String _linuxRenderFixModeKey = 'linux_render_fix_mode';
  
  bool _isEnabled = false;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_linuxRenderFixEnabledKey) ?? false;
    final renderFixMode = prefs.getInt(_linuxRenderFixModeKey) ?? 0;
    
    // 只有当修复模式设置为1(不可见菜单)时才启用
    if (isEnabled && renderFixMode == 1) {
      setState(() {
        _isEnabled = true;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    // 如果未启用修复，返回空容器
    if (!_isEnabled) {
      return const SizedBox.shrink();
    }
    
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        // 不在播放状态或已经显示了其他菜单时不需要显示
        if (!videoState.hasVideo || 
            !videoState.showControls || 
            videoState.isFullscreen) {
          return const SizedBox.shrink();
        }
        
        // 使用与普通设置菜单相同的渲染方式，但设置为完全透明
        return Positioned(
          right: 240,
          top: 80,
          child: Opacity(
            opacity: 0.001, // 几乎完全透明，但仍然保持渲染
            child: Container(
              width: 300,
              height: 200, // 足够触发渲染效果的高度
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
} 
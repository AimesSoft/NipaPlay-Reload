import 'package:flutter/material.dart';
import 'dart:ui';
import '../utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'subtitle_tracks_menu.dart';
import '../utils/globals.dart' as globals;
import 'control_bar_settings_menu.dart';
import 'danmaku_settings_menu.dart';
import 'audio_tracks_menu.dart';

class VideoSettingsMenu extends StatefulWidget {
  final VoidCallback onClose;

  const VideoSettingsMenu({
    super.key,
    required this.onClose,
  });

  @override
  State<VideoSettingsMenu> createState() => _VideoSettingsMenuState();
}

class _VideoSettingsMenuState extends State<VideoSettingsMenu> {
  final List<OverlayEntry> _overlayEntries = [];
  bool _showSubtitleTracks = false;
  bool _showControlBarSettings = false;
  bool _showDanmakuSettings = false;
  bool _showAudioTracks = false;
  OverlayEntry? _subtitleTracksOverlay;
  OverlayEntry? _controlBarSettingsOverlay;
  OverlayEntry? _danmakuSettingsOverlay;
  OverlayEntry? _audioTracksOverlay;
  late final List<SettingsItem> _settingsItems;
  late final VideoPlayerState videoState;

  @override
  void initState() {
    super.initState();
    videoState = Provider.of<VideoPlayerState>(context, listen: false);
    _settingsItems = [
      SettingsItem(
        icon: Icons.subtitles,
        title: '字幕轨道',
        onTap: _toggleSubtitleTracksMenu,
        isActive: () => _showSubtitleTracks,
      ),
      SettingsItem(
        icon: Icons.audiotrack,
        title: '音频轨道',
        onTap: _toggleAudioTracksMenu,
        isActive: () => _showAudioTracks,
      ),
      SettingsItem(
        icon: Icons.height,
        title: '控制栏设置',
        onTap: _toggleControlBarSettingsMenu,
        isActive: () => _showControlBarSettings,
      ),
      SettingsItem(
        icon: Icons.text_fields,
        title: '弹幕设置',
        onTap: _toggleDanmakuSettingsMenu,
        isActive: () => _showDanmakuSettings,
      ),
    ];
  }

  void _toggleSubtitleTracksMenu() {
    if (_showSubtitleTracks) {
      _subtitleTracksOverlay?.remove();
      _subtitleTracksOverlay = null;
      setState(() => _showSubtitleTracks = false);
    } else {
      _subtitleTracksOverlay?.remove();
      _controlBarSettingsOverlay?.remove();
      _danmakuSettingsOverlay?.remove();
      _audioTracksOverlay?.remove();
      _controlBarSettingsOverlay = null;
      _danmakuSettingsOverlay = null;
      _audioTracksOverlay = null;
      setState(() {
        _showSubtitleTracks = true;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
      });
      
      _subtitleTracksOverlay = OverlayEntry(
        builder: (context) => SubtitleTracksMenu(
          onClose: () {
            _subtitleTracksOverlay?.remove();
            _subtitleTracksOverlay = null;
            setState(() => _showSubtitleTracks = false);
          },
        ),
      );

      Overlay.of(context).insert(_subtitleTracksOverlay!);
    }
  }

  void _toggleAudioTracksMenu() {
    if (_showAudioTracks) {
      _audioTracksOverlay?.remove();
      _audioTracksOverlay = null;
      setState(() => _showAudioTracks = false);
    } else {
      _subtitleTracksOverlay?.remove();
      _controlBarSettingsOverlay?.remove();
      _danmakuSettingsOverlay?.remove();
      _audioTracksOverlay?.remove();
      _subtitleTracksOverlay = null;
      _controlBarSettingsOverlay = null;
      _danmakuSettingsOverlay = null;
      setState(() {
        _showAudioTracks = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
      });
      
      _audioTracksOverlay = OverlayEntry(
        builder: (context) => AudioTracksMenu(
          onClose: () {
            _audioTracksOverlay?.remove();
            _audioTracksOverlay = null;
            setState(() => _showAudioTracks = false);
          },
        ),
      );

      Overlay.of(context).insert(_audioTracksOverlay!);
    }
  }

  void _toggleControlBarSettingsMenu() {
    if (_showControlBarSettings) {
      _controlBarSettingsOverlay?.remove();
      _controlBarSettingsOverlay = null;
      setState(() => _showControlBarSettings = false);
    } else {
      _subtitleTracksOverlay?.remove();
      _controlBarSettingsOverlay?.remove();
      _danmakuSettingsOverlay?.remove();
      _audioTracksOverlay?.remove();
      _subtitleTracksOverlay = null;
      _danmakuSettingsOverlay = null;
      _audioTracksOverlay = null;
      setState(() {
        _showControlBarSettings = true;
        _showSubtitleTracks = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
      });

      _controlBarSettingsOverlay = OverlayEntry(
        builder: (context) => ControlBarSettingsMenu(
          onClose: () {
            _controlBarSettingsOverlay?.remove();
            _controlBarSettingsOverlay = null;
            setState(() => _showControlBarSettings = false);
          },
          videoState: videoState,
        ),
      );

      Overlay.of(context).insert(_controlBarSettingsOverlay!);
    }
  }

  void _toggleDanmakuSettingsMenu() {
    if (_showDanmakuSettings) {
      _danmakuSettingsOverlay?.remove();
      _danmakuSettingsOverlay = null;
      setState(() => _showDanmakuSettings = false);
    } else {
      _subtitleTracksOverlay?.remove();
      _controlBarSettingsOverlay?.remove();
      _danmakuSettingsOverlay?.remove();
      _audioTracksOverlay?.remove();
      _subtitleTracksOverlay = null;
      _controlBarSettingsOverlay = null;
      _audioTracksOverlay = null;
      setState(() {
        _showDanmakuSettings = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showAudioTracks = false;
      });

      _danmakuSettingsOverlay = OverlayEntry(
        builder: (context) => DanmakuSettingsMenu(
          onClose: () {
            _danmakuSettingsOverlay?.remove();
            _danmakuSettingsOverlay = null;
            setState(() => _showDanmakuSettings = false);
          },
          videoState: videoState,
        ),
      );

      Overlay.of(context).insert(_danmakuSettingsOverlay!);
    }
  }

  @override
  void dispose() {
    _subtitleTracksOverlay?.remove();
    _controlBarSettingsOverlay?.remove();
    _danmakuSettingsOverlay?.remove();
    _audioTracksOverlay?.remove();
    for (var entry in _overlayEntries) {
      entry.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final backgroundColor = isDarkMode 
            ? const Color.fromARGB(255, 130, 130, 130).withOpacity(0.5)
            : const Color.fromARGB(255, 193, 193, 193).withOpacity(0.5);
        final borderColor = Colors.white.withOpacity(0.5);

        return Material(
          type: MaterialType.transparency,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                // 添加一个全屏的透明点击区域
                Positioned.fill(
                  child: GestureDetector(
                    onTap: widget.onClose,
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                Positioned(
                  right: 20,
                  top: globals.isPhone ? 10 : 80,
                  child: Container(
                    width: 200,
                    constraints: BoxConstraints(
                      maxHeight: globals.isPhone 
                          ? MediaQuery.of(context).size.height - 120 
                          : MediaQuery.of(context).size.height - 200,
                    ),
                    child: MouseRegion(
                      onEnter: (_) => videoState.setControlsHovered(true),
                      onExit: (_) => videoState.setControlsHovered(false),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
                          child: Container(
                            decoration: BoxDecoration(
                              color: backgroundColor,
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: borderColor,
                                width: 0.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                  spreadRadius: 0,
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // 标题栏
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: borderColor,
                                        width: 0.5,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Text(
                                        '设置',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                ),
                                // 设置选项列表
                                Expanded(
                                  child: SingleChildScrollView(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: _settingsItems.map((item) => _buildSettingsItem(item)).toList(),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSettingsItem(SettingsItem item) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(
                item.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 设置项数据类
class SettingsItem {
  final IconData icon;
  final String title;
  final void Function() onTap;
  final bool Function() isActive;

  const SettingsItem({
    required this.icon,
    required this.title,
    required this.onTap,
    required this.isActive,
  });
} 
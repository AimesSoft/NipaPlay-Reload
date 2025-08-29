import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'subtitle_tracks_menu.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'control_bar_settings_menu.dart';
import 'danmaku_settings_menu.dart';
import 'audio_tracks_menu.dart';
import 'danmaku_list_menu.dart';
import 'danmaku_tracks_menu.dart';
import 'subtitle_list_menu.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'playlist_menu.dart';
import 'playback_rate_menu.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'danmaku_offset_menu.dart';
import 'jellyfin_quality_menu.dart';
import 'playback_info_menu.dart';

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
  bool _showDanmakuList = false;
  bool _showDanmakuTracks = false;
  bool _showSubtitleList = false;
  bool _showPlaylist = false;
  bool _showPlaybackRate = false;
  bool _showDanmakuOffset = false;
  bool _showJellyfinQuality = false;
  bool _showPlaybackInfo = false;

  OverlayEntry? _subtitleTracksOverlay;
  OverlayEntry? _controlBarSettingsOverlay;
  OverlayEntry? _danmakuSettingsOverlay;
  OverlayEntry? _audioTracksOverlay;
  OverlayEntry? _danmakuListOverlay;
  OverlayEntry? _danmakuTracksOverlay;
  OverlayEntry? _subtitleListOverlay;
  OverlayEntry? _playlistOverlay;
  OverlayEntry? _playbackRateOverlay;
  OverlayEntry? _danmakuOffsetOverlay;
  OverlayEntry? _jellyfinQualityOverlay;
  OverlayEntry? _playbackInfoOverlay;

  late final List<SettingsItem> _settingsItems;
  late final VideoPlayerState videoState;
  late final PlayerKernelType _currentKernelType;

  @override
  void initState() {
    super.initState();
    videoState = Provider.of<VideoPlayerState>(context, listen: false);
    // 获取当前播放器内核类型
    _currentKernelType = PlayerFactory.getKernelType();
    
    // 根据当前播放器内核类型决定显示哪些菜单项
    _settingsItems = [];
    
    // 字幕轨道 - 当内核为MDK时显示
    if (_currentKernelType != PlayerKernelType.videoPlayer) {
      _settingsItems.add(SettingsItem(
        icon: Icons.subtitles,
        title: '字幕轨道',
        onTap: _toggleSubtitleTracksMenu,
        isActive: () => _showSubtitleTracks,
      ));
    }
    
    // 字幕列表 - 当内核为MDK时显示
    if (_currentKernelType != PlayerKernelType.videoPlayer) {
      _settingsItems.add(SettingsItem(
        icon: Icons.list,
        title: '字幕列表',
        onTap: _toggleSubtitleListMenu,
        isActive: () => _showSubtitleList,
      ));
    }
    
    // 音频轨道 - 当内核为MDK时显示
    if (_currentKernelType != PlayerKernelType.videoPlayer) {
      _settingsItems.add(SettingsItem(
        icon: Icons.audiotrack,
        title: '音频轨道',
        onTap: _toggleAudioTracksMenu,
        isActive: () => _showAudioTracks,
      ));
    }
    
    // 以下菜单项无论什么内核都显示
    _settingsItems.add(SettingsItem(
      icon: Icons.text_fields,
      title: '弹幕设置',
      onTap: _toggleDanmakuSettingsMenu,
      isActive: () => _showDanmakuSettings,
    ));
    
    _settingsItems.add(SettingsItem(
      icon: Icons.track_changes,
      title: '弹幕轨道',
      onTap: _toggleDanmakuTracksMenu,
      isActive: () => _showDanmakuTracks,
    ));
    
    _settingsItems.add(SettingsItem(
      icon: Icons.list_alt_outlined,
      title: '弹幕列表',
      onTap: _toggleDanmakuListMenu,
      isActive: () => _showDanmakuList,
    ));
    
    _settingsItems.add(SettingsItem(
      icon: Icons.schedule,
      title: '弹幕偏移',
      onTap: _toggleDanmakuOffsetMenu,
      isActive: () => _showDanmakuOffset,
    ));
    
    _settingsItems.add(SettingsItem(
      icon: Icons.height,
      title: '控制栏设置',
      onTap: _toggleControlBarSettingsMenu,
      isActive: () => _showControlBarSettings,
    ));
    
    // 添加倍速设置菜单项
    _settingsItems.add(SettingsItem(
      icon: Icons.speed,
      title: '倍速设置',
      onTap: _togglePlaybackRateMenu,
      isActive: () => _showPlaybackRate,
    ));
    
    // 添加 Jellyfin/Emby 转码清晰度设置（播放 Jellyfin 或 Emby 内容时显示，同复用 JellyfinQualityMenu UI）
    if (videoState.currentVideoPath?.startsWith('jellyfin://') == true ||
      videoState.currentVideoPath?.startsWith('emby://') == true) {
      _settingsItems.add(SettingsItem(
        icon: Icons.hd,
        title: '清晰度',
        onTap: _toggleJellyfinQualityMenu,
        isActive: () => _showJellyfinQuality,
      ));
    }
    
    // 播放信息 - 当有视频播放时显示
    if (videoState.currentVideoPath != null) {
      _settingsItems.add(SettingsItem(
        icon: Icons.info_outline,
        title: '播放信息',
        onTap: _togglePlaybackInfoMenu,
        isActive: () => _showPlaybackInfo,
      ));
    }
    
    // 剧集列表 - 当有视频文件时显示（整合了API、数据库、文件系统三种模式）
    if (videoState.currentVideoPath != null || videoState.animeId != null) {
      _settingsItems.add(SettingsItem(
        icon: Icons.playlist_play,
        title: '播放列表',
        onTap: _togglePlaylistMenu,
        isActive: () => _showPlaylist,
      ));
    }
  }

  void _toggleSubtitleTracksMenu() {
    if (_showSubtitleTracks) {
      _subtitleTracksOverlay?.remove();
      _subtitleTracksOverlay = null;
      if (mounted) {
        setState(() => _showSubtitleTracks = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showSubtitleTracks = true;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }
      
      _subtitleTracksOverlay = OverlayEntry(
        builder: (context) => SubtitleTracksMenu(
          onClose: () {
            _subtitleTracksOverlay?.remove();
            _subtitleTracksOverlay = null;
            if (mounted) {
              setState(() => _showSubtitleTracks = false);
            }
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
      if (mounted) {
        setState(() => _showAudioTracks = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showAudioTracks = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }
      
      _audioTracksOverlay = OverlayEntry(
        builder: (context) => AudioTracksMenu(
          onClose: () {
            _audioTracksOverlay?.remove();
            _audioTracksOverlay = null;
            if (mounted) {
              setState(() => _showAudioTracks = false);
            }
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
      if (mounted) {
        setState(() => _showControlBarSettings = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showControlBarSettings = true;
          _showSubtitleTracks = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }

      _controlBarSettingsOverlay = OverlayEntry(
        builder: (context) => ControlBarSettingsMenu(
          onClose: () {
            _controlBarSettingsOverlay?.remove();
            _controlBarSettingsOverlay = null;
            if (mounted) {
              setState(() => _showControlBarSettings = false);
            }
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
      if (mounted) {
        setState(() => _showDanmakuSettings = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showDanmakuSettings = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }

      _danmakuSettingsOverlay = OverlayEntry(
        builder: (context) => DanmakuSettingsMenu(
          onClose: () {
            _danmakuSettingsOverlay?.remove();
            _danmakuSettingsOverlay = null;
            if (mounted) {
              setState(() => _showDanmakuSettings = false);
            }
          },
          videoState: videoState,
        ),
      );

      Overlay.of(context).insert(_danmakuSettingsOverlay!);
    }
  }

  void _toggleDanmakuListMenu() {
    if (_showDanmakuList) {
      _danmakuListOverlay?.remove();
      _danmakuListOverlay = null;
      if (mounted) {
        setState(() => _showDanmakuList = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showDanmakuList = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }

      _danmakuListOverlay = OverlayEntry(
        builder: (context) => DanmakuListMenu(
          videoState: videoState,
          onClose: () {
            _danmakuListOverlay?.remove();
            _danmakuListOverlay = null;
            if (mounted) {
              setState(() => _showDanmakuList = false);
            }
          },
        ),
      );

      Overlay.of(context).insert(_danmakuListOverlay!);
    }
  }

  void _toggleDanmakuTracksMenu() {
    if (_showDanmakuTracks) {
      _danmakuTracksOverlay?.remove();
      _danmakuTracksOverlay = null;
      if (mounted) {
        setState(() => _showDanmakuTracks = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showDanmakuTracks = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }

      _danmakuTracksOverlay = OverlayEntry(
        builder: (context) => DanmakuTracksMenu(
          onClose: () {
            _danmakuTracksOverlay?.remove();
            _danmakuTracksOverlay = null;
            if (mounted) {
              setState(() => _showDanmakuTracks = false);
            }
          },
        ),
      );

      Overlay.of(context).insert(_danmakuTracksOverlay!);
    }
  }

  void _toggleSubtitleListMenu() {
    if (_showSubtitleList) {
      _subtitleListOverlay?.remove();
      _subtitleListOverlay = null;
      if (mounted) {
        setState(() => _showSubtitleList = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showSubtitleList = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
        });
      }

      _subtitleListOverlay = OverlayEntry(
        builder: (context) => SubtitleListMenu(
          onClose: () {
            _subtitleListOverlay?.remove();
            _subtitleListOverlay = null;
            if (mounted) {
              setState(() => _showSubtitleList = false);
            }
          },
        ),
      );

      Overlay.of(context).insert(_subtitleListOverlay!);
    }
  }

  void _togglePlaylistMenu() {
    if (_showPlaylist) {
      _playlistOverlay?.remove();
      _playlistOverlay = null;
      setState(() => _showPlaylist = false);
    } else {
      _closeAllOverlays();
      setState(() {
        _showPlaylist = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
        _showDanmakuList = false;
        _showDanmakuTracks = false;
        _showSubtitleList = false;
        _showDanmakuOffset = false;
      });

      _playlistOverlay = OverlayEntry(
        builder: (context) => PlaylistMenu(
          onClose: () {
            _playlistOverlay?.remove();
            _playlistOverlay = null;
            setState(() => _showPlaylist = false);
          },
        ),
      );

      Overlay.of(context).insert(_playlistOverlay!);
    }
  }

  void _closeAllOverlays() {
    _subtitleTracksOverlay?.remove();
    _subtitleTracksOverlay = null;
    _controlBarSettingsOverlay?.remove();
    _controlBarSettingsOverlay = null;
    _danmakuSettingsOverlay?.remove();
    _danmakuSettingsOverlay = null;
    _audioTracksOverlay?.remove();
    _audioTracksOverlay = null;
    _danmakuListOverlay?.remove();
    _danmakuListOverlay = null;
    _danmakuTracksOverlay?.remove();
    _danmakuTracksOverlay = null;
    _subtitleListOverlay?.remove();
    _subtitleListOverlay = null;
    _playlistOverlay?.remove();
    _playlistOverlay = null;
    _playbackRateOverlay?.remove();
    _playbackRateOverlay = null;
    _danmakuOffsetOverlay?.remove();
    _danmakuOffsetOverlay = null;
    _jellyfinQualityOverlay?.remove();
    _jellyfinQualityOverlay = null;
    _playbackInfoOverlay?.remove();
    _playbackInfoOverlay = null;
    
    // 只有在组件仍然挂载时才调用setState
    if (mounted) {
      setState(() {
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
        _showDanmakuList = false;
        _showDanmakuTracks = false;
        _showSubtitleList = false;
        _showPlaylist = false;
        _showDanmakuOffset = false;
        _showPlaybackRate = false;
        _showJellyfinQuality = false;
        _showPlaybackInfo = false;
      });
    } else {
      // 如果组件已经被销毁，直接更新值而不调用setState
      _showSubtitleTracks = false;
      _showControlBarSettings = false;
      _showDanmakuSettings = false;
      _showAudioTracks = false;
      _showDanmakuList = false;
      _showDanmakuTracks = false;
      _showSubtitleList = false;
      _showPlaylist = false;
      _showDanmakuOffset = false;
      _showPlaybackRate = false;
      _showJellyfinQuality = false;
      _showPlaybackInfo = false;
    }
  }

  @override
  void dispose() {
    // 直接移除所有Overlay入口，不再调用_closeAllOverlays避免setState问题
    _subtitleTracksOverlay?.remove();
    _controlBarSettingsOverlay?.remove();
    _danmakuSettingsOverlay?.remove();
    _audioTracksOverlay?.remove();
    _danmakuListOverlay?.remove();
    _danmakuTracksOverlay?.remove();
    _subtitleListOverlay?.remove();
    _playlistOverlay?.remove();
    _danmakuOffsetOverlay?.remove();
    
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
          child: SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      _closeAllOverlays();
                      widget.onClose();
                    },
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
                          filter: ImageFilter.blur(sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0, sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0),
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
                                  child: const Row(
                                    children: [
                                      Text(
                                        '设置',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Spacer(),
                                    ],
                                  ),
                                ),
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
    final bool isActive = item.isActive();
    
    return Material(
      color: isActive ? Colors.white.withOpacity(0.15) : Colors.transparent,
      child: InkWell(
        onTap: item.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          decoration: BoxDecoration(
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
                isActive ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 添加倍速设置菜单切换方法
  void _togglePlaybackRateMenu() {
    if (_showPlaybackRate) {
      _playbackRateOverlay?.remove();
      _playbackRateOverlay = null;
      setState(() => _showPlaybackRate = false);
    } else {
      _closeAllOverlays();
      setState(() {
        _showPlaybackRate = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
        _showDanmakuList = false;
        _showDanmakuTracks = false;
        _showSubtitleList = false;
        _showPlaylist = false;
        _showDanmakuOffset = false;
      });
      
      _playbackRateOverlay = OverlayEntry(
        builder: (context) => PlaybackRateMenu(
          onClose: () {
            _playbackRateOverlay?.remove();
            _playbackRateOverlay = null;
            setState(() => _showPlaybackRate = false);
          },
        ),
      );

      Overlay.of(context).insert(_playbackRateOverlay!);
    }
  }

  // 添加弹幕偏移菜单切换方法
  void _toggleDanmakuOffsetMenu() {
    if (_showDanmakuOffset) {
      _danmakuOffsetOverlay?.remove();
      _danmakuOffsetOverlay = null;
      setState(() => _showDanmakuOffset = false);
    } else {
      _closeAllOverlays();
      setState(() {
        _showDanmakuOffset = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
        _showDanmakuList = false;
        _showDanmakuTracks = false;
        _showSubtitleList = false;
        _showPlaylist = false;
        _showPlaybackRate = false;
      });
      
      _danmakuOffsetOverlay = OverlayEntry(
        builder: (context) => DanmakuOffsetMenu(
          onClose: () {
            _danmakuOffsetOverlay?.remove();
            _danmakuOffsetOverlay = null;
            setState(() => _showDanmakuOffset = false);
          },
        ),
      );

      Overlay.of(context).insert(_danmakuOffsetOverlay!);
    }
  }

  // 添加 Jellyfin 转码质量菜单切换方法
  void _toggleJellyfinQualityMenu() {
    if (_showJellyfinQuality) {
      _jellyfinQualityOverlay?.remove();
      _jellyfinQualityOverlay = null;
      if (mounted) {
        setState(() => _showJellyfinQuality = false);
      }
    } else {
      _closeAllOverlays();
      if (mounted) {
        setState(() {
          _showJellyfinQuality = true;
          _showSubtitleTracks = false;
          _showControlBarSettings = false;
          _showDanmakuSettings = false;
          _showAudioTracks = false;
          _showDanmakuList = false;
          _showDanmakuTracks = false;
          _showSubtitleList = false;
          _showPlaylist = false;
          _showDanmakuOffset = false;
          _showPlaybackRate = false;
        });
      }
      
      _jellyfinQualityOverlay = OverlayEntry(
        builder: (context) => JellyfinQualityMenu(
          onClose: () {
            _jellyfinQualityOverlay?.remove();
            _jellyfinQualityOverlay = null;
            if (mounted) {
              setState(() => _showJellyfinQuality = false);
            }
          },
        ),
      );

      Overlay.of(context).insert(_jellyfinQualityOverlay!);
    }
  }

  // 添加播放信息菜单切换方法
  void _togglePlaybackInfoMenu() {
    if (_showPlaybackInfo) {
      _playbackInfoOverlay?.remove();
      _playbackInfoOverlay = null;
      setState(() => _showPlaybackInfo = false);
    } else {
      _closeAllOverlays();
      setState(() {
        _showPlaybackInfo = true;
        _showSubtitleTracks = false;
        _showControlBarSettings = false;
        _showDanmakuSettings = false;
        _showAudioTracks = false;
        _showDanmakuList = false;
        _showDanmakuTracks = false;
        _showSubtitleList = false;
        _showPlaylist = false;
        _showDanmakuOffset = false;
        _showPlaybackRate = false;
        _showJellyfinQuality = false;
      });
      
      _playbackInfoOverlay = OverlayEntry(
        builder: (context) => PlaybackInfoMenu(
          onClose: () {
            _playbackInfoOverlay?.remove();
            _playbackInfoOverlay = null;
            if (mounted) {
              setState(() => _showPlaybackInfo = false);
            }
          },
        ),
      );

      Overlay.of(context).insert(_playbackInfoOverlay!);
    }
  }
}

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
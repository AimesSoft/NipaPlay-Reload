import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'video_player_state.dart';
import 'package:flutter/services.dart';

class FullscreenHandler {
  // 处理全屏切换
  static KeyEventResult handleFullscreenKey(RawKeyEvent event, BuildContext context) {
    if (event is! RawKeyDownEvent) {
      return KeyEventResult.ignored;
    }

    // 对于ESC键特殊处理
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      // 只有在全屏状态下才处理Esc键
      if (videoState.isFullscreen) {
        videoState.toggleFullscreen();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }
} 
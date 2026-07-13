// ignore_for_file: sized_box_for_whitespace, prefer_typing_uninitialized_variables

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_ui.dart';

class VideoPlayerWidget extends StatelessWidget {
  final Widget? emptyPlaceholder;
  final double danmakuScale;

  const VideoPlayerWidget({
    super.key,
    this.emptyPlaceholder,
    this.danmakuScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    return VideoPlayerUI(
      emptyPlaceholder: emptyPlaceholder,
      danmakuScale: danmakuScale,
    );
  }
}

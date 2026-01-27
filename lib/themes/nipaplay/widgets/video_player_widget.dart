// ignore_for_file: sized_box_for_whitespace, prefer_typing_uninitialized_variables

import 'package:flutter/material.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_player_ui.dart';

class VideoPlayerWidget extends StatelessWidget {
  final Widget? emptyPlaceholder;

  const VideoPlayerWidget({
    super.key,
    this.emptyPlaceholder,
  });

  @override
  Widget build(BuildContext context) {
    return VideoPlayerUI(emptyPlaceholder: emptyPlaceholder);
  }
} 

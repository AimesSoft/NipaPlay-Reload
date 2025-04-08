import 'dart:io'; 
import 'package:fnipaplay/danmaku/lib/canvas_danmaku.dart';
// ignore: depend_on_referenced_packages
import 'package:fnipaplay/videos.dart';
import 'fnipaplayLink.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:fvp/mdk.dart';
double _iconOpacity7 = 0.5;
double getFontSize() {
  if (Platform.isIOS || Platform.isAndroid) {
    return 15.0; // 如果是iOS或Android设备
  } else {
    return 30.0; // 其他平台，例如Web、桌面
  }
}
void _handleMouseHover7(bool isHovering) {
  _iconOpacity7 = isHovering ? 1.0 : 0.5;
}
class DanmakuControl extends StatelessWidget {
  final Player controller;
  // ignore: non_constant_identifier_names
  final double IconOpacity6;
  final Function(DanmakuController) onControllerCreated;

  const DanmakuControl({
    super.key,
    required this.controller,
    // ignore: non_constant_identifier_names
    required this.IconOpacity6,
    required this.onControllerCreated,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        DanmakuScreen(
          createdController: (DanmakuController e) {
            onControllerCreated(e);
          },
          option: DanmakuOption(
            fontSize: getFontSize(),
          ),
        ),
        Positioned(
          top: 45,
          left: 0,
          child: MouseRegion(
            onEnter: (_) {
              conop = true;
            },
            onExit: (_) {
              conop = false;
            },
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: IconOpacity6,
              child: BlurTextContainer(
                animeTitle: anime.animeTitle ?? '',
                episodeTitle: anime.episodeTitle ?? '',
                iconOpacity: _iconOpacity7,
                onHover: _handleMouseHover7,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

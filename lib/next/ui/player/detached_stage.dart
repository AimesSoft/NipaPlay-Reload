import 'dart:async';

import 'package:flutter/material.dart';

import '../../player/ports/session_playback.dart';
import 'timeline.dart';
import 'video_stage.dart';

/// Same playback and scene, in a second FlutterView. The OS frame supplies
/// dragging/close; no Classic page or VideoPlayerState is mounted here.
class NextDetachedPlayer extends StatelessWidget {
  const NextDetachedPlayer({super.key, required this.playback});
  final SessionPlayback playback;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(),
        home: Material(
            color: Colors.black,
            child: Stack(fit: StackFit.expand, children: [
              NextVideoStage(key: playback.windows.stageKey, host: playback),
              ListenableBuilder(
                  listenable: playback.frame,
                  builder: (context, _) => playback.showControls
                      ? Align(
                          alignment: Alignment.bottomCenter,
                          child: ColoredBox(
                              color: const Color(0xB3000000),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PlayerTimeline(
                                        duration: playback.duration,
                                        live: () => playback.position,
                                        repaint: playback.frame,
                                        onSeek: playback.seek),
                                    Row(children: [
                                      IconButton(
                                          tooltip: '播放 / 暂停',
                                          icon: Icon(playback.playIntent
                                              ? Icons.pause
                                              : Icons.play_arrow),
                                          onPressed: playback.togglePlay),
                                      IconButton(
                                          tooltip: '逐帧后退',
                                          icon: const Icon(Icons.skip_previous),
                                          onPressed: () => unawaited(
                                              playback.inspection.inspect(
                                                  'playback.navigate',
                                                  {'frameDelta': -1}))),
                                      IconButton(
                                          tooltip: '逐帧前进',
                                          icon: const Icon(Icons.skip_next),
                                          onPressed: () => unawaited(
                                              playback.inspection.inspect(
                                                  'playback.navigate',
                                                  {'frameDelta': 1}))),
                                      const Spacer(),
                                      IconButton(
                                          tooltip: '画中画',
                                          icon: const Icon(
                                              Icons.picture_in_picture),
                                          onPressed: () => unawaited(playback
                                              .pictureInPicture(context))),
                                      IconButton(
                                          tooltip: '返回主窗口',
                                          icon: const Icon(
                                              Icons.close_fullscreen),
                                          onPressed: () => unawaited(
                                              playback.windows.returnToMain())),
                                    ]),
                                  ])),
                        )
                      : const SizedBox.shrink()),
            ])),
      );
}

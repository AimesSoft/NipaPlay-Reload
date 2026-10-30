import 'dart:async';

import 'package:flutter/material.dart';

import '../../player/ports/session_playback.dart';
import '../widgets/buttons.dart';
import '../widgets/icons.dart';
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
                          // The main player's scrim and quiet round buttons.
                          child: DecoratedBox(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x00000000), Color(0xCC000000)],
                              ),
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 40, 16, 12),
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    PlayerTimeline(
                                        duration: playback.duration,
                                        live: () => playback.position,
                                        repaint: playback.frame,
                                        onSeek: playback.seek),
                                    const SizedBox(height: 6),
                                    Row(children: [
                                      NextIconButton(
                                          glyph: playback.playIntent
                                              ? NextGlyph.pause
                                              : NextGlyph.play,
                                          label:
                                              playback.playIntent ? '暂停' : '播放',
                                          size: 36,
                                          onTap: playback.togglePlay),
                                      NextIconButton(
                                          glyph: NextGlyph.frameBack,
                                          label: '逐帧后退',
                                          size: 36,
                                          onTap: () => unawaited(
                                              playback.inspection.inspect(
                                                  'playback.navigate',
                                                  {'frameDelta': -1}))),
                                      NextIconButton(
                                          glyph: NextGlyph.frameForward,
                                          label: '逐帧前进',
                                          size: 36,
                                          onTap: () => unawaited(
                                              playback.inspection.inspect(
                                                  'playback.navigate',
                                                  {'frameDelta': 1}))),
                                      const Spacer(),
                                      NextIconButton(
                                          glyph: NextGlyph.pictureInPicture,
                                          label: '画中画',
                                          size: 36,
                                          onTap: () => unawaited(playback
                                              .pictureInPicture(context))),
                                      NextIconButton(
                                          glyph: NextGlyph.exitFullscreen,
                                          label: '回到主窗口',
                                          size: 36,
                                          onTap: () => unawaited(
                                              playback.windows.returnToMain())),
                                    ]),
                                  ]),
                            ),
                          ),
                        )
                      : const SizedBox.shrink()),
            ])),
      );
}

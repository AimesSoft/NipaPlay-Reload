import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:kmbal_ionicons/kmbal_ionicons.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:provider/provider.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';

class IndicatorWidget extends StatelessWidget {
  final bool Function(VideoPlayerState) isVisible;
  final double Function(VideoPlayerState) getValue;
  final IconData Function(VideoPlayerState) getIcon;

  const IndicatorWidget({
    super.key,
    required this.isVisible,
    required this.getValue,
    required this.getIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<VideoPlayerState>(
      builder: (context, videoState, child) {
        return IgnorePointer(
          child: AnimatedOpacity(
            opacity: isVisible(videoState) ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12.0),
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
                  sigmaY: context.watch<AppearanceSettingsProvider>().enableWidgetBlurEffect ? 25 : 0,
                ),
                child: Container(
                  width: 55,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.6), width: 0.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Icon(
                        getIcon(videoState),
                        color: Colors.white.withOpacity(0.8),
                        size: 20,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: globals.isDesktopOrTablet 
                            ? MediaQuery.of(context).size.height * 0.3
                            : MediaQuery.of(context).size.height * 0.7,
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SizedBox(
                            height: 6,
                            child: LinearProgressIndicator(
                              value: getValue(videoState),
                              backgroundColor: Colors.white.withOpacity(0.25),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white.withOpacity(0.9)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.all(5),
                        child: Text(
                          "${(getValue(videoState) * 100).toInt()}%",
                          locale: const Locale("zh-Hans","zh"),
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none),
                        ),
                      )
                    ],
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
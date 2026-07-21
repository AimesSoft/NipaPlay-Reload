import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';

/// Ensures the player page exists in exactly one FlutterView at a time.
class DesktopPlayerPageSlot extends StatelessWidget {
  const DesktopPlayerPageSlot({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DesktopPlayerWindowService.instance;
    if (!DesktopPlayerWindowService.isFeatureEnabled) {
      return PlayVideoPage(key: service.playerPageKey);
    }

    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.isPlayerDetached) {
          return PlayVideoPage(key: service.playerPageKey);
        }
        return ColoredBox(
          color: Colors.black,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.open_in_new_rounded,
                      color: Colors.white70,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '播放器已移至独立窗口',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () =>
                              unawaited(service.focusDetachedPlayer()),
                          icon: const Icon(Icons.filter_center_focus_rounded),
                          label: const Text('定位独立窗口'),
                        ),
                        FilledButton.icon(
                          onPressed: () =>
                              unawaited(service.returnPlayerToMain()),
                          icon: const Icon(Icons.call_merge_rounded),
                          label: const Text('移回主窗口'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

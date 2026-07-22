import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/pages/play_video_page.dart';
import 'package:nipaplay/services/desktop_player_window_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/video_upload_ui.dart';

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
        return VideoUploadUI(
          detachedPlayer: true,
          onLocateDetachedPlayer: () =>
              unawaited(service.focusDetachedPlayer()),
          onReturnDetachedPlayer: () => unawaited(service.returnPlayerToMain()),
        );
      },
    );
  }
}

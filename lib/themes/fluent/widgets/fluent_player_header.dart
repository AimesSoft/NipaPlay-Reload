import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' as material;
import 'package:provider/provider.dart';
import 'package:nipaplay/services/system_share_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/widgets/airplay_route_picker.dart';
import 'package:nipaplay/utils/video_player_state.dart';

class FluentPlayerHeader extends StatelessWidget {
  const FluentPlayerHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final videoState = Provider.of<VideoPlayerState>(context);
    final theme = FluentTheme.of(context);

    Future<void> shareCurrent() async {
      if (!SystemShareService.isSupported) return;

      final currentVideoPath = videoState.currentVideoPath;
      final currentActualUrl = videoState.currentActualPlayUrl;

      String? filePath;
      String? url;
      if (currentVideoPath != null && currentVideoPath.isNotEmpty) {
        final uri = Uri.tryParse(currentVideoPath);
        final scheme = uri?.scheme.toLowerCase();
        if (scheme == 'http' || scheme == 'https') {
          url = currentVideoPath;
        } else if (scheme == 'jellyfin' || scheme == 'emby') {
          url = currentActualUrl;
        } else {
          filePath = currentVideoPath;
        }
      } else {
        url = currentActualUrl;
      }

      final titleParts = <String>[
        if ((videoState.animeTitle ?? '').trim().isNotEmpty)
          videoState.animeTitle!.trim(),
        if ((videoState.episodeTitle ?? '').trim().isNotEmpty)
          videoState.episodeTitle!.trim(),
      ];
      final subject = titleParts.isEmpty ? null : titleParts.join(' · ');

      if ((filePath == null || filePath.isEmpty) &&
          (url == null || url.isEmpty)) {
        await BlurDialog.show(
          context: context,
          title: '分享',
          content: '没有可分享的内容',
          actions: [
            Button(
              child: const Text('关闭'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
        return;
      }

      try {
        await SystemShareService.share(
          text: subject,
          url: url,
          filePath: filePath,
          subject: subject,
        );
      } catch (e) {
        if (!context.mounted) return;
        await BlurDialog.show(
          context: context,
          title: '分享失败',
          content: '$e',
          actions: [
            Button(
              child: const Text('关闭'),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        );
      }
    }

    Future<void> showAirPlayPicker() async {
      if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

      await BlurDialog.show(
        context: context,
        title: '投屏',
        contentWidget: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(height: 8),
            Text(
              '点击下方 AirPlay 图标选择设备',
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16),
            Center(child: AirPlayRoutePicker(size: 44)),
          ],
        ),
        actions: [
          Button(
            child: const Text('关闭'),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(FluentIcons.back, size: 20),
            onPressed: () async {
              try {
                // 先调用handleBackButton处理截图
                await videoState.handleBackButton();
                // 然后重置播放器状态
                await videoState.resetPlayer();
              } catch (e) {
                // 静默处理错误，保持与nipaplay主题一致的行为
              }
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (videoState.animeTitle != null &&
                    videoState.animeTitle!.isNotEmpty)
                  Text(
                    videoState.animeTitle!,
                    style: theme.typography.bodyStrong,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (videoState.episodeTitle != null &&
                    videoState.episodeTitle!.isNotEmpty)
                  Text(
                    videoState.episodeTitle!,
                    style: theme.typography.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
            IconButton(
              icon: const Icon(material.Icons.airplay_rounded, size: 20),
              onPressed: () async {
                videoState.resetHideControlsTimer();
                await showAirPlayPicker();
              },
            ),
          if (SystemShareService.isSupported &&
              (defaultTargetPlatform == TargetPlatform.iOS ||
                  defaultTargetPlatform == TargetPlatform.android))
            IconButton(
              icon: const Icon(material.Icons.share_rounded, size: 20),
              onPressed: () async {
                videoState.resetHideControlsTimer();
                await shareCurrent();
              },
            ),
        ],
      ),
    );
  }
}

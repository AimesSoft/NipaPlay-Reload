import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/playback_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:path/path.dart' as path;

class BigScreenPlaybackHelper {
  static Future<bool> playFromHistory(
    BuildContext context,
    WatchHistoryItem item,
  ) async {
    final isNetworkUrl = item.filePath.startsWith('http://') ||
        item.filePath.startsWith('https://');
    final isJellyfinProtocol = item.filePath.startsWith('jellyfin://');
    final isEmbyProtocol = item.filePath.startsWith('emby://');

    var playableItem = item;
    var fileExists = false;
    dynamic playbackSession;

    if (isNetworkUrl || isJellyfinProtocol || isEmbyProtocol) {
      fileExists = true;
      if (isJellyfinProtocol) {
        try {
          final jellyfinId = item.filePath.replaceFirst('jellyfin://', '');
          final jellyfinService = JellyfinService.instance;
          if (!jellyfinService.isConnected) {
            if (!context.mounted) {
              return false;
            }
            BlurSnackBar.show(context, '未连接到Jellyfin服务器');
            return false;
          }
          playbackSession = await jellyfinService.createPlaybackSession(
            itemId: jellyfinId,
            startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
          );
        } catch (e) {
          if (!context.mounted) {
            return false;
          }
          BlurSnackBar.show(context, '获取Jellyfin播放会话失败: $e');
          return false;
        }
      }

      if (isEmbyProtocol) {
        try {
          final embyPath = item.filePath.replaceFirst('emby://', '');
          final parts = embyPath.split('/');
          final embyId = parts.isNotEmpty ? parts.last : embyPath;
          final embyService = EmbyService.instance;
          if (!embyService.isConnected) {
            if (!context.mounted) {
              return false;
            }
            BlurSnackBar.show(context, '未连接到Emby服务器');
            return false;
          }
          playbackSession = await embyService.createPlaybackSession(
            itemId: embyId,
            startPositionMs: item.lastPosition > 0 ? item.lastPosition : null,
          );
        } catch (e) {
          if (!context.mounted) {
            return false;
          }
          BlurSnackBar.show(context, '获取Emby播放会话失败: $e');
          return false;
        }
      }
    } else if (kIsWeb) {
      fileExists = true;
    } else {
      final file = File(item.filePath);
      fileExists = file.existsSync();
      if (!fileExists && Platform.isIOS) {
        final alternatePath = item.filePath.startsWith('/private')
            ? item.filePath.replaceFirst('/private', '')
            : '/private${item.filePath}';
        final alternateFile = File(alternatePath);
        if (alternateFile.existsSync()) {
          playableItem = item.copyWith(filePath: alternatePath);
          fileExists = true;
        }
      }
    }

    if (!fileExists) {
      if (!context.mounted) {
        return false;
      }
      BlurSnackBar.show(context, '文件不存在或无法访问: ${path.basename(item.filePath)}');
      return false;
    }

    await PlaybackService().play(
      PlayableItem(
        videoPath: playableItem.filePath,
        title: playableItem.animeName,
        subtitle: playableItem.episodeTitle,
        animeId: playableItem.animeId,
        episodeId: playableItem.episodeId,
        historyItem: playableItem,
        playbackSession: playbackSession,
      ),
    );
    return true;
  }
}

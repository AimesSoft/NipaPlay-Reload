import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExternalPlayerConfig {
  final bool enabled;
  final String playerPath;

  const ExternalPlayerConfig({
    required this.enabled,
    required this.playerPath,
  });

  bool get isReady => enabled && playerPath.trim().isNotEmpty;
}

class ExternalPlayerService {
  static bool get isSupportedPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  static Future<ExternalPlayerConfig> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(SettingsKeys.useExternalPlayer) ?? false;
    final path = prefs.getString(SettingsKeys.externalPlayerPath) ?? '';
    return ExternalPlayerConfig(enabled: enabled, playerPath: path);
  }

  static String resolveMediaPath({
    required String videoPath,
    String? actualPlayUrl,
    PlaybackSession? playbackSession,
  }) {
    final sessionUrl = playbackSession?.streamUrl;
    if (sessionUrl != null && sessionUrl.trim().isNotEmpty) {
      return sessionUrl;
    }
    if (actualPlayUrl != null && actualPlayUrl.trim().isNotEmpty) {
      return actualPlayUrl;
    }
    return videoPath;
  }

  static Future<bool> tryHandlePlayback(
    BuildContext context,
    PlayableItem item,
  ) async {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    if (!settings.useExternalPlayer) {
      return false;
    }

    if (!isSupportedPlatform) {
      BlurSnackBar.show(context, '外部播放器仅支持桌面端');
      return true;
    }

    final playerPath = settings.externalPlayerPath.trim();
    if (playerPath.isEmpty) {
      BlurSnackBar.show(context, '请先选择外部播放器');
      return true;
    }

    final mediaPath = resolveMediaPath(
      videoPath: item.videoPath,
      actualPlayUrl: item.actualPlayUrl,
      playbackSession: item.playbackSession,
    );

    final launched = await launch(
      playerPath: playerPath,
      mediaPath: mediaPath,
    );

    BlurSnackBar.show(
      context,
      launched ? '已通过外部播放器打开' : '外部播放器启动失败',
    );

    return true;
  }

  static Future<bool> launch({
    required String playerPath,
    required String mediaPath,
  }) async {
    if (!isSupportedPlatform) {
      return false;
    }

    final resolvedPath = await _resolvePlayerPath(playerPath.trim());
    if (resolvedPath == null || resolvedPath.isEmpty) {
      return false;
    }

    final exists = await FileSystemEntity.type(resolvedPath) !=
        FileSystemEntityType.notFound;
    if (!exists) {
      debugPrint('外部播放器不存在: $resolvedPath');
      return false;
    }

    try {
      if (Platform.isWindows) {
        await Process.start(
          'cmd',
          ['/c', 'start', '', resolvedPath, mediaPath],
          runInShell: true,
        );
        return true;
      }

      if (Platform.isMacOS) {
        if (resolvedPath.toLowerCase().endsWith('.app')) {
          await Process.start('open', ['-a', resolvedPath, mediaPath]);
        } else {
          await Process.start(resolvedPath, [mediaPath]);
        }
        return true;
      }

      await Process.start(resolvedPath, [mediaPath]);
      return true;
    } catch (e) {
      debugPrint('外部播放器启动失败: $e');
      return false;
    }
  }

  static Future<String?> _resolvePlayerPath(String path) async {
    if (path.isEmpty) {
      return null;
    }
    if (Platform.isMacOS) {
      final resolved = await SecurityBookmarkService.resolveBookmark(path);
      return resolved ?? path;
    }
    return path;
  }
}

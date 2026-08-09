
// lib/services/external_player_service.dart
// 协调外部播放器启动, 参数注入和 mpv 弹幕控制台注册

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:nipaplay/constants/media_extensions.dart';
import 'package:nipaplay/models/danmaku/danmaku_item.dart';
import 'package:nipaplay/models/external_player_session/mpv_session.dart';
import 'package:nipaplay/models/external_player_session/other_session.dart';
import 'package:nipaplay/models/external_player_session/session.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/danmaku/danmaku_service.dart';
import 'package:nipaplay/services/external_player_console_service.dart';
import 'package:nipaplay/services/external_player_console_window_service.dart';
import 'package:nipaplay/services/security_bookmark_service.dart';
import 'package:nipaplay/utils/app_platform.dart';
import 'package:nipaplay/utils/color.dart';
import 'package:nipaplay/utils/external_player_utils.dart';


/// 协调桌面端外部播放器启动, 命令行参数注入和 mpv 控制台注册.
///
/// 本服务只负责发起播放请求, 无法保证外部播放器最终成功解码媒体.
abstract final class ExternalPlayerService {

  /// 使用当前外部播放器设置播放 [item].
  ///
  /// 不支持的平台, 无效配置和启动失败会写入调试日志并结束本次请求.
  static Future<void> play(SettingsProvider settings, PlayableItem item) async {

    final platform = AppPlatform.current;
    final playerPath = settings.externalPlayerPath.trim();

    _log(
      '${color('play 触发', ColorCode.boldGreen)}: '
      'danmakuOverlay=${settings.externalPlayerDanmakuOverlay}, '
      'platform=$platform, title=${item.title}, '
      'episodeId=${item.episodeId}, animeId=${item.animeId}',
    );

    if (!platform.supportsExternalPlayer) {
      _log('play: 当前平台不支持外部播放器');
      return;
    }
    if (playerPath.isEmpty) {
      _log('play: externalPlayerPath 为空');
      return;
    }

    final playerType = detectExternalPlayerType(playerPath);
    if (playerPath.toLowerCase().endsWith('.lnk')) {
      _log(
        'play: playerPath 是 .lnk 快捷方式；若启动参数未透传，'
        '请改为选择播放器的实际可执行文件',
      );
    }

    // 解析媒体路径, 可能是远程 URL 或本地文件路径
    String? mediaPath;
    try {
      mediaPath = await resolveExternalPlayerMediaPath(item);
      if (mediaPath == null || mediaPath.isEmpty) {
        _log('play: 无法将媒体路径解析为外部播放器可访问的地址');
      }
    } catch (error, stackTrace) {
      _log('play: 解析远程媒体路径失败: $error');
      debugPrintStack(stackTrace: stackTrace);
      mediaPath = null;
    }
    if (mediaPath == null) return;

    DanmakuItemSet? danmakuSet;
    if (!settings.externalPlayerDanmakuOverlay) {
      _log('danmaku: 弹幕外挂未启用');
    } else if (item.episodeId == null) {
      _log('danmaku: 缺少 episodeId，跳过弹幕获取');
    } else if (!_usesMpvSession(playerType)) {
      _log('danmaku: $playerType 暂不支持运行时弹幕刷新，跳过弹幕获取');
    } else {
      final stopwatch = Stopwatch()..start();
      try {
        danmakuSet = await DanmakuService.getDanmakuFromEpisodeId(
          item.episodeId!,
        );
        if (danmakuSet == null) {
          _log('danmaku: 获取失败');
        } else {
          _log('danmaku: 获取完成，共 ${danmakuSet.length} 条');
        }
      } catch (error, stackTrace) {
        _log('danmaku: 获取异常: $error');
        debugPrintStack(stackTrace: stackTrace);
      } finally {
        stopwatch.stop();
        _log('danmaku: 准备耗时=${stopwatch.elapsedMilliseconds}ms');
      }
    }

    final extraArgs = <String>[];
    if (danmakuSet?.isNotEmpty == true && playerType == ExternalPlayerType.mpv) {
      const smoothArgs = [
        '--blend-subtitles=video',
        '--vf-add=lavfi=[fps=fps=60:round=down]',
      ];
      extraArgs.addAll(smoothArgs);
      _log('launch: 注入弹幕平滑参数: $smoothArgs');
    }

    final userAgent = PlayerFactory.getCustomPlayerUA();
    if (userAgent.isNotEmpty) {
      final userAgentArg = switch (playerType) {
        ExternalPlayerType.mpv || ExternalPlayerType.mpvNet =>
          '--user-agent=$userAgent',
        ExternalPlayerType.vlc => '--http-user-agent=$userAgent',
        ExternalPlayerType.potPlayer || ExternalPlayerType.generic => null,
      };
      if (userAgentArg != null) {
        extraArgs.add(userAgentArg);
        _log('launch: 已注入自定义 User-Agent');
      }
    }

    String? resolvedPlayerPath;
    try {
      resolvedPlayerPath = platform == AppPlatform.macOS
          ? await SecurityBookmarkService.resolveBookmark(playerPath) ??
              playerPath
          : playerPath;
      final exists = await FileSystemEntity.type(resolvedPlayerPath) !=
          FileSystemEntityType.notFound;
      if (!exists) {
        _log('launch: 外部播放器不存在: $resolvedPlayerPath');
        return;
      }
    } catch (error, stackTrace) {
      _log('launch: 解析外部播放器路径失败: $error');
      debugPrintStack(stackTrace: stackTrace);
      return;
    }

    if (ExternalPlayerConsoleService.isSupportedPlatform &&
        ExternalPlayerConsoleService.hasActiveSession) {
      ExternalPlayerConsoleService.closePlayerAndConsole();
    }

    _log(
      'launch: playerPath="$resolvedPlayerPath", mediaPath="$mediaPath", '
      'playerType=$playerType, extraArgCount=${extraArgs.length}',
    );


    // 尝试启动外部播放器
    final history = item.historyItem;
    ExternalPlayerLaunchSession? session;
    try {
      if (_usesMpvSession(playerType)) {
        session = MpvSession(
          resolvedPlayerPath,
          mediaPath,
          extraArgs: extraArgs,
          duration: Duration(milliseconds: history?.duration ?? 0),
          position: Duration(milliseconds: history?.lastPosition ?? 0),
          isMpvNet: playerType == ExternalPlayerType.mpvNet,
        );
        await session.launch();
      } else {
        final config = switch (platform) {
          AppPlatform.windows => resolvedPlayerPath.toLowerCase().endsWith('.lnk')
              ? (
                  executable: 'cmd',
                  arguments: [
                    '/c',
                    'start',
                    '',
                    resolvedPlayerPath,
                    mediaPath,
                    ...extraArgs,
                  ],
                  mode: ProcessStartMode.normal,
                  runInShell: true,
                  monitorProcess: false,
                )
              : (
                  executable: resolvedPlayerPath,
                  arguments: [mediaPath, ...extraArgs],
                  mode: ProcessStartMode.detached,
                  runInShell: false,
                  monitorProcess: false,
                ),
          AppPlatform.macOS => resolvedPlayerPath.toLowerCase().endsWith('.app')
              ? (
                  executable: 'open',
                  arguments: [
                    '-a',
                    resolvedPlayerPath,
                    mediaPath,
                    if (extraArgs.isNotEmpty) '--args',
                    ...extraArgs,
                  ],
                  mode: ProcessStartMode.normal,
                  runInShell: false,
                  monitorProcess: false,
                )
              : (
                  executable: resolvedPlayerPath,
                  arguments: [mediaPath, ...extraArgs],
                  mode: ProcessStartMode.normal,
                  runInShell: false,
                  monitorProcess: false,
                ),
          AppPlatform.linux => (
              executable: resolvedPlayerPath,
              arguments: [mediaPath, ...extraArgs],
              mode: ProcessStartMode.detached,
              runInShell: false,
              monitorProcess: true,
            ),
          AppPlatform.web ||
          AppPlatform.android ||
          AppPlatform.iOS ||
          AppPlatform.unknown => throw StateError('不支持的平台: $platform'),
        };
        final process = await Process.start(
          config.executable,
          config.arguments,
          mode: config.mode,
          runInShell: config.runInShell,
        );

        session = OtherSession.attach(
          type: playerType,
          playerPath: resolvedPlayerPath,
          mediaPath: mediaPath,
          processId: process.pid,
          duration: Duration(milliseconds: history?.duration ?? 0),
          position: Duration(milliseconds: history?.lastPosition ?? 0),
          monitorProcess: config.monitorProcess,
        );
      }
    } catch (error, stackTrace) {
      _log('launch: 启动异常: $error');
      debugPrintStack(stackTrace: stackTrace);
    }

    _log('launch: 启动成功=${session != null}');
    if (session is! MpvSession) return;

    ExternalPlayerConsoleService.setState(
      ConsoleState(
        session: session,
        shrinkMainWindow: settings.externalPlayerShrinkWindow,
        episodeMetaData: EpisodeMetaData(
          animeTitle: history?.animeName ?? item.title,
          episodeTitle: history?.episodeTitle ?? item.subtitle,
          episodeId: item.episodeId,
        ),
        danmakuList: danmakuSet?.toList(growable: false),
      ),
    );

    if (settings.externalPlayerConsoleWindowMode) {
      await ExternalPlayerConsoleWindowService.instance.showControlsWindow();
    }
    ExternalPlayerConsoleService.queueDanmakuRefresh();
  }

  static bool _usesMpvSession(ExternalPlayerType playerType) =>
      playerType == ExternalPlayerType.mpv ||
      playerType == ExternalPlayerType.mpvNet;

  static void _log(String message) {
    final label = color('[ExtPlayer]', ColorCode.blue);
    debugPrint('$label $message');
  }
}

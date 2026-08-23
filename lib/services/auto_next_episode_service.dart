import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipaplay/models/playback_detail_context.dart';
import 'package:nipaplay/models/playable_item.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/bangumi_comment_prompt_controller.dart';
import 'package:nipaplay/themes/nipaplay/widgets/countdown_snackbar.dart';
import 'package:nipaplay/utils/media_identity_resolver.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/providers/settings_provider.dart';
import 'package:nipaplay/services/playback_service.dart';

class AutoNextEpisodeService {
  static AutoNextEpisodeService? _instance;
  static AutoNextEpisodeService get instance =>
      _instance ??= AutoNextEpisodeService._();
  static const int defaultCountdownSeconds = 3;
  static const int minCountdownSeconds = 0;
  static const int maxCountdownSeconds = 15;

  AutoNextEpisodeService._();

  Timer? _countdownTimer;
  int _countdownSeconds = defaultCountdownSeconds;
  int _countdownDurationSeconds = defaultCountdownSeconds;
  bool _isCountingDown = false;
  PlaybackDetailEpisode? _nextEpisode;
  bool _isCancelled = false;
  bool _autoPlayEnabled = true;
  // 标记上一轮是否显示过续播倒计时，用于抑制退出后的"全部看完"误报。
  bool _countdownWasActive = false;

  // 开始自动播放下一话的倒计时
  Future<void> startAutoNextEpisode(
    BuildContext context,
    String currentVideoPath,
  ) async {
    if (!_autoPlayEnabled) {
      debugPrint('[AutoNext] 自动连播已禁用，跳过startAutoNextEpisode调用');
      return;
    }
    debugPrint(
        '[AutoNext] startAutoNextEpisode called, _isCountingDown=$_isCountingDown, mounted=${(context is Element) ? (context).mounted : 'unknown'}');
    if (_isCountingDown) {
      debugPrint('[AutoNext] _isCountingDown为true，直接return，不触发自动连播');
      return;
    }

    debugPrint('[自动播放] 开始检查下一话: $currentVideoPath');

    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    final cursor = await _resolvePlaylistCursor(videoState);
    if (!context.mounted) return;
    late final PlaybackDetailEpisode nextEpisode;
    switch (cursor) {
      case PlaylistHasNext(:final episode):
        nextEpisode = episode;
      case PlaylistAtEnd():
        debugPrint('[自动播放] 当前播放列表已到最后一项，不显示倒计时');
        _showNoNextEpisodeMessage(context);
        return;
      case PlaylistCurrentNotFound():
        debugPrint('[自动播放] 刷新播放列表后仍无法定位当前项，取消本次续播');
        BlurSnackBar.show(context, '无法确认当前播放项，未执行自动续播');
        return;
      case PlaylistLoadFailed(:final error):
        debugPrint('[自动播放] 播放列表加载失败: $error');
        BlurSnackBar.show(context, '播放列表加载失败，未执行自动续播');
        return;
    }

    // 加载播放列表期间可能已经切换了视频，丢弃过期结果。
    if (videoState.currentVideoPath != currentVideoPath) {
      return;
    }

    _nextEpisode = nextEpisode;
    _countdownSeconds = _countdownDurationSeconds;
    _isCountingDown = true;

    debugPrint('[自动播放] 播放列表下一项: ${nextEpisode.videoPath}，开始倒计时');

    debugPrint(
        '[AutoNext] 调用_startCountdown, nextEpisode=${_nextEpisode?.videoPath}');
    // 显示初始倒计时消息
    _startCountdown(context);
  }

  Future<PlaylistCursorResult> _resolvePlaylistCursor(
    VideoPlayerState videoState,
  ) async {
    var result = await videoState.resolvePlaylistCursor();
    if (result is PlaylistCurrentNotFound) {
      debugPrint('[自动播放] 缓存列表未定位到当前项，强制刷新后重试');
      result = await videoState.resolvePlaylistCursor(forceRefresh: true);
    }
    return result;
  }

  // 取消自动播放
  void cancelAutoNext() {
    debugPrint(
        '[AutoNext] cancelAutoNext called, _isCountingDown=$_isCountingDown');
    final wasCountingDown = _isCountingDown;
    _isCancelled = true;
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
    _isCountingDown = false;
    _nextEpisode = null;

    // 隐藏倒计时通知
    CountdownSnackBar.hide();

    // 仅在倒计时未活跃时清除 _countdownWasActive 标记。
    // 用户退出播放器时 _isCountingDown=true，标记保留以抑制后续的
    // "已经全部看完了"误报；新视频手动载入时 _isCountingDown=false，
    // 标记清除以恢复干净状态。
    if (!wasCountingDown) {
      _countdownWasActive = false;
    }

    debugPrint('[自动播放] 已取消自动播放下一话');
  }

  void updateAutoPlayEnabled(bool enabled) {
    _autoPlayEnabled = enabled;
    if (!_autoPlayEnabled && _isCountingDown) {
      cancelAutoNext();
    }
  }

  bool get autoPlayEnabled => _autoPlayEnabled;
  int get countdownDurationSeconds => _countdownDurationSeconds;

  void updateCountdownDuration(int seconds) {
    final clampedSeconds =
        seconds.clamp(minCountdownSeconds, maxCountdownSeconds).toInt();
    if (_countdownDurationSeconds == clampedSeconds) {
      return;
    }
    _countdownDurationSeconds = clampedSeconds;
    debugPrint('[AutoNext] 倒计时时长更新为 ${_countdownDurationSeconds}s');
  }

  // 显示倒计时消息
  void _startCountdown(BuildContext context) {
    debugPrint(
        '[AutoNext] _startCountdown called, _countdownSeconds=$_countdownSeconds');
    _countdownSeconds = _countdownDurationSeconds;
    _isCancelled = false;
    // 倒计时正式开始，标记本轮已显示过续播提示。
    _countdownWasActive = true;

    if (_countdownSeconds <= 0) {
      debugPrint('[AutoNext] 倒计时设置为0秒，直接播放下一话');
      CountdownSnackBar.hide();
      _isCountingDown = false;
      _playNextEpisode(context);
      return;
    }

    // 显示初始倒计时
    CountdownSnackBar.show(
      context,
      '将在 $_countdownSeconds 秒后播放下一话',
      onCancel: () {
        debugPrint('[自动播放] 用户取消自动播放');
        _isCancelled = true;
        _countdownTimer?.cancel();
        _countdownTimer = null;
        _isCountingDown = false;
        _nextEpisode = null;
        debugPrint('[AutoNext] 倒计时被用户取消');
      },
    );

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      debugPrint(
          '[AutoNext] 倒计时tick, 剩余秒数: $_countdownSeconds, _isCancelled=$_isCancelled');
      if (_isCancelled) {
        timer.cancel();
        CountdownSnackBar.hide();
        debugPrint('[AutoNext] 倒计时tick检测到_isCancelled，提前结束');
        _isCountingDown = false;
        return;
      }

      _countdownSeconds--;

      if (_countdownSeconds <= 0) {
        timer.cancel();
        CountdownSnackBar.hide();
        _isCountingDown = false;

        if (!_isCancelled) {
          debugPrint('[AutoNext] 倒计时结束，重新检查播放列表下一项');
          _playNextEpisode(context);
        }
      } else {
        // 更新倒计时显示，而不是重新创建
        CountdownSnackBar.update('将在 $_countdownSeconds 秒后播放下一话');
      }
    });
  }

  // 显示没有下一话的消息
  void _showNoNextEpisodeMessage(BuildContext context) {
    // 如果上一轮显示过续播倒计时（说明存在下一话，用户只是手动退出），
    // 不弹出"已经全部看完了"以免误报。
    if (_countdownWasActive) {
      debugPrint('[AutoNext] 上一轮存在续播倒计时，跳过"全部看完"提示');
      _countdownWasActive = false;
      return;
    }
    final canComment = BangumiCommentPromptController.isAvailable;
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    BlurSnackBar.show(
      context,
      canComment ? '已经全部看完了，要留个评论吗？' : '播放完成，没有下一话了',
      actionText: canComment ? '打分和评论' : null,
      actionColor: canComment ? Theme.of(context).colorScheme.primary : null,
      duration: canComment ? const Duration(seconds: 8) : null,
      onAction: canComment
          ? () {
              unawaited(
                BangumiCommentPromptController.showForCurrentAnime(
                  context,
                  videoState,
                ),
              );
            }
          : null,
    );
  }

  // 播放下一话
  Future<void> _playNextEpisode(BuildContext context) async {
    debugPrint('[AutoNext] _playNextEpisode called');
    // 如果倒计时已被取消（退出播放器等场景），直接返回，不播放也不显示提示。
    if (_isCancelled) {
      debugPrint('[AutoNext] _playNextEpisode: 倒计时已取消，跳过');
      return;
    }
    final videoState = Provider.of<VideoPlayerState>(context, listen: false);
    // 倒计时期间播放列表可能变化，播放前必须以当前列表重新判定。
    final cursor = await _resolvePlaylistCursor(videoState);
    if (!context.mounted) return;
    late final PlaybackDetailEpisode nextEpisode;
    switch (cursor) {
      case PlaylistHasNext(:final episode):
        nextEpisode = episode;
      case PlaylistAtEnd():
        _nextEpisode = null;
        if (!_isCancelled && context.mounted) {
          _showNoNextEpisodeMessage(context);
        }
        return;
      case PlaylistCurrentNotFound():
        _nextEpisode = null;
        if (!_isCancelled && context.mounted) {
          BlurSnackBar.show(context, '无法确认当前播放项，已取消自动续播');
        }
        return;
      case PlaylistLoadFailed(:final error):
        _nextEpisode = null;
        debugPrint('[自动播放] 播放前检查列表失败: $error');
        if (!_isCancelled && context.mounted) {
          BlurSnackBar.show(context, '播放列表加载失败，已取消自动续播');
        }
        return;
    }
    _nextEpisode = nextEpisode;
    final settingsProvider =
        Provider.of<SettingsProvider>(context, listen: false);
    if (settingsProvider.useExternalPlayer) {
      await PlaybackService().tryPlayExternally(
        context,
        PlayableItem(
          videoPath: nextEpisode.videoPath,
          title: nextEpisode.title,
          subtitle: nextEpisode.subtitle,
          animeId: nextEpisode.animeId,
          episodeId: nextEpisode.episodeId,
          historyItem: nextEpisode.historyItem,
          actualPlayUrl: nextEpisode.actualPlayUrl,
          playbackSession: nextEpisode.playbackSession,
          mediaKey: MediaIdentityResolver.forPath(nextEpisode.videoPath),
        ),
      );
      _nextEpisode = null;
      return;
    }
    // 优先调用VideoPlayerState的playNextEpisode，兼容Jellyfin/Emby等特殊情况
    try {
      await videoState.playNextEpisode(verifiedPlaylistEpisode: nextEpisode);
      if (context.mounted) {
        BlurSnackBar.show(context, '正在播放：${nextEpisode.title}');
      }
    } catch (e) {
      debugPrint('[自动播放] 播放列表下一项失败: $e');
      if (context.mounted) {
        BlurSnackBar.show(context, '播放下一话失败：$e');
      }
    } finally {
      _nextEpisode = null;
    }
  }

  // 检查是否正在倒计时
  bool get isCountingDown => _isCountingDown;

  // 获取剩余倒计时秒数
  int get remainingSeconds => _countdownSeconds;

  // 获取下一话路径
  String? get nextEpisodePath => _nextEpisode?.videoPath;
}

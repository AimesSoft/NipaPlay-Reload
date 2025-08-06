import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/countdown_snackbar.dart';
import 'package:nipaplay/utils/video_player_state.dart';
import 'package:provider/provider.dart';

class AutoNextEpisodeService {
  static AutoNextEpisodeService? _instance;
  static AutoNextEpisodeService get instance => _instance ??= AutoNextEpisodeService._();
  
  AutoNextEpisodeService._();
  
  Timer? _countdownTimer;
  int _countdownSeconds = 10;
  bool _isCountingDown = false;
  String? _nextEpisodePath;
  BuildContext? _context;
  bool _isCancelled = false;
  
  // 设置上下文
  void setContext(BuildContext context) {
    _context = context;
  }
  
  // 开始自动播放下一话的倒计时
  void startAutoNextEpisode(BuildContext context, String currentVideoPath) {
    debugPrint('[AutoNext] startAutoNextEpisode called, _isCountingDown=$_isCountingDown, context=${context != null}, mounted=${(context is Element) ? (context).mounted : 'unknown'}');
    if (_isCountingDown) {
      debugPrint('[AutoNext] _isCountingDown为true，直接return，不触发自动连播');
      return;
    }
    
    debugPrint('[自动播放] 开始检查下一话: $currentVideoPath');
    
    // 查找下一话
    final nextEpisode = _findNextEpisode(currentVideoPath);
    
    // 只对本地文件进行检查，流媒体和网络URL跳过检查（保持原有行为）
    if (nextEpisode == null && _isLocalFile(currentVideoPath)) {
      debugPrint('[自动播放] 本地视频没有找到下一话，不显示倒计时');
      _showNoNextEpisodeMessage(context);
      return;
    }
    
    _nextEpisodePath = nextEpisode;
    _countdownSeconds = 10;
    _isCountingDown = true;
    
    debugPrint('[自动播放] 找到下一话: $nextEpisode，开始倒计时');
    
    debugPrint('[AutoNext] 调用_startCountdown, nextEpisode=$_nextEpisodePath');
    // 显示初始倒计时消息
    _startCountdown(context, nextEpisode ?? '');
  }
  
  // 取消自动播放
  void cancelAutoNext() {
    debugPrint('[AutoNext] cancelAutoNext called, _isCountingDown=$_isCountingDown');
    _isCancelled = true;
    if (_countdownTimer != null) {
      _countdownTimer!.cancel();
      _countdownTimer = null;
    }
    _isCountingDown = false;
    _nextEpisodePath = null;
    
    // 隐藏倒计时通知
    CountdownSnackBar.hide();
    
    debugPrint('[自动播放] 已取消自动播放下一话');
  }
  
  // 查找下一话
  String? _findNextEpisode(String currentVideoPath) {
    try {
      final currentFile = File(currentVideoPath);
      final directory = currentFile.parent;
      
      if (!directory.existsSync()) {
        return null;
      }
      
      // 获取目录中的所有视频文件
      final videoExtensions = ['.mp4', '.mkv', '.avi', '.mov', '.wmv', '.flv', '.webm', '.m4v', '.3gp', '.ts', '.m2ts'];
      final videoFiles = directory
          .listSync()
          .whereType<File>()
          .where((file) => videoExtensions.any((ext) => file.path.toLowerCase().endsWith(ext)))
          .toList();

      // 按文件名排序
      videoFiles.sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      
      // 找到当前文件的索引
      final currentIndex = videoFiles.indexWhere((file) => file.path == currentVideoPath);
      
      if (currentIndex == -1 || currentIndex >= videoFiles.length - 1) {
        // 当前文件不在列表中或已经是最后一个文件
        return null;
      }
      
      // 返回下一个文件的路径
      return videoFiles[currentIndex + 1].path;
      
    } catch (e) {
      debugPrint('[自动播放] 查找下一话失败: $e');
      return null;
    }
  }
  
  // 判断是否为本地文件
  bool _isLocalFile(String filePath) {
    // 不是HTTP URL 且不是流媒体协议的就是本地文件
    return !filePath.startsWith('http') && 
           !filePath.startsWith('jellyfin://') && 
           !filePath.startsWith('emby://');
  }
  
  // 显示倒计时消息
  void _startCountdown(BuildContext context, String nextEpisodePath) {
    debugPrint('[AutoNext] _startCountdown called, nextEpisodePath=$nextEpisodePath, _countdownSeconds=$_countdownSeconds');
    _countdownSeconds = 10;
    _isCancelled = false;
    
    // 显示初始倒计时
    CountdownSnackBar.show(
      context,
      '将在 $_countdownSeconds 秒后播放下一话',
      onCancel: () {
        print('[自动播放] 用户取消自动播放');
        _isCancelled = true;
        _countdownTimer?.cancel();
        debugPrint('[AutoNext] 倒计时被用户取消');
      },
    );
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      debugPrint('[AutoNext] 倒计时tick, 剩余秒数: $_countdownSeconds, _isCancelled=$_isCancelled');
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
        
        if (!_isCancelled) {
          debugPrint('[AutoNext] 倒计时结束，调用_playNextEpisode, nextEpisodePath=$nextEpisodePath');
          _playNextEpisode(context, nextEpisodePath);
        }
      } else {
        // 更新倒计时显示，而不是重新创建
        CountdownSnackBar.update('将在 $_countdownSeconds 秒后播放下一话');
      }
    });
  }
  
  // 显示没有下一话的消息
  void _showNoNextEpisodeMessage(BuildContext context) {
    BlurSnackBar.show(context, '播放完成，没有下一话了');
  }
  
  // 播放下一话
  void _playNextEpisode(BuildContext context, String nextEpisodePath) {
    debugPrint('[AutoNext] _playNextEpisode called, nextEpisodePath=$nextEpisodePath');
    // 优先调用VideoPlayerState的playNextEpisode，兼容Jellyfin/Emby等特殊情况
    try {
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.playNextEpisode();
      BlurSnackBar.show(context, '正在尝试播放下一话...');
      // 如果playNextEpisode能正确处理，直接return，不再走下面的本地文件逻辑
      return;
    } catch (e) {
      debugPrint('[自动播放] playNextEpisode()调用失败，回退到本地文件逻辑: $e');
      // 继续走原有本地文件查找逻辑
    }
    // ====== 原有本地文件播放逻辑保留 ======
    try {
      debugPrint('[自动播放] 开始播放下一话: $nextEpisodePath');
      final file = File(nextEpisodePath);
      if (!file.existsSync()) {
        throw Exception('下一话文件不存在: $nextEpisodePath');
      }
      final videoState = Provider.of<VideoPlayerState>(context, listen: false);
      videoState.initializePlayer(nextEpisodePath);
      
      final fileName = _getEpisodeDisplayName(nextEpisodePath);
      BlurSnackBar.show(context, '正在播放：$fileName');
      
    } catch (e) {
      debugPrint('[自动播放] 播放下一话失败: $e');
      BlurSnackBar.show(context, '播放下一话失败：$e');
    } finally {
      _nextEpisodePath = null;
    }
  }
  
  // 获取剧集显示名称
  String _getEpisodeDisplayName(String filePath) {
    final fileName = filePath.split('/').last;
    // 移除文件扩展名
    final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return nameWithoutExt;
  }
  
  // 检查是否正在倒计时
  bool get isCountingDown => _isCountingDown;
  
  // 获取剩余倒计时秒数
  int get remainingSeconds => _countdownSeconds;
  
  // 获取下一话路径
  String? get nextEpisodePath => _nextEpisodePath;
}
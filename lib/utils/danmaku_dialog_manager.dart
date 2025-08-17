import 'dart:io';
import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:nipaplay/widgets/nipaplay_theme/send_danmaku_dialog.dart';
import 'hotkey_service.dart';

/// 弹幕对话框管理器，用于防止多个弹幕对话框堆叠
class DanmakuDialogManager {
  static final DanmakuDialogManager _instance = DanmakuDialogManager._internal();
  
  // 单例模式
  factory DanmakuDialogManager() {
    return _instance;
  }
  
  DanmakuDialogManager._internal();
  
  // 是否正在显示弹幕对话框
  bool _isShowingDialog = false;
  
  // 热键服务
  final HotkeyService _hotkeyService = HotkeyService();
  
  // 当前对话框的上下文
  BuildContext? _currentContext;
  
  // 显示弹幕对话框
  Future<void> showSendDanmakuDialog({
    required BuildContext context,
    required int episodeId,
    required double currentTime,
    required Function(Map<String, dynamic> danmaku) onDanmakuSent,
    required Function() onDialogClosed,
    required bool wasPlaying,
  }) async {
    // 如果已经在显示弹幕对话框，则不再显示
    if (_isShowingDialog) {
      debugPrint('[DanmakuDialogManager] 已经在显示弹幕对话框，不再显示');
      return;
    }
    
    _isShowingDialog = true;
    _currentContext = context;
    
    try {
      // 检查是否为手机设备
      final window = WidgetsBinding.instance.window;
      final size = window.physicalSize / window.devicePixelRatio;
      final shortestSide = size.width < size.height ? size.width : size.height;
      final bool isRealPhone = Platform.isIOS || Platform.isAndroid && shortestSide < 600;
      
      await BlurDialog.show(
        context: context,
        title: isRealPhone ? '' : '发送弹幕', // 手机设备不显示标题
        contentWidget: SendDanmakuDialogContent(
          episodeId: episodeId,
          currentTime: currentTime,
          onDanmakuSent: onDanmakuSent,
        ),
        actions: [],
      ).then((_) {
        _isShowingDialog = false;
        _currentContext = null;
        onDialogClosed();
      });
    } catch (e) {
      debugPrint('[DanmakuDialogManager] 显示弹幕对话框出错: $e');
      _isShowingDialog = false;
      _currentContext = null;
    }
  }
  
  // 关闭当前弹幕对话框
  void closeCurrentDialog() {
    if (_isShowingDialog && _currentContext != null) {
      Navigator.of(_currentContext!).pop();
      _isShowingDialog = false;
      _currentContext = null;
    }
  }
  
  // 注册发送弹幕快捷键处理
  bool handleSendDanmakuHotkey() {
    debugPrint('[DanmakuDialogManager] 处理发送弹幕快捷键，当前对话框状态: ${_isShowingDialog ? "显示中" : "未显示"}');
    
    if (_isShowingDialog) {
      // 如果已经在显示弹幕对话框，则关闭它
      debugPrint('[DanmakuDialogManager] 关闭当前弹幕对话框');
      closeCurrentDialog();
      return true; // 返回true表示已处理
    }
    
    // 返回false表示未处理，需要显示新对话框
    return false;
  }
} 
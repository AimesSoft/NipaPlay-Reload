import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_service.dart';

/// 账号页面的业务逻辑控制器
/// 包含所有共享的功能和状态管理
mixin AccountPageController<T extends StatefulWidget> on State<T> {
  // 控制器
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  
  // 状态变量
  bool isLoggedIn = false;
  String username = '';
  bool isLoading = false;
  String? avatarUrl;

  @override
  void initState() {
    super.initState();
    loadLoginStatus();
  }

  @override
  void dispose() {
    usernameController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  /// 加载登录状态
  Future<void> loadLoginStatus() async {
    if (mounted) {
      setState(() {
        isLoggedIn = DandanplayService.isLoggedIn;
        username = DandanplayService.userName ?? '';
        updateAvatarUrl();
      });
    }
  }

  /// 更新头像URL
  void updateAvatarUrl() {
    if (username.contains('@qq.com')) {
      final qqNumber = username.split('@')[0];
      avatarUrl = 'http://q.qlogo.cn/headimg_dl?dst_uin=$qqNumber&spec=640';
    } else {
      avatarUrl = null;
    }
  }

  /// 执行登录
  Future<void> performLogin() async {
    if (usernameController.text.isEmpty || passwordController.text.isEmpty) {
      showMessage('请输入用户名和密码');
      return;
    }

    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final result = await DandanplayService.login(
        usernameController.text,
        passwordController.text,
      );

      if (result['success'] == true) {
        await loadLoginStatus();
        usernameController.clear();
        passwordController.clear();
        if (mounted) {
          showMessage(result['message'] ?? '登录成功');
        }
      } else {
        if (mounted) {
          showMessage(result['message'] ?? '登录失败');
        }
      }
    } catch (e) {
      if (mounted) {
        showMessage('登录失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  /// 执行退出登录
  Future<void> performLogout() async {
    await DandanplayService.clearLoginInfo();
    if (mounted) {
      setState(() {
        isLoggedIn = false;
        username = '';
        avatarUrl = null;
      });
      showMessage('已退出登录');
    }
  }

  /// 显示消息 - 子类需要实现具体的UI显示方式
  void showMessage(String message);

  /// 显示登录对话框 - 子类需要实现具体的UI
  void showLoginDialog();
}
import 'package:flutter/material.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/debug_log_service.dart';

/// 账号页面的业务逻辑控制器
/// 包含所有共享的功能和状态管理
mixin AccountPageController<T extends StatefulWidget> on State<T> {
  // 控制器
  final usernameController = TextEditingController();
  final passwordController = TextEditingController();
  // 注册用的控制器
  final registerUsernameController = TextEditingController();
  final registerPasswordController = TextEditingController();
  final registerEmailController = TextEditingController();
  final registerScreenNameController = TextEditingController();
  
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
    registerUsernameController.dispose();
    registerPasswordController.dispose();
    registerEmailController.dispose();
    registerScreenNameController.dispose();
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
    final logService = DebugLogService();
    
    logService.addLog('[账号控制器] 开始登录流程', level: 'INFO', tag: 'AccountController');
    
    if (usernameController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      logService.addWarning('[账号控制器] 登录信息不完整', tag: 'AccountController');
      showMessage('请输入用户名和密码');
      return;
    }

    logService.addLog('[账号控制器] 登录信息验证通过，开始登录', level: 'INFO', tag: 'AccountController');

    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      logService.addLog('[账号控制器] 调用登录服务', level: 'INFO', tag: 'AccountController');
      
      final result = await DandanplayService.login(
        usernameController.text.trim(),
        passwordController.text.trim(),
      );

      logService.addLog('[账号控制器] 登录服务返回结果: ${result.toString()}', level: 'INFO', tag: 'AccountController');

      if (result['success'] == true) {
        logService.addLog('[账号控制器] 登录成功，重新加载登录状态', level: 'INFO', tag: 'AccountController');
        await loadLoginStatus();
        usernameController.clear();
        passwordController.clear();
        if (mounted) {
          showMessage(result['message'] ?? '登录成功');
        }
      } else {
        logService.addError('[账号控制器] 登录失败: ${result['message']}', tag: 'AccountController');
        if (mounted) {
          showMessage(result['message'] ?? '登录失败');
        }
      }
    } catch (e, stackTrace) {
      logService.addError('[账号控制器] 登录时发生异常: $e', tag: 'AccountController');
      logService.addError('[账号控制器] 异常堆栈: $stackTrace', tag: 'AccountController');
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

  /// 执行注册
  Future<void> performRegister() async {
    final logService = DebugLogService();
    
    logService.addLog('[账号控制器] 开始注册流程', level: 'INFO', tag: 'AccountController');
    
    if (registerUsernameController.text.trim().isEmpty ||
        registerPasswordController.text.trim().isEmpty ||
        registerEmailController.text.trim().isEmpty ||
        registerScreenNameController.text.trim().isEmpty) {
      logService.addWarning('[账号控制器] 注册信息不完整', tag: 'AccountController');
      showMessage('请填写完整的注册信息');
      return;
    }

    logService.addLog('[账号控制器] 注册信息验证通过，开始注册', level: 'INFO', tag: 'AccountController');

    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      logService.addLog('[账号控制器] 调用注册服务', level: 'INFO', tag: 'AccountController');
      
      final result = await DandanplayService.register(
        username: registerUsernameController.text.trim(),
        password: registerPasswordController.text.trim(),
        email: registerEmailController.text.trim(),
        screenName: registerScreenNameController.text.trim(),
      );

      logService.addLog('[账号控制器] 注册服务返回结果: ${result.toString()}', level: 'INFO', tag: 'AccountController');

      if (result['success'] == true) {
        logService.addLog('[账号控制器] 注册成功，重新加载登录状态', level: 'INFO', tag: 'AccountController');
        await loadLoginStatus();
        // 清空注册表单
        registerUsernameController.clear();
        registerPasswordController.clear();
        registerEmailController.clear();
        registerScreenNameController.clear();
        if (mounted) {
          showMessage(result['message'] ?? '注册成功');
        }
      } else {
        logService.addError('[账号控制器] 注册失败: ${result['message']}', tag: 'AccountController');
        if (mounted) {
          showMessage(result['message'] ?? '注册失败');
        }
        // 抛出异常，以便UI层可以捕获并打印日志
        throw Exception(result['message'] ?? '注册失败');
      }
    } catch (e, stackTrace) {
      logService.addError('[账号控制器] 注册时发生异常: $e', tag: 'AccountController');
      logService.addError('[账号控制器] 异常堆栈: $stackTrace', tag: 'AccountController');
      if (mounted) {
        showMessage('注册失败: $e');
      }
      // 重新抛出异常，以便UI层可以捕获并打印日志
      rethrow;
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

  /// 显示注册对话框 - 子类需要实现具体的UI
  void showRegisterDialog();
}
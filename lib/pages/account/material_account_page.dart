import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'account_controller.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';

/// Material Design版本的账号页面
class MaterialAccountPage extends StatefulWidget {
  const MaterialAccountPage({super.key});

  @override
  State<MaterialAccountPage> createState() => _MaterialAccountPageState();
}

class _MaterialAccountPageState extends State<MaterialAccountPage> 
    with AccountPageController {

  @override
  void showMessage(String message) {
    BlurSnackBar.show(context, message);
  }

  @override
  void showLoginDialog() {
    BlurLoginDialog.show(
      context,
      title: '登录弹弹play账号',
      fields: [
        LoginField(
          key: 'username',
          label: '用户名/邮箱',
          hint: '请输入用户名或邮箱',
          initialValue: usernameController.text,
        ),
        LoginField(
          key: 'password',
          label: '密码',
          isPassword: true,
          initialValue: passwordController.text,
        ),
      ],
      loginButtonText: '登录',
      onLogin: (values) async {
        usernameController.text = values['username']!;
        passwordController.text = values['password']!;
        await performLogin();
        return LoginResult(success: isLoggedIn);
      },
    );
  }

  @override
  void showRegisterDialog() {
    BlurLoginDialog.show(
      context,
      title: '注册弹弹play账号',
      fields: [
        LoginField(
          key: 'username',
          label: '用户名',
          hint: '5-20位英文或数字，首位不能为数字',
          initialValue: registerUsernameController.text,
        ),
        LoginField(
          key: 'password',
          label: '密码',
          hint: '5-20位密码',
          isPassword: true,
          initialValue: registerPasswordController.text,
        ),
        LoginField(
          key: 'email',
          label: '邮箱',
          hint: '用于找回密码',
          initialValue: registerEmailController.text,
        ),
        LoginField(
          key: 'screenName',
          label: '昵称',
          hint: '显示名称，不超过50个字符',
          initialValue: registerScreenNameController.text,
        ),
      ],
      loginButtonText: '注册',
      onLogin: (values) async {
        final logService = DebugLogService();
        try {
          // 先记录日志
          logService.addLog('[Material账号页面] 注册对话框onLogin回调被调用', level: 'INFO', tag: 'AccountPage');
          logService.addLog('[Material账号页面] 收到的values: ${values.toString()}', level: 'INFO', tag: 'AccountPage');
          
          // 设置控制器的值
          registerUsernameController.text = values['username'] ?? '';
          registerPasswordController.text = values['password'] ?? '';
          registerEmailController.text = values['email'] ?? '';
          registerScreenNameController.text = values['screenName'] ?? '';
          
          logService.addLog('[Material账号页面] 准备调用performRegister', level: 'INFO', tag: 'AccountPage');
          
          // 调用注册方法
          await performRegister();
          
          logService.addLog('[Material账号页面] performRegister执行完成，isLoggedIn=$isLoggedIn', level: 'INFO', tag: 'AccountPage');
          
          return LoginResult(success: isLoggedIn, message: isLoggedIn ? '注册成功' : '注册失败');
        } catch (e) {
          // 捕获并记录详细错误
          print('[REGISTRATION ERROR]: $e');
          logService.addLog('[Material账号页面] performRegister时发生异常: $e', level: 'ERROR', tag: 'AccountPage');
          return LoginResult(success: false, message: '注册失败: $e');
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '弹弹play账号',
              locale:Locale("zh","CN"),
style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            if (isLoggedIn) ...[
              _buildLoggedInView(blurValue),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 0.5,
                        ),
                      ),
                      child: MaterialUserActivity(key: ValueKey(username)),
                    ),
                  ),
                ),
              ),
            ] else
              _buildLoggedOutView(blurValue),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInView(double blurValue) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              // 头像
              avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        avatarUrl!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(
                            Icons.account_circle,
                            size: 48,
                            color: Colors.white60,
                          );
                        },
                      ),
                    )
                  : const Icon(
                      Icons.account_circle,
                      size: 48,
                      color: Colors.white60,
                    ),
              const SizedBox(width: 16),
              // 用户信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '已登录',
                      locale:Locale("zh","CN"),
style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              // 退出按钮
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: performLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.logout,
                          color: Colors.white70,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '退出',
                          locale:Locale("zh","CN"),
style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedOutView(double blurValue) {
    return Column(
      children: [
        ListTile(
          title: const Text(
            "登录弹弹play账号",
            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "登录后可以同步观看记录和个人设置",
            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.login, color: Colors.white),
          onTap: showLoginDialog,
        ),
        const Divider(color: Colors.white12, height: 1),
        ListTile(
          title: const Text(
            "注册弹弹play账号",
            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "创建新的弹弹play账号，享受完整功能",
            locale:Locale("zh","CN"),
style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.person_add, color: Colors.white),
          onTap: showRegisterDialog,
        ),
        const Divider(color: Colors.white12, height: 1),
      ],
    );
  }
}
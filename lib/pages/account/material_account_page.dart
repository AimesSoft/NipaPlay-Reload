import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_snackbar.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_login_dialog.dart';
import 'account_controller.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';

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
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          subtitle: const Text(
            "登录后可以同步观看记录和个人设置",
            style: TextStyle(color: Colors.white70),
          ),
          trailing: const Icon(Icons.login, color: Colors.white),
          onTap: showLoginDialog,
        ),
        const Divider(color: Colors.white12, height: 1),
      ],
    );
  }
}
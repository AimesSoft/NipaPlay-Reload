import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:url_launcher/url_launcher.dart';

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
  void showDeleteAccountDialog(String deleteAccountUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    BlurDialog.show(
      context: context,
      title: '账号注销确认',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '警告：账号注销是不可逆操作！',
            style: TextStyle(
              color: Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '注销后将：',
            style: TextStyle(color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            '• 永久删除您的弹弹play账号\n• 清除所有个人数据和收藏\n• 无法恢复已发送的弹幕\n• 失去所有积分和等级',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 16),
          const Text(
            '点击"继续注销"将在浏览器中打开注销页面，请在页面中完成最终确认。',
            style: TextStyle(color: Colors.yellow),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            '取消',
            style: TextStyle(color: colorScheme.onSurface.withOpacity(0.6)),
          ),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
            try {
              // Web和其他平台分别处理URL打开
              if (kIsWeb) {
                // Web平台暂时显示URL让用户手动复制
                showMessage('请复制以下链接到浏览器中打开：$deleteAccountUrl');
              } else {
                // 移动端和桌面端使用url_launcher
                final uri = Uri.parse(deleteAccountUrl);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  showMessage('无法打开注销页面');
                }
              }
            } catch (e) {
              showMessage('打开注销页面失败: $e');
            }
          },
          child: const Text(
            '继续注销',
            style: TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildDandanplayPage(blurValue),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: colorScheme.onSurface.withOpacity(0.12),
            ),
            Expanded(
              child: _buildBangumiPage(blurValue),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInView(double blurValue) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.onSurface.withOpacity(0.3),
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
                          return Icon(
                            Icons.account_circle,
                            size: 48,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          );
                        },
                      ),
                    )
                  : Icon(
                      Icons.account_circle,
                      size: 48,
                      color: colorScheme.onSurface.withOpacity(0.6),
                    ),
              const SizedBox(width: 16),
              // 用户信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已登录',
                      locale:const Locale("zh-Hans","zh"),
style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.6),
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
                      color: colorScheme.onSurface.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.onSurface.withOpacity(0.2),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.logout,
                          color: colorScheme.onSurface.withOpacity(0.7),
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '退出',
                          locale: const Locale("zh-Hans", "zh"),
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 账号注销按钮
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: isLoading ? null : startDeleteAccount,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isLoading)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                            ),
                          )
                        else
                          const Icon(
                            Icons.delete_forever,
                            color: Colors.red,
                            size: 16,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          isLoading ? '处理中...' : '注销账号',
                          locale: const Locale("zh-Hans", "zh"),
                          style: const TextStyle(
                            color: Colors.red,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        ListTile(
          title: Text(
            "登录弹弹play账号",
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            "登录后可以同步观看记录和个人设置",
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          trailing: Icon(Icons.login, color: colorScheme.onSurface),
          onTap: showLoginDialog,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
        ListTile(
          title: Text(
            "注册弹弹play账号",
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface, fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            "创建新的弹弹play账号，享受完整功能",
            locale:const Locale("zh-Hans","zh"),
style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
          ),
          trailing: Icon(Icons.person_add, color: colorScheme.onSurface),
          onTap: showRegisterDialog,
        ),
        Divider(color: colorScheme.onSurface.withOpacity(0.12), height: 1),
      ],
    );
  }

  Widget _buildBangumiSyncSection(double blurValue) {
    final colorScheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurValue, sigmaY: blurValue),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.onSurface.withOpacity(0.3),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.sync, color: colorScheme.onSurface, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Bangumi观看记录同步',
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              if (isBangumiLoggedIn) ...[
                // 已登录状态
                _buildBangumiLoggedInView(),
              ] else ...[
                // 未登录状态
                _buildBangumiLoggedOutView(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBangumiLoggedInView() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.onSurface.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '已连接到 ${bangumiUserInfo?['nickname'] ?? bangumiUserInfo?['username'] ?? 'Bangumi'}',
                      locale: const Locale("zh-Hans", "zh"),
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (lastBangumiSyncTime != null)
                      Text(
                        '上次同步: ${_formatDateTime(lastBangumiSyncTime!)}',
                        locale: const Locale("zh-Hans", "zh"),
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 同步状态
        if (isBangumiSyncing) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.blue.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onSurface),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    bangumiSyncStatus,
                    locale: const Locale("zh-Hans", "zh"),
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 操作按钮
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildActionButton(
              '同步到Bangumi',
              Icons.sync,
              isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: false),
            ),
            _buildActionButton(
              '同步所有本地记录',
              Icons.sync_alt,
              isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: true),
            ),
            _buildActionButton(
              '验证令牌',
              Icons.wifi_protected_setup,
              isLoading ? null : testBangumiConnection,
            ),
            _buildActionButton(
              '清除同步记录缓存',
              Icons.clear_all,
              clearBangumiSyncCache,
            ),
            _buildActionButton(
              '删除Bangumi令牌',
              Icons.logout,
              clearBangumiToken,
              isDestructive: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBangumiLoggedOutView() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步本地观看历史到Bangumi收藏',
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),

        // 可点击的URL链接
        Row(
          children: [
            Text(
              '需要在 ',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            GestureDetector(
              onTap: () async {
                const url = 'https://next.bgm.tv/demo/access-token';
                try {
                  if (kIsWeb) {
                    // Web平台暂时显示URL让用户手动复制
                    showMessage('请复制以下链接到浏览器中打开：$url');
                  } else {
                    // 移动端和桌面端使用url_launcher
                    final uri = Uri.parse(url);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    } else {
                      if (mounted) {
                        BlurSnackBar.show(context, '无法打开链接');
                      }
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    BlurSnackBar.show(context, '打开链接失败：$e');
                  }
                }
              },
              child: const Text(
                'https://next.bgm.tv/demo/access-token',
                locale: Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: Color(0xFF53A8DC), // 使用弹弹play的蓝色作为链接色
                  fontSize: 12,
                  decoration: TextDecoration.underline,
                  decorationColor: Color(0xFF53A8DC),
                ),
              ),
            ),
            Text(
              ' 创建访问令牌',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // 令牌输入框
        Container(
          decoration: BoxDecoration(
            color: colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.onSurface.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: TextField(
            controller: bangumiTokenController,
            decoration: InputDecoration(
              hintText: '请输入Bangumi访问令牌',
              hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.54)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(16),
            ),
            style: TextStyle(color: colorScheme.onSurface),
            obscureText: true,
          ),
        ),
        const SizedBox(height: 16),

        // 保存按钮
        SizedBox(
          width: double.infinity,
          child: _buildActionButton(
            '保存令牌',
            Icons.save,
            isLoading ? null : saveBangumiToken,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    VoidCallback? onPressed, {
    bool isDestructive = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isDestructive 
                ? Colors.red.withOpacity(0.2)
                : colorScheme.onSurface.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isDestructive
                  ? Colors.red.withOpacity(0.3)
                  : colorScheme.onSurface.withOpacity(0.2),
              width: 0.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: onPressed != null 
                    ? (isDestructive ? Colors.red : colorScheme.onSurface)
                    : colorScheme.onSurface.withOpacity(0.38),
                size: 16,
              ),
              const SizedBox(width: 6),
              Text(
                text,
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: onPressed != null 
                      ? (isDestructive ? Colors.red : colorScheme.onSurface)
                      : colorScheme.onSurface.withOpacity(0.38),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}天前';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}小时前';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}分钟前';
    } else {
      return '刚刚';
    }
  }

  // 构建弹弹play页面内容
  Widget _buildDandanplayPage(double blurValue) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
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
                    color: colorScheme.onSurface.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.onSurface.withOpacity(0.3),
                      width: 0.5,
                    ),
                  ),
                  child: MaterialUserActivity(key: ValueKey(username)),
                ),
              ),
            ),
          ),
        ] else ...[
          _buildLoggedOutView(blurValue),
        ],
      ],
    );
  }

  // 构建Bangumi页面内容
  Widget _buildBangumiPage(double blurValue) {
    return SingleChildScrollView(
      child: _buildBangumiSyncSection(blurValue),
    );
  }
}

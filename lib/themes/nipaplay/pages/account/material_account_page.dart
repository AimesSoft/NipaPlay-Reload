import 'dart:ui';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/providers/appearance_settings_provider.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Fluent UI版本的账号页面
class MaterialAccountPage extends StatefulWidget {
  const MaterialAccountPage({super.key});

  @override
  State<MaterialAccountPage> createState() => _MaterialAccountPageState();
}

class _MaterialAccountPageState extends State<MaterialAccountPage>
    with AccountPageController {
  static const Color _accentColor = Color(0xFFFF2E55);

  @override
  void showMessage(String message) {
    if (!mounted) return;
    fluent.displayInfoBar(
      context,
      builder: (context, close) {
        return fluent.InfoBar(
          title: Text(message),
          action: fluent.IconButton(
            icon: const fluent.Icon(fluent.FluentIcons.chrome_close),
            onPressed: close,
          ),
        );
      },
    );
  }

  fluent.FluentThemeData _buildFluentThemeData(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return fluent.FluentThemeData(
      brightness: brightness,
      accentColor: fluent.AccentColor.swatch({'normal': _accentColor}),
      micaBackgroundColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
    );
  }

  fluent.ButtonStyle _buttonStyle({bool isCompact = false}) {
    final padding = isCompact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return fluent.ButtonStyle(
      padding: fluent.WidgetStatePropertyAll(padding),
    );
  }

  fluent.ButtonStyle _destructiveButtonStyle(
    BuildContext context, {
    bool isCompact = false,
  }) {
    final theme = fluent.FluentTheme.of(context);
    final padding = isCompact
        ? const EdgeInsets.symmetric(horizontal: 12, vertical: 6)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 8);
    return fluent.ButtonStyle(
      padding: fluent.WidgetStatePropertyAll(padding),
      backgroundColor: fluent.WidgetStateProperty.resolveWith((states) {
        if (states.contains(fluent.WidgetState.disabled)) {
          return theme.resources.controlFillColorDisabled;
        }
        if (states.contains(fluent.WidgetState.pressed)) {
          return fluent.Colors.errorPrimaryColor.withOpacity(0.9);
        }
        if (states.contains(fluent.WidgetState.hovered)) {
          return fluent.Colors.errorPrimaryColor.withOpacity(0.85);
        }
        return fluent.Colors.errorPrimaryColor;
      }),
      foregroundColor: const fluent.WidgetStatePropertyAll(fluent.Colors.white),
    );
  }

  Future<void> _showFluentLoginDialog({
    required String title,
    required List<LoginField> fields,
    required String actionText,
    required Future<LoginResult> Function(Map<String, String> values) onSubmit,
  }) async {
    final controllers = <String, TextEditingController>{};
    final focusNodes = <String, FocusNode>{};

    for (final field in fields) {
      controllers[field.key] = TextEditingController(text: field.initialValue);
      focusNodes[field.key] = FocusNode();
    }

    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setState) {
            Future<void> handleSubmit() async {
              final values = <String, String>{};
              for (final field in fields) {
                final value = controllers[field.key]?.text ?? '';
                if (field.required && value.trim().isEmpty) {
                  showMessage('请输入${field.label}');
                  return;
                }
                values[field.key] = value.trim();
              }

              setState(() {
                isLoading = true;
              });

              try {
                final result = await onSubmit(values);
                if (!mounted) return;
                setState(() {
                  isLoading = false;
                });
                if (result.success) {
                  Navigator.of(dialogContext).pop();
                }
                if (result.message != null) {
                  showMessage(result.message!);
                }
              } catch (e) {
                if (!mounted) return;
                setState(() {
                  isLoading = false;
                });
                showMessage('$actionText失败: $e');
              }
            }

            void handleFieldSubmitted(int index) {
              final isLast = index == fields.length - 1;
              if (isLast) {
                if (!isLoading) {
                  handleSubmit();
                }
                return;
              }
              final nextField = fields[index + 1];
              focusNodes[nextField.key]?.requestFocus();
            }

            return fluent.ContentDialog(
              title: Text(title),
              content: SizedBox(
                width: 360,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < fields.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: fluent.InfoLabel(
                            label: fields[i].label,
                            child: fields[i].isPassword
                                ? fluent.PasswordBox(
                                    controller: controllers[fields[i].key],
                                    focusNode: focusNodes[fields[i].key],
                                    placeholder: fields[i].hint,
                                    autofocus: i == 0,
                                    onSubmitted: (_) => handleFieldSubmitted(i),
                                  )
                                : fluent.TextBox(
                                    controller: controllers[fields[i].key],
                                    focusNode: focusNodes[fields[i].key],
                                    placeholder: fields[i].hint,
                                    autofocus: i == 0,
                                    textInputAction:
                                        i == fields.length - 1
                                            ? TextInputAction.done
                                            : TextInputAction.next,
                                    onSubmitted: (_) => handleFieldSubmitted(i),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                fluent.Button(
                  onPressed:
                      isLoading ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                fluent.FilledButton(
                  onPressed: isLoading ? null : handleSubmit,
                  child: isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: fluent.ProgressRing(
                            strokeWidth: 2,
                            activeColor: fluent.Colors.white,
                          ),
                        )
                      : Text(actionText),
                ),
              ],
            );
          },
        );
      },
    );

    for (final controller in controllers.values) {
      controller.dispose();
    }
    for (final focusNode in focusNodes.values) {
      focusNode.dispose();
    }
  }

  @override
  void showLoginDialog() {
    _showFluentLoginDialog(
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
      actionText: '登录',
      onSubmit: (values) async {
        usernameController.text = values['username']!;
        passwordController.text = values['password']!;
        await performLogin();
        return LoginResult(success: isLoggedIn);
      },
    );
  }

  @override
  void showRegisterDialog() {
    _showFluentLoginDialog(
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
      actionText: '注册',
      onSubmit: (values) async {
        final logService = DebugLogService();
        try {
          // 先记录日志
          logService.addLog('[Fluent账号页面] 注册对话框onLogin回调被调用', level: 'INFO', tag: 'AccountPage');
          logService.addLog('[Fluent账号页面] 收到的values: ${values.toString()}', level: 'INFO', tag: 'AccountPage');

          // 设置控制器的值
          registerUsernameController.text = values['username'] ?? '';
          registerPasswordController.text = values['password'] ?? '';
          registerEmailController.text = values['email'] ?? '';
          registerScreenNameController.text = values['screenName'] ?? '';

          logService.addLog('[Fluent账号页面] 准备调用performRegister', level: 'INFO', tag: 'AccountPage');

          // 调用注册方法
          await performRegister();

          logService.addLog('[Fluent账号页面] performRegister执行完成，isLoggedIn=$isLoggedIn', level: 'INFO', tag: 'AccountPage');

          return LoginResult(success: isLoggedIn, message: isLoggedIn ? '注册成功' : '注册失败');
        } catch (e) {
          // 捕获并记录详细错误
          print('[REGISTRATION ERROR]: $e');
          logService.addLog('[Fluent账号页面] performRegister时发生异常: $e', level: 'ERROR', tag: 'AccountPage');
          return LoginResult(success: false, message: '注册失败: $e');
        }
      },
    );
  }

  @override
  void showDeleteAccountDialog(String deleteAccountUrl) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return fluent.FluentTheme(
          data: _buildFluentThemeData(context),
          child: Builder(
            builder: (fluentContext) {
              return fluent.ContentDialog(
                title: const Text('账号注销确认'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '警告：账号注销是不可逆操作！',
                      style: TextStyle(
                        color: fluent.Colors.errorPrimaryColor,
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
                      style:
                          TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '点击"继续注销"将在浏览器中打开注销页面，请在页面中完成最终确认。',
                      style: TextStyle(color: fluent.Colors.warningPrimaryColor),
                    ),
                  ],
                ),
                actions: [
                  fluent.Button(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('取消'),
                  ),
                  fluent.FilledButton(
                    style: _destructiveButtonStyle(fluentContext),
                    onPressed: () async {
                      Navigator.of(dialogContext).pop();
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
                    child: const Text('继续注销'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final appearanceSettings = context.watch<AppearanceSettingsProvider>();
    final blurValue = appearanceSettings.enableWidgetBlurEffect ? 25.0 : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return fluent.FluentTheme(
      data: _buildFluentThemeData(context),
      child: fluent.ScaffoldPage(
        padding: EdgeInsets.zero,
        content: Padding(
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
                          return fluent.Icon(
                            fluent.FluentIcons.contact,
                            size: 48,
                            color: colorScheme.onSurface.withOpacity(0.6),
                          );
                        },
                      ),
                    )
                  : fluent.Icon(
                      fluent.FluentIcons.contact,
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
              _buildActionButton(
                '退出',
                fluent.FluentIcons.sign_out,
                performLogout,
                isCompact: true,
              ),
              const SizedBox(width: 8),
              // 账号注销按钮
              _buildActionButton(
                isLoading ? '处理中...' : '注销账号',
                fluent.FluentIcons.delete,
                isLoading ? null : startDeleteAccount,
                isDestructive: true,
                isCompact: true,
                showProgress: isLoading,
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
        fluent.ListTile(
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
          trailing: fluent.Icon(
            fluent.FluentIcons.signin,
            color: colorScheme.onSurface,
          ),
          onPressed: showLoginDialog,
        ),
        fluent.Divider(
          style: fluent.DividerThemeData(
            thickness: 1,
            horizontalMargin: EdgeInsets.zero,
            verticalMargin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.12),
            ),
          ),
        ),
        fluent.ListTile(
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
          trailing: fluent.Icon(
            fluent.FluentIcons.add_friend,
            color: colorScheme.onSurface,
          ),
          onPressed: showRegisterDialog,
        ),
        fluent.Divider(
          style: fluent.DividerThemeData(
            thickness: 1,
            horizontalMargin: EdgeInsets.zero,
            verticalMargin: EdgeInsets.zero,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withOpacity(0.12),
            ),
          ),
        ),
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
                  fluent.Icon(
                    fluent.FluentIcons.sync,
                    color: colorScheme.onSurface,
                    size: 24,
                  ),
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
              const fluent.Icon(
                fluent.FluentIcons.accept,
                color: Colors.green,
                size: 20,
              ),
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
              color: _accentColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _accentColor.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: fluent.ProgressRing(
                    strokeWidth: 2,
                    activeColor: _accentColor,
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
              fluent.FluentIcons.sync,
              isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: false),
            ),
            _buildActionButton(
              '同步所有本地记录',
              fluent.FluentIcons.sync_folder,
              isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: true),
            ),
            _buildActionButton(
              '验证令牌',
              fluent.FluentIcons.wifi,
              isLoading ? null : testBangumiConnection,
            ),
            _buildActionButton(
              '清除同步记录缓存',
              fluent.FluentIcons.clear,
              clearBangumiSyncCache,
            ),
            _buildActionButton(
              '删除Bangumi令牌',
              fluent.FluentIcons.sign_out,
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
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '需要在',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
            fluent.HyperlinkButton(
              onPressed: () async {
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
                      showMessage('无法打开链接');
                    }
                  }
                } catch (e) {
                  showMessage('打开链接失败：$e');
                }
              },
              child: const Text(
                'https://next.bgm.tv/demo/access-token',
                locale: Locale("zh-Hans", "zh"),
              ),
            ),
            Text(
              '创建访问令牌',
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
        fluent.PasswordBox(
          controller: bangumiTokenController,
          placeholder: '请输入Bangumi访问令牌',
        ),
        const SizedBox(height: 16),

        // 保存按钮
        SizedBox(
          width: double.infinity,
          child: fluent.FilledButton(
            onPressed: isLoading ? null : saveBangumiToken,
            style: _buttonStyle(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const fluent.Icon(
                  fluent.FluentIcons.save,
                  size: 16,
                ),
                const SizedBox(width: 6),
                const Text(
                  '保存令牌',
                  locale: Locale("zh-Hans", "zh"),
                ),
              ],
            ),
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
    bool isCompact = false,
    bool showProgress = false,
  }) {
    return Builder(
      builder: (context) {
        final theme = fluent.FluentTheme.of(context);
        final progressColor = isDestructive
            ? fluent.Colors.white
            : theme.resources.textFillColorPrimary;
        final content = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showProgress)
              SizedBox(
                width: 16,
                height: 16,
                child: fluent.ProgressRing(
                  strokeWidth: 2,
                  activeColor: progressColor,
                ),
              )
            else
              fluent.Icon(
                icon,
                size: 16,
              ),
            const SizedBox(width: 6),
            Text(
              text,
              locale: const Locale("zh-Hans", "zh"),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        );

        if (isDestructive) {
          return fluent.FilledButton(
            onPressed: onPressed,
            style: _destructiveButtonStyle(context, isCompact: isCompact),
            child: content,
          );
        }

        return fluent.Button(
          onPressed: onPressed,
          style: _buttonStyle(isCompact: isCompact),
          child: content,
        );
      },
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

import 'package:flutter/material.dart' as material;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fluent_ui/fluent_ui.dart';
import 'package:nipaplay/widgets/user_activity/fluent_user_activity.dart';
import 'package:nipaplay/widgets/fluent_ui/fluent_info_bar.dart';
import 'package:nipaplay/widgets/nipaplay_theme/blur_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'account_controller.dart';

/// Fluent UI版本的账号页面
class FluentAccountPage extends StatefulWidget {
  const FluentAccountPage({super.key});

  @override
  State<FluentAccountPage> createState() => _FluentAccountPageState();
}

class _FluentAccountPageState extends State<FluentAccountPage> 
    with AccountPageController {

  // 页面切换状态：true为弹弹play页面，false为Bangumi页面
  bool _showDandanplayPage = true;

  @override
  void showMessage(String message) {
    FluentInfoBar.show(
      context,
      message,
      severity: InfoBarSeverity.info,
    );
  }

  @override
  void showLoginDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('登录弹弹play账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(
              label: '用户名/邮箱',
              child: TextBox(
                controller: usernameController,
                placeholder: '请输入用户名或邮箱',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '密码',
              child: PasswordBox(
                controller: passwordController,
                placeholder: '请输入密码',
              ),
            ),
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: isLoading ? null : () async {
              await performLogin();
              if (isLoggedIn && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: isLoading 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Text('登录'),
          ),
        ],
      ),
    );
  }

  @override
  void showRegisterDialog() {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('注册弹弹play账号'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InfoLabel(
              label: '用户名',
              child: TextBox(
                controller: registerUsernameController,
                placeholder: '5-20位英文或数字，首位不能为数字',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '密码',
              child: PasswordBox(
                controller: registerPasswordController,
                placeholder: '5-20位密码',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '邮箱',
              child: TextBox(
                controller: registerEmailController,
                placeholder: '用于找回密码',
              ),
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: '昵称',
              child: TextBox(
                controller: registerScreenNameController,
                placeholder: '显示名称，不超过50个字符',
              ),
            ),
          ],
        ),
        actions: [
          Button(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: isLoading ? null : () async {
              await performRegister();
              if (isLoggedIn && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: ProgressRing(strokeWidth: 2),
                  )
                : const Text('注册'),
          ),
        ],
      ),
    );
  }

  @override
  void showDeleteAccountDialog(String deleteAccountUrl) {
    BlurDialog.show(
      context: context,
      title: '账号注销确认',
      contentWidget: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '警告：账号注销是不可逆操作！',
            style: TextStyle(
              color: material.Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text('注销后将：'),
          const SizedBox(height: 8),
          const Text(
            '• 永久删除您的弹弹play账号\n'
            '• 清除所有个人数据和收藏\n'
            '• 无法恢复已发送的弹幕\n'
            '• 失去所有积分和等级',
          ),
          const SizedBox(height: 16),
          Text(
            '点击"继续注销"将在浏览器中打开注销页面，请在页面中完成最终确认。',
            style: TextStyle(
              color: material.Colors.orange,
            ),
          ),
        ],
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: ButtonStyle(
            backgroundColor: ButtonState.all(material.Colors.red),
          ),
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
            style: TextStyle(color: material.Colors.white),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('账号管理'),
        commandBar: _buildTabSelector(),
      ),
      content: Padding(
        padding: const EdgeInsets.all(24.0),
        child: _showDandanplayPage 
            ? _buildDandanplayContent() 
            : _buildBangumiContent(),
      ),
    );
  }

  /// 构建Fluent风格的Tab选择器
  Widget _buildTabSelector() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: FluentTheme.of(context).acrylicBackgroundColor.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: FluentTheme.of(context).resources.dividerStrokeColorDefault,
          width: 0.5,
        ),
      ),
      child: Stack(
        children: [
          // 滑动指示器（放在底层）
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: _showDandanplayPage ? 2 : null,
            right: _showDandanplayPage ? null : 2,
            top: 2,
            bottom: 2,
            width: 118, // 精确控制宽度
            child: Container(
              decoration: BoxDecoration(
                color: FluentTheme.of(context).accentColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: FluentTheme.of(context).accentColor,
                  width: 1,
                ),
              ),
            ),
          ),
          // 可点击选项（只有一层，带文字）
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildFluentTabOption('Dandanplay账户', true),
              _buildFluentTabOption('Bangumi同步', false),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFluentTabOption(String text, bool isDandanplay) {
    final isActive = _showDandanplayPage == isDandanplay;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _showDandanplayPage = isDandanplay;
        });
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 120,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            color: isActive 
                ? FluentTheme.of(context).accentColor 
                : FluentTheme.of(context).typography.body?.color,
            fontSize: 13,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDandanplayContent() {
    return isLoggedIn ? _buildLoggedInView() : _buildLoggedOutView();
  }

  Widget _buildBangumiContent() {
    return SingleChildScrollView(
      child: _buildBangumiSyncSection(),
    );
  }

  Widget _buildLoggedInView() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // 头像
                avatarUrl != null
                    ? ClipOval(
                        child: material.Image.network(
                          avatarUrl!,
                          width: 48,
                          height: 48,
                          fit: material.BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const Icon(FluentIcons.contact, size: 48);
                          },
                        ),
                      )
                    : const Icon(FluentIcons.contact, size: 48),
                const SizedBox(width: 16),
                // 用户信息
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        username,
                        style: FluentTheme.of(context).typography.body,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '已登录',
                        style: FluentTheme.of(context).typography.caption,
                      ),
                    ],
                  ),
                ),
                // 退出按钮
                Button(
                  onPressed: performLogout,
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(FluentIcons.sign_out),
                      SizedBox(width: 8),
                      Text('退出登录'),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // 账号注销按钮
                Button(
                  onPressed: isLoading ? null : startDeleteAccount,
                  style: ButtonStyle(
                    backgroundColor: ButtonState.resolveWith((states) {
                      if (states.isDisabled) return material.Colors.grey.withOpacity(0.3);
                      if (states.isPressed) return material.Colors.red.shade700;
                      if (states.isHovered) return material.Colors.red.shade600;
                      return material.Colors.red.withOpacity(0.1);
                    }),
                    foregroundColor: ButtonState.all(material.Colors.red),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: ProgressRing(strokeWidth: 2),
                        )
                      else
                        const Icon(FluentIcons.delete),
                      const SizedBox(width: 8),
                      Text(isLoading ? '处理中...' : '注销账号'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 用户活动记录
        Expanded(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: FluentUserActivity(key: ValueKey(username)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Bangumi同步部分
        _buildBangumiSyncSection(),
      ],
    );
  }

  Widget _buildLoggedOutView() {
    return Column(
      children: [
        Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FluentIcons.contact,
                    size: 64,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '未登录弹弹play账号',
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录后可以同步观看记录和个人设置',
                    style: FluentTheme.of(context).typography.caption,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FilledButton(
                        onPressed: showLoginDialog,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.signin),
                            SizedBox(width: 8),
                            Text('登录账号'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Button(
                        onPressed: showRegisterDialog,
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(FluentIcons.add_friend),
                            SizedBox(width: 8),
                            Text('注册账号'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Bangumi同步部分
        _buildBangumiSyncSection(),
      ],
    );
  }

  Widget _buildBangumiSyncSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(FluentIcons.sync, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Bangumi观看记录同步',
                  style: FluentTheme.of(context).typography.subtitle,
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
    );
  }

  Widget _buildBangumiLoggedInView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户信息
        InfoBar(
          title: Text('已连接到 ${bangumiUserInfo?['nickname'] ?? bangumiUserInfo?['username'] ?? 'Bangumi'}'),
          content: lastBangumiSyncTime != null
              ? Text('上次同步: ${_formatDateTime(lastBangumiSyncTime!)}')
              : const Text('尚未同步'),
          severity: InfoBarSeverity.success,
        ),
        const SizedBox(height: 16),

        // 同步状态
        if (isBangumiSyncing) ...[
          InfoBar(
            title: const Text('同步中'),
            content: Text(bangumiSyncStatus),
            severity: InfoBarSeverity.info,
          ),
          const SizedBox(height: 16),
        ],

        // 操作按钮
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Button(
              onPressed: isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: false),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.sync),
                  SizedBox(width: 6),
                  Text('同步到Bangumi'),
                ],
              ),
            ),
            Button(
              onPressed: isBangumiSyncing ? null : () => performBangumiSync(forceFullSync: true),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.refresh),
                  SizedBox(width: 6),
                  Text('同步所有本地记录'),
                ],
              ),
            ),
            Button(
              onPressed: isLoading ? null : testBangumiConnection,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.globe),
                  SizedBox(width: 6),
                  Text('验证令牌'),
                ],
              ),
            ),
            Button(
              onPressed: clearBangumiSyncCache,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.delete),
                  SizedBox(width: 6),
                  Text('清除同步记录缓存'),
                ],
              ),
            ),
            Button(
              onPressed: clearBangumiToken,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(FluentIcons.sign_out),
                  SizedBox(width: 6),
                  Text('删除Bangumi令牌'),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBangumiLoggedOutView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步本地观看历史到Bangumi收藏',
          style: FluentTheme.of(context).typography.body,
        ),
        const SizedBox(height: 8),
        Text(
          '需要在 https://next.bgm.tv/demo/access-token 创建访问令牌',
          style: FluentTheme.of(context).typography.caption,
        ),
        const SizedBox(height: 16),
        
        // 令牌输入框
        InfoLabel(
          label: 'Bangumi访问令牌',
          child: PasswordBox(
            controller: bangumiTokenController,
            placeholder: '请输入访问令牌',
          ),
        ),
        const SizedBox(height: 16),

        // 保存按钮
        FilledButton(
          onPressed: isLoading ? null : saveBangumiToken,
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ProgressRing(strokeWidth: 2),
                )
              : const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(FluentIcons.save),
                    SizedBox(width: 6),
                    Text('保存令牌'),
                  ],
                ),
        ),
      ],
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
}
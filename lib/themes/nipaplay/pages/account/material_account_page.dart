import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
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
  static const double _buttonHoverScale = 1.06;
  static const double _authControlFontSize = 16;
  static const double _authControlIconSize = 20;
  static const EdgeInsets _authControlPadding =
      EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  @override
  void showMessage(String message) {
    if (!mounted) return;
    BlurSnackBar.show(context, message);
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

  Future<void> _showFluentLoginDialog({
    required String title,
    required List<LoginField> fields,
    required String actionText,
    required Future<LoginResult> Function(Map<String, String> values) onSubmit,
  }) async {
    await BlurLoginDialog.show(
      context,
      title: title,
      fields: fields,
      loginButtonText: actionText,
      onLogin: onSubmit,
    );
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
          logService.addLog('[Fluent账号页面] 注册对话框onLogin回调被调用',
              level: 'INFO', tag: 'AccountPage');
          logService.addLog('[Fluent账号页面] 收到的values: ${values.toString()}',
              level: 'INFO', tag: 'AccountPage');

          // 设置控制器的值
          registerUsernameController.text = values['username'] ?? '';
          registerPasswordController.text = values['password'] ?? '';
          registerEmailController.text = values['email'] ?? '';
          registerScreenNameController.text = values['screenName'] ?? '';

          logService.addLog('[Fluent账号页面] 准备调用performRegister',
              level: 'INFO', tag: 'AccountPage');

          // 调用注册方法
          await performRegister();

          logService.addLog(
              '[Fluent账号页面] performRegister执行完成，isLoggedIn=$isLoggedIn',
              level: 'INFO',
              tag: 'AccountPage');

          return LoginResult(
              success: isLoggedIn, message: isLoggedIn ? '注册成功' : '注册失败');
        } catch (e) {
          // 捕获并记录详细错误
          print('[REGISTRATION ERROR]: $e');
          logService.addLog('[Fluent账号页面] performRegister时发生异常: $e',
              level: 'ERROR', tag: 'AccountPage');
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
            builder: (_) {
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
                      style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.7)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '点击"继续注销"将在浏览器中打开注销页面，请在页面中完成最终确认。',
                      style:
                          TextStyle(color: fluent.Colors.warningPrimaryColor),
                    ),
                  ],
                ),
                actions: [
                  BlurButton(
                    icon: fluent.FluentIcons.cancel,
                    text: '取消',
                    flatStyle: true,
                    hoverScale: _buttonHoverScale,
                    onTap: () => Navigator.of(dialogContext).pop(),
                  ),
                  BlurButton(
                    icon: fluent.FluentIcons.delete,
                    text: '继续注销',
                    flatStyle: true,
                    hoverScale: _buttonHoverScale,
                    onTap: () async {
                      Navigator.of(dialogContext).pop();
                      await _openExternalUrl(
                        deleteAccountUrl,
                        cannotOpenMessage: '无法打开注销页面',
                      );
                    },
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
                child: _buildDandanplayPage(),
              ),
              Container(
                width: 1,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: colorScheme.onSurface.withOpacity(0.12),
              ),
              Expanded(
                child: _buildBangumiPage(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedInView() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
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
                  locale: const Locale("zh-Hans", "zh"),
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
          ),
          const SizedBox(width: 8),
          // 账号注销按钮
          _buildActionButton(
            isLoading ? '处理中...' : '注销账号',
            fluent.FluentIcons.delete,
            isLoading ? null : startDeleteAccount,
          ),
        ],
      ),
    );
  }

  Widget _buildAuthControlButton({
    required String text,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final isDisabled = onTap == null;
    return SizedBox(
      width: double.infinity,
      child: IgnorePointer(
        ignoring: isDisabled,
        child: Opacity(
          opacity: isDisabled ? 0.6 : 1.0,
          child: BlurButton(
            icon: icon,
            text: text,
            flatStyle: true,
            hoverScale: _buttonHoverScale,
            iconSize: _authControlIconSize,
            fontSize: _authControlFontSize,
            padding: _authControlPadding,
            onTap: onTap ?? () {},
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedOutView() {
    final colorScheme = Theme.of(context).colorScheme;
    final subtitleStyle = TextStyle(
      color: colorScheme.onSurface.withOpacity(0.7),
      fontSize: 12,
    );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAuthControlButton(
            icon: fluent.FluentIcons.signin,
            text: "登录弹弹play账号",
            onTap: showLoginDialog,
          ),
          const SizedBox(height: 6),
          Text(
            "登录后可以同步观看记录和个人设置",
            locale: const Locale("zh-Hans", "zh"),
            style: subtitleStyle,
          ),
          const SizedBox(height: 16),
          _buildAuthControlButton(
            icon: fluent.FluentIcons.add_friend,
            text: "注册弹弹play账号",
            onTap: showRegisterDialog,
          ),
          const SizedBox(height: 6),
          Text(
            "创建新的弹弹play账号，享受完整功能",
            locale: const Locale("zh-Hans", "zh"),
            style: subtitleStyle,
          ),
        ],
      ),
    );
  }

  Widget _buildBangumiSyncSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
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
          _buildDandanplayBangumiLinkCard(),
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
    );
  }

  Widget _buildBangumiLoggedInView() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 用户信息
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
              isBangumiSyncing
                  ? null
                  : () => performBangumiSync(forceFullSync: false),
            ),
            _buildActionButton(
              '同步所有本地记录',
              fluent.FluentIcons.sync_folder,
              isBangumiSyncing
                  ? null
                  : () => performBangumiSync(forceFullSync: true),
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

        Text(
          '需要在以下页面创建访问令牌',
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        _buildAuthControlButton(
          icon: fluent.FluentIcons.link,
          text: '打开访问令牌页面',
          onTap: () async {
            const url = 'https://next.bgm.tv/demo/access-token';
            await _openExternalUrl(url, cannotOpenMessage: '无法打开链接');
          },
        ),
        const SizedBox(height: 4),
        SelectableText(
          'https://next.bgm.tv/demo/access-token',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        // 令牌输入框
        SizedBox(
          width: double.infinity,
          child: fluent.PasswordBox(
            controller: bangumiTokenController,
            placeholder: '请输入Bangumi访问令牌',
            style: const TextStyle(fontSize: _authControlFontSize),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        const SizedBox(height: 16),

        // 保存按钮
        _buildAuthControlButton(
          icon: fluent.FluentIcons.save,
          text: '保存令牌',
          onTap: isLoading ? null : saveBangumiToken,
        ),
      ],
    );
  }

  Widget _buildDandanplayBangumiLinkCard() {
    final colorScheme = Theme.of(context).colorScheme;
    final linked = dandanLinkedBangumiInfo;
    final expiresAt = dandanLinkedBangumiExpireTime;
    final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());
    final displayRaw = linked?['display']?.toString();
    final displayName = (displayRaw != null && displayRaw.trim().isNotEmpty)
        ? displayRaw.trim()
        : linked?['userName']?.toString();
    final userId = linked?['userId']?.toString();

    String statusText;
    if (!isLoggedIn) {
      statusText = '请先登录弹弹play账号后再绑定。';
    } else if (linked == null) {
      statusText = '当前未绑定 Bangumi 账号。';
    } else {
      final label = (displayName == null || displayName.isEmpty)
          ? 'Bangumi用户'
          : displayName;
      statusText = userId == null || userId.isEmpty
          ? '已绑定：$label'
          : '已绑定：$label（ID: $userId）';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.onSurface.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '弹弹play内置 Bangumi 绑定（仅同步进度）',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            statusText,
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: isExpired
                  ? Colors.orange
                  : colorScheme.onSurface.withOpacity(0.8),
              fontSize: 12,
            ),
          ),
          if (expiresAt != null) ...[
            const SizedBox(height: 4),
            Text(
              '授权过期时间：${_formatAbsoluteDateTime(expiresAt)}',
              locale: const Locale("zh-Hans", "zh"),
              style: TextStyle(
                color: isExpired
                    ? Colors.orange
                    : colorScheme.onSurface.withOpacity(0.7),
                fontSize: 12,
              ),
            ),
          ],
          if (isExpired) ...[
            const SizedBox(height: 4),
            Text(
              '授权已过期或续期失败，请重新授权。',
              locale: const Locale("zh-Hans", "zh"),
              style: const TextStyle(
                color: Colors.orange,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          _buildAuthControlButton(
            icon: fluent.FluentIcons.link,
            text: isRequestingDandanBangumiAuth
                ? '获取授权链接中...'
                : (linked == null ? '绑定 Bangumi 账号' : '重新授权 Bangumi 账号'),
            onTap: (!isLoggedIn || isRequestingDandanBangumiAuth)
                ? null
                : _startDandanBangumiAuthorize,
          ),
          const SizedBox(height: 8),
          _buildAuthControlButton(
            icon: fluent.FluentIcons.link,
            text: linked == null ? '先绑定后再管理同步设置' : '管理Bangumi同步设置',
            onTap:
                (!isLoggedIn || linked == null || isRequestingDandanBangumiAuth)
                    ? null
                    : _openDandanBangumiManagePage,
          ),
          const SizedBox(height: 8),
          _buildAuthControlButton(
            icon: fluent.FluentIcons.sync,
            text: '我已完成网页操作，刷新状态',
            onTap: !isLoggedIn ? null : _manualRefreshDandanBangumiStatus,
          ),
          const SizedBox(height: 6),
          Text(
            '此方式不支持评论，仅用于让弹弹服务器自动同步观看历史。',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: colorScheme.onSurface.withOpacity(0.6),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startDandanBangumiAuthorize() async {
    final result = await requestBangumiOauthByDandanplay();
    if (!mounted) return;

    if (result['success'] != true) {
      showMessage(result['message']?.toString() ?? '获取授权链接失败');
      return;
    }

    final url = result['url']?.toString();
    if (url == null || url.isEmpty) {
      showMessage('授权链接为空');
      return;
    }
    await _openExternalUrl(url, cannotOpenMessage: '无法打开Bangumi授权页面');
    if (!mounted) return;
    showMessage('已在浏览器打开授权页，完成后点击“我已完成网页操作，刷新状态”。');
    _tryAutoRefreshDandanBangumiStatus();
  }

  Future<void> _openDandanBangumiManagePage() async {
    final result = await requestDandanBangumiManageUrl();
    if (!mounted) return;

    if (result['success'] != true) {
      showMessage(result['message']?.toString() ?? '获取Bangumi同步设置页面失败');
      return;
    }

    final url = result['url']?.toString();
    if (url == null || url.isEmpty) {
      showMessage('同步设置页面链接为空');
      return;
    }

    await _openExternalUrl(url, cannotOpenMessage: '无法打开Bangumi同步设置页面');
    if (!mounted) return;
    showMessage('已在浏览器打开同步设置页，网页内操作后请刷新状态或重新登录。');
    _tryAutoRefreshDandanBangumiStatus();
  }

  Future<bool> _refreshDandanBangumiStatusAfterAuth() async {
    final result = await refreshDandanBangumiLinkStatus();
    if (!mounted) return result['success'] == true;
    if (result['success'] != true) {
      showMessage(result['message']?.toString() ?? '刷新绑定状态失败');
      return false;
    }
    return true;
  }

  Future<void> _manualRefreshDandanBangumiStatus() async {
    final success = await _refreshDandanBangumiStatusAfterAuth();
    if (!mounted) return;
    if (success && dandanLinkedBangumiInfo != null) {
      showMessage('Bangumi账号绑定已更新。');
    } else if (success) {
      showMessage('暂未检测到绑定状态，请稍后再试。');
    }
  }

  Future<void> _tryAutoRefreshDandanBangumiStatus() async {
    for (var i = 0; i < 4; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final result = await refreshDandanBangumiLinkStatus();
      if (!mounted) return;
      if (result['success'] == true && dandanLinkedBangumiInfo != null) {
        showMessage('Bangumi账号绑定已更新。');
        return;
      }
    }
  }

  Future<void> _openExternalUrl(
    String url, {
    String cannotOpenMessage = '无法打开链接',
  }) async {
    try {
      if (kIsWeb) {
        showMessage('请复制以下链接到浏览器中打开：$url');
        return;
      }
      final uri = Uri.tryParse(url);
      if (uri == null) {
        showMessage('链接无效');
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        showMessage(cannotOpenMessage);
      }
    } catch (e) {
      showMessage('打开链接失败：$e');
    }
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    VoidCallback? onPressed,
  ) {
    final isDisabled = onPressed == null;
    return IgnorePointer(
      ignoring: isDisabled,
      child: BlurButton(
        icon: icon,
        text: text,
        flatStyle: true,
        hoverScale: _buttonHoverScale,
        onTap: () {
          if (isDisabled) return;
          onPressed();
        },
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

  String _formatAbsoluteDateTime(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$year-$month-$day $hour:$minute';
  }

  // 构建弹弹play页面内容
  Widget _buildDandanplayPage() {
    return Column(
      children: [
        if (isLoggedIn) ...[
          _buildLoggedInView(),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: MaterialUserActivity(key: ValueKey(username)),
            ),
          ),
        ] else ...[
          _buildLoggedOutView(),
        ],
      ],
    );
  }

  // 构建Bangumi页面内容
  Widget _buildBangumiPage() {
    return SingleChildScrollView(
      child: _buildBangumiSyncSection(),
    );
  }
}

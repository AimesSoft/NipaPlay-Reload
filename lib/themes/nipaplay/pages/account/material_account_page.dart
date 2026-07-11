import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/services/debug_log_service.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_mode_scope.dart';
import 'package:nipaplay/themes/nipaplay/widgets/large_screen_page_scaffold.dart';
import 'package:nipaplay/widgets/user_activity/material_user_activity.dart';
import 'package:nipaplay/widgets/user_activity/cupertino_user_activity.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/pages/account/sections/bangumi_section.dart';
import 'package:nipaplay/themes/cupertino/pages/account/sections/dandanplay_account_section.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/app_theme.dart';

enum _BangumiSyncHelpService { dandanplay, nipaplay }

/// Fluent UI版本的账号页面
class UnifiedAccountPage extends StatefulWidget {
  const UnifiedAccountPage({super.key});

  @override
  State<UnifiedAccountPage> createState() => _UnifiedAccountPageState();
}

class _UnifiedAccountPageState extends State<UnifiedAccountPage>
    with AccountPageController {
  static Color get _accentColor => AppAccentColors.current;
  static const double _buttonHoverScale = 1.06;
  static const double _authControlFontSize = 16;
  static const double _authControlIconSize = 20;
  static const EdgeInsets _authControlPadding = EdgeInsets.symmetric(
    horizontal: 18,
    vertical: 12,
  );
  bool _showDandanplayPhoneSection = true;
  bool _isRefreshingDandanBangumiStatus = false;

  bool get _isPhoneSurface =>
      AppDisplaySurfaceScope.of(context) == AppDisplaySurface.phone;

  @override
  void showMessage(String message) {
    if (!mounted) return;
    if (_isPhoneSurface) {
      AdaptiveSnackBar.show(
        context,
        message: message,
        type: AdaptiveSnackBarType.info,
      );
      return;
    }
    BlurSnackBar.show(context, message);
  }

  fluent.FluentThemeData _buildFluentThemeData(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return fluent.FluentThemeData(
      brightness: brightness,
      accentColor: fluent.AccentColor.swatch({'normal': _accentColor}),
      typography: _buildFluentTypography(context),
      micaBackgroundColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
    );
  }

  fluent.Typography _buildFluentTypography(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final resources = brightness == Brightness.light
        ? const fluent.ResourceDictionary.light()
        : const fluent.ResourceDictionary.dark();
    return _withCjkFallback(
      fluent.Typography.fromBrightness(
        brightness: brightness,
        color: resources.textFillColorPrimary,
      ),
    );
  }

  fluent.Typography _withCjkFallback(fluent.Typography typography) {
    return fluent.Typography.raw(
      display: _textStyleWithCjkFallback(typography.display),
      titleLarge: _textStyleWithCjkFallback(typography.titleLarge),
      title: _textStyleWithCjkFallback(typography.title),
      subtitle: _textStyleWithCjkFallback(typography.subtitle),
      bodyLarge: _textStyleWithCjkFallback(typography.bodyLarge),
      bodyStrong: _textStyleWithCjkFallback(typography.bodyStrong),
      body: _textStyleWithCjkFallback(typography.body),
      caption: _textStyleWithCjkFallback(typography.caption),
    );
  }

  TextStyle? _textStyleWithCjkFallback(TextStyle? style) {
    if (style == null) return null;
    return style.copyWith(
      fontFamilyFallback: AppTheme.platformFontFamilyFallback,
      decoration: TextDecoration.none,
      decorationColor: Colors.transparent,
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
    if (_isPhoneSurface) {
      unawaited(_showCupertinoLoginDialog());
      return;
    }
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
    if (_isPhoneSurface) {
      unawaited(_showCupertinoRegisterDialog());
      return;
    }
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
          logService.addLog(
            '[Fluent账号页面] 注册对话框onLogin回调被调用',
            level: 'INFO',
            tag: 'AccountPage',
          );
          logService.addLog(
            '[Fluent账号页面] 收到的values: ${values.toString()}',
            level: 'INFO',
            tag: 'AccountPage',
          );

          // 设置控制器的值
          registerUsernameController.text = values['username'] ?? '';
          registerPasswordController.text = values['password'] ?? '';
          registerEmailController.text = values['email'] ?? '';
          registerScreenNameController.text = values['screenName'] ?? '';

          logService.addLog(
            '[Fluent账号页面] 准备调用performRegister',
            level: 'INFO',
            tag: 'AccountPage',
          );

          // 调用注册方法
          await performRegister();

          logService.addLog(
            '[Fluent账号页面] performRegister执行完成，isLoggedIn=$isLoggedIn',
            level: 'INFO',
            tag: 'AccountPage',
          );

          return LoginResult(
            success: isLoggedIn,
            message: isLoggedIn ? '注册成功' : '注册失败',
          );
        } catch (e) {
          // 捕获并记录详细错误
          print('[REGISTRATION ERROR]: $e');
          logService.addLog(
            '[Fluent账号页面] performRegister时发生异常: $e',
            level: 'ERROR',
            tag: 'AccountPage',
          );
          return LoginResult(success: false, message: '注册失败: $e');
        }
      },
    );
  }

  @override
  void showDeleteAccountDialog(String deleteAccountUrl) {
    if (_isPhoneSurface) {
      AdaptiveAlertDialog.show(
        context: context,
        title: '账号注销确认',
        message: '账号注销为不可逆操作，将清除账号关联的所有数据。点击“继续注销”将在浏览器中打开注销页面。',
        actions: [
          AlertAction(
            title: '取消',
            style: AlertActionStyle.cancel,
            onPressed: () {},
          ),
          AlertAction(
            title: '继续注销',
            style: AlertActionStyle.destructive,
            onPressed: () {
              Future.microtask(
                () => _openExternalUrl(
                  deleteAccountUrl,
                  cannotOpenMessage: '无法打开注销页面',
                ),
              );
            },
          ),
          AlertAction(
            title: '已完成注销',
            style: AlertActionStyle.primary,
            onPressed: () {
              Future.microtask(completeAccountDeletion);
            },
          ),
        ],
      );
      return;
    }
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
                    SizedBox(height: 12),
                    Text(
                      '注销后将：',
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• 永久删除您的弹弹play账号\n• 清除所有个人数据和收藏\n• 无法恢复已发送的弹幕\n• 失去所有积分和等级',
                      style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                    SizedBox(height: 16),
                    const Text(
                      '点击"继续注销"将在浏览器中打开注销页面，请在页面中完成最终确认。',
                      style: TextStyle(
                        color: fluent.Colors.warningPrimaryColor,
                      ),
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

  Future<void> _showBangumiSyncHelpDialog(
    _BangumiSyncHelpService service,
  ) async {
    final isDandanplay = service == _BangumiSyncHelpService.dandanplay;
    final title = isDandanplay ? '弹弹play Bangumi同步说明' : 'NipaPlay Bangumi同步说明';
    final message = isDandanplay
        ? '这是弹弹play提供的 Bangumi 同步服务，会在你看完后自动同步观看记录。\n\n你可以和下方 NipaPlay 的 Bangumi 同步配合使用，也可以按需只使用其中之一。'
        : '这是 NipaPlay 提供的 Bangumi 服务。默认需要你在番剧详情页手动配置观看集数；支持打分和写评价，也支持按钮一键同步。\n\n你可以和上方弹弹play同步配合使用，也可以按需只使用其中之一。';

    if (_isPhoneSurface) {
      await AdaptiveAlertDialog.show(
        context: context,
        title: title,
        message: message,
        actions: [
          AlertAction(
            title: '知道了',
            style: AlertActionStyle.primary,
            onPressed: () {},
          ),
        ],
      );
      return;
    }

    await BlurDialog.show<void>(
      context: context,
      title: title,
      content: message,
      actions: [
        BlurButton(
          icon: fluent.FluentIcons.accept,
          text: '知道了',
          flatStyle: true,
          hoverScale: _buttonHoverScale,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildBangumiSyncHelpButton(_BangumiSyncHelpService service) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: '查看说明',
      child: fluent.IconButton(
        icon: Icon(
          Icons.help_outline_rounded,
          size: 18,
          color: colorScheme.onSurface.withOpacity(0.72),
        ),
        onPressed: () => _showBangumiSyncHelpDialog(service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isPhoneSurface) {
      return _buildCupertinoAccountPage();
    }
    final colorScheme = Theme.of(context).colorScheme;

    return fluent.FluentTheme(
      data: _buildFluentThemeData(context),
      child: NipaplayLargeScreenModeScope.isActiveOf(context)
          ? _buildLargeScreenAccountPage(colorScheme)
          : fluent.ScaffoldPage(
              padding: EdgeInsets.zero,
              content: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _buildDandanplayPage()),
                    Container(
                      width: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      color: colorScheme.onSurface.withOpacity(0.12),
                    ),
                    Expanded(child: _buildBangumiPage()),
                  ],
                ),
              ),
            ),
    );
  }

  Future<String?> _showCupertinoInputDialog({
    required String title,
    required String message,
    required String placeholder,
    required String confirmLabel,
    String initialValue = '',
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
  }) async {
    final result = await AdaptiveAlertDialog.inputShow(
      context: context,
      title: title,
      message: message,
      input: AdaptiveAlertDialogInput(
        placeholder: placeholder,
        initialValue: initialValue,
        keyboardType: keyboardType,
        obscureText: obscureText,
      ),
      actions: [
        AlertAction(
          title: '取消',
          style: AlertActionStyle.cancel,
          onPressed: () {},
        ),
        AlertAction(
          title: confirmLabel,
          style: AlertActionStyle.primary,
          onPressed: () {},
        ),
      ],
    );
    final trimmed = result?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<void> _showCupertinoLoginDialog() async {
    final username = await _showCupertinoInputDialog(
      title: '登录弹弹play账号',
      message: '请输入用户名或邮箱',
      placeholder: '用户名/邮箱',
      confirmLabel: '下一步',
      initialValue: usernameController.text,
      keyboardType: TextInputType.emailAddress,
    );
    if (username == null || !mounted) return;
    usernameController.text = username;

    final password = await _showCupertinoInputDialog(
      title: '登录弹弹play账号',
      message: '请输入密码',
      placeholder: '密码',
      confirmLabel: '登录',
      obscureText: true,
    );
    if (password == null || !mounted) return;
    passwordController.text = password;
    await performLogin();
  }

  Future<void> _showCupertinoRegisterDialog() async {
    final username = await _showCupertinoInputDialog(
      title: '注册弹弹play账号',
      message: '请输入用户名（5-20位英文或数字，首位不能为数字）',
      placeholder: '用户名',
      confirmLabel: '下一步',
      initialValue: registerUsernameController.text,
    );
    if (username == null || !mounted) return;
    registerUsernameController.text = username;

    final password = await _showCupertinoInputDialog(
      title: '注册弹弹play账号',
      message: '请输入密码',
      placeholder: '密码',
      confirmLabel: '下一步',
      obscureText: true,
      initialValue: registerPasswordController.text,
    );
    if (password == null || !mounted) return;
    registerPasswordController.text = password;

    final email = await _showCupertinoInputDialog(
      title: '注册弹弹play账号',
      message: '请输入邮箱（用于找回密码）',
      placeholder: '邮箱',
      confirmLabel: '下一步',
      initialValue: registerEmailController.text,
      keyboardType: TextInputType.emailAddress,
    );
    if (email == null || !mounted) return;
    registerEmailController.text = email;

    final screenName = await _showCupertinoInputDialog(
      title: '注册弹弹play账号',
      message: '请输入昵称（不超过50个字符）',
      placeholder: '昵称',
      confirmLabel: '注册',
      initialValue: registerScreenNameController.text,
    );
    if (screenName == null || !mounted) return;
    registerScreenNameController.text = screenName;

    try {
      await performRegister();
    } catch (_) {
      // performRegister already presents the error.
    }
  }

  Widget _buildCupertinoAccountPage() {
    final background = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final statusBarHeight = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: background,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: statusBarHeight + 58)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 116, 14),
              child: Text(
                '账户',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdaptiveSegmentedControl(
                    labels: const ['弹弹play', 'Bangumi'],
                    selectedIndex: _showDandanplayPhoneSection ? 0 : 1,
                    onValueChanged: (index) {
                      setState(() {
                        _showDandanplayPhoneSection = index == 0;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showDandanplayPhoneSection
                        ? _buildCupertinoDandanplaySection()
                        : _buildCupertinoBangumiSection(),
                  ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 84)),
        ],
      ),
    );
  }

  Widget _buildCupertinoDandanplaySection() {
    return CupertinoDandanplayAccountSection(
      key: const ValueKey<String>('dandanplay-account'),
      isLoggedIn: isLoggedIn,
      username: username.isEmpty ? '未登录' : username,
      avatarUrl: avatarUrl,
      isLoading: isLoading,
      onLogin: showLoginDialog,
      onRegister: showRegisterDialog,
      onLogout: performLogout,
      onDeleteAccount: startDeleteAccount,
      userActivity: CupertinoUserActivity(key: ValueKey<String>(username)),
    );
  }

  Widget _buildCupertinoBangumiSection() {
    return CupertinoBangumiSection(
      key: const ValueKey<String>('bangumi-account'),
      isAuthorized: isBangumiLoggedIn,
      userInfo: bangumiUserInfo,
      isDandanplayLoggedIn: isLoggedIn,
      dandanLinkedBangumiInfo: dandanLinkedBangumiInfo,
      dandanLinkedBangumiExpireTime: dandanLinkedBangumiExpireTime,
      isRequestingDandanBangumiAuth: isRequestingDandanBangumiAuth,
      isRefreshingDandanBangumiStatus: _isRefreshingDandanBangumiStatus,
      isLoading: isLoading,
      isSyncing: isBangumiSyncing,
      syncStatus: bangumiSyncStatus,
      lastSyncTime: lastBangumiSyncTime,
      tokenController: bangumiTokenController,
      onRequestDandanBangumiAuth: _startDandanBangumiAuthorize,
      onOpenDandanBangumiManage: _openDandanBangumiManagePage,
      onRefreshDandanBangumiStatus: _manualRefreshDandanBangumiStatus,
      onSaveToken: saveBangumiToken,
      onClearToken: clearBangumiToken,
      onSync: () => performBangumiSync(forceFullSync: false),
      onFullSync: () => performBangumiSync(forceFullSync: true),
      onTestConnection: testBangumiConnection,
      onClearCache: clearBangumiSyncCache,
      onOpenHelp: () => _showBangumiSyncHelpDialog(
        _BangumiSyncHelpService.nipaplay,
      ),
    );
  }

  Widget _buildLargeScreenAccountPage(ColorScheme colorScheme) {
    final loginState = isLoggedIn ? '已登录 $username' : '未登录弹弹play账号';
    final bangumiState = isBangumiLoggedIn ? 'Bangumi 已连接' : 'Bangumi 未连接';
    return NipaplayLargeScreenPageScaffold(
      title: '账号',
      subtitle: '$loginState / $bangumiState',
      actions: [
        if (!isLoggedIn)
          NipaplayLargeScreenActionButton(
            icon: fluent.FluentIcons.signin,
            label: '登录',
            onPressed: showLoginDialog,
          )
        else
          NipaplayLargeScreenActionButton(
            icon: fluent.FluentIcons.sign_out,
            label: '退出',
            onPressed: performLogout,
          ),
        NipaplayLargeScreenActionButton(
          icon: fluent.FluentIcons.sync,
          label: '同步 Bangumi',
          onPressed: isBangumiLoggedIn && !isBangumiSyncing
              ? () => performBangumiSync(forceFullSync: false)
              : null,
        ),
      ],
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: NipaplayLargeScreenPanel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NipaplayLargeScreenSectionHeader(
                    title: '弹弹play账号',
                    subtitle: isLoggedIn ? username : '登录后同步观看记录和个人设置',
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildLargeScreenDandanplayContent()),
                ],
              ),
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: NipaplayLargeScreenPanel(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NipaplayLargeScreenSectionHeader(
                    title: 'Bangumi同步',
                    subtitle: isBangumiLoggedIn
                        ? '可同步收藏、评分与评价'
                        : '连接 Bangumi 访问令牌后启用',
                  ),
                  const SizedBox(height: 16),
                  Expanded(child: _buildLargeScreenBangumiContent()),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenDandanplayContent() {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);

    if (!isLoggedIn) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '未登录弹弹play账号',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '登录后可以同步观看记录、使用弹弹play内置 Bangumi 绑定和账号活动记录。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor.withValues(alpha: 0.62),
                  fontSize: 14,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NipaplayLargeScreenActionButton(
                    icon: fluent.FluentIcons.signin,
                    label: '登录',
                    onPressed: showLoginDialog,
                    autofocus: true,
                  ),
                  const SizedBox(width: 12),
                  NipaplayLargeScreenActionButton(
                    icon: fluent.FluentIcons.add_friend,
                    label: '注册',
                    onPressed: showRegisterDialog,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            avatarUrl != null
                ? ClipOval(
                    child: Image.network(
                      avatarUrl!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          fluent.FluentIcons.contact,
                          size: 58,
                          color: textColor.withValues(alpha: 0.58),
                        );
                      },
                    ),
                  )
                : Icon(
                    fluent.FluentIcons.contact,
                    size: 58,
                    color: textColor.withValues(alpha: 0.58),
                  ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '弹弹play账号已登录',
                    style: TextStyle(
                      color: textColor.withValues(alpha: 0.60),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.sign_out,
              label: '退出',
              onPressed: performLogout,
            ),
            const SizedBox(width: 10),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.delete,
              label: isLoading ? '处理中' : '注销账号',
              onPressed: isLoading ? null : startDeleteAccount,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: MaterialUserActivity(key: ValueKey(username)),
        ),
      ],
    );
  }

  Widget _buildLargeScreenBangumiContent() {
    return ListView(
      padding: const EdgeInsets.only(bottom: 80),
      children: [
        _buildLargeScreenDandanplayBangumiSection(),
        const SizedBox(height: 24),
        _buildLargeScreenNipaBangumiSection(),
      ],
    );
  }

  Widget _buildLargeScreenDandanplayBangumiSection() {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NipaplayLargeScreenSectionHeader(
          title: '弹弹play内置绑定',
          subtitle: '由弹弹play服务器自动同步进度',
          trailing: NipaplayLargeScreenIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: '查看说明',
            onPressed: () =>
                _showBangumiSyncHelpDialog(_BangumiSyncHelpService.dandanplay),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          statusText,
          style: TextStyle(
            color: isExpired ? Colors.orangeAccent : textColor,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (expiresAt != null) ...[
          const SizedBox(height: 6),
          Text(
            '授权过期时间：${_formatAbsoluteDateTime(expiresAt)}',
            style: TextStyle(
              color: isExpired
                  ? Colors.orangeAccent
                  : textColor.withValues(alpha: 0.62),
              fontSize: 13,
            ),
          ),
        ],
        if (isExpired) ...[
          const SizedBox(height: 6),
          const Text(
            '授权已过期或续期失败，请重新授权。',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.link,
              label: isRequestingDandanBangumiAuth
                  ? '获取授权中'
                  : (linked == null ? '绑定 Bangumi' : '重新授权'),
              onPressed: (!isLoggedIn || isRequestingDandanBangumiAuth)
                  ? null
                  : _startDandanBangumiAuthorize,
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.settings,
              label: linked == null ? '管理设置' : '管理同步',
              onPressed: (!isLoggedIn ||
                      linked == null ||
                      isRequestingDandanBangumiAuth)
                  ? null
                  : _openDandanBangumiManagePage,
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.sync,
              label: '刷新状态',
              onPressed: !isLoggedIn ? null : _manualRefreshDandanBangumiStatus,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLargeScreenNipaBangumiSection() {
    final textColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : const Color(0xFF151820);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NipaplayLargeScreenSectionHeader(
          title: 'NipaPlay Bangumi同步',
          subtitle: '支持收藏、评分与评价',
          trailing: NipaplayLargeScreenIconButton(
            icon: Icons.help_outline_rounded,
            tooltip: '查看说明',
            onPressed: () =>
                _showBangumiSyncHelpDialog(_BangumiSyncHelpService.nipaplay),
          ),
        ),
        const SizedBox(height: 12),
        if (isBangumiLoggedIn)
          _buildLargeScreenBangumiLoggedIn(textColor)
        else
          _buildLargeScreenBangumiLoggedOut(textColor),
      ],
    );
  }

  Widget _buildLargeScreenBangumiLoggedIn(Color textColor) {
    final displayName = bangumiUserInfo?['nickname'] ??
        bangumiUserInfo?['username'] ??
        'Bangumi';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.lightGreenAccent, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '已连接到 $displayName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        if (lastBangumiSyncTime != null) ...[
          const SizedBox(height: 6),
          Text(
            '上次同步: ${_formatDateTime(lastBangumiSyncTime!)}',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.62),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        if (isBangumiSyncing) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: _accentColor,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  bangumiSyncStatus,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.sync,
              label: '同步',
              onPressed: isBangumiSyncing
                  ? null
                  : () => performBangumiSync(forceFullSync: false),
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.sync_folder,
              label: '全量同步',
              onPressed: isBangumiSyncing
                  ? null
                  : () => performBangumiSync(forceFullSync: true),
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.wifi,
              label: '验证令牌',
              onPressed: isLoading ? null : testBangumiConnection,
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.clear,
              label: '清缓存',
              onPressed: clearBangumiSyncCache,
            ),
            NipaplayLargeScreenActionButton(
              icon: fluent.FluentIcons.sign_out,
              label: '删除令牌',
              onPressed: clearBangumiToken,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLargeScreenBangumiLoggedOut(Color textColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '同步本地观看历史到 Bangumi 收藏前，需要先创建并保存访问令牌。',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.70),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        NipaplayLargeScreenActionButton(
          icon: fluent.FluentIcons.link,
          label: '打开访问令牌页面',
          onPressed: () async {
            const url = 'https://next.bgm.tv/demo/access-token';
            await _openExternalUrl(url, cannotOpenMessage: '无法打开链接');
          },
        ),
        const SizedBox(height: 8),
        SelectableText(
          'https://next.bgm.tv/demo/access-token',
          style: TextStyle(
            color: textColor.withValues(alpha: 0.62),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),
        _buildLargeScreenPasswordInput(
          controller: bangumiTokenController,
          hintText: '请输入 Bangumi 访问令牌',
        ),
        const SizedBox(height: 14),
        NipaplayLargeScreenActionButton(
          icon: fluent.FluentIcons.save,
          label: '保存令牌',
          onPressed: isLoading ? null : saveBangumiToken,
        ),
      ],
    );
  }

  Widget _buildLargeScreenPasswordInput({
    required TextEditingController controller,
    required String hintText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF171923);
    return TextField(
      controller: controller,
      obscureText: true,
      style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: TextStyle(color: textColor.withValues(alpha: 0.48)),
        prefixIcon: Icon(
          Icons.key_rounded,
          color: textColor.withValues(alpha: 0.58),
        ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.09)
            : Colors.white.withValues(alpha: 0.82),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: textColor.withValues(alpha: 0.10)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: textColor.withValues(alpha: 0.10)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: _accentColor, width: 2),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
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
          SizedBox(width: 16),
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
                SizedBox(height: 4),
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
          _buildActionButton('退出', fluent.FluentIcons.sign_out, performLogout),
          SizedBox(width: 8),
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
          SizedBox(height: 6),
          Text(
            "登录后可以同步观看记录和个人设置",
            locale: const Locale("zh-Hans", "zh"),
            style: subtitleStyle,
          ),
          SizedBox(height: 16),
          _buildAuthControlButton(
            icon: fluent.FluentIcons.add_friend,
            text: "注册弹弹play账号",
            onTap: showRegisterDialog,
          ),
          SizedBox(height: 6),
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
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Bangumi观看记录同步',
                  locale: const Locale("zh-Hans", "zh"),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          _buildDandanplayBangumiLinkCard(),
          SizedBox(height: 16),
          _buildNipaPlayBangumiSyncHeader(),
          SizedBox(height: 12),
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
              SizedBox(width: 8),
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
        SizedBox(height: 16),

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
                SizedBox(width: 12),
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
          SizedBox(height: 16),
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

  Widget _buildNipaPlayBangumiSyncHeader() {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            'NipaPlay Bangumi同步（支持打分与评价）',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ),
        _buildBangumiSyncHelpButton(_BangumiSyncHelpService.nipaplay),
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
          style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
        ),
        SizedBox(height: 8),

        Text(
          '需要在以下页面创建访问令牌',
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        SizedBox(height: 8),
        _buildAuthControlButton(
          icon: fluent.FluentIcons.link,
          text: '打开访问令牌页面',
          onTap: () async {
            const url = 'https://next.bgm.tv/demo/access-token';
            await _openExternalUrl(url, cannotOpenMessage: '无法打开链接');
          },
        ),
        SizedBox(height: 4),
        SelectableText(
          'https://next.bgm.tv/demo/access-token',
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.7),
            fontSize: 12,
          ),
        ),
        SizedBox(height: 16),

        // 令牌输入框
        SizedBox(
          width: double.infinity,
          child: fluent.PasswordBox(
            controller: bangumiTokenController,
            placeholder: '请输入Bangumi访问令牌',
            style: TextStyle(fontSize: _authControlFontSize),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
        ),
        SizedBox(height: 16),

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '弹弹play内置 Bangumi 绑定（仅同步进度）',
                locale: const Locale("zh-Hans", "zh"),
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _buildBangumiSyncHelpButton(_BangumiSyncHelpService.dandanplay),
          ],
        ),
        SizedBox(height: 6),
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
          SizedBox(height: 4),
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
          SizedBox(height: 4),
          Text(
            '授权已过期或续期失败，请重新授权。',
            locale: const Locale("zh-Hans", "zh"),
            style: TextStyle(
              color: Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        SizedBox(height: 10),
        _buildAuthControlButton(
          icon: fluent.FluentIcons.link,
          text: isRequestingDandanBangumiAuth
              ? '获取授权链接中...'
              : (linked == null ? '绑定 Bangumi 账号' : '重新授权 Bangumi 账号'),
          onTap: (!isLoggedIn || isRequestingDandanBangumiAuth)
              ? null
              : _startDandanBangumiAuthorize,
        ),
        SizedBox(height: 8),
        _buildAuthControlButton(
          icon: fluent.FluentIcons.link,
          text: linked == null ? '先绑定后再管理同步设置' : '管理Bangumi同步设置',
          onTap:
              (!isLoggedIn || linked == null || isRequestingDandanBangumiAuth)
                  ? null
                  : _openDandanBangumiManagePage,
        ),
        SizedBox(height: 8),
        _buildAuthControlButton(
          icon: fluent.FluentIcons.sync,
          text: '我已完成网页操作，刷新状态',
          onTap: !isLoggedIn ? null : _manualRefreshDandanBangumiStatus,
        ),
        SizedBox(height: 6),
        Text(
          '此方式不支持评论，仅用于让弹弹服务器自动同步观看历史。',
          locale: const Locale("zh-Hans", "zh"),
          style: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.6),
            fontSize: 11,
          ),
        ),
      ],
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
    if (_isRefreshingDandanBangumiStatus) return;
    setState(() => _isRefreshingDandanBangumiStatus = true);
    final success = await _refreshDandanBangumiStatusAfterAuth();
    if (!mounted) return;
    setState(() => _isRefreshingDandanBangumiStatus = false);
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
          SizedBox(height: 16),
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
    return SingleChildScrollView(child: _buildBangumiSyncSection());
  }
}

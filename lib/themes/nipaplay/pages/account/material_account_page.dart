import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/cupertino.dart' show CupertinoTheme;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:nipaplay/app/app_display_surface.dart';
import 'package:nipaplay/app/app_display_surface_scope.dart';
import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/pages/account/account_page_view_model.dart';
import 'package:nipaplay/themes/cupertino/cupertino_adaptive_platform_ui.dart';
import 'package:nipaplay/themes/cupertino/pages/account/sections/bangumi_section.dart';
import 'package:nipaplay/themes/cupertino/pages/account/sections/dandanplay_account_section.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_app_page_header.dart';
import 'package:nipaplay/themes/cupertino/widgets/cupertino_bottom_sheet.dart';
import 'package:nipaplay/themes/nipaplay/pages/account/desktop_account_view.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_button.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_login_dialog.dart';
import 'package:nipaplay/themes/nipaplay/widgets/blur_snackbar.dart';
import 'package:nipaplay/utils/app_accent_color.dart';
import 'package:nipaplay/utils/app_theme.dart';
import 'package:nipaplay/widgets/user_activity/adaptive_user_activity.dart';
import 'package:url_launcher/url_launcher.dart';

enum _BangumiSyncHelpService { dandanplay, nipaplay }

class UnifiedAccountPage extends StatefulWidget {
  const UnifiedAccountPage({super.key});

  @override
  State<UnifiedAccountPage> createState() => _UnifiedAccountPageState();
}

class _UnifiedAccountPageState extends State<UnifiedAccountPage>
    with AccountPageController {
  static const double _buttonHoverScale = 1.06;

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

  @override
  void showLoginDialog() {
    if (_isPhoneSurface) {
      unawaited(_showCupertinoLoginDialog());
      return;
    }
    unawaited(
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
          usernameController.text = values['username'] ?? '';
          passwordController.text = values['password'] ?? '';
          await performLogin();
          return LoginResult(success: isLoggedIn);
        },
      ),
    );
  }

  @override
  void showRegisterDialog() {
    if (_isPhoneSurface) {
      unawaited(_showCupertinoRegisterDialog());
      return;
    }
    unawaited(
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
          registerUsernameController.text = values['username'] ?? '';
          registerPasswordController.text = values['password'] ?? '';
          registerEmailController.text = values['email'] ?? '';
          registerScreenNameController.text = values['screenName'] ?? '';
          try {
            await performRegister();
            return LoginResult(
              success: isLoggedIn,
              message: isLoggedIn ? '注册成功' : '注册失败',
            );
          } catch (error) {
            return LoginResult(success: false, message: '注册失败: $error');
          }
        },
      ),
    );
  }

  @override
  void showDeleteAccountDialog(String deleteAccountUrl) {
    if (_isPhoneSurface) {
      unawaited(
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
                unawaited(
                  _openExternalUrl(
                    deleteAccountUrl,
                    cannotOpenMessage: '无法打开注销页面',
                  ),
                );
              },
            ),
            AlertAction(
              title: '已完成注销',
              style: AlertActionStyle.primary,
              onPressed: () => unawaited(completeAccountDeletion()),
            ),
          ],
        ),
      );
      return;
    }

    unawaited(
      BlurDialog.show<void>(
        context: context,
        title: '账号注销确认',
        content: '账号注销不可逆，将永久删除账号及其关联数据。继续后会在浏览器中打开注销页面。',
        actions: [
          BlurButton(
            icon: fluent.FluentIcons.cancel,
            text: '取消',
            flatStyle: true,
            hoverScale: _buttonHoverScale,
            onTap: () => Navigator.of(context).pop(),
          ),
          BlurButton(
            icon: fluent.FluentIcons.delete,
            text: '继续注销',
            flatStyle: true,
            hoverScale: _buttonHoverScale,
            onTap: () {
              Navigator.of(context).pop();
              unawaited(
                _openExternalUrl(
                  deleteAccountUrl,
                  cannotOpenMessage: '无法打开注销页面',
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _buildAccountPageViewModel();
    final userActivity = AdaptiveUserActivity(
      key: ValueKey<String>(username),
    );
    if (_isPhoneSurface) {
      return _buildCupertinoAccountPage(data, userActivity);
    }

    return fluent.FluentTheme(
      data: _buildFluentThemeData(context),
      child: DesktopAccountView(data: data, userActivity: userActivity),
    );
  }

  AccountPageViewModel _buildAccountPageViewModel() {
    return AccountPageViewModel(
      dandanplay: DandanplayAccountViewModel(
        isLoggedIn: isLoggedIn,
        username: username.isEmpty ? '未登录' : username,
        avatarUrl: avatarUrl,
        isLoading: isLoading,
        onLogin: showLoginDialog,
        onRegister: showRegisterDialog,
        onLogout: performLogout,
        onDeleteAccount: startDeleteAccount,
      ),
      bangumi: BangumiAccountViewModel(
        isAuthorized: isBangumiLoggedIn,
        userInfo: bangumiUserInfo,
        isDandanplayLoggedIn: isLoggedIn,
        dandanLinkedInfo: dandanLinkedBangumiInfo,
        dandanLinkedExpireTime: dandanLinkedBangumiExpireTime,
        isRequestingDandanAuth: isRequestingDandanBangumiAuth,
        isRefreshingDandanStatus: _isRefreshingDandanBangumiStatus,
        isLoading: isLoading,
        isSyncing: isBangumiSyncing,
        syncStatus: bangumiSyncStatus,
        lastSyncTime: lastBangumiSyncTime,
        tokenController: bangumiTokenController,
        onRequestDandanAuth: _startDandanBangumiAuthorize,
        onOpenDandanManage: _openDandanBangumiManagePage,
        onRefreshDandanStatus: _manualRefreshDandanBangumiStatus,
        onSaveToken: saveBangumiToken,
        onClearToken: clearBangumiToken,
        onSync: () => performBangumiSync(forceFullSync: false),
        onFullSync: () => performBangumiSync(forceFullSync: true),
        onTestConnection: testBangumiConnection,
        onClearCache: clearBangumiSyncCache,
        onOpenDandanHelp: () => _showBangumiSyncHelpDialog(
          _BangumiSyncHelpService.dandanplay,
        ),
        onOpenNipaplayHelp: () => _showBangumiSyncHelpDialog(
          _BangumiSyncHelpService.nipaplay,
        ),
      ),
    );
  }

  Widget _buildCupertinoAccountPage(
    AccountPageViewModel data,
    Widget userActivity,
  ) {
    return ColoredBox(
      color: Colors.transparent,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(
            child: CupertinoAppPageHeader(
              title: AccountPageViewModel.title,
              bottomPadding: 14,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AdaptiveSegmentedControl(
                    labels: const [
                      AccountPageViewModel.dandanplayLabel,
                      AccountPageViewModel.bangumiLabel,
                    ],
                    selectedIndex: _showDandanplayPhoneSection ? 0 : 1,
                    onValueChanged: (index) {
                      setState(() => _showDandanplayPhoneSection = index == 0);
                    },
                  ),
                  const SizedBox(height: 24),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _showDandanplayPhoneSection
                        ? CupertinoDandanplayAccountSection(
                            key: const ValueKey<String>('dandanplay-account'),
                            data: data.dandanplay,
                            userActivity: userActivity,
                          )
                        : CupertinoBangumiSection(
                            key: const ValueKey<String>('bangumi-account'),
                            data: data.bangumi,
                          ),
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

  Future<void> _showFluentLoginDialog({
    required String title,
    required List<LoginField> fields,
    required String actionText,
    required Future<LoginResult> Function(Map<String, String> values) onSubmit,
  }) {
    return BlurLoginDialog.show(
      context,
      title: title,
      fields: fields,
      loginButtonText: actionText,
      onLogin: onSubmit,
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
    final account = await _showCupertinoInputDialog(
      title: '登录弹弹play账号',
      message: '请输入用户名或邮箱',
      placeholder: '用户名/邮箱',
      confirmLabel: '下一步',
      initialValue: usernameController.text,
      keyboardType: TextInputType.emailAddress,
    );
    if (account == null || !mounted) return;
    usernameController.text = account;

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
    final account = await _showCupertinoInputDialog(
      title: '注册弹弹play账号',
      message: '请输入用户名（5-20位英文或数字，首位不能为数字）',
      placeholder: '用户名',
      confirmLabel: '下一步',
      initialValue: registerUsernameController.text,
    );
    if (account == null || !mounted) return;
    registerUsernameController.text = account;

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
      // The controller has already surfaced the registration error.
    }
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
      await CupertinoBottomSheet.show<void>(
        context: context,
        title: title,
        heightRatio: 0.55,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                style: CupertinoTheme.of(context).textTheme.textStyle.copyWith(
                      fontSize: 15,
                      height: 1.45,
                    ),
              ),
              const SizedBox(height: 16),
              AdaptiveButton(
                onPressed: () => Navigator.of(context).pop(),
                style: AdaptiveButtonStyle.filled,
                label: '知道了',
              ),
            ],
          ),
        ),
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
    unawaited(_tryAutoRefreshDandanBangumiStatus());
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
    unawaited(_tryAutoRefreshDandanBangumiStatus());
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
    for (var attempt = 0; attempt < 4; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
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
    } catch (error) {
      showMessage('打开链接失败：$error');
    }
  }

  fluent.FluentThemeData _buildFluentThemeData(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return fluent.FluentThemeData(
      brightness: brightness,
      accentColor: fluent.AccentColor.swatch({
        'normal': AppAccentColors.current,
      }),
      typography: _withCjkFallback(
        fluent.Typography.fromBrightness(brightness: brightness),
      ),
      micaBackgroundColor: Colors.transparent,
      scaffoldBackgroundColor: Colors.transparent,
    );
  }

  fluent.Typography _withCjkFallback(fluent.Typography typography) {
    TextStyle? fallback(TextStyle? style) => style?.copyWith(
          fontFamilyFallback: AppTheme.platformFontFamilyFallback,
          decoration: TextDecoration.none,
        );

    return fluent.Typography.raw(
      display: fallback(typography.display),
      titleLarge: fallback(typography.titleLarge),
      title: fallback(typography.title),
      subtitle: fallback(typography.subtitle),
      bodyLarge: fallback(typography.bodyLarge),
      bodyStrong: fallback(typography.bodyStrong),
      body: fallback(typography.body),
      caption: fallback(typography.caption),
    );
  }
}

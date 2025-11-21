import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/widgets/user_activity/cupertino_user_activity.dart';

import 'sections/bangumi_section.dart';
import 'sections/dandanplay_account_section.dart';

class CupertinoAccountPage extends StatefulWidget {
  const CupertinoAccountPage({super.key});

  @override
  State<CupertinoAccountPage> createState() => _CupertinoAccountPageState();
}

class _CupertinoAccountPageState extends State<CupertinoAccountPage>
    with AccountPageController {
  bool _showDandanplayPage = true;
  final ScrollController _scrollController = ScrollController();
  double _scrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
  }

  void _handleScroll() {
    if (!mounted) return;
    setState(() {
      _scrollOffset = _scrollController.offset;
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void showMessage(String message) {
    AdaptiveSnackBar.show(
      context,
      message: message,
      type: AdaptiveSnackBarType.info,
    );
  }

  Future<String?> _showAdaptiveInputDialog({
    required String title,
    String? message,
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

    if (result == null) {
      return null;
    }

    final trimmed = result.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  void showLoginDialog() async {
    debugPrint('[登录弹窗] 开始显示登录对话框');

    final usernameResult = await _showAdaptiveInputDialog(
      title: '登录弹弹play账号',
      message: '请输入用户名或邮箱',
      placeholder: '用户名/邮箱',
      confirmLabel: '下一步',
      initialValue: usernameController.text,
      keyboardType: TextInputType.emailAddress,
    );

    debugPrint('[登录弹窗] 用户名输入结果: ${usernameResult ?? 'null'}');

    if (usernameResult == null || usernameResult.isEmpty) {
      debugPrint('[登录弹窗] 用户名为空或用户取消，终止登录流程');
      return;
    }

    usernameController.text = usernameResult;
    debugPrint('[登录弹窗] 已保存用户名: ${usernameController.text}');

    if (!mounted) {
      debugPrint('[登录弹窗] Widget已卸载，终止登录流程');
      return;
    }

    final passwordResult = await _showAdaptiveInputDialog(
      title: '登录弹弹play账号',
      message: '请输入密码',
      placeholder: '密码',
      confirmLabel: '登录',
      obscureText: true,
    );

    debugPrint('[登录弹窗] 密码输入结果: ${passwordResult != null ? "***已输入***" : "null"}');

    if (passwordResult == null || passwordResult.isEmpty) {
      debugPrint('[登录弹窗] 密码为空或用户取消，终止登录流程');
      return;
    }

    passwordController.text = passwordResult;
    debugPrint('[登录弹窗] 已保存密码，开始调用登录方法');
    debugPrint('[登录弹窗] 用户名: ${usernameController.text}, 密码长度: ${passwordController.text.length}');

    try {
      await performLogin();
      debugPrint('[登录弹窗] performLogin() 调用完成');
    } catch (e, stackTrace) {
      debugPrint('[登录弹窗] performLogin() 调用异常: $e');
      debugPrint('[登录弹窗] 异常堆栈: $stackTrace');
    }

    debugPrint('[登录弹窗] 登录流程完成');
  }

  @override
  void showRegisterDialog() async {
    final usernameResult = await _showAdaptiveInputDialog(
      title: '注册弹弹play账号',
      message: '请输入用户名（5-20位英文或数字，首位不能为数字）',
      placeholder: '用户名',
      confirmLabel: '下一步',
      initialValue: registerUsernameController.text,
    );

    if (usernameResult == null) {
      return;
    }
    registerUsernameController.text = usernameResult;

    final passwordResult = await _showAdaptiveInputDialog(
      title: '注册弹弹play账号',
      message: '请输入密码',
      placeholder: '密码',
      confirmLabel: '下一步',
      obscureText: true,
      initialValue: registerPasswordController.text,
    );

    if (passwordResult == null) {
      return;
    }
    registerPasswordController.text = passwordResult;

    final emailResult = await _showAdaptiveInputDialog(
      title: '注册弹弹play账号',
      message: '请输入邮箱（用于找回密码）',
      placeholder: '邮箱',
      confirmLabel: '下一步',
      initialValue: registerEmailController.text,
      keyboardType: TextInputType.emailAddress,
    );

    if (emailResult == null) {
      return;
    }
    registerEmailController.text = emailResult;

    final screenNameResult = await _showAdaptiveInputDialog(
      title: '注册弹弹play账号',
      message: '请输入昵称（不超过50个字符）',
      placeholder: '昵称',
      confirmLabel: '注册',
      initialValue: registerScreenNameController.text,
    );

    if (screenNameResult == null) {
      return;
    }
    registerScreenNameController.text = screenNameResult;

    try {
      await performRegister();
    } catch (_) {
      // 错误信息已经通过 showMessage 提示
    }
  }

  @override
  void showDeleteAccountDialog(String deleteAccountUrl) {
    AdaptiveAlertDialog.show(
      context: context,
      title: '账号注销确认',
      message:
          '警告：账号注销为不可逆操作，将清除账号关联的所有数据。\n\n点击“继续注销”将在浏览器中打开注销页面，请在页面中完成最终确认。',
      icon: PlatformInfo.isIOS26OrHigher()
          ? 'exclamationmark.triangle.fill'
          : null,
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
            Future.microtask(() => _openExternalUrl(deleteAccountUrl));
          },
        ),
        AlertAction(
          title: '已完成注销',
          style: AlertActionStyle.primary,
          onPressed: () {
            Future.microtask(() => completeAccountDeletion());
          },
        ),
      ],
    );
  }

  Future<void> _openExternalUrl(String url) async {
    if (kIsWeb) {
      showMessage('请复制以下链接到浏览器访问：$url');
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
      showMessage('无法打开链接');
    }
  }

  Future<void> _openBangumiTokenGuide() async {
    const url = 'https://next.bgm.tv/demo/access-token';
    await _openExternalUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = CupertinoDynamicColor.resolve(
      CupertinoColors.systemGroupedBackground,
      context,
    );
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final double headerHeight = statusBarHeight + 52;
    final double titleOpacity = (1.0 - (_scrollOffset / 10.0)).clamp(0.0, 1.0);

    return ColoredBox(
      color: backgroundColor,
      child: Stack(
        children: [
          CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SizedBox(height: headerHeight),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSegmentedControl(context),
                      const SizedBox(height: 24),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: _showDandanplayPage
                            ? _buildDandanplaySection()
                            : _buildBangumiSection(),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
            ],
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      backgroundColor,
                      backgroundColor.withOpacity(0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: statusBarHeight,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Opacity(
                opacity: titleOpacity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '账户',
                    style: CupertinoTheme.of(context)
                        .textTheme
                        .navLargeTitleTextStyle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedControl(BuildContext context) {
    final Color textColor =
        CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.black,
        darkColor: CupertinoColors.white,
      ),
      context,
    );
    final Color segmentColor = CupertinoDynamicColor.resolve(
      const CupertinoDynamicColor.withBrightness(
        color: CupertinoColors.white,
        darkColor: CupertinoColors.inactiveGray,
      ),
      context,
    );

    final baseTheme = CupertinoTheme.of(context);
    final segmentedTheme = baseTheme.copyWith(
      primaryColor: textColor,
      textTheme: baseTheme.textTheme.copyWith(
        textStyle: baseTheme.textTheme.textStyle.copyWith(color: textColor),
      ),
    );

    return CupertinoTheme(
      data: segmentedTheme,
      child: DefaultTextStyle.merge(
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w500,
        ),
        child: AdaptiveSegmentedControl(
          labels: const ['弹弹play', 'Bangumi'],
          selectedIndex: _showDandanplayPage ? 0 : 1,
          color: segmentColor,
          onValueChanged: (index) {
            setState(() {
              _showDandanplayPage = index == 0;
            });
          },
        ),
      ),
    );
  }

  Widget _buildDandanplaySection() {
    return CupertinoDandanplayAccountSection(
      key: const ValueKey('dandanplay'),
      isLoggedIn: isLoggedIn,
      username: username.isNotEmpty ? username : '未登录',
      avatarUrl: avatarUrl,
      isLoading: isLoading,
      onLogin: showLoginDialog,
      onRegister: showRegisterDialog,
      onLogout: performLogout,
      onDeleteAccount: startDeleteAccount,
      userActivity: const CupertinoUserActivity(),
    );
  }

  Widget _buildBangumiSection() {
    return CupertinoBangumiSection(
      key: const ValueKey('bangumi'),
      isAuthorized: isBangumiLoggedIn,
      userInfo: bangumiUserInfo,
      isLoading: isLoading,
      isSyncing: isBangumiSyncing,
      syncStatus: bangumiSyncStatus,
      lastSyncTime: lastBangumiSyncTime,
      tokenController: bangumiTokenController,
      onSaveToken: saveBangumiToken,
      onClearToken: clearBangumiToken,
      onSync: () => performBangumiSync(forceFullSync: false),
      onFullSync: () => performBangumiSync(forceFullSync: true),
      onTestConnection: testBangumiConnection,
      onClearCache: clearBangumiSyncCache,
      onOpenHelp: _openBangumiTokenGuide,
    );
  }
}

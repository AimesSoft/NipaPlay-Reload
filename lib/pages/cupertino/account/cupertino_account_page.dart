import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'package:nipaplay/pages/account/account_controller.dart';
import 'package:nipaplay/widgets/user_activity/cupertino_user_activity.dart';

import 'pages/cupertino_account_credentials_page.dart';
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

  @override
  void showLoginDialog() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => CupertinoAccountCredentialsPage(
          title: '登录弹弹play账号',
          actionLabel: '登录',
          fields: [
            CupertinoCredentialField(
              label: '用户名/邮箱',
              controller: usernameController,
              placeholder: '请输入用户名或邮箱',
            ),
            CupertinoCredentialField(
              label: '密码',
              controller: passwordController,
              placeholder: '请输入密码',
              obscureText: true,
            ),
          ],
          onSubmit: () async {
            await performLogin();
            return isLoggedIn;
          },
        ),
      ),
    );
  }

  @override
  void showRegisterDialog() {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => CupertinoAccountCredentialsPage(
          title: '注册弹弹play账号',
          actionLabel: '注册',
          fields: [
            CupertinoCredentialField(
              label: '用户名',
              controller: registerUsernameController,
              placeholder: '5-20位英文或数字，首位不能为数字',
            ),
            CupertinoCredentialField(
              label: '密码',
              controller: registerPasswordController,
              placeholder: '请输入密码',
              obscureText: true,
            ),
            CupertinoCredentialField(
              label: '邮箱',
              controller: registerEmailController,
              placeholder: '用于找回密码',
            ),
            CupertinoCredentialField(
              label: '昵称',
              controller: registerScreenNameController,
              placeholder: '显示名称，不超过50个字符',
            ),
          ],
          onSubmit: () async {
            try {
              await performRegister();
            } catch (_) {
              // 错误信息已经通过 showMessage 提示
            }
            return isLoggedIn;
          },
        ),
      ),
    );
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
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        AlertAction(
          title: '继续注销',
          style: AlertActionStyle.destructive,
          onPressed: () async {
            Navigator.of(context).pop();
            await _openExternalUrl(deleteAccountUrl);
          },
        ),
        AlertAction(
          title: '已完成注销',
          style: AlertActionStyle.primary,
          onPressed: () async {
            Navigator.of(context).pop();
            await completeAccountDeletion();
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
                      AdaptiveSegmentedControl(
                        labels: const ['弹弹play', 'Bangumi'],
                        selectedIndex: _showDandanplayPage ? 0 : 1,
                        onValueChanged: (index) {
                          setState(() {
                            _showDandanplayPage = index == 0;
                          });
                        },
                      ),
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

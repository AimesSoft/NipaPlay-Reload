import 'package:flutter/material.dart';
import 'package:nipaplay_core/services/nipaplay_server_router.dart';
import 'package:nipaplay_core/utils/network_settings.dart';
import 'package:nipaplay_ui_common/l10n/l10n.dart';

import '../../data/tv_account_service.dart';
import '../focusable_card.dart';
import '../widgets/tv_input_dialog.dart';

/// 我的：账号登录（弹弹play）+ 登录后可用能力说明。
///
/// 用户要求：**弹弹play 远程服务需登录账号后才可使用**，此页即该闸门的入口。
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.entryFocusNode});

  final FocusNode? entryFocusNode;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _account = TvAccountService.instance;
  bool _busy = false;
  String? _server;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _account.load();
    final server = await NipaplayServerRouter.instance.effectiveServer();
    if (mounted) {
      setState(() => _server = server);
    }
  }

  Future<void> _login() async {
    final result = await showDialog<_Credentials>(
      context: context,
      builder: (_) => const _LoginDialog(),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _account.login(result.username, result.password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登录成功：${_account.screenName ?? result.username}')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await _account.logout();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已退出登录')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final loggedIn = _account.isLoggedIn;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(l10n.tabAccount,
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        FocusableCard(
          focusNode: widget.entryFocusNode,
          onActivate: loggedIn ? _logout : _login,
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: const Color(0xFF26C6DA).withValues(alpha: 0.2),
                child: Icon(
                  loggedIn ? Icons.person : Icons.person_outline,
                  color: const Color(0xFF26C6DA),
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      loggedIn
                          ? (_account.screenName ??
                              _account.userName ??
                              '已登录')
                          : '未登录',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      loggedIn
                          ? '点击退出登录'
                          : '登录弹弹play账号后可使用远程服务、评分与弹幕发送',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: Colors.white54),
                    ),
                  ],
                ),
              ),
              if (_busy)
                const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF26C6DA)))
              else
                Icon(loggedIn ? Icons.logout : Icons.login,
                    color: const Color(0xFF26C6DA)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FocusableCard(
          onActivate: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('账号状态',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              _kv(context, '弹弹play 账号',
                  loggedIn ? (_account.userName ?? '已登录') : '未登录'),
              _kv(context, '远程服务',
                  loggedIn ? '可用（已登录）' : '需登录后可用'),
              _kv(context, '当前网关', _server ?? '解析中…'),
              _kv(context, '官方站点', NetworkSettings.hongKongServer),
            ],
          ),
        ),
        const SizedBox(height: 18),
        FocusableCard(
          onActivate: () {},
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('登录后可用的能力',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                '· 弹弹play 远程服务（远程媒体库、远程播放）\n'
                '· 番剧评分与收藏同步\n'
                '· 发送弹幕到弹弹play\n'
                '· 观看历史云同步',
                style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.7),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kv(BuildContext context, String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(k,
                  style: const TextStyle(color: Colors.white38, fontSize: 14)),
            ),
            Expanded(
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 14)),
            ),
          ],
        ),
      );
}

class _Credentials {
  const _Credentials(this.username, this.password);
  final String username;
  final String password;
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog();

  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TvInputDialog(
      title: '登录弹弹play',
      maxWidth: 520,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('登录')),
      ],
      children: [
        TextField(
          controller: _user,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '账号',
            hintText: '弹弹play 用户名 / 邮箱',
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _pass,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: '密码',
            suffixIcon: IconButton(
              icon: Icon(_obscure
                  ? Icons.visibility_off_outlined
                  : Icons.visibility_outlined),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
      ],
    );
  }

  void _submit() {
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) return;
    Navigator.of(context).pop(_Credentials(u, p));
  }
}

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_data/host_settings.dart';
import 'controls.dart';

class CodexAccountCard extends StatefulWidget {
  const CodexAccountCard(
      {super.key, required this.host, required this.canLogin});

  final NextCodexAccountSettings host;
  final bool canLogin;

  @override
  State<CodexAccountCard> createState() => _CodexAccountCardState();
}

class _CodexAccountCardState extends State<CodexAccountCard> {
  late final StreamSubscription<void> _changes;
  Map<String, Object?> _account = {};
  UiCodexLogin? _login;
  bool _busy = false;
  int _readVersion = 0;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _changes =
        widget.host.codexAccountChanges.listen((_) => unawaited(_read()));
    unawaited(_read());
  }

  @override
  void dispose() {
    unawaited(_changes.cancel());
    super.dispose();
  }

  Future<void> _read() async {
    final version = ++_readVersion;
    Map<String, Object?> account;
    try {
      account = await widget.host.codexAccount();
    } catch (_) {
      account = {'status': 'unavailable'};
    }
    if (!mounted || version != _readVersion) return;
    setState(() {
      _account = account;
      if (const {'completed', 'failed', 'canceled'}
          .contains(account['loginState'])) {
        _login = null;
      }
    });
  }

  Future<void> _operate(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _problem = null;
    });
    try {
      await operation();
    } catch (_) {
      if (mounted) setState(() => _problem = '没能完成，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start(bool deviceCode) => _operate(() async {
        final login = await widget.host.startCodexLogin(deviceCode: deviceCode);
        if (mounted) setState(() => _login = login);
      });

  @override
  Widget build(BuildContext context) {
    final status = _account['status'];
    final login = _login;
    final metrics = _account['usage'] as Map?;
    final limits = _account['rateLimits'] as List?;
    return SettingsCard(title: 'Codex 账号', children: [
      SettingsRow(
        title: login != null
            ? '等待授权'
            : switch (status) {
                'signedIn' => '已登录',
                'signedOut' => '未登录',
                'unavailable' => '无法读取账号状态',
                _ => '正在读取账号状态',
              },
        subtitle:
            _problem ?? (_account['loginState'] == 'failed' ? '未完成授权' : null),
        trailing: widget.canLogin && login == null && status != 'signedIn'
            ? Wrap(spacing: 6, children: [
                PillButton(
                    label: '登录 ChatGPT',
                    busy: _busy,
                    onTap: () => _start(false)),
                PillButton(label: '使用设备码', onTap: () => _start(true)),
              ])
            : null,
      ),
      if (login != null)
        SettingsRow(
            title: login.code == null ? '在浏览器中授权' : '设备码：${login.code}',
            trailing: Wrap(spacing: 6, children: [
              PillButton(
                  label: '打开浏览器',
                  onTap: () => _operate(() async {
                        if (!await launchUrl(login.url,
                            mode: LaunchMode.externalApplication)) {
                          throw StateError('无法打开浏览器');
                        }
                      })),
              PillButton(
                  label: '取消',
                  onTap: () => _operate(() async {
                        await widget.host.cancelCodexLogin();
                        if (mounted) setState(() => _login = null);
                      })),
            ])),
      if (_account['email'] case final String email)
        SettingsRow(title: '邮箱', subtitle: email),
      if (_account['plan'] case final String plan)
        SettingsRow(title: '套餐', subtitle: plan),
      if (_account['rateLimitsAvailable'] == false)
        const SettingsRow(title: '暂时无法读取额度', dim: true),
      for (final limit in limits?.whereType<Map>() ?? const <Map>[])
        for (final key in ['primary', 'secondary'])
          if (limit[key] case final Map window)
            SettingsRow(
                title: limit['name'] as String? ?? '额度',
                subtitle:
                    '${window['windowDurationMins'] ?? '—'} 分钟窗口 · 已用 ${window['usedPercent'] ?? '—'}%'),
      if (_account['usageAvailable'] == false)
        const SettingsRow(title: '暂时无法读取用量', dim: true),
      if (metrics?['lifetimeTokens'] case final num tokens)
        SettingsRow(title: '累计用量', subtitle: '$tokens token'),
    ]);
  }
}

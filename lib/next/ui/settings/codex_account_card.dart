import 'dart:async';

import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../ui_data/host_settings.dart';
import '../theme/tokens.dart';
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

  static String _window(Object? minutes) => switch (minutes) {
        300 => '5 小时',
        1440 => '每天',
        10080 => '每周',
        final int m when m % 60 == 0 => '${m ~/ 60} 小时',
        final int m => '$m 分钟',
        _ => '额度',
      };

  static String? _resets(Object? at) {
    if (at is! num) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000)
        .difference(DateTime.now());
    if (left.isNegative) return null;
    if (left.inHours >= 24) return '${left.inDays} 天后重置';
    if (left.inHours >= 1) return '${left.inHours} 小时后重置';
    return '${left.inMinutes.clamp(1, 59)} 分钟后重置';
  }

  @override
  Widget build(BuildContext context) {
    final status = _account['status'];
    final login = _login;
    final pending = login != null || _account['loginState'] == 'pending';
    final metrics = _account['usage'] as Map?;
    final limits = [
      for (final limit in (_account['rateLimits'] as List?)?.whereType<Map>() ??
          const <Map>[])
        for (final key in ['primary', 'secondary'])
          if (limit[key] case final Map window) (limit['name'] as String?, window)
    ];
    final email = _account['email'] as String?;
    final plan = _account['plan'] as String?;
    return SettingsCard(title: 'ChatGPT 账号', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x3D5BE3B0), Color(0x0F5BE3B0)],
                ),
                border: Border.all(color: const Color(0x475BE3B0)),
              ),
              child: Text(
                  (email?.isNotEmpty == true ? email![0] : 'C').toUpperCase(),
                  style: NextText.serif(19).copyWith(color: NextColors.paper)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Flexible(
                        child: Text(
                            email ??
                                switch (status) {
                                  'signedIn' => '已登录',
                                  'unavailable' => '读不到账号状态',
                                  'signedOut' => '还没有登录',
                                  _ => '正在读取…',
                                },
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: NextText.sans(15, weight: FontWeight.w600)),
                      ),
                      if (plan != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0x245BE3B0),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(plan,
                              style: NextText.sans(11, color: NextColors.mint)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                        _problem ??
                            (_account['loginState'] == 'failed'
                                ? '没有完成授权'
                                : status == 'signedIn'
                                    ? '梨花用这个账号的套餐对话'
                                    : '登录后，梨花用你的 ChatGPT 套餐对话'),
                        style: NextText.sans(12.5,
                            color: _problem != null
                                ? NextColors.accent2
                                : NextColors.p3)),
                  ]),
            ),
            if (widget.canLogin && !pending && status != 'signedIn')
              Row(mainAxisSize: MainAxisSize.min, children: [
                PillButton(label: '用设备码', onTap: () => _start(true)),
                const SizedBox(width: 6),
                PillButton(
                    label: '登录',
                    primary: true,
                    busy: _busy,
                    onTap: () => _start(false)),
              ]),
          ]),
          if (pending) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              decoration: BoxDecoration(
                color: const Color(0x0DFFFFFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: NextColors.line),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            login?.code == null
                                ? '在浏览器里完成授权'
                                : '在浏览器里输入这个代码',
                            style: NextText.sans(13.5)),
                        if (login?.code case final code?) ...[
                          const SizedBox(height: 6),
                          SelectableText(code,
                              style: NextText.mono(22).copyWith(
                                  letterSpacing: 3,
                                  color: NextColors.paper)),
                        ],
                      ]),
                ),
                if (login != null) ...[
                  PillButton(
                      label: '打开浏览器',
                      primary: true,
                      onTap: () => _operate(() async {
                            if (!await launchUrl(login.url,
                                mode: LaunchMode.externalApplication)) {
                              throw StateError('无法打开浏览器');
                            }
                          })),
                  const SizedBox(width: 6),
                ],
                PillButton(
                    label: '取消',
                    onTap: () => _operate(() async {
                          await widget.host.cancelCodexLogin();
                          if (mounted) setState(() => _login = null);
                        })),
              ]),
            ),
          ],
          if (limits.isNotEmpty || _account['rateLimitsAvailable'] == false) ...[
            const SizedBox(height: 16),
            if (_account['rateLimitsAvailable'] == false)
              Text('暂时读不到额度',
                  style: NextText.sans(12.5, color: NextColors.p4)),
            for (final (name, window) in limits) _Limit(
                label: name ?? _window(window['windowDurationMins']),
                used: (window['usedPercent'] as num?)?.toDouble(),
                resets: _resets(window['resetsAt'])),
          ],
          if (metrics?['lifetimeTokens'] case final num tokens) ...[
            const SizedBox(height: 10),
            Text('累计用了 ${_tokens(tokens)} token',
                style: NextText.sans(12, color: NextColors.p4)),
          ],
        ]),
      ),
    ]);
  }

  static String _tokens(num n) => n >= 1e6
      ? '${(n / 1e6).toStringAsFixed(1)}M'
      : n >= 1e3
          ? '${(n / 1e3).toStringAsFixed(1)}K'
          : '$n';
}

/// A rate-limit window: what share of it is used, as a bar, and when it
/// starts again.
class _Limit extends StatelessWidget {
  const _Limit({required this.label, required this.used, this.resets});
  final String label;
  final double? used;
  final String? resets;

  @override
  Widget build(BuildContext context) {
    final share = ((used ?? 0) / 100).clamp(0.0, 1.0);
    final color = share >= 0.9
        ? NextColors.accent
        : share >= 0.7
            ? NextColors.amber
            : NextColors.mint;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(label, style: NextText.sans(12.5, color: NextColors.p2)),
          const Spacer(),
          Text(
              [
                used == null ? '—' : '已用 ${used!.round()}%',
                if (resets != null) resets!,
              ].join(' · '),
              style: NextText.sans(12, color: NextColors.p3)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Stack(children: [
              Container(color: const Color(0x14FFFFFF)),
              FractionallySizedBox(
                  widthFactor: share,
                  child: Container(color: color)),
            ]),
          ),
        ),
      ]),
    );
  }
}

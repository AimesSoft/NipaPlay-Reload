import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart' as harness;
import 'capability.dart';
import 'platform_session.dart';

final class PlatformSessionsPage extends StatefulWidget {
  const PlatformSessionsPage({super.key, required this.sessions});
  final PlatformSessions sessions;
  @override
  State<PlatformSessionsPage> createState() => _PlatformSessionsPageState();
}

final class _PlatformSessionsPageState extends State<PlatformSessionsPage> {
  String? _message;
  bool _busy = false;
  Future<void> _invoke(String action, harness.JsonMap input) async {
    setState(() => _busy = true);
    final api = harness.Harness([PlatformSessionCapability(widget.sessions)]);
    final result =
        await api.invokeJson(action, input, harness.Invocation(origin: 'gui'));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result is harness.Failed
          ? result.failure.message
          : action == 'ui.open_platform_login'
              ? '请在登录窗口中完成登录，再点击「完成登录并保存」。'
              : '已注销。';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('平台登录')),
        body: ListenableBuilder(
          listenable: widget.sessions,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('在 NipaPlay 内置 WebView 中登录。会话保存在本机凭据保险库，'
                  '密码只能由你输入。当前仅支持 macOS。'),
              const SizedBox(height: 16),
              for (final platform in sessionPlatforms)
                Card(
                    child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(platform == 'youku' ? '优酷' : 'B 站',
                            style: Theme.of(context).textTheme.titleLarge),
                        Text(switch (
                            widget.sessions.status(platform)['status']) {
                          'sessionPresent' => '会话已保存（本地检查；有效性在请求时确认）',
                          'expiredOrRejected' => '会话已过期或被平台拒绝，请重新登录',
                          'unsupported' => '当前平台未支持',
                          'unavailable' => widget.sessions
                              .status(platform)['notice'] as String,
                          _ => '未登录',
                        }),
                        const SizedBox(height: 12),
                        Row(children: [
                          FilledButton(
                            onPressed: _busy || !widget.sessions.login.supported
                                ? null
                                : () => _invoke('ui.open_platform_login',
                                    {'platform': platform}),
                            child: const Text('打开登录页'),
                          ),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _invoke('sessions.logout', {
                                      'platforms': [platform]
                                    }),
                            child: const Text('注销'),
                          ),
                        ]),
                      ]),
                )),
              if (_message != null) Text(_message!),
            ],
          ),
        ),
      );
}

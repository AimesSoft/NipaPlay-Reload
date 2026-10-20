import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart';
import '../media_sources/login_dialog.dart';
import '../ui/widgets/dialog.dart';

Future<JsonMap?> showAccountLogin(JsonMap input, Future<void> stopped) =>
    showNextLogin<JsonMap>(
        (_) => _AccountDialog(input: input, stopped: stopped));

class _AccountDialog extends StatefulWidget {
  const _AccountDialog({required this.input, required this.stopped});
  final JsonMap input;
  final Future<void> stopped;
  @override
  State<_AccountDialog> createState() => _AccountDialogState();
}

class _AccountDialogState extends State<_AccountDialog> {
  late final username =
      TextEditingController(text: widget.input['username'] as String?);
  final secret = TextEditingController();
  bool submitted = false;
  bool get dandan => widget.input['provider'] == 'dandanplay';
  @override
  void initState() {
    super.initState();
    widget.stopped.then((_) {
      if (mounted && !submitted) {
        Navigator.of(context).removeRoute(ModalRoute.of(context)!);
      }
    });
  }

  bool get ready =>
      secret.text.isNotEmpty && (!dandan || username.text.trim().isNotEmpty);

  void submit() {
    if (!ready) return;
    submitted = true;
    Navigator.of(context).pop<JsonMap>({
      if (dandan) 'username': username.text.trim(),
      dandan ? 'password' : 'accessToken': secret.text,
    });
  }

  void cancel() {
    submitted = true;
    Navigator.of(context).pop();
  }

  String get title => dandan ? '登录弹弹play' : '登录 Bangumi';
  String get secretLabel => dandan ? '密码' : 'Bangumi 个人访问令牌';

  @override
  Widget build(BuildContext context) =>
      NextDialogRoute.of(context) ? next() : classic();

  /// Who logs in and the secret; Return in the secret logs in. The cursor
  /// starts where the typing does.
  Widget next() {
    final named = username.text.isNotEmpty;
    return NextDialog(
      title: title,
      onCancel: cancel,
      body: [
        if (dandan)
          NextDialogField(
              label: '用户名', controller: username, autofocus: !named),
        NextDialogField(
            label: secretLabel,
            controller: secret,
            obscure: true,
            autofocus: !dandan || named,
            onSubmitted: (_) => submit()),
      ],
      actions: [
        NextDialogButton(label: '取消', onTap: cancel),
        ListenableBuilder(
          listenable: Listenable.merge([username, secret]),
          builder: (context, _) => NextDialogButton(
              label: '登录',
              kind: NextDialogButtonKind.primary,
              onTap: ready ? submit : null),
        ),
      ],
    );
  }

  Widget classic() => AlertDialog(
        title: Text(title),
        content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (dandan)
                TextField(
                    controller: username,
                    decoration: const InputDecoration(labelText: '用户名')),
              TextField(
                  controller: secret,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  autofocus: true,
                  decoration: InputDecoration(labelText: secretLabel),
                  onSubmitted: (_) => submit()),
            ])),
        actions: [
          TextButton(onPressed: cancel, child: const Text('取消')),
          FilledButton(onPressed: submit, child: const Text('登录')),
        ],
      );
  @override
  void dispose() {
    username.dispose();
    secret.clear();
    secret.dispose();
    super.dispose();
  }
}

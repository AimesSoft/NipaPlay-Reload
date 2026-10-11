import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart';
import '../media_sources/login_dialog.dart';

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

  void submit() {
    if (secret.text.isEmpty || (dandan && username.text.trim().isEmpty)) return;
    submitted = true;
    Navigator.of(context).pop<JsonMap>({
      if (dandan) 'username': username.text.trim(),
      dandan ? 'password' : 'accessToken': secret.text,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(dandan ? '登录弹弹play' : '登录 Bangumi'),
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
                  decoration: InputDecoration(
                      labelText: dandan ? '密码' : 'Bangumi 个人访问令牌'),
                  onSubmitted: (_) => submit()),
            ])),
        actions: [
          TextButton(
              onPressed: () {
                submitted = true;
                Navigator.of(context).pop();
              },
              child: const Text('取消')),
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

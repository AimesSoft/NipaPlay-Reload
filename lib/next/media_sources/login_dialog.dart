import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:window_manager/window_manager.dart';
import 'package:nipaplay/utils/lab_profile.dart';

import '../ui/widgets/dialog.dart';

/// NipaPlay's own window over whatever shows: in Next's look while Next is
/// the interface ([NextDialogRoute]), Classic's dialog otherwise.
Future<T?> showNextLogin<T>(Widget Function(BuildContext) builder) async {
  final navigator = globals.navigatorKey.currentState;
  final context = navigator?.overlay?.context;
  if (navigator == null || context == null) {
    throw const Failure(
        FailureCode.unavailable, 'The NipaPlay login window is not ready.');
  }
  if (globals.isDesktop) {
    if (await windowManager.isMinimized()) await windowManager.restore();
    if (LabProfile.quiet) {
      await LabProfile.showBehind();
    } else {
      await windowManager.show();
      await windowManager.focus();
    }
  }
  if (!context.mounted) {
    throw const Failure(
        FailureCode.unavailable, 'The NipaPlay login window has closed.');
  }
  // Flutter 3.44 showDialog chooses an experimental native dialog under
  // windowing. Its new FlutterView stays at zero metrics. Use the main view.
  return navigator.push<T>(globals.nextShellHostsPlayer
      ? NextDialogRoute<T>(builder: builder)
      : DialogRoute<T>(
          context: context, barrierDismissible: false, builder: builder));
}

Future<String?> showMediaSourceLogin(
    JsonMap source, Future<void> stopped) async {
  return showNextLogin<String>(
      (_) => _PasswordDialog(source: source, stopped: stopped));
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.source, required this.stopped});
  final JsonMap source;
  final Future<void> stopped;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final password = TextEditingController();
  bool submitted = false;
  @override
  void initState() {
    super.initState();
    widget.stopped.then((_) {
      if (mounted && !submitted) {
        Navigator.of(context).removeRoute(ModalRoute.of(context)!);
      }
    });
  }

  void login() {
    submitted = true;
    Navigator.of(context).pop(password.text);
  }

  void cancel() {
    submitted = true;
    Navigator.of(context).pop();
  }

  String get secretLabel =>
      widget.source['type'] == 'dandanplay_remote' ? 'API 密钥' : '密码';

  @override
  Widget build(BuildContext context) =>
      NextDialogRoute.of(context) ? next() : classic();

  /// The source's name, its address under it, who logs in, the secret.
  Widget next() {
    final username = widget.source['username'] as String? ?? '';
    return NextDialog(
      title: '登录 ${widget.source['name']}',
      subtitle: widget.source['url'] as String?,
      onCancel: cancel,
      body: [
        if (username.isNotEmpty)
          NextDialogField(label: '用户名', value: username),
        NextDialogField(
            label: secretLabel,
            controller: password,
            obscure: true,
            autofocus: true,
            onSubmitted: (_) => login()),
      ],
      actions: [
        NextDialogButton(label: '取消', onTap: cancel),
        NextDialogButton(
            label: '登录', kind: NextDialogButtonKind.primary, onTap: login),
      ],
    );
  }

  Widget classic() => AlertDialog(
        title: Text('登录 ${widget.source['name']}'),
        content: SizedBox(
            width: 400,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  initialValue: widget.source['url'] as String,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: '服务器地址')),
              TextFormField(
                  initialValue: widget.source['username'] as String,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: '用户名')),
              TextField(
                  controller: password,
                  autofocus: true,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: InputDecoration(labelText: secretLabel),
                  onSubmitted: (_) => login()),
            ])),
        actions: [
          TextButton(onPressed: cancel, child: const Text('取消')),
          FilledButton(onPressed: login, child: const Text('登录')),
        ],
      );
  @override
  void dispose() {
    password.clear();
    password.dispose();
    super.dispose();
  }
}

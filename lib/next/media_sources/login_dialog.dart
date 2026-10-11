import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/utils/globals.dart' as globals;
import 'package:window_manager/window_manager.dart';

Future<T?> showNextLogin<T>(Widget Function(BuildContext) builder) async {
  final navigator = globals.navigatorKey.currentState;
  final context = navigator?.overlay?.context;
  if (navigator == null || context == null) {
    throw const Failure(
        FailureCode.unavailable, 'The NipaPlay login window is not ready.');
  }
  if (globals.isDesktop) {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }
  if (!context.mounted) {
    throw const Failure(
        FailureCode.unavailable, 'The NipaPlay login window has closed.');
  }
  // Flutter 3.44 showDialog chooses an experimental native dialog under
  // windowing. Its new FlutterView stays at zero metrics. Use the main view.
  return navigator.push<T>(DialogRoute<T>(
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

  @override
  Widget build(BuildContext context) => AlertDialog(
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
                  decoration: const InputDecoration(labelText: '密码'),
                  onSubmitted: (_) => login()),
            ])),
        actions: [
          TextButton(
              onPressed: () {
                submitted = true;
                Navigator.of(context).pop();
              },
              child: const Text('取消')),
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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../services/file_association_service.dart';
import '../../next_runtime.dart';

/// External file events belong to the mounted Next interface, not a hidden
/// Classic page. Closing Next releases both subscriptions and queued requests.
class NextFileOpenHost extends StatefulWidget {
  const NextFileOpenHost(
      {super.key,
      required this.child,
      this.launchFilePath,
      this.openFile,
      this.fileEvents,
      this.errorEvents});
  final Widget child;
  final String? launchFilePath;
  final Future<void> Function(String path)? openFile;
  final Stream<String>? fileEvents;
  final Stream<String>? errorEvents;

  @override
  State<NextFileOpenHost> createState() => _NextFileOpenHostState();
}

class _NextFileOpenHostState extends State<NextFileOpenHost> {
  StreamSubscription<String>? _files, _errors;
  Future<void> _requests = Future.value();
  String? _error;

  @override
  void initState() {
    super.initState();
    final launch = widget.launchFilePath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (launch != null && launch.isNotEmpty) _enqueue(launch);
      final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
      _files = (widget.fileEvents ??
              (ios ? FileAssociationService.openFileStream : null))
          ?.listen(_enqueue);
      _errors = (widget.errorEvents ??
              (ios ? FileAssociationService.openFileErrorStream : null))
          ?.listen(_showError);
    });
  }

  void _showError(String message) {
    if (mounted) setState(() => _error = message);
  }

  void _enqueue(String path) {
    _requests = _requests.then((_) async {
      if (!mounted) return;
      final open = widget.openFile;
      if (open != null) {
        await open(path);
      } else {
        await context
            .read<NextRuntime>()
            .openExternalFile(path, stillActive: () => mounted);
      }
    }).catchError((Object error) => _showError('无法打开文件：$error'));
  }

  @override
  void dispose() {
    unawaited(_files?.cancel());
    unawaited(_errors?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        widget.child,
        if (_error != null)
          Positioned(
              left: 16,
              right: 16,
              bottom: 20,
              child: GestureDetector(
                  onTap: () => setState(() => _error = null),
                  child: ColoredBox(
                      color: const Color(0xEE262329),
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Color(0xFFFFFFFF))))))),
      ]);
}

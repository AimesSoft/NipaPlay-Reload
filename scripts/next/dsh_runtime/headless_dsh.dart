// The headless host's runtime commands without the host: `install` fetches the
// pinned Node.js and trimmed DeepSeek Harness into <data>/dsh-runtime, `status`
// says which runtime would be launched, `check` starts it with NipaPlay's
// plugins and opens a thread (no model is called).
//
//   dart run scripts/next/dsh_runtime/headless_dsh.dart install|status|check \
//       --data <dir> [--agent-assets assets/next/agent]
//
// The same commands are `--dsh-install`, `--dsh-status` and `--dsh-check` of
// bin/nipaplay_headless.dart.
import 'dart:io';

import 'package:nipaplay/next/headless/dsh.dart';

Future<void> main(List<String> args) async {
  String? option(String name) {
    final i = args.indexOf(name);
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final mode = args.isEmpty ? null : args.first;
  final data = option('--data');
  if (!const {'install', 'status', 'check'}.contains(mode) || data == null) {
    stderr.writeln('usage: headless_dsh.dart install|status|check --data <dir> [--agent-assets <dir>]');
    exitCode = 64;
    return;
  }
  exitCode = await runHeadlessDshCommand(mode!, Directory(data).absolute,
      assets: option('--agent-assets'));
}

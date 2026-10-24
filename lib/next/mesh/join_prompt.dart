import 'package:flutter/material.dart';
import 'package:nipa_harness/nipa_harness.dart' show JsonMap;

import '../media_sources/login_dialog.dart';
import '../ui/widgets/dialog.dart';

/// Asks the person at this screen about a device that has just joined their
/// devices. True: not theirs (it is to be removed). False: theirs. Null:
/// the window could not be shown, or was closed without an answer.
Future<bool?> showMeshJoinPrompt(String name, String? platform) async {
  try {
    return await showNextLogin<bool>(
        (_) => MeshJoinPromptDialog(name: name, platform: platform));
  } catch (_) {
    return null;
  }
}

String _platform(String? platform) => switch (platform) {
      'macos' => 'macOS',
      'ios' => 'iOS',
      'android' => 'Android',
      'windows' => 'Windows',
      'linux' => 'Linux',
      final other? => other,
      null => '',
    };

/// The question itself: in Next's look under a Next dialog route, Classic's
/// dialog otherwise. Pops true (not mine), false (mine), or null (Esc).
class MeshJoinPromptDialog extends StatelessWidget {
  const MeshJoinPromptDialog({super.key, required this.name, required this.platform});
  final String name;
  final String? platform;

  String get _words {
    final kind = _platform(platform);
    return kind.isEmpty ? '“$name”刚刚加入。' : '“$name”（$kind）刚刚加入。';
  }

  @override
  Widget build(BuildContext context) {
    void answer(bool? notMe) => Navigator.of(context).pop(notMe);
    return NextDialogRoute.of(context)
        ? NextDialog(
            title: '有新设备加入',
            subtitle: _words,
            width: 400,
            autofocus: true,
            onCancel: () => answer(null),
            actions: [
              NextDialogButton(label: '是我', onTap: () => answer(false)),
              NextDialogButton(
                  label: '不是我',
                  kind: NextDialogButtonKind.danger,
                  onTap: () => answer(true)),
            ],
          )
        : AlertDialog(
            title: const Text('有新设备加入'),
            content: Text(_words),
            actions: [
              TextButton(onPressed: () => answer(false), child: const Text('是我')),
              FilledButton(
                  onPressed: () => answer(true), child: const Text('不是我')),
            ],
          );
  }
}

/// Puts the question about a device that joined to the person and acts on the
/// answer: “not me” removes the device, “mine” is remembered so it is not asked
/// again. No answer (the window could not be shown, or was closed) is tried a
/// few times and otherwise left for the next start; nothing is decided for the
/// person.
Future<void> answerJoin(
  JsonMap device, {
  required Future<bool?> Function(JsonMap device) prompt,
  required Future<void> Function(String deviceId) remove,
  required Future<void> Function(String deviceId) acknowledge,
  Duration retryAfter = const Duration(seconds: 5),
  int attempts = 4,
}) async {
  final id = device['deviceId'] as String;
  for (var attempt = 0; attempt < attempts; attempt++) {
    if (attempt > 0) await Future<void>.delayed(retryAfter);
    final notMe = await prompt(device);
    if (notMe == null) continue;
    await (notMe ? remove(id) : acknowledge(id));
    return;
  }
}

import 'dart:io';
import 'package:nipa_harness/nipa_harness.dart';

/// A device that can show Next's interface but cannot host Nipa: an iPad.
/// It starts only the body (the capability layer, the player, the Mesh) and
/// does not start the local agent endpoint or a conversation host.
final class NextBody {
  const NextBody._();

  /// Tests set this to run the body-only paths on any host.
  static bool? debugBodyOnly;

  static bool get bodyOnly => debugBodyOnly ?? Platform.isIOS;

  /// What an iPad does not have: no process can be started, nothing runs
  /// programs or conversations, and an iOS application is not quit or
  /// restarted by a program.
  static bool excludes(String id) =>
      const [
        'window.',
        'program.',
        'chat.',
        'agent.',
        'memory.',
      ].any(id.startsWith) ||
      const {'app.quit', 'app.restart'}.contains(id);

  /// The capabilities this device really has.
  static List<Capability> filter(Iterable<Capability> capabilities) =>
      bodyOnly
          ? [for (final capability in capabilities) _Filtered(capability)]
          : capabilities.toList();
}

final class _Filtered implements Capability {
  _Filtered(Capability capability)
      : actions = [
          for (final action in capability.actions)
            if (!NextBody.excludes(action.spec.id)) action,
        ];
  @override
  final List<Action> actions;
}

import 'package:nipa_harness/nipa_harness.dart';
import 'identity_store.dart';

/// Classic file listings carry locations, not work IDs. Playback receipts
/// describe an already resolved source; they are not file discovery.
final class FileIndexingCapability implements Capability {
  FileIndexingCapability(Capability capability, IdentityStore store)
      : actions = [
          for (final action in capability.actions) _IndexFiles(action, store)
        ];
  @override
  final List<Action> actions;
}

final class _IndexFiles extends Action<JsonEncodable, JsonEncodable> {
  const _IndexFiles(this.action, this.store);
  final Action action;
  final IdentityStore store;
  @override
  ActionSpec get spec => action.spec;
  @override
  JsonEncodable decodeInput(JsonMap json) => action.decodeInput(json);
  Future<void> _locations(Object? value) async {
    if (value is Map) {
      for (final entry in value.entries) {
        if ((entry.key == 'path' || entry.key == 'filePath') &&
            entry.value is String &&
            (entry.value as String).isNotEmpty) {
          final path = entry.value as String;
          if (Uri.tryParse(path)?.scheme != 'mesh') {
            await store.ensureFile(path);
          }
        } else {
          await _locations(entry.value);
        }
      }
    } else if (value is List) {
      for (final item in value) {
        await _locations(item);
      }
    }
  }

  @override
  Future<Outcome<JsonEncodable>> run(
      JsonEncodable input, Invocation invocation) async {
    final outcome = await action.run(input, invocation);
    if (spec.id.startsWith('playback.') ||
        spec.id == 'ui.open' ||
        spec.id.startsWith('download.play')) {
      return outcome;
    }
    if (outcome is Completed) await _locations(outcome.value.toJson());
    if (outcome is NeedsDecision) {
      for (final option in outcome.decision.options) {
        await _locations(option.call.input);
      }
    }
    return outcome;
  }
}

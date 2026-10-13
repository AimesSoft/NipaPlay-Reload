import 'package:nipa_harness/nipa_harness.dart';
import 'service.dart';

final class MemoryCapability implements Capability {
  MemoryCapability(HarnessMemory memory)
      : actions = [
          for (final verb in ['list', 'read', 'edit', 'delete', 'context'])
            _MemoryAction(memory, verb),
        ];
  @override
  final List<Action> actions;
}

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _MemoryAction extends Action<_Json, _Json> {
  _MemoryAction(this.memory, this.verb);
  final HarnessMemory memory;
  final String verb;
  @override
  ActionSpec get spec => ActionSpec(
        id: 'memory.$verb',
        title: 'Memory $verb',
        description: switch (verb) {
          'list' =>
            'List Markdown files under harness memory/ with byte sizes and revisions for Nipa 记得的事.',
          'read' =>
            'Read a memory Markdown file. Preferences live in preferences.md, the one-line-per-topic index in MEMORY.md. Secrets are redacted.',
          'edit' =>
            'Replace a memory file using its read revision. Resident files have an 8192 UTF-8 byte limit. Record dates and sources; update changed preferences in place. Settings-backed preferences belong in settings.set with a reason. Secrets are rejected. Commits only this file and records activity.',
          'delete' =>
            'Forget a memory file using its read revision. Commits as the actual caller and records activity. To delete one preference, use memory.edit with the remaining file content. Existing conversation history is retained; the next turn receives a change notice.',
          _ =>
            'Read the current resident preferences, settings with provenance, index and bounded verbatim recent facts. Used by SessionStart; no generated handoff or new transcript store.',
        },
        effect: const {'edit', 'delete'}.contains(verb)
            ? Effect.write
            : Effect.read,
        input: ObjectSchema({
          if (const {'read', 'edit', 'delete'}.contains(verb))
            'path': const StringSchema(minLength: 1),
          if (const {'edit', 'delete'}.contains(verb))
            'revision': const StringSchema(minLength: 1),
          if (verb == 'edit') 'content': const StringSchema(),
          if (verb == 'context') 'threadId': const StringSchema(),
        }, required: [
          if (const {'read', 'edit', 'delete'}.contains(verb)) 'path',
          if (const {'edit', 'delete'}.contains(verb)) 'revision',
          if (verb == 'edit') 'content',
        ]),
        output: const ObjectSchema({}, additionalProperties: true),
      );
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async {
    final data = input.value;
    return Completed(_Json(switch (verb) {
      'list' => {'files': await memory.list()},
      'read' => await memory.read(data['path'] as String),
      'edit' => await memory.edit(data['path'] as String,
          data['content'] as String, data['revision'] as String, invocation),
      'delete' => await memory.delete(
          data['path'] as String, data['revision'] as String, invocation),
      _ => await memory.context(data['threadId'] as String?),
    }));
  }
}

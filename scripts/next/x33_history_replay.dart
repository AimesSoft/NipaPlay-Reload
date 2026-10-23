import 'dart:convert';
import 'dart:io';
import 'package:nipaplay/next/chat/turn_process_store.dart';

Future<void> main(List<String> args) async {
  final root = await Directory.systemTemp.createTemp('x33-history-');
  try {
    final store = TurnProcessStore(Directory('${root.path}/process'));
    final histories = <String, Map>{};
    for (final line in await File(args.single).readAsLines()) {
      final event = jsonDecode(line) as Map;
      final message = Map<String, dynamic>.from(event['m'] as Map);
      store.observe(
          message, 'replay-of-real-host', DateTime.parse(event['t'] as String));
      final result = message['result'];
      if (result is Map && result['thread'] is Map) {
        final thread = result['thread'] as Map;
        if ((thread['turns'] as List).isNotEmpty)
          histories[thread['id'] as String] = thread;
      }
    }
    await store.flush();
    final reopened = TurnProcessStore(store.directory);
    for (final entry in histories.entries) {
      for (final turn in entry.value['turns'] as List) {
        final before = (turn['items'] as List)
            .where((v) =>
                v['type'] == 'agentMessage' || v['type'] == 'userMessage')
            .toList();
        await reopened.restore(entry.key, turn as Map);
        final items = turn['items'] as List;
        final after = items
            .where((v) =>
                v['type'] == 'agentMessage' || v['type'] == 'userMessage')
            .toList();
        if (jsonEncode(before) != jsonEncode(after))
          throw StateError('messages changed');
        final commands =
            items.where((v) => v['type'] == 'commandExecution').length;
        final summaries = items.where((v) => v['type'] == 'reasoning').length;
        if (commands != 1 || summaries != 2)
          throw StateError('duplicate process');
        print(jsonEncode({
          'threadId': entry.key,
          'turnId': turn['id'],
          'commands': commands,
          'summaries': summaries,
          'messagesPreserved': true
        }));
      }
    }
  } finally {
    await root.delete(recursive: true);
  }
}

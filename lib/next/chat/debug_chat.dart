import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import '../../utils/lab_profile.dart';
import '../harness_redaction.dart';
import 'chat_host.dart';

/// VM-service-only lab driver. Absent from the harness catalog and release builds.
void installDebugChat(ChatHost? Function() current) {
  registerExtension('ext.nipaplay.chat', (_, params) async {
    try {
      final host = current();
      if (host == null) throw StateError('Chat host not running');
      final Object? result;
      switch (params['op']) {
        case 'start':
          result = await host.startThread();
        case 'main':
          result = await host.getMainSession();
        case 'sessions':
          result = await host.listSessions(cursor: params['cursor']);
        case 'resume':
          result = await host.resumeThread(params['threadId']!);
        case 'list':
          result = await host.listThreads(cursor: params['cursor']);
        case 'turn':
          result = await host.startTurn(params['text']!);
        case 'steer':
          result = await host.steer(params['text']!, onThread: params['threadId']);
        case 'interrupt':
          result = await host.interrupt(onThread: params['threadId']);
        case 'answer':
          final answers = jsonDecode(params['answers']!) as Map;
          await host.answerUserInput(jsonDecode(params['id']!), {
            for (final entry in answers.entries)
              entry.key as String: List<String>.from(entry.value as List)
          });
          result = {};
        case 'status':
          result = {
            'header': host.header,
            'liveness': host.liveness.snapshot(DateTime.now()),
            'threads': {for (final entry in host.threadLiveness.entries)
              entry.key: entry.value.snapshot(DateTime.now())},
            'environment': host.launchEnvironment
          };
        case 'read':
          result = await host.readThread(params['threadId']!);
        case 'close':
          await host.close();
          result = {'closed': true};
        default:
          throw ArgumentError('Unknown debug operation');
      }
      return ServiceExtensionResponse.result(
          jsonEncode(redactHarnessJson(result)));
    } catch (error) {
      return ServiceExtensionResponse.error(
          ServiceExtensionResponse.extensionError,
          redactHarnessText(error.toString()));
    }
  });
}

void recordDebugChat(ChatHost host) {
  final events = File(LabProfile.location('chat-events.jsonl'));
  host.events.listen((message) => events.writeAsStringSync(
      '${jsonEncode({'t': DateTime.now().toIso8601String(), 'm': message})}\n',
      mode: FileMode.append));
}

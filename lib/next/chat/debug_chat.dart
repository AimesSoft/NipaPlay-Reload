import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import '../../utils/lab_profile.dart';
import '../harness_redaction.dart';
import 'package:nipa_harness/nipa_harness.dart' show Invocation;
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
        case 'compact':
          result = await host.compactThread(params['threadId']!);
        case 'hooks':
          result = await host.listHooks();
        case 'memoryEdit':
          result = await host.memory!.edit(params['path']!, params['content']!,
              params['revision']!, Invocation(origin: 'gui'));
        case 'memoryDelete':
          result = await host.memory!.delete(params['path']!, params['revision']!,
              Invocation(origin: 'gui'));
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

/// Appends every host event to the lab's chat-events.jsonl, in order. The
/// events (a whole thread read back among them) are encoded and written by a
/// background isolate.
void recordDebugChat(ChatHost host) {
  final path = LabProfile.location('chat-events.jsonl');
  final waiting = <Object?>[];
  SendPort? writer;
  void send(Object? entry) =>
      writer == null ? waiting.add(entry) : writer!.send(entry);
  final ready = ReceivePort();
  ready.listen((port) {
    writer = port as SendPort;
    waiting.forEach(port.send);
    waiting.clear();
    ready.close();
  });
  unawaited(Isolate.spawn(_appendEvents, (ready.sendPort, path),
      debugName: 'chat-events'));
  host.events.listen(
      (message) => send((DateTime.now().toIso8601String(), message)),
      onDone: () => send(null));
}

void _appendEvents((SendPort, String) setup) {
  final (ready, path) = setup;
  final file = File(path).openSync(mode: FileMode.append);
  final port = ReceivePort();
  port.listen((entry) {
    if (entry case (String at, Object? message)) {
      file.writeStringSync('${jsonEncode({'t': at, 'm': message})}\n');
    } else {
      file.closeSync();
      port.close();
    }
  });
  ready.send(port.sendPort);
}

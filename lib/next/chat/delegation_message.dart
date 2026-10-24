import 'dart:convert';

import '../harness_redaction.dart';

/// What opens a delegated turn's first message, for the host that sent it and
/// for the conversation view that shows it.
const delegationMarker = '[NipaPlay 委托';

const _note = '这是那台设备上的 Nipa 写给你的任务，你的最后一条回复会回到她那里。'
    '这台设备上的人随时能看到这段对话，也可以插话。';

/// The first message of a delegated turn: where it came from, then the task
/// as the sending Nipa wrote it, then what she referred to.
String delegationMessage(String id, String from, String text, List? refs) {
  final buffer = StringBuffer()
    ..writeln('$delegationMarker $id]')
    ..writeln('来自 $from 上的 Nipa 的委托。')
    ..writeln(_note)
    ..writeln()
    ..write(text.trimRight());
  if (refs != null && refs.isNotEmpty) {
    buffer
      ..writeln()
      ..writeln()
      ..writeln('对方带来的引用（原样，未经核对）：');
    for (final ref in refs) {
      buffer.writeln('- ${jsonEncode(publicHarnessFacts(ref))}');
    }
  }
  return buffer.toString().trimRight();
}

/// [message] as the person reads it: where it came from and the task, without
/// the marker line and the standing note.
String showDelegation(String message) {
  if (!message.startsWith(delegationMarker)) return message;
  final lines = message.split('\n');
  return [
    for (final (i, line) in lines.indexed)
      if (i != 0 && line != _note) line
  ].join('\n').trim();
}

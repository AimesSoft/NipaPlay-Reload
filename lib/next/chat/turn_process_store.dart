import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../harness_redaction.dart';

/// Bounded, redacted execution facts, separate from Codex's transcript.
final class TurnProcessStore {
  static File fileFor(Directory root, String harnessPath) => File(
      '${root.path}/turn-process/${sha256.convert(utf8.encode(harnessPath))}.json');
  TurnProcessStore(this.file,
      {this.maxTurns = 60, this.maxBytes = 4 * 1024 * 1024}) {
    if (file.existsSync()) {
      _turns.addAll((jsonDecode(file.readAsStringSync()) as List)
          .map((v) => Map<String, dynamic>.from(v as Map)));
    }
  }

  final File file;
  final int maxTurns, maxBytes;
  final _turns = <Map<String, dynamic>>[];

  Map<String, dynamic>? read(String threadId, String turnId) {
    final row = _turns
        .where((t) => t['threadId'] == threadId && t['turnId'] == turnId)
        .firstOrNull;
    return row == null
        ? null
        : jsonDecode(jsonEncode(row)) as Map<String, dynamic>;
  }

  void restore(String threadId, Map turn) {
    final saved = read(threadId, turn['id'] as String);
    if (saved == null) return;
    turn['items'] = [
      for (final item in turn['items'] as List)
        if (item['type'] != 'commandExecution' && item['type'] != 'reasoning')
          item,
      ...saved['items'] as List,
    ];
    turn['durationMs'] ??= saved['durationMs'];
  }

  void observe(Map<String, dynamic> message, String origin, DateTime now) {
    final method = message['method'];
    final params = message['params'];
    if (params is! Map) return;
    final thread = params['threadId'];
    final turn = method == 'turn/started' || method == 'turn/completed'
        ? params['turn']['id']
        : params['turnId'];
    if (thread is! String || turn is! String) return;
    var row = _turns
        .where((t) => t['threadId'] == thread && t['turnId'] == turn)
        .firstOrNull;
    if (method == 'turn/started') {
      row ??= {
        'threadId': thread,
        'turnId': turn,
        'origin': origin,
        'startedAt': now.toUtc().toIso8601String(),
        'status': 'inProgress',
        'items': <dynamic>[]
      };
      if (!_turns.contains(row)) _turns.add(row);
    } else if (row == null) {
      return;
    } else if (method == 'turn/completed') {
      row['status'] = params['turn']['status'];
      row['endedAt'] = now.toUtc().toIso8601String();
      row['durationMs'] = now
          .difference(DateTime.parse(row['startedAt'] as String))
          .inMilliseconds;
    } else if (method == 'item/started' || method == 'item/completed') {
      final item = params['item'] as Map;
      if (item['type'] != 'commandExecution' && item['type'] != 'reasoning')
        return;
      final items = row['items'] as List;
      final index = items.indexWhere((v) => v['id'] == item['id']);
      if (index < 0 && items.length >= 128) {
        row['truncated'] = true;
        return;
      }
      final previous = index < 0 ? null : items[index] as Map;
      String clip(Object? value, int limit) {
        final text = redactHarnessText(
            value is List ? value.join(' ') : '${value ?? ''}');
        if (text.runes.length <= limit) return text;
        row!['truncated'] = true;
        return '${String.fromCharCodes(text.runes.take(limit))}…';
      }

      final safe = <String, dynamic>{
        'id': item['id'],
        'type': item['type'],
        'status': item['status'],
        'startedAt': previous?['startedAt'] ?? now.toUtc().toIso8601String(),
        if (method == 'item/completed')
          'endedAt': now.toUtc().toIso8601String(),
        if (item['type'] == 'commandExecution') ...{
          'command': clip(item['command'], 4096),
          'exitCode': item['exitCode'],
          'durationMs': item['durationMs'] ??
              (method == 'item/completed'
                  ? now
                      .difference(DateTime.parse(
                          previous?['startedAt'] as String? ??
                              now.toIso8601String()))
                      .inMilliseconds
                  : null),
          'aggregatedOutput': clip(item['aggregatedOutput'], 8192),
        },
        if (item['type'] == 'reasoning')
          'summary': [
            for (final part in (item['summary'] as List? ?? const []).take(8))
              {
                'type': 'summary_text',
                'text': clip(part is Map ? part['text'] : part, 2048)
              }
          ],
      };
      if (index < 0) {
        items.add(safe);
      } else {
        items[index] = safe;
      }
    } else {
      return;
    }
    _save();
  }

  void _save() {
    while (_turns.length > maxTurns) {
      _turns.removeAt(0);
    }
    var encoded = jsonEncode(_turns);
    while (utf8.encode(encoded).length > maxBytes && _turns.isNotEmpty) {
      _turns.removeAt(0);
      encoded = jsonEncode(_turns);
    }
    file.parent.createSync(recursive: true);
    final temp = File('${file.path}.tmp');
    temp.writeAsStringSync(encoded, flush: true);
    temp.renameSync(file.path);
  }
}

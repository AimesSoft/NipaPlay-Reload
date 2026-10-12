import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';

import '../harness_redaction.dart';

/// Bounded, redacted execution facts, separate from Codex's transcript.
final class TurnProcessStore {
  /// What the store keeps itself; Codex's history keeps the rest.
  static const _process = {
    'commandExecution',
    'reasoning',
    'collabAgentToolCall',
  };

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

  /// Puts the saved process back into Codex's [turn], in the order it
  /// happened: saved markers stand for Codex's own items (messages, tools),
  /// matched by type in order.
  void restore(String threadId, Map turn) {
    final saved = read(threadId, turn['id'] as String);
    if (saved == null) return;
    bool own(Object? item) => item is Map && !_process.contains(item['type']);
    final codex = [
      for (final item in turn['items'] as List)
        if (own(item)) item as Map
    ];
    final process = saved['items'] as List;
    if (!process.any((v) => v is Map && v['marker'] == true)) {
      turn['items'] = [...codex, ...process];
    } else {
      final byType = <Object?, List<Map>>{};
      for (final item in codex) {
        (byType[item['type']] ??= []).add(item);
      }
      final used = <Object?, int>{};
      final merged = <Object?>[];
      for (final v in process.cast<Map>()) {
        if (v['marker'] != true) {
          merged.add(v);
          continue;
        }
        final list = byType[v['type']] ?? const [];
        final i = used[v['type']] ?? 0;
        if (i < list.length) {
          merged.add(list[i]);
          used[v['type']] = i + 1;
        }
      }
      final seen = <Object?, int>{};
      for (final item in codex) {
        final i = seen[item['type']] ?? 0;
        seen[item['type']] = i + 1;
        if (i >= (used[item['type']] ?? 0)) merged.add(item);
      }
      turn['items'] = merged;
    }
    if (turn['durationMs'] == null && saved['durationMs'] != null) {
      turn['durationMs'] = saved['durationMs'];
    }
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
      final items = row['items'] as List;
      final index = items.indexWhere((v) => v['id'] == item['id']);
      if (!_process.contains(item['type'])) {
        // Where Codex's own item came, without its content.
        if (index >= 0 || items.length >= 128) return;
        items.add({'id': item['id'], 'type': item['type'], 'marker': true});
        _save();
        return;
      }
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
        // A helper sent off: what it was asked and where it works.
        if (item['type'] == 'collabAgentToolCall') ...{
          'tool': item['tool'],
          'prompt': clip(item['prompt'], 4096),
          'receiverThreadIds': [
            for (final id in (item['receiverThreadIds'] as List? ?? const [])
                .take(8))
              '$id'
          ],
        },
        if (item['type'] == 'reasoning') ...{
          'summary': [
            for (final part in (item['summary'] as List? ?? const []).take(8))
              {
                'type': 'summary_text',
                'text': clip(part is Map ? part['text'] : part, 2048)
              }
          ],
          // Models that think without a summary keep their thinking here.
          if ((item['summary'] as List? ?? const []).isEmpty)
            'content': [
              for (final part in (item['content'] as List? ?? const []).take(8))
                clip(part is Map ? part['text'] : part, 4096)
            ],
        },
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

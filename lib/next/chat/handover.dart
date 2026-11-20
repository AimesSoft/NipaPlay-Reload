import 'dart:convert';
import 'dart:isolate';

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

typedef ConversationJson = Map<String, dynamic>;

Future<R> _work<T, R>(T input, R Function(T) run) =>
    Isolate.run(() => run(input));

Future<List<ConversationJson>> projectHandover(List<ConversationTurn> turns) =>
    _work(turns, (input) => input.map((turn) => turn.project()).toList());

Future<String> _encodeTurn(ConversationTurn turn) =>
    _work(turn, (input) => jsonEncode(input.toJson()));

Future<String> _encodePrefix(List<ConversationTurn> turns) =>
    _work(turns, jsonEncode);

Future<List<ConversationTurn>> _decodePrefix(String encoded) => _work(
    encoded,
    (input) => (jsonDecode(input) as List)
        .map((row) => ConversationTurn.decode(row as Map))
        .toList());

Future<void> migrateHandover(Database db) async {
  await db.execute('''CREATE TABLE IF NOT EXISTS conversation_turns (
    sequence INTEGER PRIMARY KEY AUTOINCREMENT, thread TEXT NOT NULL,
    turn TEXT NOT NULL, record TEXT NOT NULL, UNIQUE(thread, turn))''');
  await db.execute('''CREATE TABLE IF NOT EXISTS conversation_prefixes (
    thread TEXT PRIMARY KEY, record TEXT NOT NULL)''');
}

final class ConversationTurn {
  ConversationTurn(this.id, this.status, this.items);
  final String id;
  final String status;
  final List<ConversationJson> items;

  factory ConversationTurn.decode(Map record) {
    if (record['version'] != 1)
      throw const FormatException('Unknown conversation version');
    return ConversationTurn(record['id'] as String, record['status'] as String,
        (record['items'] as List).cast<ConversationJson>());
  }

  ConversationJson toJson() => {
        'version': 1,
        'id': id,
        'status': status,
        'items': items,
      };

  static ConversationJson message(String role, String text) => {
        'type': 'message',
        'role': role,
        'content': [
          {'type': role == 'user' ? 'input_text' : 'output_text', 'text': text}
        ],
      };

  static const omitted = '［部分非文本内容未交接］';
  static const incomplete = '［工具调用未完成，未重新执行］';
  static const truncated = '［较早的对话未纳入新运行器的上下文］';
  static const missingTool = '［运行器未提供原始工具记录］';

  static ConversationJson? displayItem(Map item) => switch (item['type']) {
        'agentMessage' when item['text'] is String =>
          message('assistant', item['text'] as String),
        'commandExecution' ||
        'dynamicToolCall' ||
        'mcpToolCall' ||
        'fileChange' ||
        'webSearch' ||
        'collabAgentToolCall' =>
          message('assistant', missingTool),
        _ => capture(item, raw: false),
      };

  static String text(Object? content, Set<String> kinds) {
    if (content is String) return content;
    if (content is! List) return omitted;
    return content
        .map((part) => part is Map &&
                kinds.contains(part['type']) &&
                part['text'] is String
            ? part['text'] as String
            : omitted)
        .join('\n');
  }

  static ConversationJson? capture(Map item, {required bool raw}) {
    if (!raw) {
      return switch (item['type']) {
        'userMessage' => message('user', text(item['content'], {'text'})),
        _ => null,
      };
    }
    switch (item['type']) {
      case 'message':
        if (item['role'] == 'assistant') {
          return message('assistant', text(item['content'], {'output_text'}));
        }
      case 'function_call':
        if (item['call_id'] is String &&
            item['name'] is String &&
            item['arguments'] is String) {
          return {
            'type': 'function_call',
            'call_id': item['call_id'],
            'name': item['name'],
            'arguments': item['arguments']
          };
        }
        return message('assistant', incomplete);
      case 'function_call_output':
        if (item['call_id'] is String) {
          return {
            'type': 'function_call_output',
            'call_id': item['call_id'],
            'output':
                text(item['output'], {'input_text', 'output_text', 'text'}),
            if (item['failed'] == true) 'failed': true
          };
        }
      case 'custom_tool_call':
      case 'custom_tool_call_output':
      case 'local_shell_call':
      case 'web_search_call':
      case 'image_generation_call':
        return message('assistant', '［此运行器的专有工具条目未交接］');
    }
    return null;
  }

  ConversationJson project() {
    final calls = <String, ConversationJson>{};
    final result = <ConversationJson>[];
    for (final (index, item) in items.indexed) {
      final itemId = '$id-handover-$index';
      switch (item['type']) {
        case 'message':
          final content = text(item['content'], {'input_text', 'output_text'});
          result.add(item['role'] == 'user'
              ? {
                  'type': 'userMessage',
                  'id': itemId,
                  'content': [
                    {'type': 'text', 'text': content}
                  ]
                }
              : {'type': 'agentMessage', 'id': itemId, 'text': content});
        case 'function_call':
          final projected = <String, dynamic>{
            'type': 'dynamicToolCall',
            'id': itemId,
            'tool': item['name'],
            'arguments': item['arguments'],
            'status': 'failed',
            'contentItems': [
              {'type': 'inputText', 'text': incomplete}
            ]
          };
          calls[item['call_id'] as String] = projected;
          result.add(projected);
        case 'function_call_output':
          final call = calls.remove(item['call_id']);
          if (call == null) continue;
          call['success'] = item['failed'] != true;
          call['status'] = item['failed'] == true ? 'failed' : 'completed';
          call['contentItems'] = [
            {'type': 'inputText', 'text': item['output']}
          ];
      }
    }
    return {'id': id, 'status': status, 'items': result};
  }
}

final class HandoverPayload {
  HandoverPayload(this.turns, this.context, this.wasTruncated);
  final List<ConversationTurn> turns;
  final List<List<ConversationJson>> context;
  final bool wasTruncated;

  static HandoverPayload build(List<ConversationTurn> turns,
      {int byteLimit = 12000}) {
    final accepted = <List<ConversationJson>>[];
    var remaining = byteLimit;
    for (final turn in turns.reversed) {
      final items = _paired(turn.items);
      if (items.isEmpty) continue;
      remaining -= utf8.encode(jsonEncode(items)).length;
      if (remaining < 0) break;
      accepted.add(items);
    }
    final truncated = remaining < 0;
    return HandoverPayload(
        turns,
        [
          if (truncated)
            [ConversationTurn.message('assistant', ConversationTurn.truncated)],
          ...accepted.reversed,
        ],
        truncated);
  }

  static List<ConversationJson> _paired(List<ConversationJson> items) {
    final counts = <Object?, int>{};
    final outputs = <Object?, int>{};
    final pending = <Object?, int>{};
    for (final (index, item) in items.indexed) {
      final id = item['call_id'];
      if (item['type'] == 'function_call') {
        counts[id] = (counts[id] ?? 0) + 1;
        pending[id] = index;
      } else if (item['type'] == 'function_call_output' &&
          pending.containsKey(id)) {
        outputs[id] = (outputs[id] ?? 0) + 1;
      }
    }
    // A placeholder for a call without its result, and a message that sits
    // between a paired call and its output, wait until no paired call is
    // open, so every call is followed by its output before anything else.
    final result = <ConversationJson>[];
    final open = <Object?>{};
    final deferred = <ConversationJson>[];
    var incomplete = false;
    void settle() {
      if (open.isNotEmpty) return;
      if (incomplete) {
        result.add(
            ConversationTurn.message('assistant', ConversationTurn.incomplete));
        incomplete = false;
      }
      result.addAll(deferred);
      deferred.clear();
    }

    for (final (index, item) in items.indexed) {
      final id = item['call_id'];
      if (item['type'] == 'message') {
        if (open.isEmpty) {
          settle();
          result.add(item);
        } else {
          deferred.add(item);
        }
      } else if (counts[id] == 1 &&
          outputs[id] == 1 &&
          (item['type'] == 'function_call' || index > pending[id]!)) {
        result.add(item);
        if (item['type'] == 'function_call') {
          open.add(id);
        } else {
          open.remove(id);
          settle();
        }
      } else if (item['type'] == 'function_call') {
        incomplete = true;
        settle();
      }
    }
    open.clear();
    settle();
    return result;
  }

  Iterable<ConversationJson> get responses sync* {
    for (final turn in context) {
      for (final item in turn) {
        if (item['type'] == 'function_call_output' && item['failed'] == true) {
          yield {...item}..remove('failed');
        } else {
          yield item;
        }
      }
    }
  }
}

final class ConversationHistory {
  ConversationHistory(this.db);
  final Database db;
  final _active = <String,
      ({
    String id,
    List<ConversationJson> wire,
    List<ConversationJson> display
  })>{};
  Future<void> _writes = Future.value();
  Object? _writeError;

  void observe(String method, String thread, Map params) {
    switch (method) {
      case 'turn/started':
        if (params['turn'] case {'id': final String id})
          _active[thread] = (id: id, wire: [], display: []);
      case 'rawResponseItem/completed':
      case 'item/completed':
        final active = _active[thread];
        if (active == null ||
            active.id != params['turnId'] ||
            params['item'] is! Map) return;
        final item = params['item'] as Map;
        final raw = method == 'rawResponseItem/completed';
        if (ConversationTurn.capture(item, raw: raw) case final captured?) {
          active.wire.add(captured);
        }
        if (!raw) {
          if (ConversationTurn.displayItem(item) case final display?) {
            active.display.add(display);
          }
        }
      case 'turn/completed':
        if (params['turn']
            case {'id': final String id, 'status': final String status}) {
          final active = _active.remove(thread);
          if (active == null || active.id != id) return;
          final hasRaw = active.wire.any((item) => item['role'] != 'user');
          final turn = ConversationTurn(
              id, status, hasRaw ? active.wire : active.display);
          _writes = _writes.then((_) async {
            final encoded = await _encodeTurn(turn);
            await db.insert('conversation_turns',
                {'thread': thread, 'turn': id, 'record': encoded},
                conflictAlgorithm: ConflictAlgorithm.ignore);
          }).catchError((Object error) {
            _writeError ??= error;
          });
        }
    }
  }

  Future<void> flush() async {
    await _writes;
    if (_writeError case final error?) throw error;
  }

  Future<List<ConversationTurn>> prefix(String thread) async {
    final rows = await db
        .query('conversation_prefixes', where: 'thread=?', whereArgs: [thread]);
    if (rows.isEmpty) return [];
    final encoded = rows.single['record'] as String;
    return _decodePrefix(encoded);
  }

  Future<HandoverPayload> prepare(String thread, List<Map> native) async {
    await flush();
    final previous = await prefix(thread);
    final rows = await db.query('conversation_turns',
        columns: ['record'],
        where: 'thread=?',
        whereArgs: [thread],
        orderBy: 'sequence');
    return _merge((previous, rows, native));
  }

  static Future<HandoverPayload> _merge(
      (List<ConversationTurn>, List<Map<String, Object?>>, List<Map>) input) {
    return _work(input, (parts) {
      final (previous, rows, native) = parts;
      final captured = <String, ConversationTurn>{};
      for (final row in rows) {
        final turn =
            ConversationTurn.decode(jsonDecode(row['record'] as String) as Map);
        captured[turn.id] = turn;
      }
      final merged = <ConversationTurn>[...previous];
      final seen = previous.map((turn) => turn.id).toSet();
      for (final row in native) {
        final id = row['id'] as String;
        if (!seen.add(id)) continue;
        final live = captured.remove(id);
        merged.add(live ??
            ConversationTurn(id, row['status'] as String? ?? 'completed', [
              for (final item
                  in (row['items'] as List? ?? const []).whereType<Map>())
                if (item['type'] == 'agentMessage' && item['text'] is String)
                  ConversationTurn.message('assistant', item['text'] as String)
                else if (ConversationTurn.capture(item, raw: false)
                    case final message?)
                  message,
              ConversationTurn.message('assistant', '［这是旧版对话，未保存可交接的工具记录］'),
            ]));
      }
      merged.addAll(captured.values);
      return HandoverPayload.build(merged);
    });
  }

  Future<void> promote(String repository, String thread,
      HandoverPayload payload, Future<void> Function() saveRuntime) async {
    final turns = [
      ...payload.turns,
      if (payload.wasTruncated)
        ConversationTurn('$thread-context', 'completed', [
          ConversationTurn.message('assistant', ConversationTurn.truncated)
        ]),
    ];
    final encoded = await _encodePrefix(turns);
    await db.transaction((tx) async {
      await tx.insert(
          'conversation_prefixes', {'thread': thread, 'record': encoded});
      await tx.rawInsert(
          '''INSERT INTO harness_sessions (repository, main_thread, current_thread)
        VALUES (?,?,?) ON CONFLICT(repository) DO UPDATE SET
        main_thread=excluded.main_thread, current_thread=excluded.current_thread''',
          [repository, thread, thread]);
      await saveRuntime();
    });
  }
}

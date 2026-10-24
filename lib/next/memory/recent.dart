import 'dart:collection';
import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import '../chat/chat_host.dart';
import '../harness_redaction.dart';
import 'capability_changes.dart';
import 'service.dart';

/// Reads only tasks that can still run. Listing every terminal task just to
/// discard it made memory context grow with the whole task history.
Future<List<JsonMap>> activeJobFacts(TaskEngine engine) async {
  final jobs = <JsonMap>[];
  for (final state in JobState.values.where((state) => !state.isTerminal)) {
    for (final job in await engine.list(state: state)) {
      jobs.add(job.toJson());
    }
  }
  return jobs;
}

/// Field projections of existing facts, in their original order and wording.
Future<JsonMap> recentMemoryFacts(ConversationHistory host, List<JsonMap> jobs,
    List<JsonMap> followups, List<JsonMap> activity, String? current,
    {List<JsonMap> finishedHelpers = const [],
    List<JsonMap> capabilityChanges = const [],
    Future<String> Function(String)? redact}) async {
  String? source;
  final messages = ListQueue<JsonMap>();
  var olderMessagesOmitted = false;

  final sessions = await host.listThreads(limit: 30, sortKey: 'updated_at');
  final candidates = [
    ...sessions['data'] as List,
    // A newly selected provider home has no index for the resumed main rollout.
    if (host.mainThreadId case final id?)
      if (!(sessions['data'] as List).any((row) => row['id'] == id)) {'id': id},
  ].take(30);
  for (final row in candidates) {
    if (host.threadOrigins.containsKey(row['id'])) {
      continue;
    }
    final thread =
        await host.readThread(row['id'] as String, withProcess: false);
    // Read back from the end and stop after the six lines that will be kept.
    // The old code walked every turn of a long thread just to discard all but
    // its tail; this work must not grow with the conversation.
    final newestFirst = <JsonMap>[];
    final turns = thread['turns'] as List;
    outer:
    for (var turnIndex = turns.length - 1; turnIndex >= 0; turnIndex--) {
      final items = (turns[turnIndex]['items'] as List);
      for (var itemIndex = items.length - 1; itemIndex >= 0; itemIndex--) {
        final item = items[itemIndex];
        if (item['type'] == 'userMessage') {
          final content = item['content'] as List;
          for (var partIndex = content.length - 1;
              partIndex >= 0;
              partIndex--) {
            final part = content[partIndex];
            if (part['type'] == 'text') {
              newestFirst.add({'role': 'user', 'text': part['text']});
              if (newestFirst.length == 6) break outer;
            }
          }
        } else if (item['type'] == 'agentMessage') {
          newestFirst.add({'role': 'assistant', 'text': item['text']});
          if (newestFirst.length == 6) break outer;
        }
      }
    }
    if (newestFirst.isNotEmpty) {
      messages.addAll(newestFirst.reversed);
      olderMessagesOmitted = newestFirst.length == 6;
      source = row['id'] as String;
      break;
    }
  }
  final sections = <(String, String, int)>[
    ('最近会话 ${source ?? '无'} 最后几句话', jsonEncode(messages.toList()), 1250),
    (
      '未结束任务',
      jsonEncode(jobs
          .map((r) => {
                for (final key in [
                  'jobId',
                  'type',
                  'state',
                  'title',
                  'phase',
                  'origin',
                  'currentActivity'
                ])
                  if (r.containsKey(key)) key: r[key],
              })
          .toList()),
      500
    ),
    (
      '未结束后续',
      jsonEncode(followups
          .map((r) => {
                for (final key in [
                  'id',
                  'title',
                  'state',
                  'instruction',
                  'waitingFor',
                  'threadId'
                ])
                  if (r.containsKey(key)) key: r[key],
              })
          .toList()),
      400
    ),
    (
      '最近动态',
      jsonEncode(activity
          .take(5)
          .map((r) => {
                for (final key in ['at', 'title', 'actor', 'type', 'facts'])
                  if (r.containsKey(key)) key: r[key],
              })
          .toList()),
      450
    ),
    // 动态 lists every step; what a subagent or a background turn concluded
    // is its receipt.
    (
      '最近办完的后台任务',
      jsonEncode(finishedHelpers
          .map((r) => {
                for (final key in ['title', 'state', 'updatedAt'])
                  if (r.containsKey(key)) key: r[key],
                if (((r['receipt'] as Map?)?['details'] as Map?)?['summary']
                    case final summary?)
                  'summary': summary,
              })
          .toList()),
      900
    ),
    // Only when the last launches changed the capability catalogue.
    if (capabilityChanges.isNotEmpty)
      (
        'NipaPlay 更新',
        capabilityChanges.map(CapabilityCatalogChanges.describe).join('\n'),
        450
      ),
  ];
  final omitted = <String>[];
  final output = <String>[];
  for (final (label, raw, limit) in sections) {
    final runes = raw.runes.toList();
    final cut = runes.length > limit;
    final tail = label.startsWith('最近会话');
    final side = tail ? '开头' : '尾部';
    if (cut) omitted.add('$label $side ${runes.length - limit} 字符');
    final snippet =
        tail && cut ? runes.skip(runes.length - limit) : runes.take(limit);
    output.add('$label：\n${String.fromCharCodes(snippet)}'
        '${cut ? '\n[截断：此节$side ${runes.length - limit} 字符未注入]' : ''}');
  }
  if (olderMessagesOmitted) {
    omitted.add('较早的会话只保留最后 6 句话');
  }
  if (activity.length > 5) omitted.add('较早的 ${activity.length - 5} 条动态');
  if (sessions['nextCursor'] != null) {
    omitted.add('30 个会话之外的历史未扫描');
  }
  final text = await (redact?.call(output.join('\n')) ??
      redactHarnessTextOffMain(output.join('\n')));
  assert(text.runes.length <= HarnessMemory.recentCharacters);
  return {
    'text': text,
    'sourceThreadId': source,
    'truncated': omitted.isNotEmpty,
    'omitted': omitted,
    'limits': {
      'characters': HarnessMemory.recentCharacters,
      'messages': 6,
      'activity': 5,
      'sessionsScanned': 30
    }
  };
}

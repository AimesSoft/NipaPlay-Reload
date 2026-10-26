import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/memory/recent.dart';
import 'package:nipaplay/next/memory/service.dart';

void main() {
  test('harness notice stays visible within the worst-case memory budget',
      () async {
    final long = '字' * 10000;
    final facts = await recentMemoryFacts(
        _Thread([long]),
        [
          {'title': long}
        ],
        [
          {'title': long}
        ],
        [
          {'title': long}
        ],
        null,
        finishedHelpers: [
          {'title': long}
        ],
        capabilityChanges: [
          {
            'at': '2026-10-26',
            'families': {
              long: {
                'added': [long],
                'removed': [],
                'changed': []
              }
            }
          }
        ],
        harnessUpdate: {
          'state': 'conflict',
          'reason': '请检查官方更新冲突',
          'checkedAt': '2026-10-26',
          'paths': [long]
        });
    final text = facts['text'] as String;
    expect(text, contains('Harness 官方更新'));
    expect(text, contains('conflict'));
    expect(text, contains('请检查官方更新冲突'));
    expect(
        text.runes.length, lessThanOrEqualTo(HarnessMemory.recentCharacters));
    expect(facts['truncated'], true);
  });
  Future<Map<String, Object?>> recent(List<String> userTexts) =>
      recentMemoryFacts(_Thread(userTexts), [], [], [], null);

  test('the omitted flag says whether older lines exist, not whether six did',
      () async {
    final six = await recent([for (var i = 0; i < 6; i++) 'line $i']);
    expect(six['omitted'], isEmpty);
    expect(six['truncated'], false);
    final seven = await recent([for (var i = 0; i < 7; i++) 'line $i']);
    expect(seven['omitted'], ['较早的会话只保留最后 6 句话']);
    final text = seven['text'] as String;
    expect(text, contains('line 6'));
    expect(text, contains('line 1'));
    expect(text, isNot(contains('line 0')));
  });

  test('a private key block is redacted before anything is cut', () async {
    final key = '-----BEGIN PRIVATE KEY-----\n${'A' * 1500}\n'
        '-----END PRIVATE KEY-----';
    final facts = await recent(['before', key]);
    final text = facts['text'] as String;
    expect(text, isNot(contains('BEGIN PRIVATE KEY')));
    expect(text, isNot(contains('AAAAAAAAAA')));
    expect(text, contains('[redacted private key]'));
  });
}

final class _Thread implements ConversationHistory {
  _Thread(this.texts);
  final List<String> texts;
  @override
  String? get mainThreadId => 't';
  @override
  Map<String, String> get threadOrigins => {};
  @override
  Future<Map<String, dynamic>> listThreads(
          {String? cursor,
          int limit = 30,
          List<String>? sourceKinds,
          String? sortKey}) async =>
      {
        'data': [
          {'id': 't'}
        ],
        'nextCursor': null
      };
  @override
  Future<Map<String, dynamic>> readThread(String id,
          {bool withProcess = true}) async =>
      {
        'turns': [
          {
            'items': [
              for (final text in texts)
                {
                  'type': 'userMessage',
                  'content': [
                    {'type': 'text', 'text': text}
                  ]
                }
            ]
          }
        ]
      };
}

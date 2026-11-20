import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/chat/handover.dart';
import 'package:nipaplay/next/chat/session_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('交接只保留白名单内容，工具调用及其结果不可分割', () {
    final user = ConversationTurn.capture({
      'type': 'userMessage',
      'content': [
        {'type': 'text', 'text': '用户'},
        {'type': 'image', 'url': 'private'}
      ],
    }, raw: false)!;
    final call = {
      'type': 'function_call',
      'call_id': 'call_test',
      'name': 'nipa',
      'arguments': '{ "action": "system.info" }'
    };
    final result = ConversationTurn.capture({
      'type': 'function_call_output',
      'call_id': 'call_test',
      'output': [
        {'type': 'input_text', 'text': '结果'},
        {'type': 'input_image', 'url': 'private'}
      ],
    }, raw: true)!;
    expect(
        ConversationTurn.capture({'type': 'message', 'role': 'developer'},
            raw: true),
        isNull);
    expect(
        ConversationTurn.capture({'type': 'reasoning', 'summary': 'secret'},
            raw: true),
        isNull);
    final turn = ConversationTurn('turn', 'completed', [
      user,
      call,
      result,
      {...call, 'call_id': 'unfinished'}
    ]);
    final payload = HandoverPayload.build([turn]);
    expect(payload.responses.map((item) => item['type']), [
      'message',
      'function_call',
      'function_call_output',
      'message',
    ]);
    expect(payload.responses.elementAt(1)['arguments'], call['arguments']);
    expect(payload.responses.toString(), contains(ConversationTurn.omitted));
    expect(payload.responses.toString(), contains(ConversationTurn.incomplete));
    expect(payload.responses.toString(), isNot(contains('private')));
    final truncated = HandoverPayload.build([turn], byteLimit: 1);
    expect(truncated.turns, [turn]);
    expect(truncated.wasTruncated, isTrue);
    expect(truncated.responses.single.toString(),
        contains(ConversationTurn.truncated));
  });

  test('实时轮次落盘，失败不替换主对话，成功后可重新投影', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    addTearDown(db.close);
    await migrateSessions(db);
    await migrateHandover(db);
    final sessions = SessionStore(db);
    await sessions.select('target', 'prior');
    final history = ConversationHistory(db);
    history.observe('turn/started', 'source', {
      'turn': {'id': 'one'}
    });
    history.observe('item/completed', 'source', {
      'turnId': 'one',
      'item': {
        'type': 'userMessage',
        'content': [
          {'type': 'text', 'text': '原问题'}
        ],
      }
    });
    history.observe('rawResponseItem/completed', 'source', {
      'turnId': 'one',
      'item': ConversationTurn.message('assistant', '原回答'),
    });
    history.observe('turn/completed', 'source', {
      'turn': {'id': 'one', 'status': 'completed'}
    });
    final payload = await history.prepare('source', []);
    expect(payload.turns.single.items, hasLength(2));
    await expectLater(
        history.promote('target', 'new', payload, () async {
          throw StateError('拒绝提交');
        }),
        throwsStateError);
    expect(await sessions.main('target'), 'prior');
    expect(await history.prefix('new'), isEmpty);
    await history.promote('target', 'new', payload, () async {});
    expect(await sessions.main('target'), 'new');
    final prefix = await ConversationHistory(db).prefix('new');
    expect(prefix.single.project().toString(), contains('原回答'));
  });
}

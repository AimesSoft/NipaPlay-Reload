import 'dart:async';
import 'dart:convert';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../capabilities/classic_action.dart';
import '../harness_hooks.dart';

/// The followup journal is also the public event cursor; no second event store.
final class BodyEvents implements Capability {
  BodyEvents(this.database);
  final Database database;
  final committed = StreamController<void>.broadcast(sync: true);
  void changed() => committed.add(null);

  Future<JsonMap> _read(JsonMap input) async {
    final cursor = (input['afterCursor'] as num?)?.toInt() ?? 0;
    final names = (input['events'] as List?)?.cast<String>();
    final entity = input['entityId'] as String?;
    // Bound the read before fetching rows: a concurrent commit belongs to the
    // next cursor, never to a larger cursor whose rows we have not read.
    final latest = await database
        .rawQuery('SELECT MAX(sequence) AS cursor FROM followup_hook_events');
    final savedCursor = latest.single['cursor'] as int? ?? 0;
    final upper = savedCursor > cursor ? savedCursor : cursor;
    final rows = await database.query('followup_hook_events',
        where: [
          'sequence>? AND sequence<=?',
          if (names != null)
            'event IN (${List.filled(names.length, '?').join(',')})',
          if (entity != null) 'object_id=?'
        ].join(' AND '),
        whereArgs: [cursor, upper, ...?names, if (entity != null) entity],
        orderBy: 'sequence ASC',
        limit: ((input['limit'] as num?)?.toInt() ?? 100) + 1);
    final count = (input['limit'] as num?)?.toInt() ?? 100;
    final selected = rows.take(count).toList();
    return {
      'events': [
        for (final row in selected)
          {
            ...jsonDecode(row['payload'] as String) as JsonMap,
            'cursor': row['sequence'],
            'entityId': row['object_id']
          }
      ],
      'nextCursor': rows.length > count ? selected.last['sequence'] : upper,
      'truncated': rows.length > count,
      'replay': 'persisted facts; hooks are not replayed'
    };
  }

  Future<JsonMap> wait(JsonMap input) async {
    final names = (input['events'] as List?)?.cast<String>();
    if (names != null &&
        names.any((name) => !HarnessHooks.events.contains(name))) {
      throw const Failure(
          FailureCode.invalidInput, 'Unknown body event; use events.describe.');
    }
    var changed = Completer<void>();
    final subscription = committed.stream.listen((_) {
      if (!changed.isCompleted) changed.complete();
    });
    Timer? timer;
    try {
      final timeout = (input['timeoutMs'] as num?)?.toInt() ?? 60000;
      timer = Timer(Duration(milliseconds: timeout), () {
        if (!changed.isCompleted) changed.complete();
      });
      final watch = Stopwatch()..start();
      var result = await _read(input);
      // Filtered waiters must keep waiting through unrelated changes.
      while ((result['events'] as List).isEmpty &&
          watch.elapsedMilliseconds < timeout) {
        await changed.future;
        changed = Completer<void>();
        result = await _read(input);
      }
      return result;
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }

  @override
  List<Action> get actions => [
        ClassicAction(
            const ActionSpec(
                id: 'events.describe',
                title: '身体事件契约',
                description:
                    '列出事件与持久游标语义。每个事件均可触发同名 hook 和 followup.register 的 when.event。高频播放位置不发事件。',
                effect: Effect.read,
                input: ObjectSchema({}),
                output: ObjectSchema({}, additionalProperties: true)),
            (_, __) async => {
                  'events': [
                    for (final event in HarnessHooks.events)
                      {
                        'name': event,
                        'payload': [
                          'eventId',
                          'event',
                          'entityId',
                          'occurredAt',
                          'revision',
                          'changedFields',
                          'facts'
                        ],
                        'hook': true,
                        'followup': true,
                        'replayableFacts': true
                      }
                  ],
                  'cursor':
                      'database sequence, retained across restart; 0 reads from the beginning',
                  'subscription':
                      'events.wait is bounded; followup conditions are one-shot; hooks observe new occurrences'
                }),
        ClassicAction(
            const ActionSpec(
                id: 'events.wait',
                title: '等待身体变化',
                description:
                    '从 afterCursor 读取持久事实，或有界等待匹配事件。nextCursor 是已检查游标；truncated=true 时继续取下一页。不会重跑 hook。',
                effect: Effect.read,
                input: ObjectSchema({
                  'afterCursor': IntegerSchema(minimum: 0),
                  'events': ArraySchema(StringSchema(), minItems: 1),
                  'entityId': StringSchema(minLength: 1),
                  'limit': IntegerSchema(minimum: 1, maximum: 1000),
                  'timeoutMs': IntegerSchema(minimum: 0, maximum: 60000),
                }),
                output: ObjectSchema({
                  'events': ArraySchema(ObjectSchema({
                    'cursor': IntegerSchema(minimum: 1),
                    'event': StringSchema(),
                    'entityId': StringSchema(),
                    'eventId': StringSchema(),
                    'occurredAt': StringSchema(),
                    'revision': IntegerSchema(nullable: true),
                    'changedFields': ArraySchema(StringSchema()),
                    'facts': ObjectSchema({}, additionalProperties: true),
                  }, additionalProperties: true)),
                  'nextCursor': IntegerSchema(minimum: 0),
                  'truncated': BooleanSchema(),
                  'replay': StringSchema()
                }, required: [
                  'events',
                  'nextCursor',
                  'truncated',
                  'replay'
                ])),
            (input, _) => wait(input)),
      ];
}

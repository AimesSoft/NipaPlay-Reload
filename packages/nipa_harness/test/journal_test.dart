import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/nipa_harness.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late Directory directory;

  setUp(() => directory = Directory.systemTemp.createTempSync('nipa-journal-'));
  tearDown(() => directory.deleteSync(recursive: true));

  test(
      'default filter appends write and destructive records and creates parents',
      () async {
    final file = File('${directory.path}/nested/journal.jsonl');
    final observer = RecordingObserver();
    final read = FixtureAction(id: 'test.read');
    final write = FixtureAction(id: 'test.write', effect: Effect.write);
    final destructive =
        FixtureAction(id: 'test.delete', effect: Effect.destructive);
    final harness = Harness([
      FixtureCapability([read, write, destructive])
    ], observers: [
      JsonlJournal(file),
      observer
    ]);
    await harness.invokeJson(read.spec.id, {}, Invocation(origin: 'mcp'));
    expect(file.existsSync(), isFalse);
    await harness.invokeJson(write.spec.id, {}, Invocation(origin: 'mcp'));
    expect(file.readAsLinesSync(), hasLength(1));
    await harness.invokeJson(
        destructive.spec.id, {}, Invocation(origin: 'mcp'));
    await harness.invokeJson(write.spec.id, false, Invocation(origin: 'mcp'));
    final lines = file.readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines,
        observer.records.skip(1).map((record) => jsonEncode(record.toJson())));
    expect((jsonDecode(lines.last) as JsonMap)['failureCode'], 'invalid_input');
    expect(file.readAsStringSync(), endsWith('\n'));
  });

  test('specified effects are honored and existing lines survive append',
      () async {
    final file = File('${directory.path}/journal.jsonl');
    file.writeAsStringSync('{"existing":true}\n');
    final read = FixtureAction(id: 'test.read');
    final write = FixtureAction(id: 'test.write', effect: Effect.write);
    final journal = JsonlJournal(file, effects: {Effect.read});
    final harness = Harness([
      FixtureCapability([read, write])
    ], observers: [
      journal
    ]);
    for (final action in [read, write, read]) {
      await harness.invokeJson(action.spec.id, {}, Invocation(origin: 'gui'));
    }
    // Reads do not wait for their lines.
    await journal.drain();
    final lines = file.readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines.first, '{"existing":true}');
    expect(lines.skip(1).map((line) => (jsonDecode(line) as JsonMap)['effect']),
        ['read', 'read']);
  });

  test('journal keeps result IDs while excluding output secrets', () async {
    final observer = RecordingObserver();
    final action = FixtureAction(
        effect: Effect.write,
        output: const ObjectSchema(
            {'jobId': StringSchema(), 'session': StringSchema(secret: true)}),
        onRun: (_, __) async => const Completed(FixtureJson({
              'jobId': 'job-result',
              'session': 'private-session',
              'token': 'private-token'
            })));
    await Harness([
      FixtureCapability([action])
    ], observers: [
      observer
    ]).invokeJson(action.spec.id, {}, Invocation(origin: 'mesh:peer'));
    final record = observer.records.single.toJson();
    expect((record['result'] as Map)['jobId'], 'job-result');
    expect(jsonEncode(record), isNot(contains('private-session')));
    expect(jsonEncode(record), isNot(contains('private-token')));
  });

  test('reads are journalled without their result unless kept; writes whole',
      () async {
    final file = File('${directory.path}/journal.jsonl');
    final read = FixtureAction(
        id: 'test.read',
        output: const ObjectSchema({}, additionalProperties: true),
        onRun: (_, __) async => Completed(FixtureJson({
              'items': [for (var i = 0; i < 100; i++) 'item-$i']
            })));
    final kept = FixtureAction(id: 'test.kept');
    final write = FixtureAction(id: 'test.write', effect: Effect.write);
    final journal = JsonlJournal(file,
        effects: Effect.values.toSet(),
        keepsResult: (record) => record.actionId == 'test.kept');
    final harness = Harness([
      FixtureCapability([read, kept, write])
    ], observers: [
      journal
    ]);
    for (final action in [read, kept, write]) {
      await harness.invokeJson(action.spec.id, {}, Invocation(origin: 'gui'));
    }
    // The write was on disk when it returned, after the reads before it.
    final lines = [
      for (final line in file.readAsLinesSync()) jsonDecode(line) as JsonMap
    ];
    expect(lines.map((line) => line['actionId']),
        ['test.read', 'test.kept', 'test.write']);
    expect(lines[0].containsKey('result'), isFalse);
    expect(lines[0]['resultOmitted'], true);
    expect(lines[0]['input'], <String, Object?>{});
    expect(lines[1]['result'], {'value': 'done'});
    expect(lines[2]['result'], {'value': 'done'});
  });

  test('every writer of a file goes through one appender, in order, rotated',
      () async {
    final file = File('${directory.path}/journal.jsonl');
    final appender = JournalAppender.of(file, rotateBytes: 1024);
    expect(JournalAppender.of(File('${directory.path}/./journal.jsonl')),
        same(appender));
    final pending = <Future<void>>[
      for (var i = 0; i < 100; i++)
        appender.append(
            i.isEven
                ? Future.delayed(const Duration(milliseconds: 1),
                    () => utf8.encode('${jsonEncode({'n': i, 'pad': 'x' * 50})}\n'))
                : utf8.encode('${jsonEncode({'n': i, 'pad': 'x' * 50})}\n'),
            durable: i % 7 == 0)
    ];
    await Future.wait(pending);
    final segments = await JournalAppender.segments(file);
    expect(segments.length, greaterThan(2));
    expect(segments.last.path, file.path);
    expect([
      for (final segment in segments)
        for (final line in segment.readAsLinesSync())
          (jsonDecode(line) as JsonMap)['n']
    ], List.generate(100, (i) => i));
    expect(file.lengthSync(), lessThanOrEqualTo(1024));
  });
}

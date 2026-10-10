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
    final harness = Harness([
      FixtureCapability([read, write])
    ], observers: [
      JsonlJournal(file, effects: {Effect.read})
    ]);
    for (final action in [read, write, read]) {
      await harness.invokeJson(action.spec.id, {}, Invocation(origin: 'gui'));
    }
    final lines = file.readAsLinesSync();
    expect(lines, hasLength(3));
    expect(lines.first, '{"existing":true}');
    expect(lines.skip(1).map((line) => (jsonDecode(line) as JsonMap)['effect']),
        ['read', 'read']);
  });
}

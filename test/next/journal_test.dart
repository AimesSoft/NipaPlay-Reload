import 'dart:async';
import 'dart:convert';
import 'dart:core';
import 'dart:core' as core;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/chat/turn_boundaries.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/state/activity_invocations.dart';
import 'package:nipaplay/next/ui_data/service.dart' show lastTurnBoundary;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/main_thread_probe.dart';

final class _Json implements JsonEncodable {
  const _Json(this.value);
  final JsonMap value;
  @override
  JsonMap toJson() => value;
}

final class _Fixed extends Action<_Json, _Json> {
  _Fixed(String id, Effect effect, this.result,
      {ObjectSchema output = const ObjectSchema({}, additionalProperties: true),
      this.failure})
      : spec = ActionSpec(
            id: id,
            title: id,
            description: 'Fixture.',
            effect: effect,
            input: const ObjectSchema({}, additionalProperties: true),
            output: output);
  @override
  final ActionSpec spec;
  final JsonMap result;
  final Failure? failure;
  @override
  _Json decodeInput(JsonMap json) => _Json(json);
  @override
  Future<Outcome<_Json>> run(_Json input, Invocation invocation) async =>
      failure != null ? Failed(failure!) : Completed(_Json(result));
}

final class _Fixture implements Capability {
  _Fixture(this.actions);
  @override
  final List<Action> actions;
}

JsonMap _big(String prefix, int count) => {
      'items': [
        for (var i = 0; i < count; i++)
          {'id': '$prefix-$i', 'title': '作品 $i', 'tags': ['a', 'b']}
      ]
    };

List<JsonMap> _lines(File file) => [
      for (final line in file.readAsLinesSync())
        if (line.isNotEmpty) jsonDecode(line) as JsonMap
    ];

/// Records how far [File]s opened by the journal had been flushed.
final class _Flushes {
  final flushedTo = <String, int>{};
}

final class _Plain extends IOOverrides {}

File _real(String path) => IOOverrides.runWithIOOverrides(() => File(path), _Plain());

final class _SpyFile implements File {
  _SpyFile(this._file, this._flushes);
  final File _file;
  final _Flushes _flushes;
  @override
  String get path => _file.path;
  @override
  File get absolute => this;
  @override
  Uri get uri => _file.uri;
  @override
  Directory get parent => _file.parent;
  @override
  Future<bool> exists() => _file.exists();
  @override
  Future<File> rename(String newPath) => _file.rename(newPath);
  @override
  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async =>
      _SpyHandle(await _file.open(mode: mode), _file.path, _flushes);
  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

final class _SpyHandle implements RandomAccessFile {
  _SpyHandle(this._handle, this._path, this._flushes);
  final RandomAccessFile _handle;
  final String _path;
  final _Flushes _flushes;
  @override
  Future<int> length() => _handle.length();
  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer,
      [int start = 0, int? end]) async {
    await _handle.writeFrom(buffer, start, end);
    return this;
  }

  @override
  Future<RandomAccessFile> flush() async {
    await _handle.flush();
    _flushes.flushedTo[_path] = await _handle.length();
    return this;
  }

  @override
  Future<void> close() => _handle.close();
  @override
  dynamic noSuchMethod(core.Invocation invocation) =>
      throw UnsupportedError('$invocation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('next-journal-'));
  tearDown(() => root.delete(recursive: true));

  final capture = _Fixed('ui.capture', Effect.read, {'path': '/tmp/a.png'});
  final state = _Fixed('state.query', Effect.read, _big('row', 400));
  final playback = _Fixed('playback.state', Effect.read, {'positionMs': 1});
  final failing = _Fixed('db.query', Effect.read, {},
      failure: const Failure(FailureCode.conflict, 'changed'));
  final write = _Fixed('media.identity.bind_batch', Effect.write,
      {'entries': _big('entry', 30)['items'], 'session': 'private-session'},
      output: const ObjectSchema({'session': StringSchema(secret: true)},
          additionalProperties: true));
  final remove = _Fixed('media.sources.remove', Effect.destructive,
      {'removed': true});
  Harness harness(List<InvocationObserver> observers) => Harness([
        _Fixture([capture, state, playback, failing, write, remove])
      ], observers: observers);
  Future<Outcome> call(Harness api, Action action, [JsonMap? input]) =>
      api.invokeJson(action.spec.id, input ?? {'limit': 5},
          Invocation(origin: 'harness_cli:chat:test'));

  test(
      'a read is journalled without its result and is not waited for; a write '
      'is whole and flushed before it returns', () async {
    final flushes = _Flushes();
    final path = '${root.path}/journal.jsonl';
    final journal = IOOverrides.runZoned(
        () => nextJournal(File(path)),
        createFile: (path) => _SpyFile(_real(path), flushes));
    final api = harness([journal]);
    final file = File(path);

    await call(api, state);
    await call(api, playback);
    await call(api, capture);
    await call(api, failing);
    await journal.drain();
    final reads = _lines(file);
    expect(reads.map((r) => r['actionId']),
        ['state.query', 'playback.state', 'ui.capture', 'db.query']);
    // The large result is not in the journal; the shape is otherwise the same.
    expect(reads[0].containsKey('result'), isFalse);
    expect(reads[0]['resultOmitted'], true);
    expect(reads[0].keys.toSet(), {
      'invocationId', 'actionId', 'origin', 'effect', 'input', 'status',
      'startedAt', 'elapsedMs', 'resultOmitted'
    });
    expect(reads[0]['input'], {'limit': 5});
    // 动态 shows ui.capture, so its result stays; a failed read has none.
    expect(reads[2]['result'], {'path': '/tmp/a.png'});
    expect(reads[2].containsKey('resultOmitted'), isFalse);
    expect(reads[3]['failureCode'], 'conflict');
    expect(reads[3].containsKey('resultOmitted'), isFalse);
    expect(file.lengthSync(), lessThan(2000));
    // Reads are not flushed one by one.
    expect(flushes.flushedTo[path], isNull);

    for (final action in [write, remove]) {
      await call(api, action);
      // On disk, flushed, when the outcome comes back.
      final lines = _lines(file);
      expect(lines.last['actionId'], action.spec.id);
      expect(flushes.flushedTo[path], file.lengthSync());
    }
    final written = _lines(file)[4];
    expect((written['result'] as Map)['entries'], hasLength(30));
    expect(jsonEncode(written), isNot(contains('private-session')));
    expect((written['result'] as Map)['session'], {
      'credentialRef': {
        'namespace': 'invocation',
        'key': '${written['invocationId']}/result/session'
      }
    });
  });

  test('reads, writes and chat boundaries are written whole, in the order they '
      'were handed in', () async {
    final file = File('${root.path}/journal.jsonl');
    final journal = nextJournal(file);
    final api = harness([journal]);
    final boundary = {
      'event': 'chat.turn_boundary',
      'origin': 'harness_cli:chat:test',
      'threadId': 't',
      'turnId': 'u',
      'phase': 'started'
    };
    // Each is handed in after the one before; none waits for the writing.
    // A kept read and a write are encoded on an isolate, so the compact
    // lines after them are ready first and must still come after them.
    Future<void> handedIn(Future<Outcome> pending) async {
      unawaited(pending);
      await Future<void>.delayed(Duration.zero);
    }

    final pending = <Future<void>>[];
    await call(api, capture);
    await call(api, playback);
    pending.add(TurnBoundaries.write(file, boundary));
    await handedIn(call(api, write));
    await call(api, state);
    pending.add(JournalAppender.of(file)
        .appendText('{"event":"chat.endpoint_token_rotated"}\n'));
    await handedIn(call(api, remove));
    await call(api, playback);
    await Future.wait(pending);
    await journal.drain();
    expect(
        _lines(file)
            .map((r) => r['actionId'] ?? r['event'])
            .toList(),
        [
          'ui.capture',
          'playback.state',
          'chat.turn_boundary',
          'media.identity.bind_batch',
          'state.query',
          'chat.endpoint_token_rotated',
          'media.sources.remove',
          'playback.state',
        ]);
    expect(TurnBoundaries.latest(file, 'harness_cli:chat:test'), boundary);
  });

  test('past its size the journal is rotated into archives, whole lines, none '
      'lost or reordered', () async {
    final file = File('${root.path}/journal.jsonl');
    final journal = JsonlJournal(file,
        effects: Effect.values.toSet(), rotateBytes: 4096);
    final api = harness([journal]);
    final expected = <String>[];
    final marks = <Future<void>>[];
    for (var i = 0; i < 120; i++) {
      final action = [write, playback, capture][i % 3];
      // Reads return before their line is written; writes once it is.
      await call(api, action, {'n': i});
      expected.add('${action.spec.id}:$i');
      if (i % 10 == 0) {
        marks.add(JournalAppender.of(file)
            .appendText('${jsonEncode({'event': 'mark', 'n': i})}\n'));
        expected.add('mark:$i');
      }
    }
    await Future.wait(marks);
    await journal.drain();
    final segments = await JournalAppender.segments(file);
    expect(segments.length, greaterThan(5));
    expect(segments.last.path, file.path);
    final archive = JournalAppender.archiveDirectory(file);
    for (final segment in segments.take(segments.length - 1)) {
      expect(segment.parent.path, archive.path);
      expect(segment.readAsStringSync(), endsWith('\n'));
    }
    final seen = [
      for (final segment in segments)
        for (final row in _lines(segment))
          '${row['actionId'] ?? row['event']}:${(row['input'] as Map?)?['n'] ?? row['n']}'
    ];
    expect(seen, expected);
    // The hot file and every archive stay within the size.
    for (final segment in segments) {
      expect(segment.lengthSync(), lessThanOrEqualTo(4096));
    }
  });

  test('动态 rows recorded as invocations happen are the ones read back from '
      'their journal', () async {
    final database = await openNextDatabase(
        Directory('${root.path}/live'), factory: databaseFactoryFfi);
    final file = File('${root.path}/live/journal.jsonl');
    var changed = 0;
    final live = ActivityInvocations(database, file, changed: () => changed++);
    final api = harness([nextJournal(file), live]);
    final open = _Fixed('ui.open', Effect.write, {
      'opened': true,
      'actual': {'kind': 'work'}
    });
    final shown = Harness([
      _Fixture([open])
    ], observers: [
      nextJournal(file),
      live
    ]);
    await call(api, capture);
    await call(api, state);
    await call(api, failing);
    await call(api, write, {
      'entries': [
        {'entityId': 'w-1', 'kind': 'work', 'note': 'left out'}
      ],
      'provider': 'tmdb'
    });
    await call(api, remove, {'sourceId': 'src-1', 'password': 'p'});
    await shown.invokeJson('ui.open', {'entityId': 'w-2'},
        Invocation(origin: 'gui', id: 'reused'));
    await shown.invokeJson('ui.open', {'entityId': 'w-3'},
        Invocation(origin: 'gui', id: 'reused'));
    await live.settled();
    expect(changed, 5);
    Future<List<JsonMap>> rows(Database db, String table) async => [
          for (final row in await db.query(table, orderBy: 'invocation_id'))
            Map.of(row)
        ];
    final liveRows = await rows(database, 'activity_invocations');
    expect(liveRows.map((r) => r['action_id']).toSet(),
        {'ui.capture', 'db.query', 'media.sources.remove', 'ui.open'});
    expect(liveRows, hasLength(4));
    final reused = liveRows.singleWhere((r) => r['invocation_id'] == 'reused');
    expect(jsonDecode(reused['input'] as String), {'entityId': 'w-3'});
    final removed =
        liveRows.singleWhere((r) => r['action_id'] == 'media.sources.remove');
    expect(jsonDecode(removed['input'] as String), {'sourceId': 'src-1'});
    // The two writes and the reused ID, once.
    expect(await rows(database, 'invocation_origins'), hasLength(3));

    // A database that has only the journal reads the same rows back.
    await Directory('${root.path}/copy').create();
    await file.copy('${root.path}/copy/journal.jsonl');
    final copy = await openNextDatabase(Directory('${root.path}/copy'),
        factory: databaseFactoryFfi);
    final backfilled =
        ActivityInvocations(copy, File('${root.path}/copy/journal.jsonl'));
    await backfilled.settled();
    expect(await rows(copy, 'activity_invocations'), liveRows);
    expect(await rows(copy, 'invocation_origins'),
        await rows(database, 'invocation_origins'));
    expect(await copy.query('activity_backfill'), hasLength(1));
    // Read once: a second start does not read the journal again.
    await File('${root.path}/copy/journal.jsonl').writeAsString('not json\n');
    await ActivityInvocations(copy, File('${root.path}/copy/journal.jsonl'))
        .settled();
    expect(await rows(copy, 'activity_invocations'), liveRows);
    await copy.close();
    await database.close();
  });

  test('a database with no journal yet writes nothing and reads it in once one '
      'exists', () async {
    final database = await openNextDatabase(root, factory: databaseFactoryFfi);
    final file = File('${root.path}/journal.jsonl');
    final changes = await database.rawQuery('SELECT total_changes() AS n');
    final first = ActivityInvocations(database, file);
    await first.settled();
    expect(await database.rawQuery('SELECT total_changes() AS n'), changes);
    expect(await database.query('activity_backfill'), isEmpty);
    await harness([nextJournal(file)]).invokeJson(
        'ui.capture', {}, Invocation(origin: 'gui', id: 'later'));
    await nextJournal(file).drain();
    await first.settled();
    expect((await database.query('activity_invocations')).single['invocation_id'],
        'later');
    expect(await database.query('activity_backfill'), hasLength(1));
    await database.close();
  });

  test('ui.present finds the turn without the journal; a turn it did not write '
      'is looked for off the main isolate', () async {
    final file = File('${root.path}/journal.jsonl');
    await TurnBoundaries.write(file, {
      'event': 'chat.turn_boundary',
      'origin': 'harness_cli:chat:memory',
      'threadId': 'thread-m',
      'turnId': 'turn-m',
      'phase': 'started'
    });
    await file.delete();
    expect(TurnBoundaries.latest(file, 'harness_cli:chat:memory')?['turnId'],
        'turn-m');
    expect(TurnBoundaries.latest(file, 'harness_cli:chat:other'), isNull);
    // A boundary written by someone else, before 30 MB of later lines.
    final sink = file.openWrite()
      ..writeln(jsonEncode({
        'event': 'chat.turn_boundary',
        'origin': 'harness_cli:chat:other',
        'threadId': 'thread-o',
        'turnId': 'turn-o',
        'phase': 'started'
      }));
    final filler = jsonEncode({'invocationId': 'x', 'input': {'note': '弹幕' * 2000}});
    for (var written = 0; written < 30 << 20; written += filler.length + 1) {
      sink.writeln(filler);
    }
    await sink.close();
    final probe = MainThreadProbe.start();
    final found = await lastTurnBoundary(file, 'harness_cli:chat:other');
    probe.stop();
    expect(found?['turnId'], 'turn-o');
    // ignore: avoid_print
    print('fallback over 30 MB: $probe');
    expect(probe.longestMs, lessThan(16));
  });

  test('nothing in Next writes journal.jsonl but through its one appender', () {
    final direct = RegExp(
        r"journal\.jsonl'\)\s*\.(writeAsString|writeAsStringSync|writeAsBytes|openWrite)");
    final offenders = [
      for (final entity in Directory('lib/next').listSync(recursive: true))
        if (entity is File &&
            entity.path.endsWith('.dart') &&
            direct.hasMatch(entity.readAsStringSync()))
          entity.path
    ];
    expect(offenders, isEmpty);
    final chat = File('lib/next/chat/chat_host.dart').readAsStringSync();
    expect(chat, isNot(contains('writeAsStringSync')));
  });
}

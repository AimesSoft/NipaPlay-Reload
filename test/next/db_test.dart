import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/capabilities/family_descriptions.dart';
import 'package:nipaplay/next/db/capability.dart';
import 'package:nipaplay/next/db/service.dart';
import 'package:nipaplay/next/db/table_docs.dart';
import 'package:nipaplay/next/db/wiring.dart';
import 'package:nipaplay/next/events/signals.dart';
import 'package:nipaplay/next/media/media_capability.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/state/views.dart';
import 'package:nipaplay/next/ui_data/service.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/security/secret_redactor.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'media_test_support.dart';

const _writable = {
  'media_entities',
  'media_locations',
  'media_file_episodes',
  'media_external_objects',
  'media_bindings',
  'media_evidence',
  'media_snapshots',
  'media_overrides',
  'media_file_aliases',
  'media_classic_observations',
  'media_classic_current',
  'danmaku_bindings',
  'ui_shelves',
  'ui_presentations',
};

void main() {
  late MediaFixture f;
  late Database d;
  late UiDataService ui;
  late DbService db;
  late Harness h;
  late List<JsonMap> events;

  setUp(() async {
    f = MediaFixture();
    await f.open();
    d = f.jobs.database;
    ui = UiDataService(
        f.service,
        f.engine,
        StateCapability([
          StateView(
              name: 'library.files',
              description: 'fixture',
              fields: const ObjectSchema({}),
              read: (offset, limit) async => [])
        ]),
        StateSources(),
        f.root,
        MemoryVault(),
        artworkClient:
            MockClient((request) async => http.Response('missing', 404)));
    db = createDbService(database: d, media: f.service, uiData: ui);
    h = Harness([MediaCapability(f.service), DbCapability(db)]);
    events = [];
    BodySignals.emit = (event, id, facts) async {
      events.add({'event': event, 'entityId': id, ...facts});
    };
    await d.insert('media_entities', {
      'id': 'w1',
      'kind': 'work',
      'revision': 0,
      'attributes': '{"title":"原作","localOnly":true}'
    });
    await d.insert('media_entities', {
      'id': 'r1',
      'kind': 'release',
      'parent_id': 'w1',
      'revision': 0,
      'attributes': '{"title":"第一季"}'
    });
    await d.insert('media_entities', {
      'id': 'e1',
      'kind': 'episode',
      'parent_id': 'r1',
      'revision': 0,
      'attributes': '{"title":"第一集"}'
    });
  });

  tearDown(() async {
    BodySignals.emit = null;
    while (ui.artwork.busy) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await ui.close();
    await f.close();
  });

  Future<Outcome<JsonEncodable>> invoke(String id, JsonMap input,
          {String origin = 'mcp', String? invocationId}) =>
      h.invokeJson(
          id, input, Invocation(origin: origin, id: invocationId));
  Future<JsonMap> call(String id, JsonMap input,
      {String origin = 'mcp', String? invocationId}) async {
    final outcome =
        await invoke(id, input, origin: origin, invocationId: invocationId);
    expect(outcome, isA<Completed>(), reason: jsonEncode(outcome.toEnvelope()));
    final result = (outcome as Completed).value.toJson();
    expect(h.lookup(id)!.spec.output.validate(result), isEmpty);
    return result;
  }

  Future<Failure> failure(String id, JsonMap input,
      {FailureCode? code, String origin = 'mcp'}) async {
    final outcome = await invoke(id, input, origin: origin);
    expect(outcome, isA<Failed>(), reason: jsonEncode(outcome.toEnvelope()));
    final failed = (outcome as Failed).failure;
    if (code != null) expect(failed.code, code, reason: failed.message);
    return failed;
  }

  JsonMap stmt(String sql, [List<Object?> params = const []]) =>
      {'sql': sql, if (params.isNotEmpty) 'params': params};
  Future<JsonMap> preview(List<JsonMap> statements, {String? reason}) =>
      call('db.write', {
        'statements': statements,
        if (reason != null) 'reason': reason,
      });
  Future<JsonMap> commit(JsonMap previewed,
          {String origin = 'mcp', String? invocationId}) =>
      call('db.write', {'previewId': previewed['previewId']},
          origin: origin, invocationId: invocationId);
  Future<JsonMap> write(List<JsonMap> statements,
      {String? reason, String origin = 'mcp', String? invocationId}) async {
    final previewed = await preview(statements, reason: reason);
    expect(previewed['committable'], true, reason: jsonEncode(previewed));
    return commit(previewed, origin: origin, invocationId: invocationId);
  }

  Future<List<Map>> rows(String sql, [List<Object?> args = const []]) async =>
      [for (final r in (await call('db.query', {'sql': sql, 'params': args}))['rows'] as List) r as Map];

  // Every table's rows plus the schema, as comparable text.
  Future<String> dump() async {
    final out = <String, Object?>{};
    for (final t in await d.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")) {
      final name = t['name'] as String;
      out[name] = await d.rawQuery('SELECT * FROM "$name" ORDER BY rowid');
    }
    out['_master'] =
        await d.rawQuery('SELECT type,name,sql FROM sqlite_master ORDER BY name');
    out['_temp'] = await d.rawQuery('SELECT name FROM sqlite_temp_master');
    out['_pragmas'] = [
      for (final p in [
        'query_only',
        'recursive_triggers',
        'defer_foreign_keys',
        'foreign_keys',
        'user_version'
      ])
        (await d.rawQuery('PRAGMA $p')).first
    ];
    out['_databases'] = await d.rawQuery('PRAGMA database_list');
    return jsonEncode(out);
  }

  group('describe', () {
    test('every existing table has an owner and a meaning, and nothing stale', () async {
      final tables = {
        for (final r in await d.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table'"))
          r['name'] as String
      };
      expect(dbTableDocs.keys.toSet(), tables,
          reason: 'docs and schema must list the same tables');
      final result = await call('db.describe', {});
      final described = {
        for (final t in result['tables'] as List) (t as Map)['name'] as String: t
      };
      expect(described.keys.toSet(), tables);
      for (final t in described.values) {
        final name = t['name'] as String;
        expect(t['documented'], true, reason: name);
        expect(t['summary'], isNotEmpty, reason: name);
        expect(t['columns'], isNotEmpty, reason: name);
        expect(['write', 'read'], contains(t['access']));
        if (t['access'] == 'read') {
          expect(t['readOnlyReason'], isNotEmpty, reason: name);
        } else {
          expect(t['primaryKey'], isNotEmpty, reason: name);
          final columns = [for (final c in t['columns'] as List) (c as Map)['name']];
          for (final c in (t['jsonColumns'] as Map? ?? {}).keys) {
            expect(columns, contains(c), reason: '$name.$c');
          }
        }
      }
      expect({
        for (final t in described.values)
          if (t['access'] == 'write') t['name']
      }, _writable);
      expect(described['media_file_episodes']!['primaryKey'],
          ['file_id', 'episode_id']);
      final fk = (described['media_bindings']!['foreignKeys'] as List)
          .cast<Map>()
          .map((e) => '${e['columns']}->${(e['references'] as Map)['table']}')
          .toList();
      expect(fk, contains('[entity_id]->media_entities'));
      expect(
          (described['media_bindings']!['indexes'] as List)
              .map((i) => (i as Map)['name']),
          contains('media_bindings_entity'));
      expect(described['media_overrides']!['sql'], contains('PRIMARY KEY'));
      final semantics = result['semantics'] as Map;
      for (final topic in [
        'classic_match',
        'overrides_over_snapshots',
        'artwork',
        'no_classic_projection',
        'preview_binding',
        'undo'
      ]) {
        expect(semantics[topic], isNotEmpty, reason: topic);
      }
      expect(semantics['classic_match'], contains('media_classic_current'));
      expect(semantics['artwork'], contains('artwork.poster'));
    });

    test('tables narrows the answer; an unknown table is not found', () async {
      final one = await call('db.describe', {'tables': ['media_overrides']});
      expect((one['tables'] as List), hasLength(1));
      expect(one.containsKey('semantics'), false);
      await failure('db.describe', {'tables': ['nope']},
          code: FailureCode.notFound);
    });

    test('a table nobody documented is listed read-only and cannot be written',
        () async {
      await d.execute('CREATE TABLE future_table(id TEXT PRIMARY KEY, v TEXT)');
      await d.insert('future_table', {'id': 'a', 'v': '1'});
      final t = ((await call('db.describe', {'tables': ['future_table']}))['tables']
              as List)
          .single as Map;
      expect(t['documented'], false);
      expect(t['access'], 'read');
      final failed = await failure('db.write',
          {'statements': [stmt("UPDATE future_table SET v='2'")]});
      expect(failed.message, contains('future_table'));
      expect(failed.message, contains('read-only'));
      expect((await d.query('future_table')).single['v'], '1');
    });

    test('effects: describe and query read, write and undo write', () {
      expect({
        for (final s in h.catalog.where((s) => s.id.startsWith('db.')))
          s.id: s.effect
      }, {
        'db.describe': Effect.read,
        'db.query': Effect.read,
        'db.write': Effect.write,
        'db.undo': Effect.write,
      });
    });

    test('the db family is described, and media says the library can be read and written directly',
        () {
      expect(familyFacts['db'], contains('db.write'));
      expect(familyFacts['db'], contains('不往 Classic 投影'));
      expect(familyFacts['media'], contains('db.query'));
      final family = describeFamily('db', h.catalog);
      expect([for (final a in family['actions'] as List) (a as Map)['id']],
          ['db.describe', 'db.query', 'db.undo', 'db.write']);
    });
  });

  group('query', () {
    test('reads with bound parameters, WITH and aggregates', () async {
      final r = await call('db.query', {
        'sql': 'SELECT id, kind FROM media_entities WHERE kind=? ORDER BY id;',
        'params': ['episode']
      });
      expect(r['rows'], [
        {'id': 'e1', 'kind': 'episode'}
      ]);
      expect(r['columns'], ['id', 'kind']);
      expect(r['truncated'], false);
      expect(r['nextOffset'], null);
      final w = await call('db.query', {
        'sql':
            'WITH k AS (SELECT kind FROM media_entities) SELECT count(*) AS n FROM k'
      });
      expect((w['rows'] as List).single, {'n': 3});
    });

    test('nothing can be written through it, and the connection is left as it was',
        () async {
      final before = await dump();
      for (final sql in [
        "INSERT INTO media_entities VALUES('x','work',NULL,0,'{}')",
        "UPDATE media_entities SET revision=9",
        "DELETE FROM media_entities",
        'WITH x AS (SELECT id FROM media_entities) DELETE FROM media_entities WHERE id IN (SELECT id FROM x)',
        'PRAGMA user_version=7',
        'PRAGMA query_only=OFF',
        "ATTACH DATABASE ':memory:' AS other",
        'CREATE TABLE evil(a)',
        'DROP TABLE media_entities',
        'VACUUM',
        'BEGIN',
        'COMMIT',
        'SELECT 1; DELETE FROM media_entities',
        'SELECT 1) ; DELETE FROM media_entities WHERE (1',
        'SELECT 1 /* x */ ; DROP TABLE media_entities',
      ]) {
        final failed =
            await failure('db.query', {'sql': sql}, code: FailureCode.invalidInput);
        expect(failed.message, isNotEmpty, reason: sql);
        expect(await dump(), before, reason: sql);
      }
      // A plain select still works afterwards, and so does a normal write.
      expect(await rows('SELECT count(*) AS n FROM media_entities'), [
        {'n': 3}
      ]);
      await d.insert('media_entities', {
        'id': 'x',
        'kind': 'work',
        'revision': 0,
        'attributes': '{}'
      });
    });

    test('other writers are not blocked or broken while queries run', () async {
      final inserts = [
        for (var i = 0; i < 20; i++)
          d.insert('ui_cache',
              {'id': 'p$i', 'fingerprint': 'f', 'payload': 'p'})
      ];
      final queries = [
        for (var i = 0; i < 20; i++)
          call('db.query', {'sql': 'SELECT count(*) AS n FROM ui_cache'})
      ];
      await Future.wait([...inserts, ...queries]);
      expect((await d.query('ui_cache')), hasLength(20));
      expect((await d.rawQuery('PRAGMA query_only')).first.values.first, 0);
    });

    test('rows are capped and the continuation is exact', () async {
      for (var i = 0; i < 25; i++) {
        await d.insert('ui_cache',
            {'id': 'k${i.toString().padLeft(2, '0')}', 'fingerprint': 'f', 'payload': 'p'});
      }
      final seen = <Object?>[];
      int? offset = 0;
      var pages = 0;
      while (offset != null) {
        final page = await call('db.query', {
          'sql': "SELECT id FROM ui_cache WHERE id LIKE 'k%' ORDER BY id",
          'limit': 10,
          'offset': offset
        });
        pages++;
        seen.addAll([for (final r in page['rows'] as List) (r as Map)['id']]);
        if (page['truncated'] == true) {
          expect(page['truncatedBy'], 'rows');
          expect(page['hint'], contains('nextOffset'));
        }
        offset = page['nextOffset'] as int?;
      }
      expect(pages, 3);
      expect(seen, [for (var i = 0; i < 25; i++) 'k${i.toString().padLeft(2, '0')}']);
    });

    test('bytes are capped too, with a continuation, and long cells are cut',
        () async {
      for (var i = 0; i < 8; i++) {
        await d.insert('ui_cache',
            {'id': 'b$i', 'fingerprint': 'f', 'payload': 'x' * 400});
      }
      final page = await call('db.query', {
        'sql': "SELECT id, payload FROM ui_cache WHERE id LIKE 'b%' ORDER BY id",
        'maxBytes': 1500
      });
      expect(page['truncated'], true);
      expect(page['truncatedBy'], 'bytes');
      final got = (page['rows'] as List).length;
      expect(got, inInclusiveRange(1, 7));
      expect(page['nextOffset'], got);
      final rest = await call('db.query', {
        'sql': "SELECT id FROM ui_cache WHERE id LIKE 'b%' ORDER BY id",
        'offset': got
      });
      expect((rest['rows'] as List), hasLength(8 - got));
      await d.insert('ui_cache',
          {'id': 'huge', 'fingerprint': 'f', 'payload': 'y' * 5000});
      final cut = await call('db.query',
          {'sql': "SELECT payload FROM ui_cache WHERE id='huge'"});
      expect(cut['truncatedCells'], 1);
      final text = ((cut['rows'] as List).single as Map)['payload'] as String;
      expect(text.length, lessThan(2100));
      expect(text, contains('+3000 chars'));
    });

    test('blobs are summarised and parameters are typed', () async {
      final r = await call('db.query', {
        'sql': 'SELECT ? AS a, ? AS b, ? AS c, x\'0102\' AS d, length(?) AS e',
        'params': [1, true, null, {r'$blob': base64Encode([1, 2, 3])}]
      });
      final row = (r['rows'] as List).single as Map;
      expect(row['a'], 1);
      expect(row['b'], 1);
      expect(row['c'], null);
      expect((row['d'] as Map)['bytes'], 2);
      expect(row['e'], 3);
      final bad = await failure('db.query', {
        'sql': 'SELECT ?',
        'params': [
          {'nested': 1}
        ]
      }, code: FailureCode.invalidInput);
      expect(bad.message, contains('params/0'));
    });

    test('secrets in values and column names are masked', () async {
      SecretRedactor.remember(
          const CredentialRef('test', 'known'), 'zzTopSecret42');
      final r = await call('db.query', {
        'sql':
            "SELECT 'zzTopSecret42' AS plain, 'abc' AS token, 'https://h/x?api_key=hunter2&y=1' AS url"
      });
      final text = jsonEncode(r);
      expect(text, isNot(contains('zzTopSecret42')));
      expect(text, isNot(contains('hunter2')));
      expect(text, isNot(contains('"abc"')));
    });
  });

  group('write', () {
    test('a preview shows every touched row and leaves no trace', () async {
      final before = await dump();
      final p = await preview([
        stmt("INSERT INTO ui_shelves(id,payload,updated_at) VALUES(?,?,?)",
            ['s1', '{"placement":"shelf","title":"今晚看点轻松的","items":[{"workId":"w1"}]}', 'now']),
        stmt("UPDATE media_entities SET revision=revision+1 WHERE id=?", ['w1']),
        stmt("DELETE FROM media_entities WHERE id=?", ['e1']),
      ]);
      expect(await dump(), before);
      expect(p['status'], 'preview');
      expect(p['committed'], false);
      expect(p['committable'], true);
      expect(p['previewId'], startsWith('dbp-'));
      expect(p['changedRows'], 3);
      final tables = p['tables'] as Map;
      expect((tables['ui_shelves'] as Map)['insert'], 1);
      expect((tables['media_entities'] as Map)['update'], 1);
      expect((tables['media_entities'] as Map)['delete'], 1);
      final entityRows = (tables['media_entities'] as Map)['rows'] as List;
      final update = entityRows.cast<Map>().singleWhere((r) => r['op'] == 'update');
      expect(update['key'], {'id': 'w1'});
      expect(update['changed'], {
        'revision': {'before': 0, 'after': 1}
      });
      final delete = entityRows.cast<Map>().singleWhere((r) => r['op'] == 'delete');
      expect((delete['before'] as Map)['attributes'], contains('第一集'));
      expect((p['statements'] as List).map((s) => (s as Map)['rowsAffected']), [1, 1, 1]);
      expect(await d.query('db_commits'), isEmpty);
      expect(await d.query('body_changes'), isEmpty);
      expect(events, isEmpty);
    });

    test('a preview of a large batch gives counts and a sample', () async {
      for (var i = 0; i < 150; i++) {
        await d.insert('ui_shelves', {'id': 's$i', 'payload': '{"items":[]}', 'updated_at': 't'});
      }
      final p = await preview([stmt("DELETE FROM ui_shelves WHERE id LIKE 's%'")]);
      expect(p['changedRows'], 150);
      final shelf = (p['tables'] as Map)['ui_shelves'] as Map;
      expect(shelf['delete'], 150);
      expect(shelf['truncated'], true);
      expect((shelf['rows'] as List).length, lessThanOrEqualTo(20));
      expect(p['note'], contains('sample'));
      await commit(p);
      expect(await d.query('ui_shelves'), isEmpty);
    });

    test('committing the preview writes exactly it, with an audit and no temp leftovers',
        () async {
      final p = await preview([
        stmt("UPDATE media_entities SET revision=? WHERE id=?", [5, 'w1']),
        stmt("INSERT INTO media_overrides(entity_id,field,value,invocation_id,mode,actor,origin,changed_at) VALUES(?,?,?,?,?,?,?,?)",
            ['w1', 'title', '"新标题"', 'inv', 'persistent', 'agent', 'mcp', '2026-10-21T00:00:00Z']),
      ], reason: '修正作品标题');
      final done = await commit(p, invocationId: 'inv-commit-1');
      expect(done['status'], 'committed');
      expect(done['commitId'], startsWith('dbcommit-'));
      expect((await d.query('media_entities', where: "id='w1'")).single['revision'], 5);
      expect((await d.query('media_overrides')).single['value'], '"新标题"');
      expect(await d.rawQuery('SELECT name FROM sqlite_temp_master'), isEmpty);
      expect((await d.rawQuery('PRAGMA recursive_triggers')).first.values.first, 0);
      expect((await d.rawQuery('PRAGMA query_only')).first.values.first, 0);
      // The preview is used up.
      await failure('db.write', {'previewId': p['previewId']},
          code: FailureCode.notFound);

      final commitRow = (await d.query('db_commits')).single;
      expect(commitRow['id'], done['commitId']);
      expect(commitRow['kind'], 'write');
      expect(commitRow['actor'], 'agent');
      expect(commitRow['origin'], 'mcp');
      expect(commitRow['invocation_id'], 'inv-commit-1');
      expect(commitRow['reason'], '修正作品标题');
      expect(commitRow['sequence'], 1);
      expect(commitRow['undoes'], null);
      final statements = jsonDecode(commitRow['statements'] as String) as List;
      expect(statements.first['sql'], contains('UPDATE media_entities'));
      expect(statements.first['params'], [5, 'w1']);
      expect(jsonDecode(commitRow['counts'] as String), {
        'media_entities': {'insert': 0, 'update': 1, 'delete': 0},
        'media_overrides': {'insert': 1, 'update': 0, 'delete': 0},
      });
      final changes = jsonDecode(commitRow['changes'] as String) as List;
      expect(changes, hasLength(2));
      final overrideChange =
          changes.cast<Map>().singleWhere((c) => c['table'] == 'media_overrides');
      expect(overrideChange['before'], null);
      expect(overrideChange['after']['value'], '"新标题"');
      final body = (await d.query('body_changes')).single;
      expect(body['type'], 'db.write');
      expect(body['subject_id'], done['commitId']);
      expect(body['actor'], 'agent');
      expect(body['origin'], 'mcp');
      expect(body['invocation_id'], 'inv-commit-1');
      final facts = jsonDecode(body['facts'] as String) as Map;
      expect(facts['title'], contains('2'));
      expect(facts['reason'], '修正作品标题');
      expect(facts['entityIds'], contains('w1'));
      // Nothing is projected to Classic.
      expect(await d.query('media_projection_outbox'), isEmpty);
      expect(await d.query('media_binding_operations'), isEmpty);
    });

    test('a person at the keyboard is the user in the audit', () async {
      await write([stmt("UPDATE media_entities SET revision=1 WHERE id='w1'")],
          origin: 'gui');
      expect((await d.query('db_commits')).single['actor'], 'user');
      expect((await d.query('body_changes')).single['actor'], 'user');
    });

    test('rows changed after the preview make the commit refuse and write nothing',
        () async {
      final p = await preview(
          [stmt("UPDATE media_entities SET revision=revision+1 WHERE id='w1'")]);
      await d.update('media_entities', {'revision': 7}, where: "id='w1'");
      final before = await dump();
      final failed = await failure('db.write', {'previewId': p['previewId']},
          code: FailureCode.conflict);
      expect(failed.message, contains('Preview again'));
      expect(await dump(), before);
      expect(await d.query('db_commits'), isEmpty);
      // Previewing again sees the new state and commits it.
      final again = await write(
          [stmt("UPDATE media_entities SET revision=revision+1 WHERE id='w1'")]);
      expect(again['committed'], true);
      expect((await d.query('media_entities', where: "id='w1'")).single['revision'], 8);
    });

    test('a row inserted by someone else under the previewed key also refuses',
        () async {
      final p = await preview([
        stmt("INSERT INTO ui_shelves(id,payload,updated_at) VALUES('s','{\"items\":[]}','t')")
      ]);
      await d.insert('ui_shelves', {'id': 's', 'payload': '{"items":[]}', 'updated_at': 'other'});
      await failure('db.write', {'previewId': p['previewId']});
      expect((await d.query('ui_shelves')).single['updated_at'], 'other');
    });

    test('changes to unrelated tables do not stop the commit', () async {
      final p = await preview([stmt("UPDATE media_entities SET revision=2 WHERE id='w1'")]);
      await d.insert('ui_cache', {'id': 'noise', 'fingerprint': 'f', 'payload': 'p'});
      expect((await commit(p))['committed'], true);
    });

    test('a previewId needs the statements it was made for', () async {
      final p = await preview([stmt("UPDATE media_entities SET revision=2 WHERE id='w1'")]);
      final failed = await failure('db.write', {
        'previewId': p['previewId'],
        'statements': [stmt("UPDATE media_entities SET revision=3 WHERE id='w1'")]
      }, code: FailureCode.invalidInput);
      expect(failed.message, contains('differ'));
      await failure('db.write', {'previewId': 'dbp-unknown'},
          code: FailureCode.notFound);
      await failure('db.write', {}, code: FailureCode.invalidInput);
    });

    test('replace and upsert are tracked as updates, and every row is undoable',
        () async {
      await d.insert('ui_shelves', {'id': 'u', 'payload': '{"items":[]}', 'updated_at': 'a'});
      final before = await dump();
      final done = await write([
        stmt("INSERT OR REPLACE INTO ui_shelves(id,payload,updated_at) VALUES('u','{\"items\":[]}','b')"),
        stmt("INSERT INTO ui_shelves(id,payload,updated_at) VALUES('v','{\"items\":[]}','c') ON CONFLICT(id) DO UPDATE SET updated_at='d'"),
        stmt("INSERT INTO ui_shelves(id,payload,updated_at) VALUES('v','{\"items\":[]}','c') ON CONFLICT(id) DO UPDATE SET updated_at='d'"),
      ]);
      final shelf = (done['tables'] as Map)['ui_shelves'] as Map;
      expect(shelf['insert'], 1);
      expect(shelf['update'], 1);
      expect((await d.query('ui_shelves', orderBy: 'id')).map((r) => r['updated_at']),
          ['b', 'd']);
      await call('db.undo', {'commitId': done['commitId']});
      expect(
          jsonDecode(await dump())['ui_shelves'], jsonDecode(before)['ui_shelves']);
    });

    test('limits: too many statements, too many rows', () async {
      await failure('db.write', {
        'statements': [for (var i = 0; i < 101; i++) stmt('DELETE FROM ui_shelves')]
      }, code: FailureCode.invalidInput);
      for (var i = 0; i < 2100; i++) {
        await d.insert('ui_shelves', {'id': 'big$i', 'payload': '{"items":[]}', 'updated_at': 't'});
      }
      final failed = await failure('db.write',
          {'statements': [stmt('DELETE FROM ui_shelves')]},
          code: FailureCode.invalidInput);
      expect(failed.message, contains('2000'));
      expect(await d.query('ui_shelves'), hasLength(2100));
    });

    test('parameters: booleans bind as 0/1, objects are refused', () async {
      await d.insert('media_locations', {
        'id': 'l1', 'file_id': 'e1', 'source': 'local',
        'owner_device_id': 'dev', 'locator': '/a.mkv', 'available': 1
      });
      await write([
        stmt("UPDATE media_locations SET available=? WHERE id='l1'", [false]),
      ]);
      expect((await d.query('media_locations')).single['available'], 0);
      final bad = await failure('db.write', {
        'statements': [
          stmt("UPDATE media_entities SET attributes=? WHERE id='w1'", [
            {'a': 1}
          ])
        ]
      }, code: FailureCode.invalidInput);
      expect(bad.message, contains('params/0'));
    });
  });

  group('SQLite is what refuses', () {
    test('every read-only table rejects insert, update and delete', () async {
      // One row in every table that db.write must not touch, put there directly.
      await d.insert('media_external_objects', {
        'id': 'o1', 'provider': 'dandanplay', 'object_type': 'episode',
        'external_id': '1', 'scope': ''
      });
      await d.insert('media_locations', {
        'id': 'l1', 'file_id': 'e1', 'source': 'local',
        'owner_device_id': 'dev', 'locator': '/a.mkv', 'available': 1
      });
      await d.insert('danmaku_bindings', {
        'id': 'db1', 'entity_id': 'e1', 'entity_revision': 0, 'object_id': 'o1',
        'video': '{}', 'status': 'accepted', 'enabled': 1, 'deduplicate': 1,
        'offset_ms': 0, 'alignment': '{}', 'evidence': '{}', 'bound_by': 'user',
        'invocation_id': 'i', 'revision': 1, 'created_at': 't'
      });
      final seeds = <String, Map<String, Object?>>{
        'jobs': {'job_id': 'j1', 'type': 't', 'state': 'queued', 'revision': 0, 'created_at': 't', 'snapshot': '{}'},
        'job_events': {'job_id': 'j1', 'revision': 0, 'kind': 'k', 'at': 't', 'snapshot': '{}'},
        'task_origins': {'job_id': 'j1', 'origin': 'mcp'},
        'followups': {'id': 'f1', 'state': 'waiting', 'snapshot': '{}'},
        'followup_events': {'followup_id': 'f1', 'at': 't', 'type': 'x', 'origin': 'o', 'facts': '{}'},
        'followup_hook_events': {'event': 'e', 'object_id': 'o', 'payload': '{}'},
        'activity_invocations': {'invocation_id': 'i', 'action_id': 'a', 'started_at': 't', 'elapsed_ms': 1, 'input': '{}'},
        'invocation_origins': {'invocation_id': 'i', 'origin': 'o'},
        'activity_backfill': {'done': 1},
        'followup_objects': {'kind': 'download', 'object': 'o', 'followup_id': 'f1'},
        'harness_sessions': {'repository': 'r', 'main_thread': 'm', 'current_thread': 'c'},
        'harness_discoveries': {'at': 't', 'origin': 'o', 'invocation_id': 'i', 'repository': 'r', 'title': 't', 'source': 's', 'facts': '{}'},
        'body_changes': {'at': 't', 'type': 'x', 'subject_id': 's', 'actor': 'a', 'origin': 'o', 'facts': '{}'},
        'settings_changes': {'key': 'k', 'previous_value': '1', 'value': '2', 'changed_at': 't', 'changed_by': 'u', 'origin': 'gui', 'invocation_id': 'i', 'revision': 1},
        'media_metadata_edits': {'entity_id': 'w1', 'field': 'title', 'value': '"x"', 'mode': 'persistent', 'actor': 'user', 'origin': 'gui', 'invocation_id': 'i', 'changed_at': 't'},
        'danmaku_binding_events': {'id': 'ev1', 'binding_id': 'db1', 'revision': 1, 'invocation_id': 'i', 'payload': '{}', 'created_at': 't'},
        'danmaku_alignment_candidates': {'job_id': 'j1', 'binding_id': 'db1', 'binding_revision': 1, 'payload': '{}', 'state': 'x'},
        'danmaku_cache_chunks': {'cache_key': 'c', 'chunk_index': 0, 'start_ms': 0, 'end_ms': 1, 'payload': '{}', 'coverage': '{}', 'fetched_at': 't'},
        'danmaku_storage_state': {'needs_vacuum': 0},
        'media_legacy_history': {'location_id': 'l1', 'fingerprint': 'f', 'payload': '{}'},
        'media_binding_operations': {'id': 'op', 'fingerprint': 'f', 'result': '{}'},
        'media_projection_outbox': {'id': 'p', 'file_id': 'e1', 'file_revision': 0, 'binding_revision': 0, 'payload': '{}', 'state': 'pending'},
        'media_scan_items': {'job_id': 'j1', 'file_id': 'e1', 'file_revision': 0},
        'file_subtitles': {'file_id': 'e1', 'facts': '{}'},
        'file_skip_segments': {'file_id': 'e1', 'kind': 'opening', 'start_ms': 0, 'end_ms': 1, 'set_at': 't'},
        'next_library_index': {'id': 'x', 'added': 1, 'payload': '{}', 'facts': '{}'},
        'ui_cache': {'id': 'c', 'fingerprint': 'f', 'payload': 'p'},
      };
      await d.execute('PRAGMA foreign_keys=OFF');
      for (final seed in seeds.entries) {
        await d.insert(seed.key, seed.value);
      }
      await d.execute('PRAGMA foreign_keys=ON');
      // The audit table gets its first row from a real commit.
      await write([stmt("UPDATE media_entities SET revision=1 WHERE id='w1'")]);
      final readOnly = [
        for (final e in dbTableDocs.entries)
          // change_epochs is moved by the triggers of the tables it counts, so
          // a statement that writes those cannot be refused for touching it.
          if (e.value.access == DbAccess.read &&
              e.key != 'sqlite_sequence' &&
              e.key != 'change_epochs')
            e.key
      ]..sort();
      expect(readOnly, [...seeds.keys, 'db_commits']..sort(),
          reason: 'a new read-only table needs a seed row here');
      final before = await dump();
      for (final table in readOnly) {
        final first = (await d.rawQuery('PRAGMA table_info("$table")')).first['name'];
        for (final sql in [
          'UPDATE $table SET $first=$first',
          'DELETE FROM $table',
          'INSERT INTO $table SELECT * FROM $table',
          'INSERT OR REPLACE INTO $table SELECT * FROM $table',
        ]) {
          final failed = await failure('db.write', {'statements': [stmt(sql)]},
              code: FailureCode.invalidInput);
          expect(failed.message, contains(table), reason: sql);
          expect(failed.message, contains('read-only'), reason: sql);
          expect(failed.details['table'], table, reason: sql);
        }
        expect(await dump(), before, reason: table);
      }
      // A batch that mixes allowed and refused writes changes nothing.
      await failure('db.write', {
        'statements': [
          stmt("UPDATE media_entities SET revision=9 WHERE id='w1'"),
          stmt("DELETE FROM jobs"),
        ]
      });
      expect(await dump(), before);
      // Sequence counters of read-only tables cannot be edited around the triggers.
      for (final sql in [
        "UPDATE sqlite_sequence SET seq=0 WHERE name='body_changes'",
        "INSERT INTO sqlite_sequence(name,seq) VALUES('jobs', 99)",
        'DELETE FROM sqlite_sequence',
      ]) {
        await failure('db.write', {'statements': [stmt(sql)]},
            code: FailureCode.invalidInput);
      }
      expect(await dump(), before);
    });

    test('a row still referred to by a read-only table cannot be deleted', () async {
      await d.insert('file_subtitles', {'file_id': 'e1', 'facts': '{}'});
      final before = await dump();
      final p = await preview([stmt("DELETE FROM media_entities WHERE id='e1'")]);
      expect(p['committable'], false);
      expect(((p['problems'] as List).single as Map)['table'], 'file_subtitles');
      expect(await dump(), before);
    });

    test('DDL, PRAGMA, ATTACH, transaction control, RETURNING and several statements are refused',
        () async {
      final before = await dump();
      for (final sql in [
        'CREATE TABLE evil(a)',
        'CREATE INDEX evil ON media_entities(kind)',
        'DROP TABLE media_entities',
        'ALTER TABLE media_entities ADD COLUMN z',
        'PRAGMA user_version=3',
        'PRAGMA query_only=ON',
        'PRAGMA foreign_keys=OFF',
        "ATTACH DATABASE ':memory:' AS q",
        'DETACH DATABASE q',
        'COMMIT',
        'ROLLBACK',
        'BEGIN',
        'SAVEPOINT s',
        'RELEASE s',
        'VACUUM',
        'ANALYZE',
        'REINDEX',
        "INSERT INTO media_entities VALUES('x','work',NULL,0,'{}') RETURNING id",
        "INSERT INTO main.media_entities VALUES('x','work',NULL,0,'{}')",
        "WITH x AS (SELECT 'e1' i) DELETE FROM media_entities WHERE id IN (SELECT i FROM x)",
        "UPDATE media_entities SET revision=1; UPDATE media_entities SET revision=2",
        "UPDATE media_entities SET revision=1 WHERE id='w1'; DROP TABLE media_entities",
        'UPDATE media_entities SET revision=1 -- comment\n; DELETE FROM media_entities',
        'SELECT 1',
        '',
        '   ;',
      ]) {
        final outcome = await invoke('db.write', {
          'statements': [stmt(sql)]
        });
        if (sql == 'SELECT 1') {
          // Harmless: SQLite accepts a select as a trigger body; nothing changes.
          continue;
        }
        expect(outcome, isA<Failed>(), reason: 'accepted: $sql');
        expect(await dump(), before, reason: sql);
      }
      final syntax = await failure('db.write', {'statements': [stmt('CREATE TABLE evil(a)')]});
      expect(syntax.message, contains('INSERT, UPDATE or DELETE'));
      expect(syntax.message, contains('syntax'));
      // The first statement of a rejected batch did not run either.
      await failure('db.write', {
        'statements': [
          stmt("UPDATE media_entities SET revision=9 WHERE id='w1'"),
          stmt('DROP TABLE media_entities')
        ]
      });
      expect(await dump(), before);
    });

    test('a COMMIT inside a statement list cannot end the transaction early',
        () async {
      final before = await dump();
      await failure('db.write', {
        'statements': [
          stmt("UPDATE media_entities SET revision=9 WHERE id='w1'"),
          stmt('COMMIT'),
          stmt("UPDATE media_entities SET revision=10 WHERE id='r1'"),
        ]
      });
      expect(await dump(), before);
    });

    test('constraint violations reject the batch as a whole', () async {
      final before = await dump();
      final failed = await failure('db.write', {
        'statements': [
          stmt("UPDATE media_entities SET revision=9 WHERE id='w1'"),
          stmt("INSERT INTO media_entities VALUES('w1','work',NULL,0,'{}')"),
        ]
      }, code: FailureCode.conflict);
      expect(failed.message, contains('Statement 2'));
      expect(failed.details['statementIndex'], 1);
      await failure('db.write', {
        'statements': [
          stmt("INSERT INTO media_entities VALUES('bad','nonsense',NULL,0,'{}')"),
        ]
      }, code: FailureCode.conflict);
      expect(await dump(), before);
    });
  });

  group('integrity', () {
    test('a foreign key violation is rolled back and reported, whatever the order',
        () async {
      await d.insert('media_locations', {
        'id': 'l1', 'file_id': 'e1', 'source': 'local',
        'owner_device_id': 'dev', 'locator': '/a.mkv', 'available': 1
      });
      final before = await dump();
      final p = await preview(
          [stmt("DELETE FROM media_entities WHERE id='e1'")]);
      expect(p['committable'], false);
      expect(p.containsKey('previewId'), false);
      final problem = (p['problems'] as List).single as Map;
      expect(problem['kind'], 'foreign_key');
      expect(problem['table'], 'media_locations');
      expect(await dump(), before);
      // Deleting the child first or last is the same batch.
      final both = await preview([
        stmt("DELETE FROM media_entities WHERE id='e1'"),
        stmt("DELETE FROM media_locations WHERE id='l1'"),
      ]);
      expect(both['committable'], true);
      await commit(both);
      expect(await d.query('media_locations'), isEmpty);
      expect(await d.query('media_entities', where: "id='e1'"), isEmpty);
      expect((await d.rawQuery('PRAGMA foreign_key_check')), isEmpty);
    });

    test('a violation that only appears at commit time rolls the commit back',
        () async {
      final p = await preview([stmt("DELETE FROM media_entities WHERE id='e1'")]);
      expect(p['committable'], true);
      // Someone attaches a child to the row after the preview. The deleted
      // row itself is unchanged, so only the foreign key check can see it.
      await d.insert('media_locations', {
        'id': 'late', 'file_id': 'e1', 'source': 'local',
        'owner_device_id': 'dev', 'locator': '/late.mkv', 'available': 1
      });
      final before = await dump();
      final failed = await failure('db.write', {'previewId': p['previewId']},
          code: FailureCode.conflict);
      final problems = (failed.details['problems'] as List).cast<Map>();
      expect(problems.single['kind'], 'foreign_key');
      expect(problems.single['table'], 'media_locations');
      expect(await dump(), before);
      expect(await d.query('db_commits'), isEmpty);
    });

    test('violations that already existed are not blamed on the batch', () async {
      await d.execute('PRAGMA foreign_keys=OFF');
      await d.insert('media_locations', {
        'id': 'orphan', 'file_id': 'ghost', 'source': 'local',
        'owner_device_id': 'dev', 'locator': '/z.mkv', 'available': 1
      });
      await d.execute('PRAGMA foreign_keys=ON');
      final p = await preview([stmt("UPDATE media_entities SET revision=1 WHERE id='w1'")]);
      expect(p['committable'], true);
      expect((await commit(p))['committed'], true);
      expect((await d.rawQuery('PRAGMA foreign_key_check')), hasLength(1),
          reason: 'the old violation is still there, untouched');
    });

    test('JSON columns must parse and have the right shape', () async {
      for (final value in ['not json', '[1]']) {
        final p = await preview(
            [stmt("UPDATE media_entities SET attributes=? WHERE id='w1'", [value])]);
        expect(p['committable'], false, reason: value);
        expect(((p['problems'] as List).single as Map)['problem'],
            contains('attributes'));
      }
      final ok = await preview(
          [stmt("UPDATE media_entities SET attributes=? WHERE id='w1'", ['{"title":"好"}'])]);
      expect(ok['committable'], true);
    });

    test('an external object id must be the stable hash of what it names', () async {
      final bad = await preview([
        stmt("INSERT INTO media_external_objects VALUES('mine','tmdb','tv','9001','')")
      ]);
      expect(bad['committable'], false);
      final problem = ((bad['problems'] as List).single as Map)['problem'] as String;
      expect(problem, contains('object-'));
      final expected = RegExp(r'object-[0-9a-f]{64}').firstMatch(problem)!.group(0)!;
      final good = await write([
        stmt('INSERT INTO media_external_objects VALUES(?,?,?,?,?)',
            [expected, 'tmdb', 'tv', '9001', ''])
      ]);
      expect(good['committed'], true);
    });

    test('shelf text follows the viewer-text rule and its works must exist', () async {
      for (final payload in [
        '{"placement":"shelf","title":"见 https://example.test/w1","items":[{"workId":"w1"}]}',
        '{"placement":"shelf","title":"今晚","items":[{"workId":"nowhere"}]}',
        '{"placement":"shelf","title":"今晚","items":"x"}',
      ]) {
        final p = await preview([
          stmt('INSERT INTO ui_shelves VALUES(?,?,?)', ['s', payload, 't'])
        ]);
        expect(p['committable'], false, reason: payload);
      }
      final ok = await write([
        stmt('INSERT INTO ui_shelves VALUES(?,?,?)', [
          's',
          '{"placement":"shelf","title":"今晚看点轻松的","items":[{"workId":"w1"}]}',
          't'
        ])
      ]);
      expect(ok['committed'], true);
    });
  });

  group('undo', () {
    test('restores the exact rows, is itself a commit, and can be undone again',
        () async {
      final base = await dump();
      final done = await write([
        stmt("UPDATE media_entities SET revision=4, attributes='{\"title\":\"改\"}' WHERE id='w1'"),
        stmt("DELETE FROM media_entities WHERE id='e1'"),
        stmt("INSERT INTO ui_shelves VALUES('s','{\"items\":[]}','t')"),
      ], reason: '试试');
      final afterWrite = await dump();
      expect(afterWrite, isNot(base));

      final dry = await call('db.undo', {'commitId': done['commitId'], 'dryRun': true});
      expect(dry['status'], 'dry_run');
      expect(dry['committed'], false);
      expect(await dump(), afterWrite);

      final undone = await call('db.undo',
          {'commitId': done['commitId'], 'reason': '不要了'}, invocationId: 'inv-undo');
      expect(undone['status'], 'undone');
      expect(undone['undoes'], done['commitId']);
      expect(undone['commitId'], isNot(done['commitId']));
      final restored = jsonDecode(await dump()) as Map;
      final expected = jsonDecode(base) as Map;
      for (final table in ['media_entities', 'ui_shelves']) {
        expect(restored[table], expected[table], reason: table);
      }
      final commits = await d.query('db_commits', orderBy: 'sequence');
      expect(commits.map((c) => c['kind']), ['write', 'undo']);
      expect(commits.last['undoes'], done['commitId']);
      expect(commits.last['invocation_id'], 'inv-undo');
      expect(commits.last['reason'], '不要了');
      expect(commits.last['actor'], 'agent');
      expect((await d.query('body_changes', orderBy: 'sequence')).map((r) => r['type']),
          ['db.write', 'db.undo']);
      expect(await d.rawQuery('SELECT name FROM sqlite_temp_master'), isEmpty);

      // The first commit is not undone twice: its rows are not as it left them.
      final again = await failure('db.undo', {'commitId': done['commitId']},
          code: FailureCode.conflict);
      expect(again.details['conflictCount'], isPositive);
      // Undoing the undo does the write again.
      await call('db.undo', {'commitId': undone['commitId']});
      final redone = jsonDecode(await dump()) as Map;
      final written = jsonDecode(afterWrite) as Map;
      for (final table in ['media_entities', 'ui_shelves']) {
        expect(redone[table], written[table], reason: table);
      }
    });

    test('refuses when a row is no longer as the commit left it, and lists it',
        () async {
      final done = await write([
        stmt("UPDATE media_entities SET revision=4 WHERE id='w1'"),
        stmt("UPDATE media_entities SET revision=4 WHERE id='r1'"),
        stmt("INSERT INTO ui_shelves VALUES('s','{\"items\":[]}','t')"),
        stmt("DELETE FROM media_entities WHERE id='e1'"),
      ]);
      await d.update('media_entities', {'revision': 99}, where: "id='w1'");
      await d.delete('ui_shelves', where: "id='s'");
      await d.insert('media_entities', {
        'id': 'e1', 'kind': 'episode', 'parent_id': 'r1', 'revision': 0,
        'attributes': '{"title":"别人重建的"}'
      });
      final before = await dump();
      final failed = await failure('db.undo', {'commitId': done['commitId']},
          code: FailureCode.conflict);
      expect(failed.details['conflictCount'], 3);
      final conflicts = (failed.details['conflicts'] as List).cast<Map>();
      expect(conflicts.map((c) => '${c['table']}:${c['problem']}').toSet(), {
        'media_entities:row_changed',
        'ui_shelves:row_missing',
        'media_entities:row_occupied',
      });
      final changed = conflicts.singleWhere((c) => c['problem'] == 'row_changed');
      expect(changed['key'], {'id': 'w1'});
      expect((changed['actual'] as Map)['revision'], 99);
      expect((changed['expected'] as Map)['revision'], 4);
      expect(await dump(), before);
      await failure('db.undo', {'commitId': 'dbcommit-none'},
          code: FailureCode.notFound);
    });

    test('works after the app restarts, from the audit alone', () async {
      final done = await write([stmt("DELETE FROM media_entities WHERE id='e1'")]);
      db = createDbService(database: d, media: f.service, uiData: ui);
      h = Harness([DbCapability(db)]);
      await call('db.undo', {'commitId': done['commitId']});
      expect(await d.query('media_entities', where: "id='e1'"), hasLength(1));
    });
  });

  group('after a commit', () {
    test('reads see the change, the interface is told, and the entity events go out',
        () async {
      expect((await f.identities.mergedMetadata('w1'))['fields'],
          containsPair('title', '原作'));
      final changed = ui.changes.first.timeout(const Duration(seconds: 2));
      final done = await write([
        stmt('INSERT INTO media_overrides(entity_id,field,value,invocation_id,mode,actor,origin,changed_at) VALUES(?,?,?,?,?,?,?,?)',
            ['w1', 'title', '"改名后"', 'i', 'persistent', 'agent', 'mcp', '2026-10-21T00:00:00Z']),
      ]);
      await changed;
      expect((await f.identities.mergedMetadata('w1'))['fields'],
          containsPair('title', '改名后'));
      expect(done['refreshed'], containsAll(['ui_data']));
      expect(done['notified'], [
        {'event': 'media.assets.changed', 'kind': 'metadata', 'entities': 1}
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final event = events.singleWhere((e) => e['kind'] == 'metadata');
      expect(event['event'], 'media.assets.changed');
      expect(event['entityId'], 'w1');
      expect(event['commitId'], done['commitId']);
      expect(event['source'], 'db.write');
      expect(event['changedFields'], ['media_overrides']);
    });

    test('an artwork override announces artwork and starts the image', () async {
      final done = await write([
        stmt('INSERT INTO media_overrides(entity_id,field,value,invocation_id,mode,actor,origin,changed_at) VALUES(?,?,?,?,?,?,?,?)',
            ['w1', 'artwork.poster', '{"url":"https://img.test/p.png"}', 'i', 'persistent', 'agent', 'mcp', '2026-10-21T00:00:00Z']),
      ]);
      expect((done['notified'] as List).map((e) => (e as Map)['kind']), ['artwork']);
      expect(done['refreshed'], contains('artwork_cache'));
      final merged = await f.identities.mergedMetadata('w1');
      expect((merged['fields'] as Map)['artwork.poster'],
          {'url': 'https://img.test/p.png'});
    });

    test('shelves refresh the interface and identity changes announce identity',
        () async {
      var seen = 0;
      final sub = ui.changes.listen((_) => seen++);
      final shelf = await write([
        stmt('INSERT INTO ui_shelves VALUES(?,?,?)', [
          's',
          '{"placement":"shelf","title":"今晚看点轻松的","items":[{"workId":"w1"}]}',
          't'
        ])
      ]);
      expect(shelf['notified'], isEmpty);
      expect(seen, greaterThan(0));
      await sub.cancel();
      final identity = await write([
        stmt("UPDATE media_entities SET revision=1 WHERE id='e1'"),
        stmt("UPDATE media_entities SET revision=1 WHERE id='r1'"),
      ]);
      expect(identity['notified'], [
        {'event': 'media.assets.changed', 'kind': 'identity', 'entities': 2}
      ]);
    });

    test('a preview announces nothing', () async {
      await preview([stmt("UPDATE media_entities SET revision=1 WHERE id='w1'")]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(events, isEmpty);
    });
  });

  group('secrets', () {
    test('previews, commits and the audit as read back are masked', () async {
      SecretRedactor.remember(
          const CredentialRef('test', 'other'), 'qqTopSecret77');
      final p = await preview([
        stmt('INSERT INTO media_overrides(entity_id,field,value,invocation_id) VALUES(?,?,?,?)',
            ['w1', 'note', '"qqTopSecret77 and token=abc123"', 'i']),
      ]);
      expect(jsonEncode(p), isNot(contains('qqTopSecret77')));
      expect(jsonEncode(p), isNot(contains('abc123')));
      final done = await commit(p);
      expect(jsonEncode(done), isNot(contains('qqTopSecret77')));
      final audit = await call('db.query', {'sql': 'SELECT * FROM db_commits'});
      expect(jsonEncode(audit), isNot(contains('qqTopSecret77')));
      expect(jsonEncode(audit), isNot(contains('abc123')));
      final stored = (await d.query('media_overrides')).single['value'] as String;
      expect(stored, contains('qqTopSecret77'),
          reason: 'the data itself is not altered, only what is shown');
    });
  });

  group('Classic observations', () {
    test('a direct revoke of a classic_match binding follows the documented sync rules',
        () async {
      final path = '${f.media.path}/classic.mkv';
      await File(path).writeAsString('video');
      JsonMap row({int episode = 7101, String title = '第一集'}) => {
            'filePath': path,
            'animeName': '系列',
            'episodeTitle': title,
            'animeId': 7001,
            'episodeId': episode,
            'videoHash': null,
            'watchProgress': 0.5,
            'lastPosition': 1000,
          };
      f.classic.rows[path] = row();
      await f.identities.importLegacy(await f.classic.history());
      expect(
          await rows(
              "SELECT count(*) AS n FROM media_bindings WHERE source='classic_match' AND status='accepted'"),
          [
            {'n': 4}
          ]);
      expect(await rows('SELECT count(*) AS n FROM media_classic_current'), [
        {'n': 1}
      ]);
      final fileBinding = (await rows(
              "SELECT b.id FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id WHERE e.kind='file' AND b.source='classic_match'"))
          .single['id'] as String;

      // 1. Revoked directly; Classic's record is unchanged, so the sync leaves it.
      await write([
        stmt("UPDATE media_bindings SET status='revoked' WHERE id=?", [fileBinding])
      ]);
      await f.identities.importLegacy(await f.classic.history());
      expect(
          await rows('SELECT status FROM media_bindings WHERE id=?', [fileBinding]),
          [
            {'status': 'revoked'}
          ]);
      expect(await rows('SELECT count(*) AS n FROM media_classic_observations'), [
        {'n': 1}
      ]);

      // 2. Deleting the current pointer makes the next sync import it afresh.
      final location = (await rows('SELECT location_id FROM media_classic_current'))
          .single['location_id'] as String;
      await write([
        stmt('DELETE FROM media_classic_current WHERE location_id=?', [location])
      ]);
      await f.identities.importLegacy(await f.classic.history());
      expect(await rows('SELECT count(*) AS n FROM media_classic_observations'), [
        {'n': 2}
      ]);
      expect(
          await rows(
              "SELECT count(*) AS n FROM media_bindings b JOIN media_entities e ON e.id=b.entity_id WHERE e.kind='file' AND b.source='classic_match' AND b.status='accepted'"),
          [
            {'n': 1}
          ]);

      // 3. A changed Classic record regenerates the match.
      f.classic.rows[path] = row(episode: 7102, title: '第二集');
      await f.identities.importLegacy(await f.classic.history());
      expect(await rows('SELECT count(*) AS n FROM media_classic_observations'), [
        {'n': 3}
      ]);
    });
  });
}

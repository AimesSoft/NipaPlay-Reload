import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/events/signals.dart';
import 'package:nipaplay/next/harness_hooks.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/subscriptions/capability.dart';
import 'package:nipaplay/next/subscriptions/store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Directory root;
  late Database db;
  late Harness api;
  late StateCapability state;
  late List<JsonMap> events;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('subscriptions-');
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    final store = SubscriptionStore(db);
    state = StateCapability([]);
    registerSubscriptions(state, store);
    api = Harness([SubscriptionCapability(store), state]);
    events = [];
    BodySignals.emit = (name, id, facts) async {
      // Delivery is after commit, so subscribers can read the committed row.
      await db.query('subscriptions');
      events.add({'event': name, 'id': id, ...facts});
    };
  });
  tearDown(() async {
    BodySignals.emit = null;
    await db.close();
    await root.delete(recursive: true);
  });
  Future<JsonMap> call(String name, JsonMap input) async {
    final out = await api.invokeJson(name, input, Invocation(origin: 'test'));
    expect(out, isA<Completed>(), reason: jsonEncode(out.toEnvelope()));
    final value = (out as Completed).value.toJson();
    expect(api.lookup(name)!.spec.output.validate(value), isEmpty);
    return value;
  }

  JsonMap declaration([String id = 'follow']) => {
        'id': id,
        'title': '订阅作品',
        'kind': 'series',
        'note': '按用户指定字幕组巡查',
        'program': 'tools/patrol.py',
        'createdBy': 'conversation-1',
        'facts': {
          'rules': {
            'include': ['指定版本']
          }
        }
      };
  JsonMap report(String reportId) => {
        'id': 'follow',
        'reportId': reportId,
        'checkedAt': '2026-11-08T12:00:00Z',
        'found': [
          {'title': '第 1 集', 'episode': '1'}
        ],
        'downloads': [
          {'jobId': 'job-1', 'title': '第 1 集', 'episode': '1'}
        ],
        'errors': <String>[]
      };

  test('CRUD, state view and committed change events preserve declarations',
      () async {
    final saved = await call('subscription.put', declaration());
    expect(saved['state'], 'active');
    expect(saved['revision'], 1);
    final updated =
        await call('subscription.put', {...declaration(), 'title': '新标题'});
    expect(updated['createdAt'], saved['createdAt']);
    expect(updated['revision'], 2);
    final generated =
        await call('subscription.put', declaration('other')..remove('id'));
    expect(generated['id'], startsWith('sub-'));
    await call('subscription.set_state', {'id': 'follow', 'state': 'paused'});
    expect(
        (await call('subscription.list', {'state': 'paused'}))['subscriptions'],
        hasLength(1));
    await call('subscription.set_state', {'id': 'follow', 'state': 'active'});
    await call('subscription.set_state', {'id': 'follow', 'state': 'ended'});
    final rows = await call('state.query', {
      'view': 'subscriptions',
      'filter': {
        'id': {'eq': 'follow'}
      }
    });
    expect((rows['rows'] as List).single['title'], '新标题');
    expect(HarnessHooks.events, contains('subscription.changed'));
    expect(events.every((e) => e['event'] == 'subscription.changed'), isTrue);
    expect(
        (await call('subscription.remove', {'id': 'follow'}))['removed'], true);
    expect((await call('subscription.remove', {'id': 'follow'}))['removed'],
        false);
    expect(await db.query('jobs'), isEmpty);
  });

  test(
      'reports retain 20 observations, retry idempotently, reject conflicts and cascade only records',
      () async {
    await call('subscription.put', declaration());
    for (var i = 0; i < 23; i++) {
      await call('subscription.report', report('check-$i'));
    }
    final last = await call('subscription.get', {'id': 'follow'});
    expect(last['reports'], hasLength(20));
    expect((last['latestReport'] as Map)['reportId'], 'check-22');
    final count = events.length;
    await call('subscription.report', report('check-22'));
    expect(events.length, count);
    final conflict = await api.invokeJson(
        'subscription.report',
        {
          ...report('check-22'),
          'errors': ['changed']
        },
        Invocation(origin: 'test'));
    expect((conflict as Failed).failure.code, FailureCode.conflict);
    await call('subscription.remove', {'id': 'follow'});
    expect(await db.query('subscription_reports'), isEmpty);
  });

  test('invalid work/path/state and oversized facts/report fail before commit',
      () async {
    for (final input in [
      {...declaration(), 'program': '../outside.py'},
      {...declaration(), 'workId': 'missing'},
      {...declaration(), 'state': 'guess'},
      {
        ...declaration(),
        'facts': {'large': List.filled(17000, '字').join()}
      },
    ]) {
      expect(
          await api.invokeJson(
              'subscription.put', input, Invocation(origin: 'test')),
          isA<Failed>());
    }
    expect(events, isEmpty);
    await call('subscription.put', declaration());
    expect(
        await api.invokeJson(
            'subscription.report',
            {
              ...report('large'),
              'errors': List.filled(20, List.filled(999, '字').join())
            },
            Invocation(origin: 'test')),
        isA<Failed>());
    expect(await db.query('subscription_reports'), isEmpty);
  });

  test(
      'version 27 upgrades without changing existing media, and survives reopening',
      () async {
    await db.insert('media_entities', {
      'id': 'work-old',
      'kind': 'work',
      'attributes': '{"title":"保留"}',
      'revision': 0
    });
    await db.execute('DROP TABLE subscription_reports');
    await db.execute('DROP TABLE subscriptions');
    await db.execute('DROP TABLE harness_secret_names');
    await db.setVersion(27);
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    expect(await db.getVersion(), 28);
    expect((await db.query('media_entities')).single['id'], 'work-old');
    final store = SubscriptionStore(db);
    await store.put(declaration());
    await store.setState('follow', 'paused');
    await db.close();
    db = await openNextDatabase(root, factory: databaseFactoryFfi);
    expect((await SubscriptionStore(db).get('follow'))['state'], 'paused');
    final triggers = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='trigger' AND tbl_name='subscriptions'");
    expect(triggers, hasLength(3));
  });
}

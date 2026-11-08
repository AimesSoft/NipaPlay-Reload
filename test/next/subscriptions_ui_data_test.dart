import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/ui_data/ui_data.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test(
      'subscription stream pushes local changes and fake peer owners without polling or exposing rules',
      () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('subscriptions-ui-');
    final core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => false,
        loadImportedKeys: () async => {},
        classic: MemoryClassic(),
        authorizedRoots: () => [root.path],
        mediaProviders: const []);
    await core.ready;
    addTearDown(() async {
      await core.close();
      await root.delete(recursive: true);
    });
    await core.uiData.start();
    final api = Harness(core.capabilities);
    final updates = <List<UiSubscription>>[];
    final first = Completer<void>();
    var target = Completer<void>();
    final sub = core.uiData.subscriptions().listen((rows) {
      updates.add(rows);
      if (!first.isCompleted) first.complete();
      if (rows.any((r) => r.title == '本机订阅') && !target.isCompleted) {
        target.complete();
      }
    });
    addTearDown(sub.cancel);
    await first.future.timeout(const Duration(seconds: 10));
    final put = await api.invokeJson(
        'subscription.put',
        {
          'id': 'same-id',
          'title': '本机订阅',
          'kind': 'series',
          'note': '每周检查',
          'program': 'tools/patrol.py',
          'facts': {'privateRule': 'owner-only'},
          'createdBy': 'conversation'
        },
        Invocation(origin: 'test'));
    expect(put, isA<Completed>());
    await target.future.timeout(const Duration(seconds: 10));
    expect(updates.last.single.device, isNull);
    final mesh = core.uiData.meshLibrary!;
    mesh.heardSubscriptions('peer-a', '书房电脑', [
      {
        'id': 'same-id',
        'title': '远端订阅',
        'kind': 'series',
        'state': 'paused',
        'note': '等待更新',
        'lastCheckedAt': '2026-11-08T08:00:00Z',
        'downloads': [
          {'jobId': 'remote-job', 'title': '远端第 3 集', 'episode': '3'}
        ],
        'errors': <String>[]
      }
    ]);
    final peer =
        (await core.uiData.subscriptions(deviceId: 'peer-a').first).single;
    expect(peer.id, 'same-id');
    expect(peer.deviceId, 'peer-a');
    expect(peer.device, '书房电脑');
    expect(peer.state, UiSubscriptionState.paused);
    expect(peer.downloads.single.episode, '3');
    expect(await core.uiData.subscriptions(deviceId: 'unknown').first, isEmpty);
    final shared = (await core.uiData.meshSubscriptions()).single;
    expect(shared.containsKey('facts'), false);
    expect(shared.containsKey('program'), false);
    expect(shared.containsKey('createdBy'), false);
    mesh.heardSubscriptions('peer-a', null, null);
    expect(await core.uiData.subscriptions(deviceId: 'peer-a').first, isEmpty);
    await api.invokeJson('subscription.set_state',
        {'id': 'same-id', 'state': 'paused'}, Invocation(origin: 'test'));
    expect((await core.uiData.subscriptions().first).single.state,
        UiSubscriptionState.paused);
    await api.invokeJson(
        'subscription.remove', {'id': 'same-id'}, Invocation(origin: 'test'));
    expect(await core.uiData.subscriptions().first, isEmpty);
  });
}

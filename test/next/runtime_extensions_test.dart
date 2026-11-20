import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/chat/model_launch.dart';
import 'package:nipaplay/next/store/capability.dart';
import 'package:nipaplay/next/store/rika_store.dart';
import 'package:nipaplay/next/store/runtime_extensions.dart';
import 'package:nipaplay/next/store/store_fetch.dart';

void main() {
  late Directory temp;
  late AgentEndpoint endpoint;
  late File stub;
  late File calls;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('extension-rpc-');
    addTearDown(() => temp.delete(recursive: true));
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'test',
        port: 0,
        credentialFile: File('${temp.path}/endpoint.json'),
        seedRepository: Directory('${temp.path}/seed'));
    addTearDown(endpoint.stop);
    calls = File('${temp.path}/calls.jsonl');
    stub = File('${temp.path}/stub.py');
    await stub.writeAsString(
        '#!/usr/bin/env python3\nlog = ${jsonEncode(calls.path)}\n$_server');
    expect((await Process.run('chmod', ['755', stub.path])).exitCode, 0);
  });

  List<Map> requests() =>
      calls.readAsLinesSync().map((line) => jsonDecode(line) as Map).toList();

  for (final managed in [true, false]) {
    test('Codex market actions with managed configuration: $managed', () async {
      final home = await Directory('${temp.path}/codex-home').create();
      await File('${home.path}/config.toml').writeAsString('');
      final list = await Directory('${temp.path}/index').create();
      const plugin = '{"name":"fixture","version":"1.0.0","description":"red"}';
      final file = await File('${list.path}/plugin.json').writeAsString(plugin);
      final store = RikaStore(
          root: Directory('${temp.path}/store'),
          listSources: () => [Uri.directory(list.path)],
          fetch: StoreFetch(HttpClient.new),
          registries: () async => [],
          provided: () async => null);
      addTearDown(store.close);
      await File('${list.path}/index.json').writeAsString(jsonEncode({
        'version': 1,
        'items': [
          {
            'id': 'fixture',
            'name': 'Fixture',
            'kind': 'codexPlugin',
            'version': '1.0.0',
            'description': 'Fixture',
            'files': [
              {
                'path': '.codex-plugin/plugin.json',
                'url': 'plugin.json',
                'bytes': plugin.length,
                'sha256': sha256.convert(utf8.encode(plugin)).toString()
              }
            ],
          }
        ]
      }));
      final host = ChatHost(
          endpoint: endpoint,
          repository: temp,
          labRoot: temp,
          codexExecutable: stub.path,
          modelLaunch: () async =>
              ModelLaunch(revision: 0, home: managed ? home : null));
      addTearDown(host.close);
      await host.start();
      final extensions =
          RuntimeExtensions(host: () => host, installer: () => null, openUrl: () => null);
      final harness = Harness([
        StoreCapability(store, extensions: extensions),
        RuntimeExtensionCapability(extensions)
      ]);
      Future<Outcome<JsonEncodable>> invoke(String action, JsonMap input) =>
          harness.invokeJson(action, input, Invocation(origin: 'gui'));
      List<Map> writes() => requests()
          .where((request) => {
                'marketplace/add',
                'marketplace/remove',
                'plugin/install',
                'plugin/uninstall'
              }.contains(request['method']))
          .toList();
      final install = {'id': 'fixture', 'version': '1.0.0'};
      final market = store.codexMarketplace('fixture');
      if (!managed) {
        expect((await extensions.codexPlugins())['writable'], false);
        expect(await invoke('store.install', install), isNot(isA<Completed>()));
        expect(
            await invoke('store.codex.marketplace.add', {'source': list.path}),
            isNot(isA<Completed>()));
        expect(
            await invoke('store.codex.install',
                {'marketplace': 'external', 'plugin': 'other'}),
            isNot(isA<Completed>()));
        expect(await invoke('store.codex.remove', {'id': 'other@external'}),
            isNot(isA<Completed>()));
        expect(writes(), isEmpty);
        expect(await market.exists(), false);
        return;
      }
      await file.writeAsString(plugin.replaceFirst('red', 'bad'));
      expect(await invoke('store.install', install), isNot(isA<Completed>()));
      expect(writes(), isEmpty);
      expect(await market.exists(), false);
      await file.writeAsString(plugin);
      expect(await invoke('store.install', install), isA<Completed>());
      final manifest = File('${market.path}/.agents/plugins/marketplace.json');
      expect(jsonDecode(await manifest.readAsString())['name'],
          'nipaplay-fixture');
      expect(writes().map((request) => request['params']), [
        {'source': market.path},
        {'pluginName': 'fixture', 'marketplacePath': manifest.path},
      ]);
      expect(await invoke('store.remove', {'id': 'fixture'}), isA<Completed>());
      expect(writes().map((request) => request['method']), [
        'marketplace/add',
        'plugin/install',
        'plugin/uninstall',
        'marketplace/remove',
      ]);
      expect(writes()[2]['params'], {'pluginId': 'fixture@nipaplay-fixture'});
      expect(await market.exists(), false);
      expect(await store.installed(), isEmpty);
    }, skip: Platform.isWindows);
  }

  test('a Web process without a ready URL falls back to SDK chat', () async {
    final webBin = '${temp.path}/scope/dsh/lib/bin.js';
    final rows = [
      'host-webserver',
      'client-connection',
      'client-modules',
      'cordis-client-runner',
      'client-ui-renderer',
      'api-remotes',
      'client-ui-theme',
      'client-locale',
      'client-ui-settings',
      'client-shortcuts',
      'client-ui-settings-plugins',
      'client-ui-settings-plugin-inventory',
      'client-ui-agent-preset',
      'api-session-controller',
      'client-file-upload',
      'client-ui-conversation',
      'client-ui-layout',
      'client-ui-session',
      'client-ui-workspace',
      'api-workspace-controller',
      'client-ui-sidebar',
      'client-ui-plugin-manager',
      'host-plugin-inventory',
      'api-settings-controller',
      'workspace',
      'client-ui-settings-general',
      'host-frontend-static',
    ];
    for (final file in [
      webBin,
      '${temp.path}/scope/dsh-web-frontend/dist/index.html',
      for (final row in rows) '${temp.path}/scope/dsh-$row/lib/index.js'
    ]) {
      await File(file).create(recursive: true);
    }
    await stub.copy(webBin);
    expect((await Process.run('chmod', ['755', webBin])).exitCode, 0);
    final host = ChatHost(
        endpoint: endpoint,
        repository: temp,
        dsh: DshRuntime(
            node: '/usr/bin/env',
            bin: stub.path,
            webBin: webBin,
            version: 'fixture'),
        dshPlugins: Directory('assets/next/agent/dsh'),
        modelLaunch: () async => ModelLaunch(
            revision: 0,
            route: DshRoute(
                baseUrl: 'http://127.0.0.1:9/v1',
                model: 'fake',
                key: 'not-a-real-extension-key')));
    addTearDown(host.close);
    await host.start();
    expect(host.dshWebUri, isNull);
    await host.getMainSession();
    expect((await host.startTurn('SDK only'))['turn']['id'], 'turn-fixture');
    expect(
        requests()
            .where((request) => request['method'] == 'initialize')
            .map((request) => request['program']),
        [webBin, stub.path]);
    expect(
        requests().singleWhere(
            (request) => request['method'] == 'turn/start')['program'],
        stub.path);
  }, skip: Platform.isWindows);
}

const _server = r'''
import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if 'method' not in request:
        continue
    with open(log, 'a') as handle:
        print(json.dumps({**request, 'program':sys.argv[0]}), file=handle)
    if 'id' not in request:
        continue
    result = {
        'config/read': {'config': {'model': 'fake', 'model_provider': 'fixture'}},
        'plugin/list': {'marketplaces': [{'name':'external','plugins':[{'name':'other'}]}]},
        'hooks/list': {'data': []},
        'thread/start': {'thread': {'id': 'thread-fixture', 'turns': []}, 'model': 'fake', 'modelProvider': 'fixture'},
        'thread/resume': {'thread': {'id': 'thread-fixture', 'turns': []}, 'model': 'fake', 'modelProvider': 'fixture'},
        'turn/start': {'turn': {'id': 'turn-fixture', 'status': 'inProgress'}},
    }.get(request['method'], {})
    print(json.dumps({'id': request['id'], 'result': result}), flush=True)
''';

@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/runtime/codex_manifest.dart';
import 'package:nipaplay/next/runtime/codex_runtime.dart';
import 'package:nipaplay/next/runtime/dsh_install.dart';
import 'package:nipaplay/next/runtime/dsh_manifest.dart';
import 'package:nipaplay/next/chat/session_store.dart';
import 'package:nipaplay/next/mesh/runtime.dart';
import 'package:nipaplay/next/memory/recent.dart';
import 'package:nipaplay/next/next_database.dart';
import 'package:nipaplay/next/programs/runtime.dart';
import 'package:nipaplay/next/repository_location.dart';
import 'package:nipaplay/next/settings/denylist.dart';
import 'package:nipaplay/next/settings/host_settings_service.dart';
import 'package:nipaplay/next/settings/classic_host_device_settings.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/web_server_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nipaplay/next/state/change_history.dart';
import 'package:nipaplay/next/state/query.dart';
import 'package:nipaplay/next/ui_data/host_settings.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final class _Location implements RepositoryLocation {
  _Location(this.path);
  @override
  final String path;
  @override
  Future<void> get ready async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root, lab, repository;
  late HostSettingsService settings;
  late ProgramRuntime programs;
  late MeshRuntime mesh;
  late Database database;
  ChatHost? host;
  HttpServer? server;
  late String secret;
  late AgentEndpoint endpoint;
  late ChangeHistory history;
  setUp(() async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    lab = await Directory.systemTemp.createTemp('x52-host-');
    root = await Directory('${lab.path}/next').create();
    repository = await Directory('${lab.path}/harness').create();
    database = await openNextDatabase(root, factory: databaseFactoryFfi);
    history = ChangeHistory(database);
    secret =
        'x52-${Random.secure().nextInt(1 << 32)}-${Random.secure().nextInt(1 << 32)}';
    final vault = LabModelVault();
    mesh = MeshRuntime(root: root, vault: vault, token: () async => null);
    programs =
        ProgramRuntime(enabled: false, location: _Location(repository.path));
    endpoint = AgentEndpoint(
        harness: Harness([]),
        seed: {},
        appVersion: 'x52',
        credentialFile: File('${root.path}/endpoint.json'),
        seedRepository: Directory('${root.path}/harness-seed'),
        port: 0);
    settings = HostSettingsService(
        root: root,
        vault: vault,
        meshRuntime: mesh,
        programs: programs,
        history: history,
        chat: () => host,
        chatProblem: () => null,
        repository: () => repository.path,
        codexHome: Directory('${lab.path}/codex-home'),
        checkCodex: () async => const UiModelCheck(ok: false, message: '尚未配置'),
        modelSaved: () async {});
  });
  tearDown(() async {
    AppHttpProxy.clear();
    await host?.close();
    host = null;
    await server?.close(force: true);
    server = null;
    await settings.close();
    await mesh.close();
    await history.drain();
    await database.close();
    await lab.delete(recursive: true);
  });
  UiModelChoice choice(String url,
          {String? key, String model = 'managed-model'}) =>
      UiModelChoice(
          source: UiModelSource.nipaplay,
          provider: 'DeepSeek',
          baseUrl: url,
          model: model,
          apiKey: key);

  Future<void> scanSecrets(Iterable<Object?> public) async {
    await history.drain();
    var files = 0;
    await for (final entry in lab.list(recursive: true, followLinks: false)) {
      if (entry is File) {
        files++;
        final bytes = await entry.readAsBytes();
        expect(utf8.decode(bytes, allowMalformed: true).contains(secret), false,
            reason: 'Secret found in ${entry.path.substring(lab.path.length)}');
      }
    }
    expect(files, greaterThan(0));
    expect(jsonEncode(public.toList()).contains(secret), false);
  }

  test('host keys are write-only, retained by null and cleared without setting journal values', () async {
    SharedPreferences.setMockInitialValues({});
    final old = CredentialStore.instance;
    final vault = LabModelVault();
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    addTearDown(() => CredentialStore.instance = old);
    final device = ClassicHostDeviceSettings(vault: vault, webServer: WebServerService(),
      spoilerChanged: (key) async {
        await CredentialStore.instance.write(await SharedPreferences.getInstance(), 'spoiler_ai_api_key', key);
      });
    await device.setKeys(spoilerAi: secret, tmdb: secret);
    expect((await device.keys()).spoilerAi, true);
    expect((await device.keys()).tmdb, true);
    await device.setKeys();
    expect((await device.keys()).tmdb, true);
    final prefs = await SharedPreferences.getInstance();
    expect(jsonEncode({for (final key in prefs.getKeys()) key: prefs.get(key)}).contains(secret), false);
    await scanSecrets([{'spoilerAi': (await device.keys()).spoilerAi, 'tmdb': (await device.keys()).tmdb}]);
    await device.setKeys(spoilerAi: '', tmdb: '');
    expect((await device.keys()).spoilerAi, false);
    expect((await device.keys()).tmdb, false);
  });

  test('keys stay in vault; null retains only matching provider credentials',
      () async {
    await settings.setModel(choice('http://127.0.0.1:12345/v1', key: secret));
    await settings.setModel(choice('http://127.0.0.1:12345/v1'));
    expect((await settings.model()).hasKey, true);
    final launch = await settings.launch();
    await launch.prepare!();
    expect(launch.environment.values.single == secret, true);
    final config =
        await File('${launch.home!.path}/config.toml').readAsString();
    expect(config, contains('env_key = "NIPAPLAY_MODEL_API_KEY"'));
    expect(config, contains('trust_level = "trusted"'));
    await settings.setModel(choice('http://localhost:12346/v1'));
    expect((await settings.model()).hasKey, false);
    final rows = await database.query('body_changes');
    await history.drain();
    expect(
        (await database.query('body_changes'))
            .every((r) => r['actor'] == 'user' && r['origin'] == 'gui'),
        true);
    await scanSecrets([rows, config]);
  });

  test('custom endpoint needs only address/key/model; launch preserves saved vault identity', () async {
    await settings.setModel(UiModelChoice(source: UiModelSource.nipaplay,
      provider: '', baseUrl: 'https://custom.example/prefix/responses',
      model: 'arbitrary-model', apiKey: secret));
    final file = File('${root.path}/model.json');
    final saved = await file.readAsString();
    final launch = await settings.launch();
    await launch.prepare!();
    expect((await settings.model()).provider, '自定义');
    expect((await settings.model()).hasKey, true);
    expect(await file.readAsString(), saved);
    expect(await File('${launch.home!.path}/config.toml').readAsString(),
      contains('base_url = "https://custom.example/prefix"'));
    expect(launch.environment.values.single, secret);
    await scanSecrets([saved]);
  });

  test(
      'host authorization takes effect immediately, remains absent from Actions',
      () async {
    await File('${root.path}/program.json')
        .writeAsString('{"enabled":false,"extra":1}');
    expect(programs.requireEnabled, throwsA(isA<Failure>()));
    await settings.setRemotePrograms(true);
    programs.requireEnabled();
    expect(await settings.remotePrograms(), true);
    expect(
        jsonDecode(
            await File('${root.path}/program.json').readAsString())['extra'],
        1);
    await settings.setRemotePrograms(false);
    expect(programs.requireEnabled, throwsA(isA<Failure>()));
    final actions = Harness([programs.capability]);
    for (final id in [
      'hostSettings.setModel',
      'hostSettings.setMesh',
      'model.set',
      'mesh.set',
      'remotePrograms.set'
    ]) {
      expect(actions.lookup(id), isNull);
      expect(meshActionAllowed(id), false);
    }
    for (final key in [
      'program.enabled',
      'model.provider',
      'model_source',
      'mesh.enabled',
      'mesh.coordinator',
      'mesh.fileProxyPort'
    ]) {
      expect(isSettingDenied(key), true);
    }
  });

  test(
      'mesh leaves config intact when unavailable, and remembers known devices',
      () async {
    await File('${root.path}/mesh-devices.json').writeAsString(jsonEncode({
      'devices': [
        {'device_id': 'other', 'device_name': '另一台', 'revoked': false}
      ]
    }));
    await File('${root.path}/mesh-host-facts.json').writeAsString(jsonEncode({
      'other': {
        'roles': ['headless'],
        'programExecution': {'enabled': true}
      }
    }));
    await settings.setMesh(const UiMeshChoice(
        joined: true,
        name: '这台',
        coordinator: 'https://mesh.example/v1',
        port: 47812,
        addresses: ['127.0.0.1:47812', '[::1]:47812'],
        fileProxyPort: 54321));
    final value = await settings.mesh();
    expect(value.available, false);
    expect(value.joined, false);
    expect(value.problem, contains('签发者'));
    expect(value.devices.single.name, '另一台');
    expect(value.devices.single.remotePrograms, true);
    expect(value.devices.single.roles, ['headless']);
    expect(value.addresses, ['127.0.0.1:47812', '[::1]:47812']);
    await settings.setMesh(const UiMeshChoice(joined: false));
    expect(mesh.status, 'disabled');
    final saved =
        jsonDecode(await File('${root.path}/mesh.json').readAsString());
    expect(saved['coordinator'], 'https://mesh.example/v1');
    expect(saved['enabled'], false);
  });

  test(
      'check follows app proxy and path prefix; rejects keys without echoing response',
      () async {
    final requests = <String>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      requests.add(request.uri.path);
      final valid = request.headers.value(HttpHeaders.authorizationHeader) ==
          'Bearer $secret';
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = valid ? 200 : 401;
      request.response.write(jsonEncode(valid
          ? {'object': 'response', 'status': 'completed', 'output': [
              {'type': 'function_call', 'name': 'nipaplay_connection_check',
                'call_id': 'check', 'arguments': '{}'}]}
          : {
              'error': {'message': 'echo $secret'}
            }));
      await request.response.close();
    });
    AppHttpProxy.set('http://127.0.0.1:${server!.port}');
    await settings
        .setModel(choice('http://provider.invalid/prefix/v1', key: secret));
    final ok = await settings.checkModel();
    expect(ok.ok, true);
    expect(ok.latency, isNotNull);
    await settings.setModel(
        choice('http://provider.invalid/prefix/v1', key: 'wrong-key'));
    final failed = await settings.checkModel();
    expect(failed.ok, false);
    expect(failed.message, contains('密钥'));
    expect(requests, ['/prefix/v1/responses', '/prefix/v1/responses']);
    await scanSecrets([failed.message, await database.query('body_changes')]);
  });


  group('DeepSeek Harness is the runtime', () {
    var runtimeChanges = 0;
    AgentRuntimeFixed fixed = const AgentRuntimeFixed(null);
    late HostSettingsService dshSettings;
    late DshInstall install;

    DshManifest manifest() => DshManifest.parse(jsonEncode({
          'schema': 1,
          'dsh': '1.0.0',
          'node': {
            'version': '24.22.0',
            'assets': {
              'macos-arm64': {
                'url': 'https://nodejs.org/dist/v24.22.0/node.tar.gz',
                'sha256': '0' * 64,
                'bytes': 10,
                'archive': 'tar',
                'executable': 'node/bin/node'
              }
            }
          },
          'registry': 'https://registry.npmjs.org',
          'platforms': ['macos-arm64'],
          'packages': <Object>[],
        }));

    HostSettingsService service({CodexRuntime? codex}) => HostSettingsService(
        root: root,
        vault: LabModelVault(),
        meshRuntime: mesh,
        programs: programs,
        history: history,
        chat: () => null,
        chatProblem: () => null,
        repository: () => repository.path,
        codexHome: Directory('${lab.path}/codex-home'),
        checkCodex: () async => const UiModelCheck(ok: false, message: '尚未配置'),
        modelSaved: () async {},
        dsh: install,
        codex: codex,
        fixedRuntime: () async => fixed,
        defaultRuntime: AgentRuntimeKind.dsh,
        runtimeChanged: () async => runtimeChanges++);

    setUp(() {
      runtimeChanges = 0;
      fixed = const AgentRuntimeFixed(null);
      install = DshInstall(
          root: Directory('${root.path}/dsh-runtime'),
          manifest: manifest(),
          platform: 'macos-arm64',
          notify: () {},
          httpClient: HttpClient.new,
          inUse: () => false);
      dshSettings = service();
    });
    tearDown(() => dshSettings.close());

    test('its route is the model set up here, on either wire, and no file holds the key',
        () async {
      await dshSettings.setModel(UiModelChoice(
          source: UiModelSource.nipaplay,
          provider: 'DeepSeek',
          baseUrl: 'https://api.deepseek.com/chat/completions',
          model: 'deepseek-flash',
          apiKey: secret,
          api: UiModelApi.chat,
          reasoning: 'high',
          compat: const {'thinkingFormat': 'deepseek', 'supportsStore': false}));
      final launch = await dshSettings.launch();
      final route = launch.route!;
      expect(route.baseUrl, 'https://api.deepseek.com');
      expect(route.api, 'openai-completions');
      expect(route.key, secret);
      expect(route.reasoningEffort, 'high');
      expect(launch.executable, isNull);
      expect(launch.home, isNull);
      final provider = (route.piAiConfig['providers'] as Map)[DshRoute.provider]
          as Map;
      expect(provider['api'], 'openai-completions');
      expect(((provider['models'] as List).single as Map)['compat'],
          {'thinkingFormat': 'deepseek', 'supportsStore': false});
      expect(jsonEncode(route.piAiConfig), isNot(contains(secret)));

      final shown = await dshSettings.model();
      expect(shown.runtime, UiAgentRuntimeKind.dsh);
      expect(shown.source, UiModelSource.nipaplay);
      expect(shown.api, UiModelApi.chat);
      expect(shown.reasoning, 'high');
      expect(shown.hasKey, true);

      // The Responses wire loses a pasted endpoint suffix too.
      await dshSettings.setModel(UiModelChoice(
          source: UiModelSource.nipaplay,
          provider: 'Relay',
          baseUrl: 'https://relay.example/v1/responses',
          model: 'm',
          apiKey: secret,
          api: UiModelApi.responses,
          reasoning: '',
          compat: const {}));
      final second = (await dshSettings.launch()).route!;
      expect(second.baseUrl, 'https://relay.example/v1');
      expect(second.api, 'openai-responses');
      expect(second.reasoningEffort, isNull);
      expect(second.compat, isNull);
      await scanSecrets([await database.query('body_changes'), route.piAiConfig]);
    });

    test('Nipa is not ready until the runtime is there, and says what is missing first',
        () async {
      expect((await dshSettings.model()).problem, '请先填写地址和模型名');
      await dshSettings.setModel(choice('https://relay.example/v1', key: secret));
      expect((await dshSettings.model()).problem, '还没有运行环境');
      expect((await dshSettings.dshRuntime()).status, UiDshStatus.notInstalled);
      expect(await dshSettings.dshLaunchRuntime(), isNull);
      // An installation named by the environment stands in for the fetched one.
      final node = File('${lab.path}/node')..writeAsStringSync('');
      final bin = File('${lab.path}/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js')
        ..createSync(recursive: true);
      fixed = AgentRuntimeFixed(AgentRuntimeKind.dsh,
          DshRuntime(node: node.path, bin: bin.path, version: '9'));
      await dshSettings.refreshFixedRuntime();
      expect((await dshSettings.model()).problem, '模型服务尚未启动');
      expect((await dshSettings.dshLaunchRuntime())!.version, '9');
      expect((await dshSettings.dshRuntime()).fixed, true);
    });

    test('the runtime is chosen here unless the environment decides', () async {
      expect((await dshSettings.agentRuntime()).kind, UiAgentRuntimeKind.dsh);
      await expectLater(dshSettings.setAgentRuntime(UiAgentRuntimeKind.codex),
          throwsUnsupportedError);
      final withCodex = service(
          codex: CodexRuntime(
              root: Directory('${root.path}/codex-runtime'),
              platform: 'macos',
              asset: const CodexAsset('x.tgz', '0', 1, 'x'),
              notify: () {},
              httpClient: HttpClient.new,
              inUse: () => false));
      addTearDown(withCodex.close);
      await withCodex.setAgentRuntime(UiAgentRuntimeKind.codex);
      expect(runtimeChanges, 1);
      expect((await withCodex.agentRuntime()).kind, UiAgentRuntimeKind.codex);
      expect(jsonDecode(await File('${root.path}/runtime.json').readAsString()),
          {'runtime': 'codex'});
      await withCodex.setAgentRuntime(UiAgentRuntimeKind.dsh);
      expect((await withCodex.agentRuntime()).kind, UiAgentRuntimeKind.dsh);
      fixed = const AgentRuntimeFixed(AgentRuntimeKind.codex);
      await withCodex.refreshFixedRuntime();
      final decided = await withCodex.agentRuntime();
      expect((decided.kind, decided.fixed), (UiAgentRuntimeKind.codex, true));
      await expectLater(
          withCodex.setAgentRuntime(UiAgentRuntimeKind.dsh), throwsStateError);
      expect(runtimeChanges, 2);
    });

    test('fixed runtime is read once and refreshed on demand', () async {
      var reads = 0;
      AgentRuntimeFixed current = const AgentRuntimeFixed(null);
      final fixedWatch = await Directory('${lab.path}/fixed-watch').create();
      final cached = HostSettingsService(
          root: root,
          vault: LabModelVault(),
          meshRuntime: mesh,
          programs: programs,
          history: history,
          chat: () => null,
          chatProblem: () => null,
          repository: () => repository.path,
          codexHome: Directory('${lab.path}/codex-home'),
          checkCodex: () async =>
              const UiModelCheck(ok: false, message: '尚未配置'),
          modelSaved: () async {},
          fixedRuntime: () async {
            reads++;
            return current;
          },
          defaultRuntime: AgentRuntimeKind.dsh,
          fixedRuntimeDirectory: fixedWatch);
      addTearDown(cached.close);

      expect((await cached.agentRuntime()).fixed, false);
      expect(await cached.effectiveRuntime(), AgentRuntimeKind.dsh);
      expect(reads, 1);

      current = const AgentRuntimeFixed(AgentRuntimeKind.codex);
      expect((await cached.agentRuntime()).fixed, false);
      expect(reads, 1);
      await cached.refreshFixedRuntime();
      expect((await cached.agentRuntime()).fixed, true);
      expect(await cached.effectiveRuntime(), AgentRuntimeKind.codex);
      expect(reads, 2);

      current = const AgentRuntimeFixed(null);
      final changed = cached.changes.first;
      await File('${fixedWatch.path}/agent-runtime.json')
          .writeAsString('{"runtime":"codex"}');
      await changed.timeout(const Duration(seconds: 3));
      expect((await cached.agentRuntime()).fixed, false);
      expect(reads, 3);
    });

    test('a Codex configuration is read, offered without its key, and imported into the vault',
        () async {
      expect(await dshSettings.codexModel(), isNull);
      await expectLater(dshSettings.importCodexModel(), throwsStateError);
      final home = await Directory('${lab.path}/codex-home').create();
      await File('${home.path}/config.toml').writeAsString(
          'model = "deepseek-v4.1-flash"\n'
          'model_provider = "cpa"\n'
          'model_reasoning_effort = "high"\n'
          '[model_providers.cpa]\n'
          'name = "CPA"\n'
          'base_url = "https://relay.example/v1/"\n'
          'wire_api = "responses"\n'
          'experimental_bearer_token = "$secret"\n');
      final offer = (await dshSettings.codexModel())!;
      expect(
          (offer.provider, offer.baseUrl, offer.model, offer.api, offer.reasoning),
          ('CPA', 'https://relay.example/v1', 'deepseek-v4.1-flash',
              UiModelApi.responses, 'high'));
      expect(offer.apiKey, isNull);
      expect((await dshSettings.model()).hasKey, false);
      await dshSettings.importCodexModel();
      final shown = await dshSettings.model();
      expect((shown.provider, shown.model, shown.hasKey, shown.reasoning),
          ('CPA', 'deepseek-v4.1-flash', true, 'high'));
      final route = (await dshSettings.launch()).route!;
      expect((route.baseUrl, route.key), ('https://relay.example/v1', secret));
      // The import copied nothing into the app's own files.
      expect(await File('${root.path}/model.json').readAsString(),
          isNot(contains(secret)));
      expect(jsonEncode(await database.query('body_changes')),
          isNot(contains(secret)));
    });

    test('the connection check speaks the wire that was chosen', () async {
      final seen = <String>[];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server!.listen((request) async {
        seen.add('${request.method} ${request.uri.path}');
        await utf8.decoder.bind(request).join();
        final valid = request.headers.value(HttpHeaders.authorizationHeader) ==
            'Bearer $secret';
        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = valid ? 200 : 401;
        request.response.write(jsonEncode(valid
            ? {
                'choices': [
                  {
                    'message': {'role': 'assistant', 'content': 'OK'}
                  }
                ],
              }
            : {'error': {'message': 'echo $secret'}}));
        await request.response.close();
      });
      final url = 'http://127.0.0.1:${server!.port}/v1';
      await dshSettings.setModel(UiModelChoice(
          source: UiModelSource.nipaplay,
          provider: 'x',
          baseUrl: url,
          model: 'm',
          apiKey: secret,
          api: UiModelApi.chat));
      final ok = await dshSettings.checkModel();
      expect(ok.ok, true, reason: ok.message);
      await dshSettings.setModel(UiModelChoice(
          source: UiModelSource.nipaplay,
          provider: 'x',
          baseUrl: '$url/chat/completions',
          model: 'm',
          apiKey: 'wrong'));
      final bad = await dshSettings.checkModel();
      expect((bad.ok, bad.message), (false, '密钥无效或没有权限'));
      expect(seen, ['POST /v1/chat/completions', 'POST /v1/chat/completions']);
    });
  });

  test(
      'real Codex switches only between turns and resumes same rollout across homes',
      () async {
    final ProcessResult version;
    try {
      version = await Process.run('codex', ['--version']);
    } on ProcessException {
      markTestSkipped('No codex on this machine.');
      return;
    }
    expect(version.exitCode, 0);
    final firstRequest = Completer<void>(), release = Completer<void>();
    final helperRequest = Completer<void>(), releaseHelper = Completer<void>();
    var count = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) async {
      if (request.method != 'POST') {
        request.response.statusCode = 404;
        await request.response.close();
        return;
      }
      await request.drain<void>();
      count++;
      final requestNumber = count;
      if (requestNumber == 1) {
        firstRequest.complete();
        await release.future;
      }
      if (requestNumber == 2) {
        helperRequest.complete();
        await releaseHelper.future;
      }
      request.response.headers.set('content-type', 'text/event-stream');
      void event(Map<String, Object?> e) =>
          request.response.write('data: ${jsonEncode(e)}\n\n');
      final item = {
        'id': 'msg_$count',
        'type': 'message',
        'role': 'assistant',
        'status': 'completed',
        'content': [
          {'type': 'output_text', 'text': 'OK', 'annotations': []}
        ]
      };
      event({
        'type': 'response.created',
        'response': {
          'id': 'resp_$count',
          'object': 'response',
          'status': 'in_progress',
          'output': []
        }
      });
      event({
        'type': 'response.output_item.added',
        'output_index': 0,
        'item': {...item, 'status': 'in_progress'}
      });
      event({
        'type': 'response.output_text.delta',
        'item_id': 'msg_$count',
        'output_index': 0,
        'content_index': 0,
        'delta': 'OK'
      });
      event({
        'type': 'response.output_item.done',
        'output_index': 0,
        'item': item
      });
      event({
        'type': 'response.completed',
        'response': {
          'id': 'resp_$count',
          'object': 'response',
          'status': 'completed',
          'output': [item],
          'usage': {'input_tokens': 1, 'output_tokens': 1, 'total_tokens': 2}
        }
      });
      await request.response.close();
    });
    final url = 'http://127.0.0.1:${server!.port}/v1';
    final codexHome = await Directory('${lab.path}/codex-home').create();
    final original = 'model_provider="original"\n'
        '[model_providers.original]\nname="Original"\nbase_url="$url"\nwire_api="responses"\n'
        '[projects.${jsonEncode(repository.path)}]\ntrust_level="trusted"\n';
    await File('${codexHome.path}/config.toml').writeAsString(original);
    final initialized = await Process.run(
        'git', ['init', '--quiet', '--template=', '--initial-branch=main'],
        workingDirectory: repository.path);
    expect(initialized.exitCode, 0);
    await Directory('${repository.path}/.codex').create();
    await File('${repository.path}/.codex/config.toml').writeAsString(
        'sandbox_mode="danger-full-access"\napproval_policy="never"\n'
        '[features]\nmemories=false\n');
    final hookPreference = File('${repository.path}/preference.txt');
    await hookPreference.writeAsString('initial preference');
    await File('${repository.path}/session_start.py').writeAsString('''
import json
from pathlib import Path
print(json.dumps({'hookSpecificOutput': {'hookEventName': 'SessionStart',
    'additionalContext': Path('preference.txt').read_text()}}))
''');
    await File('${repository.path}/.codex/hooks.json')
        .writeAsString(jsonEncode({
      'hooks': {
        'SessionStart': [
          {
            'matcher': 'startup|resume',
            'hooks': [
              {'type': 'command', 'command': 'python3 session_start.py'}
            ]
          }
        ]
      }
    }));
    host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        labRoot: lab,
        sessions: SessionStore(database),
        modelLaunch: settings.launch);
    final public = <Object?>[];
    host!.events.listen(public.add);
    await host!.start();
    await host!.getMainSession();
    final id = host!.mainThreadId, process = host!.processId;
    final originalModel = host!.model;
    Future<void> turn(String prompt) async {
      final offset = public.length;
      final completed = host!.events.firstWhere((e) =>
          e['method'] == 'turn/completed' && e['params']['threadId'] == id);
      await host!.startTurn(prompt);
      final event = await completed.timeout(const Duration(seconds: 45));
      expect(event['params']['turn']['status'], 'completed');
      final hook = public.skip(offset).cast<Map>().singleWhere((e) =>
          e['method'] == 'hook/completed' && e['params']['threadId'] == id);
      expect(hook['params']['run']['status'], 'completed');
      expect(jsonEncode(hook['params']['run']['entries']),
          contains(await hookPreference.readAsString()));
    }

    final running = turn('Reply OK.');
    await firstRequest.future.timeout(const Duration(seconds: 30));
    final helper = await host!.helperThread('x52-helper', 'X52 helper');
    final helperDone = host!.events.firstWhere((e) =>
        e['method'] == 'turn/completed' && e['params']['threadId'] == helper);
    await host!.startThreadTurn(helper, 'Reply OK.');
    await helperRequest.future.timeout(const Duration(seconds: 30));
    await settings.setModel(choice(url, key: secret));
    expect(host!.processId, process);
    expect(host!.model, originalModel);
    release.complete();
    await running;
    final nextTurn = turn('Reply OK again.');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(host!.processId, process);
    expect(host!.busyFor(helper), true);
    await hookPreference.writeAsString('managed preference');
    releaseHelper.complete();
    await helperDone;
    await nextTurn;
    expect(host!.mainThreadId, id);
    expect(host!.threadId, id);
    expect(host!.processId, isNot(process));
    expect(host!.model, 'managed-model');
    expect(host!.provider, 'nipaplay');
    final recent = await recentMemoryFacts(host!, [], [], [], id,
        finishedHelpers: [
          {
            'title': '新进片库的 9 个文件',
            'state': 'succeeded',
            'receipt': {
              'details': {'summary': 'BACKGROUND_CONCLUSION 9 集认好'}
            }
          }
        ]);
    expect(recent['sourceThreadId'], id);
    expect(recent['text'], contains('Reply OK again.'));
    expect(recent['text'], contains('最近办完的后台任务'));
    expect(recent['text'], contains('BACKGROUND_CONCLUSION 9 集认好'),
        reason: 'what a background turn concluded, not only its steps');
    await settings.setModel(const UiModelChoice(source: UiModelSource.codex));
    await hookPreference.writeAsString('returned preference');
    await turn('Reply OK a third time.');
    expect(host!.mainThreadId, id);
    expect(host!.provider, 'original');
    expect(host!.model, originalModel);
    expect((await host!.readThread(id!))['turns'], hasLength(3));
    expect(
        await File('${codexHome.path}/config.toml').readAsString(), original);
    final journal = File('${root.path}/journal.jsonl');
    final beforeProbe = await journal.readAsBytes();
    final pathsBeforeProbe =
        await File('${root.path}/chat-rollouts.json').readAsString();
    final probe = ChatHost(
        endpoint: endpoint, repository: repository, labRoot: lab, probe: true);
    try {
      await probe.start();
      expect(await probe.checkSavedModel(), true);
    } finally {
      await probe.close();
    }
    expect(await journal.readAsBytes(), beforeProbe);
    expect(await File('${root.path}/chat-rollouts.json').readAsString(),
        pathsBeforeProbe);
    expect(await SessionStore(database).main(repository.path), id);
    // Restart the host as the application would; durable main and path survive.
    await host!.close();
    host = ChatHost(
        endpoint: endpoint,
        repository: repository,
        labRoot: lab,
        sessions: SessionStore(database),
        modelLaunch: settings.launch);
    await host!.start();
    await host!.getMainSession();
    expect(host!.mainThreadId, id);
    expect((await host!.readThread(id))['turns'], hasLength(3));
    final state = StateCapability([
      StateView(
          name: 'host.activities',
          description: 'Host changes',
          fields: const ObjectSchema({}, additionalProperties: true),
          read: (offset, limit) => database.query('body_changes'))
    ]);
    final result = await Harness([state]).invokeJson(
        'state.query', {'view': 'host.activities'}, Invocation(origin: 'test'));
    await host!.close();
    await scanSecrets(
        // Public RPCs and all owned files are scanned without printing values.
        [...public, result.toEnvelope(), host!.launchEnvironment]);
    expect(
        await lab.list(recursive: true).any(
            (file) => file.path.contains('/shell_snapshots/') && file is File),
        false);
  });
}

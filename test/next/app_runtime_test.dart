import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:nipaplay/next/agent_endpoint.dart';
import 'package:nipaplay/next/capabilities/app_runtime_capability.dart';
import 'package:nipaplay/next/chat/chat_host.dart';
import 'package:nipaplay/next/chat/dsh_runtime.dart';
import 'package:nipaplay/next/media/providers.dart';
import 'package:nipaplay/next/next_core.dart';
import 'package:nipaplay/next/settings/host_settings_service.dart';
import 'package:nipaplay/next/system/app_restart.dart';
import 'package:nipaplay/next/system/app_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../security/memory_vault.dart';
import 'download_test_support.dart';
import 'media_test_support.dart';

List<int> procArgs(String executable, List<String> args,
    {List<String> env = const ['HOME=/Users/x', 'NIPAPLAY_PROFILE=lab']}) {
  final head = ByteData(4)..setInt32(0, args.length, Endian.host);
  return [
    ...head.buffer.asUint8List(),
    ...utf8.encode(executable),
    0, 0, 0,
    for (final arg in args) ...[...utf8.encode(arg), 0],
    for (final item in env) ...[...utf8.encode(item), 0],
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('restart', () {
    test('a process\'s arguments are read from its sysctl value', () {
      final parsed = parseProcessArguments(procArgs(
          '/Applications/NipaPlay.app/Contents/MacOS/NipaPlay',
          ['/Applications/NipaPlay.app/Contents/MacOS/NipaPlay', '/v/a b.mkv', '--x=1']));
      expect(parsed.executable,
          '/Applications/NipaPlay.app/Contents/MacOS/NipaPlay');
      expect(parsed.arguments, ['/v/a b.mkv', '--x=1']);
      expect(
          parseProcessArguments(procArgs('/bin/app', ['/bin/app'])).arguments,
          isEmpty);
      expect(() => parseProcessArguments([1, 0]), throwsFormatException);
      expect(
          () => parseProcessArguments(
              procArgs('/bin/app', ['/bin/app'])..[0] = 5),
          throwsFormatException);
    });

    test('this very process\'s arguments are readable through sysctl on macOS',
        () async {
      if (!Platform.isMacOS) return;
      final parsed = parseProcessArguments(
          await AppRestart.readProcessArgumentBytes(pid));
      expect(parsed.executable, endsWith('flutter_tester'));
      expect(parsed.arguments, everyElement(isA<String>()));
    });

    test('the helper waits for the old process, then runs the same program with its arguments and environment',
        () async {
      if (Platform.isWindows) return;
      final old = await Process.start('/bin/sleep', ['1']);
      final (command, arguments) = relaunchCommand(
          old.pid, '/usr/bin/printenv', ['NIPA_RESTART_PROFILE']);
      final watch = Stopwatch()..start();
      final result = await Process.run(command, arguments,
          environment: {'NIPA_RESTART_PROFILE': 'lab-one'});
      expect(result.exitCode, 0);
      expect((result.stdout as String).trim(), 'lab-one');
      expect(watch.elapsedMilliseconds, greaterThan(500));
      await old.exitCode;
    });

    test('an argument with spaces and quotes reaches the program unchanged',
        () async {
      if (Platform.isWindows) return;
      final old = await Process.start('/bin/sleep', ['0']);
      await old.exitCode;
      final (command, arguments) = relaunchCommand(
          old.pid, '/bin/echo', ['a b', "it's", r'$HOME']);
      final result = await Process.run(command, arguments);
      expect((result.stdout as String).trim(), r"a b it's $HOME");
    });

    test('the helper starts nothing while the old process is still alive after the wait',
        () async {
      if (Platform.isWindows) return;
      final old = await Process.start('/bin/sleep', ['5']);
      final (command, arguments) =
          relaunchCommand(old.pid, '/bin/echo', ['started'], waitSeconds: 1);
      final result = await Process.run(command, arguments);
      expect(result.exitCode, 1);
      expect(result.stdout, isEmpty);
      old.kill();
    });

    test('restart: arguments are read, settings drained, helper started, then the app quits',
        () async {
      final order = <String>[];
      List<String>? helper;
      final restart = AppRestart(
          macos: true,
          windows: false,
          processId: 4242,
          executable: '/Apps/NipaPlay.app/Contents/MacOS/NipaPlay',
          profileName: 'lab',
          delay: Duration.zero,
          readArguments: (pid) async {
            order.add('read $pid');
            return procArgs('/Apps/NipaPlay.app/Contents/MacOS/NipaPlay',
                ['/Apps/NipaPlay.app/Contents/MacOS/NipaPlay', '/v/ep 1.mkv']);
          },
          beforeQuit: () async => order.add('drain'),
          spawn: (command, arguments) async {
            order.add('spawn');
            helper = [command, ...arguments];
          },
          quit: () async => order.add('quit'));
      final receipt = await restart.restart();
      expect(order, ['read 4242', 'drain', 'spawn']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order.last, 'quit');
      expect(helper!.first, '/bin/sh');
      expect(helper!.sublist(helper!.length - 3), [
        '4242',
        '/Apps/NipaPlay.app/Contents/MacOS/NipaPlay',
        '/v/ep 1.mkv'
      ]);
      expect(receipt['scheduled'], true);
      expect(receipt['processId'], 4242);
      expect(receipt['arguments'], ['/v/ep 1.mkv']);
      expect(receipt['executablePath'],
          '/Apps/NipaPlay.app/Contents/MacOS/NipaPlay');
      expect(receipt['profileName'], 'lab');
      expect(receipt['environment'], contains('inherited'));
      // A second request schedules nothing more.
      final again = await restart.restart();
      expect(again['alreadyScheduled'], true);
      expect(order.where((e) => e == 'spawn'), hasLength(1));
    });

    test('Windows: an argument reaches the command line as CommandLineToArgv reads it',
        () {
      expect(windowsArgument(r'C:\v\ep.mkv'), r'C:\v\ep.mkv');
      expect(windowsArgument(r'C:\v\a b.mkv'), r'"C:\v\a b.mkv"');
      expect(windowsArgument('say "hi"'), r'"say \"hi\""');
      expect(windowsArgument(r'dir with\'), r'"dir with\\"');
      expect(windowsArgument(''), '""');
    });

    test('Windows: the helper waits for the old process, then starts the program with its arguments and environment',
        () async {
      final old = await Process.start('cmd.exe', ['/c', 'ping -n 3 127.0.0.1 >nul']);
      final out = File(
          '${Directory.systemTemp.path}\\nipa-restart-${DateTime.now().microsecondsSinceEpoch}.txt');
      // PowerShell is the program: it reads its arguments as the command line
      // carries them, and shows the environment the new process got.
      final (command, arguments) = relaunchCommandWindows(
          old.pid,
          r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe', [
        '-NoProfile',
        '-Command',
        "Set-Content -Path '${out.path}' -Value \$env:NIPA_RESTART_PROFILE",
      ]);
      final watch = Stopwatch()..start();
      final result = await Process.run(command, arguments,
          environment: {'NIPA_RESTART_PROFILE': 'lab-one'});
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(watch.elapsedMilliseconds, greaterThan(1000));
      // The started program is detached from the helper; wait for its file.
      for (var i = 0; i < 50 && !out.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect((await out.readAsString()).trim(), 'lab-one');
      await out.delete();
      await old.exitCode;
    }, skip: Platform.isWindows ? null : 'Windows relaunch');

    test('Windows: the helper starts nothing while the old process is still alive after the wait',
        () async {
      final old = await Process.start('cmd.exe', ['/c', 'ping -n 8 127.0.0.1 >nul']);
      final (command, arguments) = relaunchCommandWindows(
          old.pid, r'C:\Windows\System32\cmd.exe', ['/c', 'echo started'],
          waitSeconds: 1);
      final result = await Process.run(command, arguments);
      expect(result.exitCode, 1);
      expect((result.stdout as String).trim(), isEmpty);
      old.kill();
    }, skip: Platform.isWindows ? null : 'Windows relaunch');

    test('Windows: this very process\'s arguments are readable through the command line',
        () async {
      expect(await readWindowsArguments(), everyElement(isA<String>()));
    }, skip: Platform.isWindows ? null : 'Windows command line');

    test('Windows: the real helper outlives the restart call and starts the program',
        () async {
      // The helper is an ordinary PowerShell child: started detached it never
      // runs its script on Windows.
      final old = await Process.start('cmd.exe', ['/c', 'exit 0']);
      await old.exitCode;
      final out = File(
          '${Directory.systemTemp.path}\\nipa-restart-real-${DateTime.now().microsecondsSinceEpoch}.txt');
      var quit = false;
      final restart = AppRestart(
          macos: false,
          windows: true,
          processId: old.pid,
          executable:
              r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
          delay: Duration.zero,
          readWindowsArgumentList: () async => [
                '-NoProfile',
                '-Command',
                "Set-Content -Path '${out.path}' -Value started",
              ],
          beforeQuit: () async {},
          quit: () async => quit = true);
      await restart.restart();
      for (var i = 0; i < 100 && !out.existsSync(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(out.existsSync(), true);
      expect(quit, true);
      await out.delete();
    }, skip: Platform.isWindows ? null : 'Windows relaunch');

    test('Windows: restart reads the command line, drains, starts the helper, then quits',
        () async {
      final order = <String>[];
      List<String>? helper;
      final restart = AppRestart(
          macos: false,
          windows: true,
          processId: 4242,
          executable: r'C:\Apps\NipaPlay\NipaPlay.exe',
          delay: Duration.zero,
          readWindowsArgumentList: () async {
            order.add('read');
            return [r'D:\v\ep 1.mkv'];
          },
          beforeQuit: () async => order.add('drain'),
          spawn: (command, arguments) async {
            order.add('spawn');
            helper = [command, ...arguments];
          },
          quit: () async => order.add('quit'));
      final receipt = await restart.restart();
      expect(order, ['read', 'drain', 'spawn']);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(order.last, 'quit');
      expect(helper!.first, 'powershell.exe');
      expect(helper!, contains('-EncodedCommand'));
      expect(receipt['arguments'], [r'D:\v\ep 1.mkv']);
      expect(receipt['processId'], 4242);
    });

    test('other platforms report it unavailable and restart nothing', () async {
      var touched = false;
      final restart = AppRestart(
          macos: false,
          windows: false,
          readArguments: (_) async {
            touched = true;
            return [];
          },
          beforeQuit: () async => touched = true,
          spawn: (_, __) async => touched = true,
          quit: () async => touched = true);
      await expectLater(
          restart.restart(),
          throwsA(isA<Failure>()
              .having((f) => f.code, 'code', FailureCode.unavailable)
              .having((f) => f.message, 'message', contains('macOS and Windows only'))));
      expect(touched, false);
    });

    test('unreadable arguments or a helper that cannot start restart nothing',
        () async {
      var quit = false;
      final unreadable = AppRestart(
          macos: true,
          windows: false,
          delay: Duration.zero,
          readArguments: (_) async => throw const FormatException('x'),
          beforeQuit: () async {},
          spawn: (_, __) async => fail('spawned'),
          quit: () async => quit = true);
      await expectLater(unreadable.restart(),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.unavailable)));
      final broken = AppRestart(
          macos: true,
          windows: false,
          delay: Duration.zero,
          readArguments: (_) async => procArgs('/bin/app', ['/bin/app']),
          beforeQuit: () async {},
          spawn: (_, __) async => throw const ProcessException('/bin/sh', []),
          quit: () async => quit = true);
      await expectLater(broken.restart(),
          throwsA(isA<Failure>().having((f) => f.code, 'code', FailureCode.unavailable)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(quit, false);
    });
  });

  group('runtime facts', () {
    late Directory root, mediaFolder;
    late NextCore core;
    late MemoryVault vault;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      sqfliteFfiInit();
      root = await Directory.systemTemp.createTemp('next-runtime-');
      mediaFolder = await Directory('${root.path}/media').create();
      vault = MemoryVault();
      core = NextCore(
        root: root,
        databaseFactory: databaseFactoryFfi,
        downloadBackend: FakeDownloadBackend(root),
        downloadLibrary: FakeDownloadLibrary(),
        isDownloaderEnabled: () async => true,
        loadImportedKeys: () async => const {},
        downloadRefreshInterval: const Duration(milliseconds: 20),
        classic: MemoryClassic(),
        authorizedRoots: () => [mediaFolder.path],
        mediaDurationProbe: (_) async => 1440000,
        mediaSubtitleProbe: (_) async => {'subtitles': <Object?>[]},
        mediaProviders: [
          TmdbMetadataProvider(FixtureTransport('tmdb')),
          DandanplayMetadataProvider(FixtureTransport('dandanplay')),
        ],
      );
      await core.ready;
    });
    tearDown(() async {
      await core.close();
      await root.delete(recursive: true);
    });

    AppRuntimeFacts facts(
            {Map<String, String> environment = const {},
            ChatHost? Function()? chat,
            AgentRuntimeKind runtime = AgentRuntimeKind.codex,
            bool managed = true}) =>
        AppRuntimeFacts(
            root: root,
            mesh: core.mesh,
            programs: core.programs,
            vault: vault,
            chat: chat ?? () => null,
            codexHome: Directory('${root.path}/codex-home'),
            environment: environment,
            defaultRuntime: runtime,
            managedModelByDefault: managed,
            remoteAccess: () async => {
                  'serviceRunning': true,
                  'port': 1180,
                  'autoStart': false,
                  'ipv6': false,
                  'receiverEnabled': true,
                  'trustedDeviceCount': 2,
                  'lastStartFailed': false,
                });

    test('remote access, the mesh and the model are read without any secret',
        () async {
      const key = 'sk-model-key-0123456789abcdef0123456789';
      final model = {
        'source': 'nipaplay',
        'provider': 'DeepSeek',
        'baseUrl': 'https://user:pass-word@models.example/v1',
        'model': 'deepseek-v4',
        'revision': 3,
      };
      await File('${root.path}/model.json').writeAsString(jsonEncode(model));
      vault.values[HostSettingsService.modelKey(root, model)] = key;
      await File('${root.path}/mesh.json').writeAsString(jsonEncode({
        'enabled': true,
        'name': '客厅',
        'coordinator': 'https://admin:coord-secret@mesh.example/hub?token=abc',
        'port': 4100,
        'loopbackOnly': false,
        'broadcastDiscovery': false,
        'addresses': [
          {'kind': 'manual', 'host': '10.0.0.8', 'port': 4101},
          {'kind': 'manual', 'host': 'fe80::1', 'port': 4102},
        ],
        'fileProxyPort': 4200,
      }));
      SharedPreferences.setMockInitialValues({'labs_enable_agent_endpoint': true});
      final result = await facts().read();
      expect(result['remoteAccess'], {
        'serviceRunning': true,
        'port': 1180,
        'autoStart': false,
        'ipv6': false,
        'receiverEnabled': true,
        'trustedDeviceCount': 2,
        'lastStartFailed': false,
      });
      final mesh = result['mesh'] as Map;
      expect(mesh['enabled'], true);
      expect(mesh['deviceName'], '客厅');
      expect(mesh['coordinator'], 'https://mesh.example/hub');
      expect(mesh['port'], 4100);
      expect(mesh['broadcastDiscovery'], false);
      expect(mesh['manualAddresses'], ['10.0.0.8:4101', '[fe80::1]:4102']);
      expect(mesh['fileProxyPort'], 4200);
      expect(mesh['remoteProgramsAllowed'], core.programs.enabled);
      expect((result['agent'] as Map)['endpointEnabled'], true);
      final shown = result['model'] as Map;
      expect(shown['source'], 'nipaplay');
      expect(shown['provider'], 'DeepSeek');
      expect(shown['model'], 'deepseek-v4');
      expect(shown['baseUrl'], 'https://models.example/v1');
      expect(shown['keyConfigured'], true);
      final text = jsonEncode(result);
      for (final secret in [key, 'pass-word', 'coord-secret', 'token=abc']) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });

    test('a missing key and an unreadable vault are said, not guessed', () async {
      final model = {
        'source': 'nipaplay',
        'provider': 'x',
        'baseUrl': 'https://models.example/v1',
        'model': 'm',
      };
      await File('${root.path}/model.json').writeAsString(jsonEncode(model));
      expect(((await facts().read())['model'] as Map)['keyConfigured'], false);
      vault.unavailable = true;
      final unreadable = (await facts().read())['model'] as Map;
      expect(unreadable['keyConfigured'], isNull);
      expect(unreadable['keyConfiguredReason'], contains('vault'));
    });

    test('a Codex model is the one its configuration names', () async {
      await Directory('${root.path}/codex-home').create();
      await File('${root.path}/codex-home/config.toml')
          .writeAsString('model = "gpt-x"\nmodel_provider = "openai"\n');
      final model = (await facts(managed: false).read())['model'] as Map;
      expect(model, {
        'source': 'codex',
        'codexConfigPresent': true,
        'model': 'gpt-x',
        'provider': 'openai'
      });
      expect(await File('${root.path}/model.json').exists(), false);
    });

    test('the runtime is what the environment fixes, else the choice in settings, else the default',
        () async {
      final codex = (await facts().read())['runtime'] as Map;
      expect(codex['selected'], {'kind': 'codex'});
      expect(codex['running'], isNull);
      expect((codex['codex'] as Map)['source'], 'managed');
      expect((codex['codex'] as Map)['installed'], false);
      expect(codex['dsh'], {'installed': false, 'version': null});
      // Nothing chose: DeepSeek Harness, fetched by NipaPlay.
      final fresh = (await facts(runtime: AgentRuntimeKind.dsh).read())['runtime']
          as Map;
      expect(fresh['selected'], {'kind': 'dsh', 'dshVersion': null});
      // The person chose in settings.
      await File('${root.path}/runtime.json')
          .writeAsString('{"runtime":"codex"}');
      expect(
          ((await facts(runtime: AgentRuntimeKind.dsh).read())['runtime']
              as Map)['selected'],
          {'kind': 'codex'});
      await File('${root.path}/runtime.json').delete();
      // The environment wins over both; DSH alone means the fetched one.
      final env = (await facts(environment: {'NIPAPLAY_AGENT_RUNTIME': 'dsh'})
              .read())['runtime'] as Map;
      expect(env['selected'], {'kind': 'dsh', 'dshVersion': null});
      final invalid = (await facts(environment: {'NIPAPLAY_AGENT_RUNTIME': 'oops'})
              .read())['runtime'] as Map;
      expect((invalid['selected'] as Map)['kind'], isNull);
      expect((invalid['selected'] as Map)['problem'], contains('Unknown agent runtime'));
      final node = File('${root.path}/node')..writeAsStringSync('');
      final bin = File('${root.path}/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js')
        ..createSync(recursive: true);
      File('${root.path}/dsh/node_modules/@deepseek-ai/dsh/package.json')
          .writeAsStringSync('{"version":"0.9.1"}');
      final dsh = (await facts(environment: {
        'NIPAPLAY_AGENT_RUNTIME': 'dsh',
        'NIPAPLAY_DSH_NODE': node.path,
        'NIPAPLAY_DSH_BIN': bin.path,
      }).read())['runtime'] as Map;
      expect(dsh['selected'], {'kind': 'dsh', 'dshVersion': '0.9.1'});
      // What NipaPlay fetched is reported.
      final installed = Directory('${root.path}/dsh-runtime/dsh-0.2.1-node-24')
        ..createSync(recursive: true);
      File('${installed.path}/installed.json')
          .writeAsStringSync('{"dsh":"0.2.1"}');
      expect(((await facts(runtime: AgentRuntimeKind.dsh).read())['runtime']
              as Map)['dsh'],
          {'installed': true, 'version': '0.2.1'});
    });

    test('a running host is described by its runtime and model, never its error text',
        () async {
      final endpoint = AgentEndpoint(
          harness: Harness([]),
          seed: {},
          appVersion: 'runtime-test',
          credentialFile: File('${root.path}/endpoint.json'),
          seedRepository: Directory('${root.path}/harness-seed'),
          port: 0);
      final host = ChatHost(
          endpoint: endpoint,
          repository: Directory('${root.path}/repo'),
          dsh: const DshRuntime(node: 'node', bin: 'bin.js', version: '1.0'),
          dshPlugins: Directory('${root.path}/plugins'));
      final running = ((await facts(chat: () => host).read())['runtime']
          as Map)['running'] as Map;
      expect(running['available'], false);
      expect(running['runtime'], 'dsh');
      expect(running['model'], isNull);
      expect(running['busy'], false);
      await host.close();
    });

    test('app.runtime and app.restart are in the core catalogue and app.runtime answers its schema',
        () async {
      final harness = Harness(core.capabilities);
      expect(harness.lookup('app.restart'), isNotNull);
      final outcome = await harness.invokeJson(
          'app.runtime', {}, Invocation(origin: 'mcp'));
      expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
      final value = (outcome as Completed).value.toJson();
      expect(harness.lookup('app.runtime')!.spec.output.validate(value), isEmpty);
      expect(value.keys,
          containsAll(['remoteAccess', 'mesh', 'agent', 'runtime', 'model']));
      expect(harness.lookup('app.runtime')!.spec.effect, Effect.read);
      expect(harness.lookup('app.restart')!.spec.effect, Effect.write);
    });

    test('the capability runs restart through its own hooks', () async {
      var quit = false;
      final restart = AppRestart(
          macos: true,
          delay: Duration.zero,
          readArguments: (_) async => procArgs('/bin/app', ['/bin/app']),
          beforeQuit: () async {},
          spawn: (_, __) async {},
          quit: () async => quit = true);
      final harness = Harness([AppRuntimeCapability(facts(), restart)]);
      final outcome = await harness.invokeJson(
          'app.restart', {}, Invocation(origin: 'mcp'));
      expect(outcome, isA<Completed>(), reason: '${outcome.toEnvelope()}');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(quit, true);
    });
  });
}

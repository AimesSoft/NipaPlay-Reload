import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/security/credential_vault.dart';
import 'package:nipaplay/services/remote_proxy_diagnostics.dart';
import 'package:nipaplay/services/smb_proxy_service.dart';
import 'package:nipaplay/services/smb_service.dart';
import 'package:nipaplay/utils/media_source_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('concurrent first use binds one healthy proxy and restart works',
      () async {
    SharedPreferences.setMockInitialValues({'smb_proxy_port': 0});
    final proxy = SMBProxyService.instance;
    expect(proxy.isRunning, isFalse);
    addTearDown(proxy.stop);
    await Future.wait(List.generate(10, (_) => proxy.initialize()));
    expect(proxy.isRunning, isTrue);
    final port = proxy.port;
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:$port/smb/health')))
          .close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    await HttpOverrides.runWithHttpOverrides(proxy.initialize, _RealHttp());
    expect(proxy.port, port);
    await proxy.stop();
    expect(proxy.isRunning, isFalse);
    await proxy.initialize();
    expect(proxy.isRunning, isTrue);
  });

  test('initialize during a stop waits for it and starts a fresh proxy',
      () async {
    SharedPreferences.setMockInitialValues({'smb_proxy_port': 0});
    final proxy = SMBProxyService.instance;
    addTearDown(proxy.stop);
    await proxy.initialize();

    final stopping = proxy.stop();
    // The stop has begun but not finished: the proxy no longer counts as
    // running, and initialize must not hand the stopping one out again.
    expect(proxy.isRunning, isFalse);
    await proxy.initialize();
    await stopping;

    expect(proxy.isRunning, isTrue);
    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final response = await (await client
              .getUrl(Uri.parse('http://127.0.0.1:${proxy.port}/smb/health')))
          .close();
      expect(response.statusCode, 200);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
  });

  test('proxy responds on its own isolate while root isolate is blocked',
      () async {
    SharedPreferences.setMockInitialValues({'smb_proxy_port': 0});
    final proxy = SMBProxyService.instance;
    addTearDown(proxy.stop);
    await proxy.initialize();
    final port = proxy.port;

    final result = await _runWhileRootIsolateSleeps(
      urls: [
        ('GET', 'http://127.0.0.1:$port/smb/health'),
        ('HEAD', 'http://127.0.0.1:$port/smb/stream?conn=missing&path=/a.mp4'),
        ('GET', 'http://127.0.0.1:$port/smb/stream'),
      ],
      blockDuration: const Duration(milliseconds: 500),
    );

    expect(result.statusCodes, [200, 404, 400]);
    expect(
      result.completedAtMicros,
      lessThan(result.rootWokeAtMicros),
      reason: 'Proxy isolate should respond before root isolate unblocks',
    );
    expect(result.elapsedMs, lessThan(400));
  });

  test('proxy isolate diagnostics reach the root log and the root probe',
      () async {
    SharedPreferences.setMockInitialValues({'smb_proxy_port': 0});
    final logs = <String>[];
    final originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    addTearDown(() => debugPrint = originalPrint);
    final proxy = SMBProxyService.instance;
    addTearDown(proxy.stop);
    await proxy.initialize();

    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final response = await (await client.openUrl(
        'HEAD',
        Uri.parse(
          'http://127.0.0.1:${proxy.port}/smb/stream?conn=private-name&path=/a.mp4',
        ),
      ))
          .close();
      expect(response.statusCode, HttpStatus.notFound);
      await response.drain<void>();
    } finally {
      client.close(force: true);
    }
    await HttpOverrides.runWithHttpOverrides(
      () => RemoteProxyDiagnostics.lifecycle('resumed'),
      _RealHttp(),
    );

    bool logged(String text) => logs.any((line) => line.contains(text));
    // Lines written inside the proxy isolate arrive through the root's log.
    expect(logged('listener-bound'), isTrue);
    expect(logged('method=HEAD range=none'), isTrue);
    expect(logged('status=404'), isTrue);
    // The root isolate reaches the listener it no longer owns.
    expect(
      logs.firstWhere((line) => line.contains('health reason=lifecycle-resumed')),
      contains('status=200'),
    );
    expect(logs.join('\n'), isNot(contains('private-name')));
  });

  test(
      'prepareRemotePath syncs resolved credentials to proxy isolate and tracks connection removal',
      () async {
    final previousStore = CredentialStore.instance;
    final vault = MemoryVault();
    const ref = CredentialRef('smb_connections', 'nas-1');
    vault.values[ref] = 's3cr3t';
    CredentialStore.instance = CredentialStore(vault, desktop: true);
    addTearDown(() => CredentialStore.instance = previousStore);

    SharedPreferences.setMockInitialValues({
      'smb_proxy_port': 0,
      'smb_connections': jsonEncode([
        {
          'id': 'nas-1',
          'name': 'TestNAS',
          'host': '127.0.0.1',
          'port': 44500,
          'wanHost': '',
          'wanPort': 445,
          'username': 'alice',
          'password': ref.placeholder,
          'domain': '',
          'isConnected': true,
        },
      ]),
    });

    final proxy = SMBProxyService.instance;
    addTearDown(() async {
      await proxy.stop();
      await SMBService.instance.removeConnection('TestNAS');
    });

    const mediaPath = 'smb://nas-1/media/episode01.mkv';
    final streamUrl =
        await MediaSourceUtils.resolveSmbPathToUrlInitialized(mediaPath);
    expect(streamUrl, isNotNull);
    expect(Uri.parse(streamUrl!).queryParameters['conn'], 'TestNAS');
    expect(vault.reads[ref], 1);

    // While the root isolate is synchronously blocked, HEAD /smb/stream must
    // reach the handler inside the proxy isolate without waiting for the root
    // isolate or triggering another credential read.
    final duringBlock = await _runWhileRootIsolateSleeps(
      urls: [('HEAD', streamUrl)],
      blockDuration: const Duration(milliseconds: 500),
    );
    expect(duringBlock.statusCodes, [500]);
    expect(duringBlock.completedAtMicros, lessThan(duringBlock.rootWokeAtMicros));
    expect(vault.reads[ref], 1);

    // Removing the connection from SMBService propagates to the proxy isolate.
    await SMBService.instance.removeConnection('TestNAS');
    // Allow the async SendPort delivery to settle on the proxy isolate.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final client =
        HttpOverrides.runWithHttpOverrides(() => HttpClient(), _RealHttp());
    try {
      final req = await client.openUrl('HEAD', Uri.parse(streamUrl));
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.notFound);
      await resp.drain<void>();
    } finally {
      client.close(force: true);
    }
  });
}

Future<
    ({
      List<int> statusCodes,
      int elapsedMs,
      int completedAtMicros,
      int rootWokeAtMicros,
    })> _runWhileRootIsolateSleeps({
  required List<(String method, String url)> urls,
  required Duration blockDuration,
}) async {
  final receivePort = ReceivePort();
  final helperPortCompleter = Completer<SendPort>();
  final startingCompleter = Completer<void>();
  final resultCompleter = Completer<Map<dynamic, dynamic>>();

  final subscription = receivePort.listen((message) {
    if (message is SendPort && !helperPortCompleter.isCompleted) {
      helperPortCompleter.complete(message);
      return;
    }
    if (message == 'starting' && !startingCompleter.isCompleted) {
      startingCompleter.complete();
      return;
    }
    if (message is Map && !resultCompleter.isCompleted) {
      resultCompleter.complete(message);
    }
  });

  final isolate = await Isolate.spawn(_probeHelperMain, receivePort.sendPort);
  try {
    final helperPort = await helperPortCompleter.future;
    helperPort.send({
      'urls': [
        for (final entry in urls) [entry.$1, entry.$2],
      ],
    });
    await startingCompleter.future;
    // Block the root isolate synchronously; only an independent isolate can
    // accept and respond to HTTP requests while this sleep is active.
    sleep(blockDuration);
    final rootWokeAtMicros = DateTime.now().microsecondsSinceEpoch;
    final result = await resultCompleter.future;
    return (
      statusCodes: (result['statusCodes'] as List).cast<int>(),
      elapsedMs: result['elapsedMs'] as int,
      completedAtMicros: result['completedAtMicros'] as int,
      rootWokeAtMicros: rootWokeAtMicros,
    );
  } finally {
    await subscription.cancel();
    receivePort.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

Future<void> _probeHelperMain(SendPort mainPort) async {
  final controlPort = ReceivePort();
  mainPort.send(controlPort.sendPort);
  final command = await controlPort.first as Map;
  controlPort.close();

  final rawUrls = (command['urls'] as List).cast<List<dynamic>>();
  final client = HttpClient();
  try {
    mainPort.send('starting');
    final sw = Stopwatch()..start();
    final statusCodes = <int>[];
    for (final item in rawUrls) {
      final method = item[0] as String;
      final url = item[1] as String;
      final req = await client.openUrl(method, Uri.parse(url));
      final resp = await req.close();
      statusCodes.add(resp.statusCode);
      await resp.drain<void>();
    }
    sw.stop();
    mainPort.send({
      'statusCodes': statusCodes,
      'elapsedMs': sw.elapsedMilliseconds,
      'completedAtMicros': DateTime.now().microsecondsSinceEpoch,
    });
  } finally {
    client.close(force: true);
  }
}

class _RealHttp extends HttpOverrides {}

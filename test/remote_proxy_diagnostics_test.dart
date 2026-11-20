import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_proxy_diagnostics.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> logs;
  late DebugPrintCallback originalPrint;
  setUp(() {
    logs = [];
    originalPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
  });
  tearDown(() => debugPrint = originalPrint);

  test('observes healthy endpoint then refusal without restarting listener',
      () async {
    final diagnostics = RemoteProxyDiagnostics('WebDAV');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    shelf_io.serveRequests(
        diagnostics.observe(server), (_) => Response.ok('ok'));
    await HttpOverrides.runWithHttpOverrides(
      () => diagnostics.probe('before-background'),
      _RealHttp(),
    );
    expect(logs.join('\n'), contains('status=200'));
    await server.close(force: true);
    await pumpEventQueue();
    await HttpOverrides.runWithHttpOverrides(
      () => diagnostics.probe('after-resume'),
      _RealHttp(),
    );
    final output = logs.join('\n');
    expect(output, contains('listener-done'));
    expect(output, contains('streamEnded=true'));
    expect(output, contains('health-failed reason=after-resume'));
    expect(output, contains('port=$port'));
    // The diagnostic must leave the endpoint closed, preserving the failure.
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
    await socket.close();
  });

  test('preserves status, headers, bytes and stream errors without URL secrets',
      () async {
    final diagnostics = RemoteProxyDiagnostics('SMB');
    final body = StreamController<List<int>>();
    final response = await diagnostics.wrap((_) => Response(
          206,
          body: body.stream,
          headers: {'content-range': 'bytes 0-2/10'},
        ))(Request(
        'GET',
        Uri.parse(
          'http://localhost/smb/stream?conn=private-name&path=secret-file',
        ),
        headers: {'range': 'bytes=0-2'}));
    expect(response.statusCode, 206);
    expect(response.headers['content-range'], 'bytes 0-2/10');
    final received = <int>[];
    final errors = <Object>[];
    final done = Completer<void>();
    response
        .read()
        .listen(received.addAll, onError: errors.add, onDone: done.complete);
    body.add([1, 2, 3]);
    body.addError(StateError('secret URL could appear in upstream error'));
    await body.close();
    await done.future;
    expect(received, [1, 2, 3]);
    expect(errors.single, isA<StateError>());
    final output = logs.join('\n');
    expect(output, contains('body-error'));
    expect(output, contains('status=206'));
    expect(output, isNot(contains('secret')));
    expect(output, isNot(contains('private-name')));
  });
}

class _RealHttp extends HttpOverrides {}

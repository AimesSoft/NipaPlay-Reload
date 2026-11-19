import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// Event-driven observations only: never restarts a proxy or changes its state.
/// Do not log URLs, credentials or query parameters here.
class RemoteProxyDiagnostics {
  RemoteProxyDiagnostics(this.protocol) {
    _instances[protocol] = this;
  }

  static final Map<String, RemoteProxyDiagnostics> _instances = {};
  final String protocol;
  HttpServer? _server;
  int _port = 0;
  bool _streamEnded = false;
  bool _probing = false;
  int _generation = 0;
  int _requests = 0;
  final Stopwatch _uptime = Stopwatch();

  void log(String event) {
    debugPrint('[RemoteProxy][$protocol] $event '
        'generation=$_generation port=$_port '
        'streamEnded=$_streamEnded uptimeMs=${_uptime.elapsedMilliseconds}');
  }

  static String errorSummary(Object error) => error is SocketException
      ? '${error.runtimeType} errno=${error.osError?.errorCode}'
      : '${error.runtimeType}';

  Stream<HttpRequest> observe(HttpServer server) {
    _server = server;
    _port = server.port;
    _streamEnded = false;
    _generation++;
    _uptime
      ..reset()
      ..start();
    final generation = _generation;
    log('listener-bound');
    return server.transform(StreamTransformer.fromHandlers(
      handleError:
          (Object error, StackTrace stack, EventSink<HttpRequest> sink) {
        log('listener-error sourceGeneration=$generation ${errorSummary(error)}');
        sink.addError(error, stack);
      },
      handleDone: (EventSink<HttpRequest> sink) {
        if (generation == _generation) _streamEnded = true;
        log('listener-done sourceGeneration=$generation');
        sink.close();
      },
    ));
  }

  Handler wrap(Handler handler) => (request) async {
        if (!request.url.path.endsWith('/stream')) return handler(request);
        final id = ++_requests;
        final watch = Stopwatch()..start();
        final range = request.headers['range'];
        final safeRange =
            range != null && RegExp(r'^bytes=[0-9,-]+$').hasMatch(range)
                ? range
                : (range == null ? 'none' : 'other');
        log('request id=$id method=${request.method} range=$safeRange');
        try {
          final response = await handler(request);
          log('response id=$id status=${response.statusCode} '
              'headersMs=${watch.elapsedMilliseconds}');
          return response.change(
              body: response.read().transform(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleError: (error, stack, sink) {
                log('body-error id=$id ${errorSummary(error)}');
                sink.addError(error, stack);
              },
            ),
          ));
        } catch (error) {
          log('handler-error id=$id ${errorSummary(error)}');
          rethrow;
        }
      };

  /// Reports whether the cached endpoint is reachable, without repairing it.
  Future<void> probe(String reason) async {
    final server = _server;
    if (server == null || _probing || kIsWeb) return;
    _probing = true;
    final generation = _generation;
    final watch = Stopwatch()..start();
    final port = _port;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    client.findProxy = (_) => 'DIRECT';
    try {
      final status = await (() async {
        final request = await client.getUrl(Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: port,
          path: '/${protocol.toLowerCase()}/health',
        ));
        request.followRedirects = false;
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      })()
          .timeout(const Duration(seconds: 2));
      log('health reason=$reason sourceGeneration=$generation status=$status '
          'elapsedMs=${watch.elapsedMilliseconds}');
    } catch (error) {
      log('health-failed reason=$reason sourceGeneration=$generation '
          '${errorSummary(error)} elapsedMs=${watch.elapsedMilliseconds}');
    } finally {
      client.close(force: true);
      _probing = false;
    }
  }

  static void lifecycle(String state) {
    debugPrint(
        '[RemoteProxy] lifecycle=$state time=${DateTime.now().toIso8601String()} '
        'initialized=${_instances.keys.join(",")}');
    for (final diagnostics in _instances.values) {
      diagnostics.log('lifecycle=$state');
      if (state == 'resumed') unawaited(diagnostics.probe('lifecycle-resumed'));
    }
  }
}

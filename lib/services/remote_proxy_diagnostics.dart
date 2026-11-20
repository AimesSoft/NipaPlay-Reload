import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';

/// Do not log URLs, credentials or query parameters here.
class RemoteProxyDiagnostics {
  RemoteProxyDiagnostics(this.protocol, {this.onResume}) {
    _instances[protocol] = this;
  }

  static const healthHeader = 'x-nipaplay-proxy-instance';
  static const _probeTimeout = Duration(milliseconds: 400);
  static final _random = Random.secure();

  static String newHealthToken() => List.generate(
        16,
        (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();

  static final Map<String, RemoteProxyDiagnostics> _instances = {};
  final String protocol;
  final Future<void> Function()? onResume;
  int _port = 0;
  String? _healthToken;
  bool _streamEnded = false;
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

  /// Records the port of a listener served by another isolate, so [probe]
  /// can reach it over loopback.
  void attach(int port, {String? healthToken}) {
    _port = port;
    _healthToken = healthToken;
    _streamEnded = false;
    _generation++;
    _uptime
      ..reset()
      ..start();
  }

  void detach() {
    _port = 0;
    _healthToken = null;
    _streamEnded = false;
    _uptime.stop();
    _generation++;
  }

  Stream<HttpRequest> observe(HttpServer server, {String? healthToken}) {
    attach(server.port, healthToken: healthToken);
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

  /// Returns true only when there is positive evidence of a lost listener.
  /// A slow or inconclusive probe must not interrupt an active stream.
  Future<bool> probe(String reason) async {
    if (_port == 0 || kIsWeb) return false;
    final generation = _generation;
    final watch = Stopwatch()..start();
    final port = _port;
    final token = _healthToken;
    final client = HttpClient()..connectionTimeout = _probeTimeout;
    client.findProxy = (_) => 'DIRECT';
    try {
      final (status, ownListener) = await (() async {
        final request = await client.openUrl(
            'HEAD',
            Uri(
              scheme: 'http',
              host: '127.0.0.1',
              port: port,
              path: '/${protocol.toLowerCase()}/health',
            ));
        request.followRedirects = false;
        final response = await request.close();
        final status = response.statusCode;
        return (
          status,
          status == HttpStatus.ok &&
              (token == null ||
                  response.headers[healthHeader]?.join(',') == token)
        );
      })()
          .timeout(_probeTimeout);
      log('health reason=$reason sourceGeneration=$generation status=$status '
          'ownListener=$ownListener elapsedMs=${watch.elapsedMilliseconds}');
      return generation == _generation && !ownListener && token != null;
    } catch (error) {
      final refused = error is SocketException &&
          (error.osError?.errorCode ==
              (Platform.isWindows
                  ? 10061
                  : Platform.isLinux || Platform.isAndroid
                      ? 111
                      : 61));
      log('health-failed reason=$reason sourceGeneration=$generation '
          '${errorSummary(error)} refused=$refused elapsedMs=${watch.elapsedMilliseconds}');
      return generation == _generation && refused;
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> lifecycle(String state) async {
    debugPrint(
        '[RemoteProxy] lifecycle=$state time=${DateTime.now().toIso8601String()} '
        'initialized=${_instances.keys.join(",")}');
    await Future.wait(_instances.values.toList().map((diagnostics) async {
      diagnostics.log('lifecycle=$state');
      if (state != 'resumed') return;
      try {
        final onResume = diagnostics.onResume;
        if (onResume == null) {
          await diagnostics.probe('lifecycle-resumed');
        } else {
          await onResume();
        }
      } catch (error) {
        diagnostics.log('resume-heal-failed ${errorSummary(error)}');
      }
    }));
  }
}

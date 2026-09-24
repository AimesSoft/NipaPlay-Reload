import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:nipaplay/plugins/url_resolver.dart';
import 'package:nipaplay/services/app_http_proxy.dart';
import 'package:nipaplay/services/certificate_trust_service.dart';
import 'package:nipaplay/services/system_proxy_service.dart';

/// Exposes a bounded set of media sources to players that cannot pass headers.
class PluginMediaProxy {
  static final instance = PluginMediaProxy();
  Future<_ProxyWorker>? _starting;

  Future<String> register(String url, Map<String, String> headers) async {
    final uri = checkedHttpUri(url);
    final checkedHeaders = checkedHttpHeaders(headers);
    if (checkedHeaders.isEmpty) return uri.toString();
    final starting = _starting ??= _ProxyWorker.start();
    late final _ProxyWorker worker;
    try {
      worker = await starting;
    } catch (_) {
      if (identical(_starting, starting)) _starting = null;
      rethrow;
    }
    return await worker.call(
        'register',
        _ProxySource(
          uri,
          checkedHeaders,
          AppHttpProxy.endpoint,
          SystemProxyService.instance,
          CertificateTrustService.instance,
        )) as String;
  }

  Future<void> close() async {
    final starting = _starting;
    _starting = null;
    if (starting != null) await (await starting).close();
  }
}

class _ProxyWorker {
  _ProxyWorker(this.isolate, this.commands);

  final Isolate isolate;
  final SendPort commands;

  static Future<_ProxyWorker> start() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      _runProxy,
      ready.sendPort,
      debugName: 'media-proxy',
    );
    try {
      final result = await ready.first.timeout(const Duration(seconds: 10));
      if (result is! SendPort) throw StateError(result.toString());
      return _ProxyWorker(isolate, result);
    } catch (_) {
      isolate.kill(priority: Isolate.immediate);
      rethrow;
    } finally {
      ready.close();
    }
  }

  Future<Object?> call(String method, [Object? value]) async {
    final reply = ReceivePort();
    try {
      commands.send([method, value, reply.sendPort]);
      final result =
          await reply.first.timeout(const Duration(seconds: 10)) as List;
      if (result[1] != null) throw StateError(result[1] as String);
      return result[0];
    } finally {
      reply.close();
    }
  }

  Future<void> close() async {
    try {
      await call('close');
    } finally {
      isolate.kill(priority: Isolate.immediate);
    }
  }
}

Future<void> _runProxy(SendPort ready) async {
  final commands = ReceivePort();
  late final _MediaProxyServer proxy;
  try {
    proxy = _MediaProxyServer(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
  } catch (error) {
    commands.close();
    ready.send(error.toString());
    return;
  }
  ready.send(commands.sendPort);
  await for (final message in commands) {
    final values = message as List;
    final reply = values[2] as SendPort;
    try {
      if (values[0] == 'close') {
        await proxy.close();
        reply.send([null, null]);
        commands.close();
        break;
      }
      reply.send([proxy.register(values[1] as _ProxySource), null]);
    } catch (error) {
      reply.send([null, error.toString()]);
    }
  }
}

class _MediaProxyServer {
  _MediaProxyServer(this.server) {
    server.listen(_serve);
  }

  final HttpServer server;
  final _sources = <String, _ProxySource>{};
  final _clients = <HttpClient>{};

  String register(_ProxySource source) {
    final random = Random.secure();
    final token = List.generate(
            24, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    while (_sources.length >= 32) {
      _sources.remove(_sources.keys.first);
    }
    _sources[token] = source;
    return 'http://127.0.0.1:${server.port}/$token/media';
  }

  Future<void> _serve(HttpRequest incoming) async {
    HttpClient? client;
    try {
      final segments = incoming.uri.pathSegments;
      final source = segments.length == 2 && segments.last == 'media'
          ? _sources[segments.first]
          : null;
      if (source == null) {
        incoming.response.statusCode = HttpStatus.notFound;
        return;
      }
      if (incoming.method != 'GET' && incoming.method != 'HEAD') {
        incoming.response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }
      client = HttpClient()
        ..autoUncompress = false
        ..connectionTimeout = const Duration(seconds: 20)
        ..findProxy = source.findProxy
        ..badCertificateCallback = (cert, host, port) =>
            source.certificateTrust.allowHost(host, derBytes: cert.der);
      _clients.add(client);
      final activeClient = client;
      unawaited(incoming.response.done.then<void>(
        (_) => activeClient.close(force: true),
        onError: (Object _) => activeClient.close(force: true),
      ));
      var uri = source.uri;
      final headers = Map<String, String>.from(source.headers);
      for (final name in ['range', 'if-range']) {
        final value = incoming.headers.value(name);
        if (value != null) headers[name] = value;
      }
      headers['accept-encoding'] = 'identity';
      for (var redirects = 0; redirects <= 5; redirects++) {
        final request = await client.openUrl(incoming.method, uri);
        request.followRedirects = false;
        headers.forEach((name, value) => request.headers.set(name, value));
        final response =
            await request.close().timeout(const Duration(seconds: 20));
        if (const [301, 302, 303, 307, 308].contains(response.statusCode)) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirects == 5) {
            throw const HttpException('媒体重定向无效');
          }
          final next = checkedHttpUri(uri.resolve(location).toString());
          if (next.origin != uri.origin) {
            headers.remove('cookie');
            headers.remove('authorization');
          }
          uri = next;
          await response.drain<void>().timeout(const Duration(seconds: 20));
          continue;
        }
        incoming.response.statusCode = response.statusCode;
        for (final name in [
          'content-type',
          'content-length',
          'content-range',
          'accept-ranges',
          'content-encoding',
          'etag',
          'last-modified',
        ]) {
          final value = response.headers.value(name);
          if (value != null) incoming.response.headers.set(name, value);
        }
        if (incoming.method != 'HEAD') {
          await incoming.response.addStream(
            response.timeout(const Duration(seconds: 30)),
          );
        }
        return;
      }
    } catch (_) {
      try {
        incoming.response.statusCode = HttpStatus.badGateway;
      } catch (_) {}
    } finally {
      if (client != null) {
        client.close(force: true);
        _clients.remove(client);
      }
      try {
        await incoming.response.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    for (final client in _clients) {
      client.close(force: true);
    }
    _clients.clear();
    _sources.clear();
    await server.close(force: true);
  }
}

class _ProxySource {
  const _ProxySource(this.uri, this.headers, this.proxyEndpoint,
      this.systemProxy, this.certificateTrust);
  final Uri uri;
  final Map<String, String> headers;
  final String proxyEndpoint;
  final SystemProxyService systemProxy;
  final CertificateTrustService certificateTrust;

  String findProxy(Uri target) {
    final endpoint = AppHttpProxy.validate(proxyEndpoint);
    if (endpoint == null) return systemProxy.findProxy(target);
    return 'PROXY ${endpoint.host}:${endpoint.hasPort ? endpoint.port : 80}';
  }
}

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

class WebUiProxyApi {
  WebUiProxyApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const Set<String> _hopByHopHeaders = {
    'connection',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
    'host',
  };

  Future<Response> handle(Request request) async {
    final rawUrl =
        request.url.queryParameters['url'] ?? request.headers['x-proxy-url'];
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return Response.badRequest(body: 'Missing url parameter');
    }

    final targetUri = Uri.tryParse(rawUrl.trim());
    if (targetUri == null ||
        !targetUri.isAbsolute ||
        !_isSupportedScheme(targetUri)) {
      return Response.badRequest(body: 'Invalid target url');
    }

    final proxyRequest = http.Request(request.method, targetUri);
    _copyHeaders(request.headers, proxyRequest.headers);

    if (_supportsRequestBody(request.method)) {
      final bodyBytes = await request.read().expand((c) => c).toList();
      if (bodyBytes.isNotEmpty) {
        proxyRequest.bodyBytes = bodyBytes;
      }
    }

    http.StreamedResponse upstream;
    try {
      upstream = await _client.send(proxyRequest);
    } catch (e) {
      return Response.internalServerError(body: 'Proxy request failed: $e');
    }

    final responseHeaders = Map<String, String>.from(upstream.headers);
    _stripHopByHop(responseHeaders);

    return Response(
      upstream.statusCode,
      body: upstream.stream,
      headers: responseHeaders,
    );
  }

  Response handleOptions(Request request) {
    return Response.ok('');
  }

  bool _supportsRequestBody(String method) {
    final upper = method.toUpperCase();
    return upper != 'GET' && upper != 'HEAD' && upper != 'OPTIONS';
  }

  bool _isSupportedScheme(Uri uri) {
    return uri.scheme == 'http' || uri.scheme == 'https';
  }

  void _copyHeaders(Map<String, String> source, Map<String, String> target) {
    for (final entry in source.entries) {
      if (_hopByHopHeaders.contains(entry.key.toLowerCase())) {
        continue;
      }
      target[entry.key] = entry.value;
    }
    target.removeWhere((key, _) => key.toLowerCase() == 'accept-encoding');
    target['accept-encoding'] = 'identity';
  }

  void _stripHopByHop(Map<String, String> headers) {
    headers.removeWhere((key, _) => _hopByHopHeaders.contains(key.toLowerCase()));
    headers.remove('content-length');
  }
}

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../kernel.dart';
import 'rpc.dart';

/// MCP tool name for an action id. Some agent runtimes reject dots in tool
/// names, so `playback.open` is exposed as `playback_open`.
String mcpToolName(String actionId) => actionId.replaceAll('.', '_');

final class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.title,
    required this.version,
  });

  final String name;
  final String title;
  final String version;
}

final class McpEndpoint {
  McpEndpoint(
    this.harness, {
    required this.serverInfo,
    required this.token,
    this.instructions,
    this.jsonHandler,
  }) : _rpc =
            McpRpc(harness, serverInfo: serverInfo, instructions: instructions);
  final Harness harness;
  final McpServerInfo serverInfo;
  String token;
  final String? instructions;
  final Handler? jsonHandler;
  final McpRpc _rpc;
  int? _port;

  Handler get handler => _handle;

  Future<HttpServer> serve({required int port}) async {
    final server =
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
    _port = server.port;
    return server;
  }

  Future<Response> _handle(Request request) async {
    final path = request.requestedUri.path;
    if (path != '/mcp' && !(path == '/harness' && jsonHandler != null)) {
      return Response.notFound('');
    }
    if (request.method != 'POST') {
      return Response(405, headers: {'allow': 'POST'});
    }
    if (!_sameToken(request.headers['authorization'] ?? '', 'Bearer $token')) {
      return Response(401);
    }
    final port = _port ?? request.requestedUri.port;
    final host = request.headers['host'];
    if (host != '127.0.0.1:$port' && host != 'localhost:$port') {
      return Response(403);
    }
    final origin = request.headers['origin'];
    if (origin != null) {
      final uri = Uri.tryParse(origin);
      if (uri == null || (uri.host != '127.0.0.1' && uri.host != 'localhost')) {
        return Response(403);
      }
    }

    if (path == '/harness') return jsonHandler!(request);
    Object? message;
    try {
      message = jsonDecode(await request.readAsString());
    } on FormatException {
      return _error(null, -32700, 'Parse error.');
    }
    final response = await _rpc.handle(message, Invocation(origin: 'mcp'));
    return response == null ? Response(202) : _response(response);
  }
}

bool _sameToken(String received, String expected) {
  final a = utf8.encode(received);
  final b = utf8.encode(expected);
  var difference = a.length ^ b.length;
  for (var i = 0; i < max(a.length, b.length); i++) {
    difference |= (i < a.length ? a[i] : 0) ^ (i < b.length ? b[i] : 0);
  }
  return difference == 0;
}

Response _error(Object? id, int code, String message) => _response({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });

Response _response(JsonMap message) => Response.ok(
      jsonEncode(message),
      headers: {'content-type': 'application/json'},
    );

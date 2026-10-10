import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../kernel.dart';

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
  }) {
    for (final spec in harness.catalog) {
      final name = mcpToolName(spec.id);
      if (_tools.containsKey(name)) {
        throw ArgumentError.value(name, 'name', 'MCP tool name collision.');
      }
      _tools[name] = spec;
    }
  }

  final Harness harness;
  final McpServerInfo serverInfo;
  final String token;
  final String? instructions;
  final Map<String, ActionSpec> _tools = {};
  int? _port;

  static const _versions = ['2025-11-25', '2025-06-18', '2025-03-26'];

  Handler get handler => _handle;

  Future<HttpServer> serve({required int port}) async {
    final server =
        await shelf_io.serve(handler, InternetAddress.loopbackIPv4, port);
    _port = server.port;
    return server;
  }

  Future<Response> _handle(Request request) async {
    if (request.requestedUri.path != '/mcp') return Response.notFound('');
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

    Object? message;
    try {
      message = jsonDecode(await request.readAsString());
    } on FormatException {
      return _error(null, -32700, 'Parse error.');
    }
    if (message is! Map<String, Object?> ||
        message['jsonrpc'] != '2.0' ||
        message['method'] is! String) {
      return _error(null, -32600, 'Invalid request.');
    }
    if (!message.containsKey('id')) return Response(202);
    final id = message['id'];
    final params = message['params'] ?? const <String, Object?>{};
    if (params is! Map<String, Object?>) {
      return _error(id, -32602, 'Invalid params.');
    }
    switch (message['method']) {
      case 'initialize':
        final version = params['protocolVersion'];
        return _result(id, {
          'protocolVersion':
              _versions.contains(version) ? version : _versions.first,
          'capabilities': {
            'tools': {'listChanged': false},
          },
          'serverInfo': {
            'name': serverInfo.name,
            'title': serverInfo.title,
            'version': serverInfo.version,
          },
          if (instructions != null) 'instructions': instructions,
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {
          'tools': [
            for (final entry in _tools.entries) _tool(entry.key, entry.value),
          ],
        });
      case 'tools/call':
        final spec = _tools[params['name']];
        if (spec == null) return _error(id, -32602, 'Unknown tool.');
        final outcome = await harness.invokeJson(
          spec.id,
          params['arguments'],
          Invocation(origin: 'mcp'),
        );
        final envelope = outcome.toEnvelope();
        return _result(id, {
          'content': [
            {'type': 'text', 'text': jsonEncode(envelope)},
          ],
          'structuredContent': envelope,
          'isError': outcome is Failed<JsonEncodable>,
        });
      default:
        return _error(id, -32601, 'Method not found.');
    }
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

Response _result(Object? id, JsonMap result) => _response({
      'jsonrpc': '2.0',
      'id': id,
      'result': result,
    });

Response _error(Object? id, int code, String message) => _response({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': code, 'message': message},
    });

Response _response(JsonMap message) => Response.ok(
      jsonEncode(message),
      headers: {'content-type': 'application/json'},
    );

JsonMap _tool(String name, ActionSpec spec) => {
      'name': name,
      'title': spec.title,
      'description': spec.description,
      'inputSchema': spec.input.toJsonSchema(),
      'outputSchema': _envelopeSchema(spec.output),
      'annotations': {
        'title': spec.title,
        'readOnlyHint': spec.effect == Effect.read,
        'destructiveHint': spec.effect == Effect.destructive,
        'idempotentHint': false,
        'openWorldHint': false,
      },
    };

JsonMap _envelopeSchema(ObjectSchema output) {
  final call = {
    'type': 'object',
    'properties': {
      'action': const StringSchema().toJsonSchema(),
      'input': {'type': 'object'},
    },
    'required': ['action', 'input'],
    'additionalProperties': false,
  };
  final option = {
    'type': 'object',
    'properties': {
      'label': const StringSchema().toJsonSchema(),
      'detail': const StringSchema().toJsonSchema(),
      'call': call,
    },
    'required': ['label', 'call'],
    'additionalProperties': false,
  };
  final decision = {
    'type': 'object',
    'properties': {
      'prompt': const StringSchema().toJsonSchema(),
      'options': {'type': 'array', 'items': option},
    },
    'required': ['prompt', 'options'],
    'additionalProperties': false,
  };
  final error = ObjectSchema({
    'code': StringSchema(
        values: [for (final code in FailureCode.values) code.wireName]),
    'message': const StringSchema(),
    'retryable': const BooleanSchema(),
    'violations': const ArraySchema(ObjectSchema({
      'path': StringSchema(),
      'message': StringSchema(),
    }, required: [
      'path',
      'message'
    ])),
  }, required: const [
    'code',
    'message',
    'retryable'
  ]).toJsonSchema();
  return {
    'type': 'object',
    'properties': {
      'status':
          const StringSchema(values: ['completed', 'needs_decision', 'failed'])
              .toJsonSchema(),
      'result': output.toJsonSchema(),
      'decision': decision,
      'error': error,
    },
    'required': ['status'],
    'additionalProperties': false,
    'oneOf': [
      {
        'properties': {
          'status': {'const': 'completed'}
        },
        'required': ['result'],
      },
      {
        'properties': {
          'status': {'const': 'needs_decision'}
        },
        'required': ['decision'],
      },
      {
        'properties': {
          'status': {'const': 'failed'}
        },
        'required': ['error'],
      },
    ],
  };
}

import 'dart:convert';
import '../kernel.dart';
import 'endpoint.dart' show McpServerInfo, mcpToolName;

/// Transport-independent MCP JSON-RPC dispatch to the same Harness.
final class McpRpc {
  McpRpc(this.harness,
      {required this.serverInfo,
      this.instructions,
      this.includeActionIds = false,
      bool Function(ActionSpec)? include,
      Failure? Function(ActionSpec, JsonMap)? authorize})
      : _authorize = authorize {
    for (final spec in harness.catalog.where(include ?? (_) => true)) {
      final name = mcpToolName(spec.id);
      if (_tools.containsKey(name))
        throw ArgumentError('MCP tool name collision: $name');
      _tools[name] = spec;
    }
  }
  final Harness harness;
  final McpServerInfo serverInfo;
  final String? instructions;
  final bool includeActionIds;
  final Failure? Function(ActionSpec, JsonMap)? _authorize;
  final Map<String, ActionSpec> _tools = {};
  static const _versions = ['2025-11-25', '2025-06-18', '2025-03-26'];

  Future<JsonMap?> handle(Object? message, Invocation invocation) async {
    if (message is! JsonMap ||
        message['jsonrpc'] != '2.0' ||
        message['method'] is! String) {
      return error(null, -32600, 'Invalid request.');
    }
    if (!message.containsKey('id')) return null;
    final id = message['id'];
    if (id is! String && id is! num && id != null)
      return error(null, -32600, 'Invalid id.');
    final params = message['params'] ?? const <String, Object?>{};
    if (params is! JsonMap) return error(id, -32602, 'Invalid params.');
    switch (message['method']) {
      case 'initialize':
        final version = params['protocolVersion'];
        return _result(id, {
          'protocolVersion':
              _versions.contains(version) ? version : _versions.first,
          'capabilities': {
            'tools': {'listChanged': false}
          },
          'serverInfo': {
            'name': serverInfo.name,
            'title': serverInfo.title,
            'version': serverInfo.version
          },
          if (instructions != null) 'instructions': instructions,
        });
      case 'ping':
        return _result(id, {});
      case 'tools/list':
        return _result(id, {
          'tools': [
            for (final entry in _tools.entries)
              {
                ..._tool(entry.key, entry.value),
                if (includeActionIds)
                  '_meta': {
                    'nipaplay/actionId': entry.value.id,
                    'nipaplay/effect': entry.value.effect.name,
                    'nipaplay/outputSchema': entry.value.output.toJsonSchema(),
                  },
              }
          ]
        });
      case 'tools/call':
        final spec = _tools[params['name']];
        if (spec == null) return error(id, -32602, 'Unknown tool.');
        final denied = _authorize?.call(spec, params);
        final outcome = denied == null
            ? await harness.invokeJson(spec.id, params['arguments'], invocation)
            : Failed<JsonEncodable>(denied);
        final envelope = outcome.toEnvelope();
        return _result(id, {
          'content': [
            {'type': 'text', 'text': jsonEncode(envelope)}
          ],
          'structuredContent': envelope,
          'isError': outcome is Failed<JsonEncodable>,
        });
      default:
        return error(id, -32601, 'Method not found.');
    }
  }

  static JsonMap error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message}
      };
}

JsonMap _result(Object? id, JsonMap result) =>
    {'jsonrpc': '2.0', 'id': id, 'result': result};

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

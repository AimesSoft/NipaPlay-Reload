import 'dart:convert';
import 'dart:io';

import 'package:nipa_harness/mcp.dart';
import 'package:nipa_harness/nipa_harness.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import 'support.dart';

const _serverInfo =
    McpServerInfo(name: 'test', title: 'Test server', version: '1.0');
const _token = 'test-token';
const _uri = 'http://127.0.0.1:47811/mcp';

Request _request({
  String method = 'POST',
  String uri = _uri,
  Object? message = const {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'},
  String? rawBody,
  Map<String, String> headers = const {},
  bool authenticated = true,
}) =>
    Request(
      method,
      Uri.parse(uri),
      headers: {
        'host': '127.0.0.1:47811',
        if (authenticated) 'authorization': 'Bearer $_token',
        ...headers,
      },
      body: rawBody ?? jsonEncode(message),
    );

Future<JsonMap> _body(Response response) async =>
    jsonDecode(await response.readAsString()) as JsonMap;

Future<JsonMap> _rpc(McpEndpoint endpoint, String method,
    {JsonMap? params, Object? id = 1}) async {
  final response = await endpoint.handler(_request(message: {
    'jsonrpc': '2.0',
    'id': id,
    'method': method,
    if (params != null) 'params': params,
  }));
  expect(response.statusCode, 200);
  expect(response.headers['content-type'], 'application/json');
  expect(response.headers.containsKey('mcp-session-id'), isFalse);
  final body = await _body(response);
  expect(body['jsonrpc'], '2.0');
  expect(body['id'], id);
  return body;
}

void main() {
  late McpEndpoint endpoint;
  late RecordingObserver observer;

  setUp(() {
    observer = RecordingObserver();
    final harness = Harness([
      FixtureCapability([
        FixtureAction(id: 'playback.state'),
        FixtureAction(
            id: 'playback.open',
            effect: Effect.write,
            input: const ObjectSchema({'path': StringSchema(minLength: 1)},
                required: ['path'])),
        FixtureAction(
            id: 'media.delete',
            effect: Effect.destructive,
            onRun: (input, invocation) async =>
                throw const Failure(FailureCode.conflict, 'In use.')),
        FixtureAction(
            id: 'media.choose',
            onRun: (input, invocation) async => const NeedsDecision(
                  Decision(prompt: 'Choose a file.', options: [
                    DecisionOption(
                        label: 'File',
                        detail: 'Local file',
                        call:
                            ActionCall('playback.open', {'path': 'file.mkv'})),
                  ]),
                )),
      ])
    ], observers: [
      observer
    ]);
    endpoint = McpEndpoint(harness,
        serverInfo: _serverInfo,
        token: _token,
        instructions: 'Read before acting.');
  });

  test('constructor rejects tool name mapping collisions', () {
    final harness = Harness([
      FixtureCapability([
        FixtureAction(id: 'test.a_b'),
        FixtureAction(id: 'test_a.b'),
      ])
    ]);
    expect(() => McpEndpoint(harness, serverInfo: _serverInfo, token: _token),
        throwsArgumentError);
  });

  group('initialize', () {
    for (final version in [
      '2025-11-25',
      '2025-06-18',
      '2025-03-26',
      'unsupported'
    ]) {
      test('negotiates $version', () async {
        final message = await _rpc(endpoint, 'initialize',
            params: {
              'protocolVersion': version,
              'capabilities': <String, Object?>{},
              'clientInfo': {'name': 'client', 'version': '1'},
            },
            id: 'init');
        expect(message['result'], {
          'protocolVersion': version == 'unsupported' ? '2025-11-25' : version,
          'capabilities': {
            'tools': {'listChanged': false}
          },
          'serverInfo': {
            'name': 'test',
            'title': 'Test server',
            'version': '1.0'
          },
          'instructions': 'Read before acting.',
        });
      });
    }

    test('omits absent optional instructions', () async {
      final withoutInstructions =
          McpEndpoint(Harness([]), serverInfo: _serverInfo, token: _token);
      final message = await _rpc(withoutInstructions, 'initialize',
          params: {'protocolVersion': '2025-11-25'});
      expect(
          (message['result'] as JsonMap).containsKey('instructions'), isFalse);
    });
  });

  test('notifications return 202 without a response body', () async {
    final response = await endpoint.handler(_request(message: {
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
    }));
    expect(response.statusCode, 202);
    expect(await response.readAsString(), isEmpty);
    expect(response.headers.containsKey('mcp-session-id'), isFalse);
    expect(observer.records, isEmpty);
  });

  test('ping returns an empty result and preserves a null request id',
      () async {
    final body = await _rpc(endpoint, 'ping', id: null);
    expect(body['result'], <String, Object?>{});
  });

  test('tools/list maps names, contracts and all effect annotations', () async {
    final body = await _rpc(endpoint, 'tools/list');
    final tools = (body['result'] as JsonMap)['tools'] as List;
    expect(tools.map((tool) => (tool as JsonMap)['name']), [
      'media_choose',
      'media_delete',
      'playback_open',
      'playback_state',
    ]);
    for (var i = 0; i < tools.length; i++) {
      final tool = tools[i] as JsonMap;
      final spec = endpoint.harness.catalog[i];
      expect(tool.keys.toSet(), {
        'name',
        'title',
        'description',
        'inputSchema',
        'outputSchema',
        'annotations',
      });
      expect(tool['title'], spec.title);
      expect(tool['description'], spec.description);
      expect(tool['inputSchema'], spec.input.toJsonSchema());
      expect(tool['outputSchema'], _expectedEnvelopeSchema);
      expect(tool['annotations'], {
        'title': spec.title,
        'readOnlyHint': spec.effect == Effect.read,
        'destructiveHint': spec.effect == Effect.destructive,
        'idempotentHint': false,
        'openWorldHint': false,
      });
    }
    expect((tools[2] as JsonMap)['inputSchema'], {
      'type': 'object',
      'properties': {
        'path': {'type': 'string', 'minLength': 1}
      },
      'required': ['path'],
      'additionalProperties': false,
    });
  });

  group('tools/call', () {
    test('completed result includes matching text and structured envelopes',
        () async {
      final body = await _rpc(endpoint, 'tools/call', params: {
        'name': 'playback_open',
        'arguments': {'path': 'file.mkv'},
      });
      final result = body['result'] as JsonMap;
      const envelope = {
        'status': 'completed',
        'result': {'value': 'done'}
      };
      expect(result, {
        'content': [
          {'type': 'text', 'text': jsonEncode(envelope)}
        ],
        'structuredContent': envelope,
        'isError': false,
      });
      expect(observer.records.single.origin, 'mcp');
      expect(observer.records.single.actionId, 'playback.open');
      expect(observer.records.single.input, {'path': 'file.mkv'});
    });

    test('absent arguments use the Harness null-input behavior', () async {
      final body = await _rpc(endpoint, 'tools/call',
          params: {'name': 'playback_state'});
      expect((body['result'] as JsonMap)['isError'], isFalse);
      expect(observer.records.single.input, isNull);
    });

    test('needs_decision is successful and its option call can be executed',
        () async {
      final body =
          await _rpc(endpoint, 'tools/call', params: {'name': 'media_choose'});
      final result = body['result'] as JsonMap;
      final envelope = result['structuredContent'] as JsonMap;
      expect(result['isError'], isFalse);
      expect(envelope, {
        'status': 'needs_decision',
        'decision': {
          'prompt': 'Choose a file.',
          'options': [
            {
              'label': 'File',
              'detail': 'Local file',
              'call': {
                'action': 'playback.open',
                'input': {'path': 'file.mkv'}
              },
            }
          ],
        },
      });
      expect(
          jsonDecode(((result['content'] as List).single as JsonMap)['text']
              as String),
          envelope);
      final next = await _rpc(endpoint, 'tools/call', params: {
        'name': 'playback_open',
        'arguments': {'path': 'file.mkv'},
      });
      expect((next['result'] as JsonMap)['isError'], isFalse);
      expect(observer.records.map((record) => record.status),
          ['needs_decision', 'completed']);
    });

    test('domain failure is a tool result with isError true', () async {
      final body =
          await _rpc(endpoint, 'tools/call', params: {'name': 'media_delete'});
      final result = body['result'] as JsonMap;
      const envelope = {
        'status': 'failed',
        'error': {'code': 'conflict', 'message': 'In use.', 'retryable': false},
      };
      expect(result, {
        'content': [
          {'type': 'text', 'text': jsonEncode(envelope)}
        ],
        'structuredContent': envelope,
        'isError': true,
      });
      expect(body.containsKey('error'), isFalse);
      expect(observer.records.single.failureCode, FailureCode.conflict);
    });

    test(
        'invalid arguments are tool results with violations, including non-map input',
        () async {
      for (final arguments in <Object?>[
        {'path': ''},
        {'extra': true},
        false,
        null
      ]) {
        final body = await _rpc(endpoint, 'tools/call', params: {
          'name': 'playback_open',
          'arguments': arguments,
        });
        final result = body['result'] as JsonMap;
        final envelope = result['structuredContent'] as JsonMap;
        expect(result['isError'], isTrue);
        expect(envelope['status'], 'failed');
        final error = envelope['error'] as JsonMap;
        expect(error['code'], 'invalid_input');
        expect(error['violations'], isNotEmpty);
        expect(body.containsKey('error'), isFalse);
        expect(observer.records.last.input, arguments);
      }
      expect(observer.records, hasLength(4));
    });

    test('unknown tool returns -32602 and does not invoke an action', () async {
      final body =
          await _rpc(endpoint, 'tools/call', params: {'name': 'missing_tool'});
      expect((body['error'] as JsonMap)['code'], -32602);
      expect(body.containsKey('result'), isFalse);
      expect(observer.records, isEmpty);
    });
  });

  group('JSON-RPC errors', () {
    test('non-object params return -32602 for any request', () async {
      for (final method in ['initialize', 'tools/call', 'ping']) {
        final response = await endpoint.handler(_request(message: {
          'jsonrpc': '2.0',
          'id': 1,
          'method': method,
          'params': ['not', 'an', 'object'],
        }));
        final body = await _body(response);
        expect((body['error'] as JsonMap)['code'], -32602, reason: method);
      }
      expect(observer.records, isEmpty);
    });

    test('unknown method returns -32601', () async {
      final body = await _rpc(endpoint, 'missing/method');
      expect((body['error'] as JsonMap)['code'], -32601);
    });

    test('bad JSON returns -32700', () async {
      final response = await endpoint.handler(_request(rawBody: '{broken'));
      expect(response.statusCode, 200);
      expect(response.headers['content-type'], 'application/json');
      expect(await _body(response), {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': -32700, 'message': 'Parse error.'},
      });
    });

    test(
        'batch, scalar, missing version/method and wrong version/method return -32600',
        () async {
      for (final message in <Object?>[
        <Object?>[],
        [
          {'jsonrpc': '2.0', 'id': 1, 'method': 'ping'}
        ],
        null,
        7,
        'ping',
        {'id': 1, 'method': 'ping'},
        {'jsonrpc': '1.0', 'id': 1, 'method': 'ping'},
        {'jsonrpc': '2.0', 'id': 1},
        {'jsonrpc': '2.0', 'id': 1, 'method': 7},
      ]) {
        final response = await endpoint.handler(_request(message: message));
        final body = await _body(response);
        expect((body['error'] as JsonMap)['code'], -32600, reason: '$message');
        expect(body['id'], isNull);
      }
    });
  });

  group('HTTP boundary', () {
    test('missing and wrong bearer tokens return 401 before parsing JSON',
        () async {
      expect(
          (await endpoint.handler(_request(authenticated: false))).statusCode,
          401);
      for (final authorization in [
        '',
        'Bearer wrong-token',
        'Bearer test-toke',
        'Bearer test-token-longer',
        'bearer test-token',
        'Basic test-token',
        'Bearer tést-token'
      ]) {
        final response = await endpoint.handler(_request(
            rawBody: '{bad', headers: {'authorization': authorization}));
        expect(response.statusCode, 401, reason: authorization);
      }
    });

    test('loopback Hosts are accepted and other Hosts are forbidden', () async {
      for (final host in ['127.0.0.1:47811', 'localhost:47811']) {
        expect(
            (await endpoint.handler(_request(headers: {'host': host})))
                .statusCode,
            200);
      }
      for (final host in [
        'evil.example:47811',
        '127.0.0.1:47812',
        'localhost',
        '127.0.0.1',
        '[::1]:47811',
        '127.0.0.1.evil:47811'
      ]) {
        expect(
            (await endpoint.handler(_request(headers: {'host': host})))
                .statusCode,
            403,
            reason: host);
      }
    });

    test(
        'optional loopback Origins are accepted and other Origins are forbidden',
        () async {
      for (final origin in [
        'http://localhost:47811',
        'http://127.0.0.1:8000'
      ]) {
        expect(
            (await endpoint.handler(_request(headers: {'origin': origin})))
                .statusCode,
            200);
      }
      for (final origin in [
        'https://evil.example',
        'http://localhost.evil',
        'null',
        'http://[::1]',
        'http://[bad'
      ]) {
        expect(
            (await endpoint.handler(_request(headers: {'origin': origin})))
                .statusCode,
            403,
            reason: origin);
      }
    });

    test('GET, DELETE and other methods return 405', () async {
      for (final method in ['GET', 'DELETE', 'PUT']) {
        final response = await endpoint.handler(_request(method: method));
        expect(response.statusCode, 405);
        expect(response.headers['allow'], 'POST');
      }
    });

    test('other paths return 404', () async {
      for (final path in ['/', '/other', '/mcp/']) {
        final response = await endpoint
            .handler(_request(uri: 'http://127.0.0.1:47811$path'));
        expect(response.statusCode, 404);
      }
    });
  });

  test(
      'serve allocates a loopback port and serves initialize and tools/call over HTTP',
      () async {
    final server = await endpoint.serve(port: 0);
    addTearDown(() => server.close(force: true));
    // Bypass HTTP(S)_PROXY so the request reaches the loopback server.
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    addTearDown(() => client.close(force: true));
    expect(server.address.address, '127.0.0.1');
    expect(server.address.type, InternetAddressType.IPv4);
    expect(server.port, greaterThan(0));
    final uri = Uri.parse('http://127.0.0.1:${server.port}/mcp');
    for (final message in <JsonMap>[
      {
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': {'protocolVersion': '2025-06-18'}
      },
      {
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'tools/call',
        'params': {
          'name': 'playback_open',
          'arguments': {'path': 'file.mkv'}
        }
      },
    ]) {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(message));
      final response = await request.close();
      expect(response.statusCode, 200);
      expect(response.headers.contentType?.mimeType, 'application/json');
      expect(response.headers.value('mcp-session-id'), isNull);
      final body =
          jsonDecode(await utf8.decoder.bind(response).join()) as JsonMap;
      expect(body['id'], message['id']);
      final result = body['result'] as JsonMap;
      if (message['method'] == 'initialize') {
        expect(result['protocolVersion'], '2025-06-18');
      } else {
        expect(result['structuredContent'], {
          'status': 'completed',
          'result': {'value': 'done'},
        });
        expect(result['isError'], isFalse);
      }
    }
    final wrongPortRequest = await client.postUrl(uri);
    wrongPortRequest.headers
        .set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    wrongPortRequest.headers
        .set(HttpHeaders.hostHeader, 'localhost:${server.port + 1}');
    wrongPortRequest
        .write(jsonEncode({'jsonrpc': '2.0', 'id': 3, 'method': 'ping'}));
    final forbidden = await wrongPortRequest.close();
    expect(forbidden.statusCode, 403);
    await forbidden.drain<void>();
    expect(observer.records.single.actionId, 'playback.open');
  });
}

const _expectedEnvelopeSchema = <String, Object?>{
  'type': 'object',
  'properties': {
    'status': {
      'type': 'string',
      'enum': ['completed', 'needs_decision', 'failed']
    },
    'result': {
      'type': 'object',
      'properties': {
        'value': {'type': 'string'}
      },
      'required': ['value'],
      'additionalProperties': false,
    },
    'decision': {
      'type': 'object',
      'properties': {
        'prompt': {'type': 'string'},
        'options': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'label': {'type': 'string'},
              'detail': {'type': 'string'},
              'call': {
                'type': 'object',
                'properties': {
                  'action': {'type': 'string'},
                  'input': {'type': 'object'}
                },
                'required': ['action', 'input'],
                'additionalProperties': false,
              },
            },
            'required': ['label', 'call'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['prompt', 'options'],
      'additionalProperties': false,
    },
    'error': {
      'type': 'object',
      'properties': {
        'code': {
          'type': 'string',
          'enum': [
            'invalid_input',
            'not_found',
            'unavailable',
            'conflict',
            'internal'
          ]
        },
        'message': {'type': 'string'},
        'retryable': {'type': 'boolean'},
        'violations': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'path': {'type': 'string'},
              'message': {'type': 'string'}
            },
            'required': ['path', 'message'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['code', 'message', 'retryable'],
      'additionalProperties': false,
    },
  },
  'required': ['status'],
  'additionalProperties': false,
  'oneOf': [
    {
      'properties': {
        'status': {'const': 'completed'}
      },
      'required': ['result']
    },
    {
      'properties': {
        'status': {'const': 'needs_decision'}
      },
      'required': ['decision']
    },
    {
      'properties': {
        'status': {'const': 'failed'}
      },
      'required': ['error']
    },
  ],
};

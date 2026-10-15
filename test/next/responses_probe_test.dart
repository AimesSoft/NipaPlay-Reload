import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/next/settings/responses_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'classifies Responses/tool/credential/model failures without echoing upstream secrets',
      () async {
    HttpOverrides.global = null;
    final paths = <String>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var status = 401;
    Object body = {
      'error': {'message': 'Bearer secret-canary'}
    };
    server.listen((request) async {
      paths.add(request.uri.path);
      final input = jsonDecode(
              await request.cast<List<int>>().transform(utf8.decoder).join())
          as Map;
      expect(input['tools'][0]['name'], 'nipaplay_connection_check');
      request.response.statusCode = status;
      request.response.write(jsonEncode(body));
      await request.response.close();
    });
    final client = HttpClient()..findProxy = (_) => 'DIRECT';
    try {
      Future<String?> check() async => (await probeResponses(
              client,
              Uri.parse('http://127.0.0.1:${server.port}/prefix/v1/responses/'),
              'custom-model',
              'secret-canary'))
          .message;
      expect(await check(), '密钥无效或没有权限');
      status = 404;
      body = {
        'error': {'code': 'model_not_found', 'message': 'secret-canary'}
      };
      expect(await check(), '模型名不存在');
      body = {
        'error': {'message': 'Only /chat/completions supported'}
      };
      expect(await check(), '端点不支持 Responses 接口');
      status = 400;
      body = {
        'error': {'param': 'tools', 'code': 'unsupported_parameter'}
      };
      expect(await check(), '此模型不支持工具调用');
      status = 200;
      body = {'object': 'response', 'status': 'completed', 'output': []};
      expect(await check(), '未通过工具调用检查');
      body = {
        'object': 'response',
        'status': 'completed',
        'output': [
          {
            'type': 'function_call',
            'name': 'nipaplay_connection_check',
            'call_id': 'test',
            'arguments': '{}'
          }
        ]
      };
      expect(await check(), contains('支持工具调用'));
      expect(paths.toSet(), {'/prefix/v1/responses'});
    } finally {
      client.close(force: true);
      await server.close(force: true);
    }
  });
}

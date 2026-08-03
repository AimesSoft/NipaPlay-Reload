import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/remote_text_input_service.dart';
import 'package:shelf/shelf.dart';

void main() {
  final service = RemoteTextInputService.instance;

  setUp(service.clearForTesting);
  tearDown(service.clearForTesting);

  test('input URL carries an opaque one-time key and can be scanned', () {
    final session = service.createSession(
      title: '服务器地址',
      initialValue: 'https://example.com',
    );
    final uri = service.buildInputUri('http://192.168.1.8:1180/', session);

    expect(
      uri.toString(),
      'http://192.168.1.8:1180/api/remote/input/${session.key}',
    );
    expect(session.displayKey, hasLength(9));

    final request = RemoteTextInputClientService.tryParseScannedText(
      uri.toString(),
    );
    expect(request, isNotNull);
    expect(request!.key, session.key);
    expect(request.uri, uri);
    expect(
      RemoteTextInputClientService.tryParseScannedText(
        'http://192.168.1.8:1180/api/info',
      ),
      isNull,
    );
  });

  test('JSON metadata and submission complete the TV session once', () async {
    final session = service.createSession(
      title: '搜索媒体库',
      initialValue: '旧内容',
      maxLength: 20,
    );
    final api = RemoteTextInputApiService();
    final uri = Uri.parse('http://localhost/${session.key}');

    final metadataResponse = await api.router.call(
      Request(
        'GET',
        uri.replace(queryParameters: const {'format': 'json'}),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final metadata = json.decode(await metadataResponse.readAsString())
        as Map<String, dynamic>;
    expect(metadataResponse.statusCode, 200);
    expect(metadata['title'], '搜索媒体库');
    expect(metadata['initialValue'], '旧内容');
    expect(metadata['status'], 'pending');

    final submitResponse = await api.router.call(
      Request(
        'POST',
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(const {'value': '新内容'}),
      ),
    );
    expect(submitResponse.statusCode, 200);
    expect(await session.result, '新内容');

    final repeatedResponse = await api.router.call(
      Request(
        'POST',
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: json.encode(const {'value': '第二次提交'}),
      ),
    );
    expect(repeatedResponse.statusCode, 409);
    expect(session.submittedValue, '新内容');
  });

  test('browser fallback renders a form without exposing password text',
      () async {
    final session = service.createSession(
      title: '密码',
      initialValue: 'do-not-render',
      obscureText: true,
    );
    final api = RemoteTextInputApiService();

    final response = await api.router.call(
      Request('GET', Uri.parse('http://localhost/${session.key}')),
    );
    final body = await response.readAsString();

    expect(response.statusCode, 200);
    expect(body, contains('发送到 Apple TV'));
    expect(body, contains('type="password"'));
    expect(body, contains(session.displayKey));
    expect(body, isNot(contains('do-not-render')));
  });

  test('group session returns multiple fields and submits them together',
      () async {
    final session = service.createGroupSession(
      title: '连接到 Emby 服务器',
      fields: const <RemoteTextInputField>[
        RemoteTextInputField(
          id: 'server',
          title: '服务器地址',
          initialValue: 'http://192.168.1.20:8096',
          inputType: 'url',
          required: true,
        ),
        RemoteTextInputField(
          id: 'username',
          title: '用户名',
          initialValue: '',
        ),
        RemoteTextInputField(
          id: 'password',
          title: '密码',
          initialValue: 'existing-secret',
          obscureText: true,
        ),
      ],
    );
    final api = RemoteTextInputApiService();
    final uri = Uri.parse('http://localhost/${session.key}');

    final metadataResponse = await api.router.call(
      Request(
        'GET',
        uri.replace(queryParameters: const {'format': 'json'}),
        headers: const {'Accept': 'application/json'},
      ),
    );
    final metadata = json.decode(await metadataResponse.readAsString())
        as Map<String, dynamic>;
    final fields = metadata['fields'] as List<dynamic>;
    expect(fields, hasLength(3));
    expect((fields.first as Map<String, dynamic>)['id'], 'server');
    expect((fields.last as Map<String, dynamic>)['initialValue'], isEmpty);
    expect((fields.last as Map<String, dynamic>)['hasInitialValue'], isTrue);

    final submitResponse = await api.router.call(
      Request(
        'POST',
        uri,
        headers: const {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
        body: json.encode(<String, dynamic>{
          'values': <String, String>{
            'server': 'http://emby.local:8096',
            'username': 'nipa',
            'password': '',
          },
        }),
      ),
    );
    expect(submitResponse.statusCode, 200);
    final submission = await session.submissionResult;
    expect(submission!.values, <String, String>{
      'server': 'http://emby.local:8096',
      'username': 'nipa',
      'password': 'existing-secret',
    });
  });

  test('browser group form renders every field and enforces required input',
      () async {
    final session = service.createGroupSession(
      title: '添加 SMB 服务器',
      fields: const <RemoteTextInputField>[
        RemoteTextInputField(
          id: 'host',
          title: '主机/IP 地址',
          initialValue: '',
          required: true,
        ),
        RemoteTextInputField(
          id: 'port',
          title: '端口',
          initialValue: '445',
          inputType: 'number',
        ),
      ],
    );
    final api = RemoteTextInputApiService();
    final uri = Uri.parse('http://localhost/${session.key}');

    final page = await api.router.call(Request('GET', uri));
    final body = await page.readAsString();
    expect(body, contains('主机&#47;IP 地址'));
    expect(body, contains('name="field_0"'));
    expect(body, contains('name="field_1"'));
    expect(body, contains('inputmode="decimal"'));

    final invalid = await api.router.call(
      Request(
        'POST',
        uri,
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: 'field_0=&field_1=445',
      ),
    );
    expect(invalid.statusCode, 400);
    expect(
      await invalid.readAsString(),
      contains('请填写主机&#47;IP 地址'),
    );
  });
}

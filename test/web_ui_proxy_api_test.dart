import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/services/web_ui_proxy_api.dart';
import 'package:shelf/shelf.dart';

void main() {
  test('转发带 Accept-Encoding 的请求不会抛错，且改写为 identity', () async {
    // 回归：代理先 removeWhere 掉 accept-encoding 再写回同名头，
    // 在 Dart 3.13 上会抛 type 'List<dynamic>' is not a subtype of type
    // 'String'（dart-lang/sdk#64217），而浏览器请求基本都带这个头。
    http.BaseRequest? forwarded;
    final api = WebUiProxyApi(
      client: MockClient((request) async {
        forwarded = request;
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final response = await api.handle(
      Request(
        'GET',
        Uri.parse('http://localhost/api/proxy?url=https%3A%2F%2Fapi.example.com%2Fv2%2Fcomment%2F1'),
        headers: {
          'accept': 'application/json',
          'accept-encoding': 'gzip, deflate, br',
        },
      ),
    );

    expect(response.statusCode, 200);
    expect(forwarded, isNotNull);
    expect(forwarded!.headers['accept-encoding'], 'identity');
    expect(forwarded!.headers['accept'], 'application/json');
    await response.readAsString();
  });
}

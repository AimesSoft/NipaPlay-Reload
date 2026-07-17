@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/services/media_server_transport.dart';

void main() {
  test('browser transports do not try to set the restricted User-Agent header',
      () async {
    final client = _RecordingClient();
    final transport = MediaServerTransport.fromClient(client);
    addTearDown(transport.close);

    await transport.send(
      http.Request('GET', Uri.parse('https://media.example/Items/1')),
      timeout: const Duration(seconds: 1),
    );

    expect(client.userAgent, isNull);
  });
}

class _RecordingClient extends http.BaseClient {
  String? userAgent;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    userAgent = request.headers['User-Agent'];
    return http.StreamedResponse(const Stream<List<int>>.empty(), 200);
  }
}

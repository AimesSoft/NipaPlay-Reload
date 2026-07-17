import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/player_abstraction/player_factory.dart';
import 'package:nipaplay/utils/remote_media_fetcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('remote media hashing sends the sanitized player User-Agent', () async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.customPlayerUA: '  PlayerClient/5.0\r\nInjected  ',
    });
    await PlayerFactory.initialize();
    addTearDown(() async {
      await PlayerFactory.saveCustomPlayerUA('');
      SharedPreferences.setMockInitialValues({});
    });
    final userAgents = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
      if (request.method == 'HEAD') {
        request.response.headers.set(HttpHeaders.contentLengthHeader, '6');
      } else {
        request.response
          ..statusCode = HttpStatus.partialContent
          ..headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-5/6')
          ..add([1, 2, 3, 4, 5, 6]);
      }
      await request.response.close();
    });

    final result = await RemoteMediaFetcher.fetchHead(
      Uri.parse('http://${server.address.address}:${server.port}/episode.mkv'),
    );

    expect(result.fileSize, 6);
    expect(result.bytesHashed, 6);
    expect(userAgents, hasLength(2));
    expect(userAgents, everyElement('PlayerClient/5.0Injected'));
  });
}

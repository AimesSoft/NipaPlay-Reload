@TestOn('browser')
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/security/credential_store.dart';
import 'package:nipaplay/services/dandanplay_http_client.dart';
import 'package:nipaplay/services/dandanplay_service.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';
import 'package:nipaplay/utils/network_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security/memory_vault.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real Web relay keeps login gating while only outbound destinations receive credentials',
      () async {
    SharedPreferences.setMockInitialValues({});
    CredentialStore.instance = CredentialStore(MemoryVault(), desktop: true);
    await WebRemoteAccessService.setBaseUrl('http://host:1180/nipa');
    final gateway =
        Uri.parse('${NetworkSettings.primaryServer}/api/v2/comment/123');
    final seen = <http.Request>[];
    final client = DandanplayHttpClient(
      authorization: () => {'Authorization': 'Bearer synthetic-secret'},
      inner: MockClient((request) async {
        seen.add(request);
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);
    final relay = WebRemoteAccessService.proxyUri(gateway);
    expect(relay.path, '/nipa/api/web_proxy');
    await expectLater(
        client.get(relay), throwsA(isA<DandanplayLoginRequired>()));
    expect(seen, isEmpty);
    for (final fake in [
      'http://host.evil:1180/nipa/api/web_proxy',
      'http://host:1181/nipa/api/web_proxy',
      'http://host:1180/nipa-evil/api/web_proxy',
    ]) {
      final uri =
          Uri.parse(fake).replace(queryParameters: {'url': gateway.toString()});
      await client
          .get(uri, headers: {'Authorization': 'Bearer synthetic-secret'});
      expect(seen.last.headers.containsKey('authorization'), isFalse);
      expect(DandanplayHttpClient.targetUri(uri), uri);
    }
    await DandanplayService.saveLoginInfo(
        'synthetic-secret', 'fixture', 'fixture');
    await client
        .get(relay, headers: {'Authorization': 'Bearer synthetic-secret'});
    expect(seen.last.url, relay);
    expect(seen.last.headers.containsKey('authorization'), isFalse);
    final image = Uri.parse('http://host:1180/nipa/api/image_proxy')
        .replace(queryParameters: {
      'url': base64Url.encode(utf8.encode(gateway.toString())),
    });
    expect(DandanplayHttpClient.targetUri(image), gateway);
    await client.get(image);
    expect(seen.last.headers.containsKey('authorization'), isFalse);
    await client.get(gateway);
    expect(seen.last.headers['authorization'], 'Bearer synthetic-secret');
    final sameHost = Uri.parse('http://host:1180/nipa/api/info');
    expect(WebRemoteAccessService.proxyUri(sameHost), sameHost);
    final other = Uri.parse('http://host.evil:1180/nipa/api/info');
    expect(WebRemoteAccessService.proxyUri(other).queryParameters['url'],
        other.toString());
  });
}

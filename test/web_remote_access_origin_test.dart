import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/services/web_remote_access_service.dart';

void main() {
  final base = Uri.parse('http://user:password@HOST.example:80/nipa');
  test(
      'same origin and base path stay direct, including default ports and Basic URLs',
      () {
    for (final url in [
      'http://host.example/nipa/api/info',
      'http://other:secret@host.example:80/nipa/api/history',
      'http://HOST.example/nipa',
    ]) {
      final target = Uri.parse(url);
      expect(WebRemoteAccessService.proxyUriForBase(target, base), target);
    }
  });
  test(
      'host prefixes, ports, schemes and path prefixes cannot impersonate the host',
      () {
    for (final url in [
      'http://host.example.evil/nipa/api/info',
      'http://host.example:8080/nipa/api/info',
      'https://host.example/nipa/api/info',
      'http://host.example/nipa-evil/api/info',
      'http://host.example/NIPA/api/info',
      'http://second-host.example:1180/api/media/local/share/episodes/id/stream',
    ]) {
      final proxy =
          WebRemoteAccessService.proxyUriForBase(Uri.parse(url), base);
      expect(proxy.host, 'host.example');
      expect(proxy.path, '/nipa/api/web_proxy');
      expect(proxy.queryParameters['url'], url);
      expect(proxy.userInfo, 'user:password');
    }
  });
  test('relative and non-HTTP resources stay direct', () {
    for (final url in [
      '/api/info',
      'data:image/png;base64,YQ==',
      'blob:https://host.example/id'
    ]) {
      final uri = Uri.parse(url);
      expect(WebRemoteAccessService.proxyUriForBase(uri, base), uri);
    }
  });
}

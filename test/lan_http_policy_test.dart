import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:nipaplay/services/lan_http_policy.dart';

void main() {
  test('host CORS replaces all upstream CORS and merges Vary', () async {
    for (final origin in [
      'http://host:1180',
      'https://independent-ui.example',
      'null'
    ]) {
      final handler =
          lanResponsePolicy()((_) => Response(206, body: 'range', headers: {
                'Access-Control-Allow-Origin': 'https://upstream.example',
                'Access-Control-Allow-Credentials': 'false',
                'Access-Control-Allow-Private-Network': 'true',
                'Vary': 'Accept-Encoding, origin',
                'Content-Range': 'bytes 0-4/10',
                'Cache-Control': 'public, max-age=3600',
              }));
      final response = await handler(Request(
          'GET', Uri.parse('http://host/api/web_proxy'),
          headers: {'Origin': origin}));
      expect(response.statusCode, 206);
      expect(response.headers['access-control-allow-origin'], origin);
      expect(response.headers['access-control-allow-credentials'], 'true');
      expect(
          response.headers.containsKey('access-control-allow-private-network'),
          isFalse);
      expect(response.headers['vary'], 'Accept-Encoding, origin');
      expect(response.headers['content-range'], 'bytes 0-4/10');
      expect(response.headers['cache-control'], 'no-store');
      expect(await response.readAsString(), 'range');
    }
  });

  test(
      'native responses strip upstream CORS and preserve multiple Set-Cookie headers',
      () async {
    final handler = lanResponsePolicy()((_) => Response.ok('data', headers: {
          'access-control-allow-origin': '*',
          'set-cookie': ['a=1', 'b=2'],
          'vary': 'Accept-Encoding',
        }));
    final response =
        await handler(Request('GET', Uri.parse('http://host/api/history')));
    expect(
        response.headers.containsKey('access-control-allow-origin'), isFalse);
    expect(response.headersAll['set-cookie'], ['a=1', 'b=2']);
    expect(response.headers['vary'], 'Accept-Encoding, Origin');
  });

  test(
      'HEAD and remote identity, Basic, Range and custom upstream headers pass preflight',
      () async {
    var dispatched = false;
    const requested =
        'Authorization, Range, X-Proxy-Url, X-NipaPlay-Remote-Client-Id, X-NipaPlay-Remote-Client-Name, X-NipaPlay-Remote-Client-Platform, X-Api-Key';
    final handler = lanResponsePolicy()((_) {
      dispatched = true;
      return Response.notFound('unused');
    });
    final response = await handler(
        Request('OPTIONS', Uri.parse('http://host/api/web_proxy'), headers: {
      'Origin': 'https://independent.example',
      'Access-Control-Request-Method': 'HEAD',
      'Access-Control-Request-Headers': requested,
    }));
    expect(response.statusCode, 200);
    expect(dispatched, isFalse);
    expect(response.headers['access-control-allow-methods'], contains('HEAD'));
    expect(response.headers['access-control-allow-headers'], requested);
    expect(response.headers['vary'], 'Origin');
  });

  test(
      'success and error responses containing input keys never cache or send Referer',
      () async {
    for (final status in [200, 400, 401, 403, 404, 409, 500]) {
      final handler =
          lanResponsePolicy()((_) => Response(status, body: 'page'));
      final response = await handler(Request(
          'GET', Uri.parse('http://host/api/remote/input/secret?format=json')));
      expect(response.headers['cache-control'], 'no-store');
      expect(response.headers['referrer-policy'], 'no-referrer');
    }
  });

  test(
      'logs redact queries, credentials, dynamic keys, unknown paths and errors',
      () async {
    final output = <String>[];
    final handler =
        lanRequestLog(write: output.add)((_) => Response.ok('secret-body'));
    for (final url in [
      'http://user:secret-password@host/api/web_proxy?url=https://target/?key=secret-key',
      'http://host/api/image_proxy?url=secret-target',
      'http://host/api/remote/input/secret-input?key=secret-key',
      'http://host/api/media/local/share/episodes/secret-share/stream',
      'http://host/secret-static?token=secret-token',
      'http://host/api/unknown-secret',
    ]) {
      await handler(Request('GET', Uri.parse(url),
          headers: {'authorization': 'Bearer secret-token'}));
    }
    final failing = lanRequestLog(write: output.add)(
        (_) => throw StateError('secret-error'));
    await expectLater(
        failing(Request('POST', Uri.parse('http://host/api/dandanplay/login'))),
        throwsStateError);
    expect(output.join('\n'), isNot(contains('secret')));
    expect(output[2], contains('/api/remote/input/<key>'));
    expect(output[3],
        contains('/api/media/local/share/episodes/<shareId>/stream'));
    expect(output.last, contains('500'));
  });

  // R1 §3 callers retain their request/response contract at the changed HTTP boundary.
  const callers = <String, List<(String, String)>>{
    'C1': [('GET', 'info')],
    'C2': [('GET', 'bangumi/calendar')],
    'C3': [('GET', 'bangumi/detail/1')],
    'C4': [('GET', 'bangumi/login_status')],
    'C5': [
      ('GET', 'danmaku/video_info'),
      ('POST', 'danmaku/match'),
      ('GET', 'danmaku/load')
    ],
    'C6': [('GET', 'image_proxy')],
    'C7': [
      ('GET', 'search/config'),
      ('POST', 'search/by-tags'),
      ('POST', 'search/advanced')
    ],
    'C8': [
      ('GET', 'dandanplay/login_status'),
      ('POST', 'dandanplay/login'),
      ('POST', 'dandanplay/logout'),
      ('POST', 'dandanplay/refresh_login'),
      ('GET', 'dandanplay/bangumi/oauth_login'),
      ('GET', 'dandanplay/webtoken'),
      ('GET', 'dandanplay/play_history'),
      ('GET', 'dandanplay/favorites'),
      ('POST', 'dandanplay/send_danmaku'),
      ('POST', 'dandanplay/add_play_history'),
      ('POST', 'dandanplay/add_favorite'),
      ('DELETE', 'dandanplay/remove_favorite/1')
    ],
    'C9': [('GET', 'media/local/items')],
    'C10': [('GET', 'history'), ('POST', 'history/progress')],
    'C11': [
      ('GET', 'web_proxy'),
      ('HEAD', 'web_proxy'),
      ('POST', 'web_proxy'),
      ('PUT', 'web_proxy'),
      ('PATCH', 'web_proxy'),
      ('DELETE', 'web_proxy')
    ],
    'C12': [
      ('GET', 'media/local/share/animes'),
      ('GET', 'media/local/share/animes/1'),
      ('GET', 'media/local/share/episodes/id/stream')
    ],
    'C13': [
      ('HEAD', 'media/local/share/episodes/id/stream'),
      ('GET', 'media/local/share/episodes/id/subtitles'),
      ('GET', 'media/local/share/episodes/id/subtitle'),
      ('GET', 'media/local/share/episodes/id/audio'),
      ('GET', 'media/local/share/episodes/id/audio_file'),
      ('GET', 'media/local/share/episodes/id/fonts'),
      ('GET', 'media/local/share/episodes/id/font'),
      ('GET', 'media/local/manage/subtitles'),
      ('GET', 'media/local/manage/subtitle')
    ],
    'C14': [
      ('POST', 'media/local/share/episodes/id/progress'),
      ('POST', 'media/local/share/episodes/id/thumbnail')
    ],
    'C15': [
      ('GET', 'media/local/manage/folders'),
      ('POST', 'media/local/manage/folders'),
      ('DELETE', 'media/local/manage/folders'),
      ('GET', 'media/local/manage/browse'),
      ('GET', 'media/local/manage/stream'),
      ('HEAD', 'media/local/manage/stream'),
      ('GET', 'media/local/manage/scan/status'),
      ('POST', 'media/local/manage/scan/rescan'),
      ('POST', 'media/local/manage/webdav'),
      ('DELETE', 'media/local/manage/webdav'),
      ('GET', 'media/local/manage/webdav/list'),
      ('POST', 'media/local/manage/webdav/test'),
      ('POST', 'media/local/manage/webdav/scan'),
      ('POST', 'media/local/manage/smb'),
      ('DELETE', 'media/local/manage/smb'),
      ('GET', 'media/local/manage/smb/list'),
      ('POST', 'media/local/manage/smb/test'),
      ('POST', 'media/local/manage/smb/scan')
    ],
    'C16': [
      ('GET', 'settings/network/jellyfin'),
      ('POST', 'settings/network/jellyfin'),
      ('GET', 'settings/network/emby'),
      ('POST', 'settings/network/emby'),
      ('GET', 'settings/network/dandanplay'),
      ('POST', 'settings/network/dandanplay')
    ],
    'C17': [
      ('GET', 'remote/control/state'),
      ('POST', 'remote/control/command')
    ],
    'C18': [
      ('GET', 'remote/input/opaque-key'),
      ('POST', 'remote/input/opaque-key')
    ],
  };
  for (final caller in callers.entries) {
    test('${caller.key} native, same-origin Web and independent Web contracts',
        () async {
      for (final origin in [
        null,
        'http://host:1180',
        'https://independent.example'
      ]) {
        for (final (method, route) in caller.value) {
          final request = Request(
              method,
              Uri.parse(
                  'http://user:pass@host:1180/api/$route?path=original&url=target'),
              headers: {
                if (origin != null) 'origin': origin,
                'authorization': 'Basic dXNlcjpwYXNz',
                'range': 'bytes=1-3',
                'x-nipaplay-remote-client-id': 'controller',
                'content-type': 'text/plain'
              },
              body: method == 'GET' || method == 'HEAD'
                  ? null
                  : jsonEncode({'path': '/media', 'scan': false}));
          final handler = lanResponsePolicy()((received) async {
            expect(identical(received, request), isTrue);
            if (method != 'GET' && method != 'HEAD') {
              expect(jsonDecode(await received.readAsString()),
                  {'path': '/media', 'scan': false});
            }
            return Response(method == 'HEAD' ? 206 : 200,
                body: method == 'HEAD' ? null : 'original-payload',
                headers: {
                  'content-type': 'application/json',
                  'content-range': 'bytes 1-3/10'
                });
          });
          final response = await handler(request);
          expect(response.statusCode, method == 'HEAD' ? 206 : 200);
          expect(await response.readAsString(),
              method == 'HEAD' ? '' : 'original-payload');
          expect(response.headers['content-range'], 'bytes 1-3/10');
          expect(response.headers['cache-control'], 'no-store');
          expect(lanRouteTemplate(request), isNot('/api/<unmatched>'));
          if (origin != null) {
            expect(response.headers['access-control-allow-origin'], origin);
          }
        }
      }
    });
  }
}

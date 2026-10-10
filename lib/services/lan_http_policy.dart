import 'package:shelf/shelf.dart';

/// Classic LAN transport keeps its existing cross-origin access contract.
Middleware lanResponsePolicy() => (inner) => (request) async {
      final origin = request.headers['origin'];
      final response = request.method == 'OPTIONS' && origin != null
          ? Response.ok('')
          : await inner(request);
      final headers = <String, Object?>{
        for (final key in response.headers.keys)
          if (key.toLowerCase().startsWith('access-control-')) key: null,
      };
      final vary = (response.headers['vary'] ?? '')
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();
      if (!vary.any((value) => value.toLowerCase() == 'origin')) {
        vary.add('Origin');
      }
      headers['vary'] = vary.join(', ');
      if (origin != null) {
        headers.addAll({
          'access-control-allow-origin': origin,
          'access-control-allow-credentials': 'true',
          'access-control-allow-methods':
              'GET, HEAD, POST, PUT, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers': request
                  .headers['access-control-request-headers'] ??
              'Origin, X-Requested-With, Content-Type, Accept, Authorization, Range, X-Proxy-Url, X-NipaPlay-Remote-Client-Id, X-NipaPlay-Remote-Client-Name, X-NipaPlay-Remote-Client-Platform',
          'access-control-expose-headers':
              'Content-Length, Content-Range, Accept-Ranges, Content-Disposition, X-Error-Message',
          'access-control-max-age': '86400',
        });
      }
      final path = request.url.path;
      if (path == 'api' || path.startsWith('api/')) {
        headers['cache-control'] = 'no-store';
      }
      if (path.startsWith('api/remote/input/')) {
        headers['referrer-policy'] = 'no-referrer';
      }
      return response.change(headers: headers);
    };

/// Dynamic path components and unknown routes never enter diagnostic output.
String lanRouteTemplate(Request request) {
  final segments = request.url.pathSegments;
  if (segments.isEmpty || segments.first != 'api') return '/<web-ui>';
  for (final template in _routes) {
    final parts = template.split('/');
    if (parts.length != segments.length - 1) continue;
    var matches = true;
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].startsWith('<') && parts[i] != segments[i + 1]) {
        matches = false;
        break;
      }
    }
    if (matches) return '/api/$template';
  }
  return '/api/<unmatched>';
}

Middleware lanRequestLog({required void Function(String) write}) =>
    (inner) => (request) async {
          final timer = Stopwatch()..start();
          var status = 500;
          try {
            final response = await inner(request);
            status = response.statusCode;
            return response;
          } finally {
            const methods = {
              'GET',
              'HEAD',
              'POST',
              'PUT',
              'PATCH',
              'DELETE',
              'OPTIONS'
            };
            final method =
                methods.contains(request.method) ? request.method : '<method>';
            write(
                '[WebServer] $method ${lanRouteTemplate(request)} $status ${timer.elapsedMilliseconds}ms');
          }
        };

const _routes = [
  'info',
  'bangumi/calendar',
  'bangumi/detail/<id>',
  'bangumi/login_status',
  'danmaku/video_info',
  'danmaku/match',
  'danmaku/load',
  'image_proxy',
  'web_proxy',
  'search/config',
  'search/by-tags',
  'search/advanced',
  'dandanplay/login_status',
  'dandanplay/login',
  'dandanplay/logout',
  'dandanplay/refresh_login',
  'dandanplay/bangumi/oauth_login',
  'dandanplay/webtoken',
  'dandanplay/play_history',
  'dandanplay/favorites',
  'dandanplay/send_danmaku',
  'dandanplay/add_play_history',
  'dandanplay/add_favorite',
  'dandanplay/remove_favorite/<animeId>',
  'media/libraries',
  'media/local/items',
  'media/local/item/<animeId>',
  'history',
  'history/progress',
  'media/local/share/animes',
  'media/local/share/animes/<animeId>',
  'media/local/share/history',
  'media/local/share/episodes/<shareId>/stream',
  'media/local/share/episodes/<shareId>/subtitles',
  'media/local/share/episodes/<shareId>/subtitle',
  'media/local/share/episodes/<shareId>/audio',
  'media/local/share/episodes/<shareId>/audio_file',
  'media/local/share/episodes/<shareId>/fonts',
  'media/local/share/episodes/<shareId>/font',
  'media/local/share/episodes/<shareId>/progress',
  'media/local/share/episodes/<shareId>/thumbnail',
  'media/local/manage/folders',
  'media/local/manage/webdav',
  'media/local/manage/webdav/list',
  'media/local/manage/webdav/test',
  'media/local/manage/webdav/scan',
  'media/local/manage/smb',
  'media/local/manage/smb/list',
  'media/local/manage/smb/test',
  'media/local/manage/smb/scan',
  'media/local/manage/browse',
  'media/local/manage/stream',
  'media/local/manage/subtitles',
  'media/local/manage/subtitle',
  'media/local/manage/scan/status',
  'media/local/manage/scan/rescan',
  'settings/network/jellyfin',
  'settings/network/emby',
  'settings/network/dandanplay',
  'remote/control/state',
  'remote/control/command',
  'remote/input/<key>',
];

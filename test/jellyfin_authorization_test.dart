import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nipaplay/models/jellyfin_transcode_settings.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousOverrides = HttpOverrides.current;
  // Exercise real HTTP against loopback fixtures, without Flutter's HTTP mock.
  HttpOverrides.global = null;
  tearDownAll(() => HttpOverrides.global = previousOverrides);

  setUp(() {
    SharedPreferences.setMockInitialValues({'server_profiles': '[]'});
    PackageInfo.setMockInitialValues(
      appName: 'NipaPlay',
      packageName: 'nipaplay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('login and library requests work with legacy authorization disabled',
      () async {
    final fixture = await _MediaServerFixture.start();
    addTearDown(fixture.close);
    final jellyfin = JellyfinService.instance..accessToken = 'stale-token';
    addTearDown(() => _reset(jellyfin));

    expect(await jellyfin.connect(fixture.baseUrl, 'viewer', 'test-password'),
        isTrue);
    expect(jellyfin.accessToken, _token);
    expect(jellyfin.availableLibraries.single.id, 'library-1');

    // Check both the saved-profile retry path and the direct request path.
    expect(await jellyfin.getFolderItems('library-1'), hasLength(1));
    jellyfin.currentProfile = null;
    expect(await jellyfin.getFolderItems('library-1'), hasLength(1));

    final login = fixture.requests.singleWhere(
      (request) => request.uri.path.endsWith('/Users/AuthenticateByName'),
    );
    expect(login.headers['authorization'], startsWith('MediaBrowser '));
    for (final field in ['Client', 'Device', 'DeviceId', 'Version']) {
      expect(login.headers['authorization'], matches('$field="[^"]+"'));
    }
    expect(login.headers['authorization'], isNot(contains('Token=')));
    expect(
        jsonDecode(login.body), {'Username': 'viewer', 'Pw': 'test-password'});
    expect(fixture.rejectedRequests, isEmpty);
    expect(
        fixture.requests.any(
            (request) => request.headers.containsKey('x-emby-authorization')),
        isFalse);
  });

  test('direct play, HLS and external subtitles use the supported ApiKey',
      () async {
    final fixture = await _MediaServerFixture.start();
    addTearDown(fixture.close);
    final jellyfin = JellyfinService.instance
      ..serverUrl = fixture.baseUrl
      ..accessToken = _token
      ..userId = 'user-1'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() => _reset(jellyfin));

    final session = await jellyfin.createPlaybackSession(
      itemId: 'episode-1',
      mediaSourceId: 'source-1',
      playSessionId: 'session-1',
    );
    final subtitles = await jellyfin.getSubtitleTracks('episode-1');
    expect(subtitles, hasLength(1));
    final urls = [
      jellyfin.getStreamUrl('episode-1'),
      jellyfin.getStreamUrlWithOptions('episode-1',
          quality: JellyfinVideoQuality.bandwidth5m),
      await jellyfin.buildHlsUrlWithOptions('episode-1',
          quality: JellyfinVideoQuality.bandwidth5m, subtitleStreamIndex: 3),
      session.streamUrl,
      subtitles.single['downloadUrl'] as String,
    ];

    for (final url in urls) {
      final uri = Uri.parse(url);
      expect(uri.path, startsWith('/jellyfin/Videos/'));
      expect(uri.queryParameters['ApiKey'], _token);
      expect(uri.queryParameters, isNot(contains('api_key')));
      expect((await http.get(uri)).statusCode, HttpStatus.ok);
    }
    expect(Uri.parse(session.streamUrl).queryParameters,
        containsPair('MediaSourceId', 'source-1'));
    expect(Uri.parse(session.streamUrl).queryParameters,
        containsPair('PlaySessionId', 'session-1'));
    expect(fixture.rejectedRequests, isEmpty);
  });

  test('shared API changes preserve the Emby authorization header', () async {
    final fixture = await _MediaServerFixture.start(
      authorizationHeader: 'x-emby-authorization',
    );
    addTearDown(fixture.close);
    final emby = EmbyService.instance
      ..serverUrl = fixture.baseUrl
      ..accessToken = _token
      ..userId = 'user-1'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() => _reset(emby));

    expect(await emby.getFolderItems('library-1'), hasLength(1));
    expect(fixture.requests.single.headers['x-emby-authorization'],
        contains('Token="$_token"'));
    expect(fixture.requests.single.headers, isNot(contains('authorization')));
    expect(fixture.rejectedRequests, isEmpty);
  });
}

const _token = 'fixture-token';

void _reset(MediaServerServiceBase service) {
  service
    ..serverUrl = null
    ..accessToken = null
    ..userId = null
    ..username = null
    ..password = null
    ..currentProfile = null
    ..currentAddressId = null
    ..isConnected = false
    ..isReady = false;
}

typedef _RecordedRequest = ({
  Uri uri,
  Map<String, String> headers,
  String body,
});

class _MediaServerFixture {
  _MediaServerFixture(this.server, this.authorizationHeader);

  final HttpServer server;
  final String authorizationHeader;
  final requests = <_RecordedRequest>[];
  final rejectedRequests = <Uri>[];

  String get baseUrl =>
      'http://${server.address.address}:${server.port}/jellyfin';

  static Future<_MediaServerFixture> start({
    String authorizationHeader = 'authorization',
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fixture = _MediaServerFixture(server, authorizationHeader);
    server.listen(fixture.handle);
    return fixture;
  }

  Future<void> close() async {
    await server.close(force: true);
  }

  Future<void> handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((key, values) => headers[key] = values.join(','));
    requests.add((
      uri: request.uri,
      headers: headers,
      body: await utf8.decoder.bind(request).join(),
    ));
    final path = request.uri.path;
    final isPublic = path.endsWith('/System/Info/Public');
    final isLogin = path.endsWith('/Users/AuthenticateByName');
    final authorization = headers[authorizationHeader] ?? '';
    final hasClient = authorization.startsWith('MediaBrowser ') &&
        ['Client', 'Device', 'DeviceId', 'Version'].every(
          (field) => RegExp('$field="[^"]+"').hasMatch(authorization),
        );
    final allowed = isPublic ||
        (isLogin
            ? hasClient && !authorization.contains('Token=')
            : (hasClient && authorization.contains('Token="$_token"')) ||
                request.uri.queryParameters['ApiKey'] == _token);

    if (!allowed) {
      rejectedRequests.add(request.uri);
      request.response.statusCode = isLogin ? 400 : 401;
    } else {
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(isPublic
          ? {'Id': 'server-1', 'ServerName': 'Fixture', 'Version': '12.0.0'}
          : isLogin
              ? {
                  'AccessToken': _token,
                  'User': {'Id': 'user-1'}
                }
              : path.endsWith('/UserViews')
                  ? {
                      'Items': [
                        {
                          'Id': 'library-1',
                          'Name': 'Anime',
                          'CollectionType': 'tvshows'
                        }
                      ]
                    }
                  : path.endsWith('/PlaybackInfo')
                      ? {
                          'MediaSources': [
                            {
                              'Id': 'source-1',
                              'MediaStreams': [
                                {
                                  'Type': 'Subtitle',
                                  'Index': 3,
                                  'IsExternal': true,
                                  'Codec': 'srt'
                                }
                              ]
                            }
                          ]
                        }
                      : {
                          'Items': [
                            {
                              'Id': 'episode-1',
                              'Name': 'Episode 1',
                              'Type': 'Episode'
                            }
                          ],
                          'TotalRecordCount': 1
                        }));
    }
    await request.response.close();
  }
}

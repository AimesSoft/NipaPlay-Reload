import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/services/emby_playback_sync_service.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Emby and Jellyfin playback sync use the configured User-Agent',
      () async {
    final embyRequests = <_RecordedRequest>[];
    final jellyfinRequests = <_RecordedRequest>[];
    final embyServer = await _startServer(
      embyRequests,
      itemResponse: {
        'UserData': {'PlayCount': 0},
      },
    );
    final jellyfinServer = await _startServer(
      jellyfinRequests,
      itemResponse: {'PlayCount': 0},
    );
    addTearDown(() => embyServer.close(force: true));
    addTearDown(() => jellyfinServer.close(force: true));

    await MediaServerServiceBase.saveConnectionUserAgent('SyncClient/4.0');
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final emby = EmbyService.instance
      ..serverUrl = 'http://${embyServer.address.address}:${embyServer.port}'
      ..accessToken = 'emby-token'
      ..userId = 'emby-user'
      ..currentProfile = null
      ..isConnected = true;
    final jellyfin = JellyfinService.instance
      ..serverUrl =
          'http://${jellyfinServer.address.address}:${jellyfinServer.port}'
      ..accessToken = 'jellyfin-token'
      ..userId = 'jellyfin-user'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() {
      emby
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
      jellyfin
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
    });
    final localHistory = WatchHistoryItem(
      filePath: 'test.mp4',
      animeName: 'Test',
      watchProgress: 0,
      lastPosition: 0,
      duration: 1000,
      lastWatchTime: DateTime.utc(2024),
    );
    final embySync = EmbyPlaybackSyncService();
    final jellyfinSync = JellyfinPlaybackSyncService();
    addTearDown(embySync.dispose);
    addTearDown(jellyfinSync.dispose);

    await embySync.syncOnPlayStart('emby-item', localHistory);
    await jellyfinSync.syncOnPlayStart('jellyfin-item', localHistory);
    await embySync.reportPlaybackStart(
      'emby-item',
      localHistory,
      playbackSession: PlaybackSession(
        itemId: 'emby-item',
        streamUrl: 'http://stream.invalid/emby',
        isTranscoding: false,
        mediaSourceId: 'emby-source',
        playSessionId: 'emby-session',
      ),
    );
    await jellyfinSync.reportPlaybackStart(
      'jellyfin-item',
      localHistory,
      playbackSession: PlaybackSession(
        itemId: 'jellyfin-item',
        streamUrl: 'http://stream.invalid/jellyfin',
        isTranscoding: false,
        mediaSourceId: 'jellyfin-source',
        playSessionId: 'jellyfin-session',
      ),
    );

    expect(embyRequests, hasLength(2));
    expect(jellyfinRequests, hasLength(2));
    expect(
      [...embyRequests, ...jellyfinRequests]
          .map((request) => request.userAgent),
      everyElement('SyncClient/4.0'),
    );
    expect(embyRequests.first.method, 'GET');
    expect(embyRequests.last.method, 'POST');
    expect(embyRequests.last.token, 'emby-token');
    expect(
      jsonDecode(embyRequests.last.body),
      containsPair('PlaySessionId', 'emby-session'),
    );
    expect(jellyfinRequests.first.method, 'GET');
    expect(jellyfinRequests.last.method, 'POST');
    expect(jellyfinRequests.last.token, 'jellyfin-token');
    expect(
      jsonDecode(jellyfinRequests.last.body),
      containsPair('PlaySessionId', 'jellyfin-session'),
    );
  });

  test('Emby and Jellyfin subtitle downloads use the configured User-Agent',
      () async {
    final previousPathProvider = PathProviderPlatform.instance;
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'nipaplay-subtitle-ua-test-',
    );
    PathProviderPlatform.instance = _TemporaryPathProvider(
      temporaryDirectory.path,
    );
    addTearDown(() async {
      PathProviderPlatform.instance = previousPathProvider;
      await temporaryDirectory.delete(recursive: true);
    });
    final embyUserAgents = <String?>[];
    final jellyfinUserAgents = <String?>[];
    final embyServer = await _startSubtitleServer(embyUserAgents);
    final jellyfinServer = await _startSubtitleServer(jellyfinUserAgents);
    addTearDown(() => embyServer.close(force: true));
    addTearDown(() => jellyfinServer.close(force: true));

    await MediaServerServiceBase.saveConnectionUserAgent('SubtitleClient/2.0');
    addTearDown(() => MediaServerServiceBase.saveConnectionUserAgent(''));
    final emby = EmbyService.instance
      ..serverUrl = 'http://${embyServer.address.address}:${embyServer.port}'
      ..accessToken = 'emby-token'
      ..userId = 'emby-user'
      ..currentProfile = null
      ..isConnected = true;
    final jellyfin = JellyfinService.instance
      ..serverUrl =
          'http://${jellyfinServer.address.address}:${jellyfinServer.port}'
      ..accessToken = 'jellyfin-token'
      ..userId = 'jellyfin-user'
      ..currentProfile = null
      ..isConnected = true;
    addTearDown(() {
      emby
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
      jellyfin
        ..isConnected = false
        ..serverUrl = null
        ..accessToken = null
        ..userId = null;
    });

    final embyFile = await emby.downloadSubtitleFile('emby-item', 0, 'srt');
    final jellyfinFile =
        await jellyfin.downloadSubtitleFile('jellyfin-item', 0, 'srt');
    addTearDown(() async {
      if (embyFile != null) await File(embyFile).delete();
      if (jellyfinFile != null) await File(jellyfinFile).delete();
    });

    expect(embyFile, isNotNull);
    expect(jellyfinFile, isNotNull);
    expect(embyUserAgents, hasLength(2));
    expect(jellyfinUserAgents, hasLength(2));
    expect(embyUserAgents, everyElement('SubtitleClient/2.0'));
    expect(jellyfinUserAgents, everyElement('SubtitleClient/2.0'));
  });
}

Future<HttpServer> _startSubtitleServer(List<String?> userAgents) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    userAgents.add(request.headers.value(HttpHeaders.userAgentHeader));
    if (request.uri.path.endsWith('/PlaybackInfo')) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'MediaSources': [
            {'Id': 'source-id'},
          ],
        }));
    } else {
      request.response
        ..statusCode = HttpStatus.ok
        ..write('1\n00:00:00,000 --> 00:00:01,000\nSubtitle');
    }
    await request.response.close();
  });
  return server;
}

Future<HttpServer> _startServer(
  List<_RecordedRequest> requests, {
  required Map<String, Object> itemResponse,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requests.add(
      _RecordedRequest(
        method: request.method,
        uri: request.requestedUri,
        body: await utf8.decoder.bind(request).join(),
        token: request.headers.value('x-emby-token'),
        userAgent: request.headers.value('user-agent'),
      ),
    );
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(itemResponse));
    await request.response.close();
  });
  return server;
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.body,
    required this.token,
    required this.userAgent,
  });

  final String method;
  final Uri uri;
  final String body;
  final String? token;
  final String? userAgent;
}

class _TemporaryPathProvider extends PathProviderPlatform {
  _TemporaryPathProvider(this.path);

  final String path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

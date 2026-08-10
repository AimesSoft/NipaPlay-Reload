import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/media_server_playback.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/emby_media_source_catalog.dart';

void main() {
  test('coalesces concurrent loads and keeps the completed result per scope',
      () async {
    var loaderCalls = 0;
    final response = Completer<List<PlaybackMediaSource>>();
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) {
        loaderCalls++;
        return response.future;
      },
    );

    final first = catalog.load('account-a', 'episode-1');
    final second = catalog.load('account-a', 'episode-1');
    expect(loaderCalls, 1);

    response.complete([_source('source-a', 'WEB-DL.Baha')]);
    final results = await Future.wait([first, second]);

    expect(identical(results.first, results.last), isTrue);
    expect(results.first.single.source.id, 'source-a');
    await catalog.load('account-a', 'episode-1');
    expect(loaderCalls, 1);
  });

  test('expires a completed entry after its TTL', () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async => [_source('source-${++loaderCalls}', 'Baha')],
      ttl: Duration.zero,
    );

    final first = await catalog.load('account-a', 'episode-1');
    final second = await catalog.load('account-a', 'episode-1');

    expect(first.single.source.id, 'source-1');
    expect(second.single.source.id, 'source-2');
    expect(loaderCalls, 2);
  });

  test('coalesces a slow in-flight load and starts TTL after completion',
      () async {
    var now = DateTime.utc(2026, 8, 9, 12);
    final responses = <Completer<List<PlaybackMediaSource>>>[];
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) {
        final response = Completer<List<PlaybackMediaSource>>();
        responses.add(response);
        return response.future;
      },
      ttl: const Duration(minutes: 1),
      now: () => now,
    );

    final first = catalog.load('account-a', 'episode-1');
    now = now.add(const Duration(minutes: 2));
    final joinedAfterOriginalTtl = catalog.load('account-a', 'episode-1');
    for (final response in List.of(responses)) {
      response.complete([_source('source-a', 'WEB-DL.Baha')]);
    }
    final initialResults = await Future.wait([first, joinedAfterOriginalTtl]);

    now = now.add(const Duration(seconds: 30));
    final cachedAfterCompletion = await catalog.load('account-a', 'episode-1');
    now = now.add(const Duration(seconds: 31));
    final expired = catalog.load('account-a', 'episode-1');
    if (!responses.last.isCompleted) {
      responses.last.complete([_source('source-b', 'WEB-DL.LoliHouse')]);
    }
    final reloaded = await expired;

    expect(responses, hasLength(2));
    expect(identical(initialResults.first, initialResults.last), isTrue);
    expect(identical(initialResults.first, cachedAfterCompletion), isTrue);
    expect(reloaded.single.source.id, 'source-b');
  });

  test('force refresh replaces a valid entry without clearing its scope',
      () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async => [_source('source-${++loaderCalls}', 'Baha')],
    );

    await catalog.load('account-a', 'episode-1');
    final refreshed = await catalog.load(
      'account-a',
      'episode-1',
      forceRefresh: true,
    );

    expect(refreshed.single.source.id, 'source-2');
    expect(loaderCalls, 2);
  });

  test('keeps different item IDs isolated within the same account scope',
      () async {
    final requestedItemIds = <String>[];
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (itemId) async {
        requestedItemIds.add(itemId);
        return [_source('source-$itemId', 'WEB-DL.Baha')];
      },
    );

    await catalog.load('account-a', 'episode-1');
    await catalog.load('account-a', 'episode-2');
    final cachedFirst = await catalog.load('account-a', 'episode-1');

    expect(requestedItemIds, ['episode-1', 'episode-2']);
    expect(cachedFirst.single.source.id, 'source-episode-1');
  });

  test('removes a failed entry so the next load can retry', () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async {
        loaderCalls++;
        if (loaderCalls == 1) throw StateError('temporary network failure');
        return [_source('source-b', 'WEB-DL.LoliHouse')];
      },
    );

    await expectLater(catalog.load('account-a', 'episode-1'), throwsStateError);
    final retry = await catalog.load('account-a', 'episode-1');

    expect(loaderCalls, 2);
    expect(retry.single.source.id, 'source-b');
  });

  test('invalidates one account scope without evicting another account',
      () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async => [_source('source-${++loaderCalls}', 'Baha')],
    );

    await catalog.load('account-a', 'episode-1');
    await catalog.load('account-b', 'episode-1');
    catalog.invalidateScope('account-a');
    await catalog.load('account-a', 'episode-1');
    await catalog.load('account-b', 'episode-1');

    expect(loaderCalls, 3);
  });

  test('clear evicts every account scope and item entry', () async {
    var loaderCalls = 0;
    final catalog = CachedEmbyMediaSourceCatalog(
      loader: (_) async => [_source('source-${++loaderCalls}', 'Baha')],
    );

    await catalog.load('account-a', 'episode-1');
    await catalog.load('account-b', 'episode-2');
    catalog.clear();
    await catalog.load('account-a', 'episode-1');
    await catalog.load('account-b', 'episode-2');

    expect(loaderCalls, 4);
  });

  test(
      'Emby metadata loading strips playback URLs and does not create a play session',
      () async {
    final requests = <_RecordedRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(
        _RecordedRequest(
          method: request.method,
          uri: request.uri,
          body: await utf8.decoder.bind(request).join(),
        ),
      );
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'PlaySessionId': 'server-session-must-not-escape',
          'MediaSources': [
            {
              'Id': 'source-a',
              'Name': 'WEB-DL.Baha',
              'Size': 536870912,
              'Bitrate': 2800000,
              'DirectStreamUrl': '/Videos/episode-1/stream',
              'TranscodingUrl': '/Videos/episode-1/master.m3u8',
              'MediaStreams': [
                {
                  'Index': 0,
                  'Type': 'Video',
                  'Codec': 'h264',
                  'Height': 1080,
                },
                {
                  'Index': 1,
                  'Type': 'Audio',
                  'Codec': 'aac',
                  'Language': 'jpn',
                },
              ],
            },
          ],
        }));
      await request.response.close();
    });

    final emby = EmbyService.instance;
    final previousServerUrl = emby.serverUrl;
    final previousAccessToken = emby.accessToken;
    final previousUserId = emby.userId;
    final previousProfile = emby.currentProfile;
    final previousConnected = emby.isConnected;
    addTearDown(() async {
      await server.close(force: true);
      emby
        ..currentProfile = previousProfile
        ..serverUrl = previousServerUrl
        ..accessToken = previousAccessToken
        ..userId = previousUserId
        ..isConnected = previousConnected;
    });
    emby
      ..currentProfile = null
      ..serverUrl = 'http://${server.address.address}:${server.port}'
      ..accessToken = 'test-token'
      ..userId = 'test-user'
      ..isConnected = true;

    final sources = await HttpOverrides.runWithHttpOverrides(
      () => emby.getPlaybackMediaSources('episode-1'),
      _RealHttpOverrides(),
    );

    expect(requests, hasLength(1));
    expect(requests.single.method, 'GET');
    expect(requests.single.uri.path, '/emby/Items/episode-1/PlaybackInfo');
    expect(requests.single.uri.queryParameters['UserId'], 'test-user');
    expect(requests.single.uri.queryParameters.containsKey('PlaySessionId'),
        isFalse);
    expect(requests.single.body, isEmpty);
    expect(sources, hasLength(1));
    expect(sources.single.id, 'source-a');
    expect(sources.single.name, 'WEB-DL.Baha');
    expect(sources.single.size, 536870912);
    expect(sources.single.bitRate, 2800000);
    expect(sources.single.directStreamUrl, isNull);
    expect(sources.single.transcodingUrl, isNull);
    expect(sources.single.mediaStreams, [
      {
        'Index': 0,
        'Type': 'Video',
        'Codec': 'h264',
        'Height': 1080,
      },
      {
        'Index': 1,
        'Type': 'Audio',
        'Codec': 'aac',
        'Language': 'jpn',
      },
    ]);
  });
}

PlaybackMediaSource _source(String id, String name) => PlaybackMediaSource(
      id: id,
      name: name,
      mediaStreams: const [
        {
          'Index': 0,
          'Type': 'Video',
          'Codec': 'h264',
          'Height': 1080,
        },
      ],
    );

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.uri,
    required this.body,
  });

  final String method;
  final Uri uri;
  final String body;
}

class _RealHttpOverrides extends HttpOverrides {}

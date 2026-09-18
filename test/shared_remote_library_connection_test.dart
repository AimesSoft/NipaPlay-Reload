import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _macUrl = 'http://192.168.31.118:8080';
const _otherUrl = 'http://192.168.31.119:1180';

http.Response _libraryResponse({int? animeId = 61}) => http.Response(
      jsonEncode({
        'success': true,
        'items': [
          if (animeId != null)
            {'animeId': animeId, 'name': 'Remote anime', 'episodeCount': 1},
        ],
      }),
      200,
    );

Future<SharedRemoteLibraryProvider> _createProvider(
  WidgetTester tester,
  FutureOr<http.Response> Function(http.Request) respond, {
  bool savedHost = true,
  bool secondHost = false,
  bool disposeAutomatically = true,
}) async {
  SharedPreferences.setMockInitialValues({
    if (savedHost) ...{
      'shared_remote_active_host': 'mac',
      'shared_remote_hosts': SharedRemoteHost.encodeList([
        SharedRemoteHost(id: 'mac', displayName: 'Mac', baseUrl: _macUrl),
        if (secondHost)
          SharedRemoteHost(
            id: 'other',
            displayName: 'Other',
            baseUrl: _otherUrl,
          ),
      ]),
    },
  });
  final provider = SharedRemoteLibraryProvider(
    clientFactory: (_) => MockClient((request) async => respond(request)),
  );
  if (disposeAutomatically) {
    await tester.pumpWidget(
      ChangeNotifierProvider<SharedRemoteLibraryProvider>(
        create: (_) => provider,
        lazy: false,
        child: const SizedBox.shrink(),
      ),
    );
  } else {
    await tester.pump();
  }
  return provider;
}

void main() {
  testWidgets(
      'reselecting the active host immediately retries a closed response',
      (tester) async {
    var requests = 0;
    Uri? requestedUri;
    final provider = await _createProvider(tester, (request) {
      requestedUri = request.url;
      if (++requests == 1) {
        throw http.ClientException(
          'Connection closed before full header was received',
          request.url,
        );
      }
      return _libraryResponse();
    });
    expect(requests, 1);
    expect(requestedUri.toString(), '$_macUrl/api/media/local/share/animes');
    expect(provider.errorMessage, contains('Connection closed'));
    expect(provider.animeSummaries, isEmpty);

    await provider.setActiveHost('mac');

    expect(requests, 2);
    expect(provider.hasReachableActiveHost, isTrue);
    expect(provider.errorMessage, isNull);
    expect(provider.animeSummaries.single.animeId, 61);
    await tester.pump(const Duration(minutes: 1));
    expect(requests, 2,
        reason: 'Successful reconnect cancels the pending retry');
  });

  testWidgets('failed discovery connections report failure and reuse the host',
      (tester) async {
    var requests = 0;
    var available = false;
    final provider = await _createProvider(tester, (_) {
      requests++;
      return available ? _libraryResponse() : http.Response('Unavailable', 503);
    }, savedHost: false);

    Future<SharedRemoteHost> connect() => provider.connectOrActivateHost(
          displayName: 'Mac',
          baseUrl: '$_macUrl/',
        );

    await expectLater(connect(), throwsA(isA<Exception>()));
    final hostId = provider.hosts.single.id;
    expect(provider.hosts.single.isOnline, isFalse);
    await expectLater(connect(), throwsA(isA<Exception>()));
    expect(requests, 2);
    expect(provider.hosts.single.id, hostId);

    available = true;
    final connected = await connect();
    expect(requests, 3);
    expect(connected.id, hostId);
    expect(connected.isOnline, isTrue);
    expect(connected.lastError, isNull);
    expect(provider.errorMessage, isNull);
    expect(provider.animeSummaries, hasLength(1));
  });

  testWidgets('a reachable empty library is a successful connection',
      (tester) async {
    final provider = await _createProvider(
      tester,
      (_) => _libraryResponse(animeId: null),
      savedHost: false,
    );

    final host = await provider.connectOrActivateHost(
      displayName: 'Mac',
      baseUrl: _macUrl,
    );
    expect(host.isOnline, isTrue);
    expect(provider.animeSummaries, isEmpty);
    expect(provider.errorMessage, isNull);
  });

  testWidgets('automatic retries back off to 30 seconds and stop on recovery',
      (tester) async {
    var requests = 0;
    var available = false;
    final provider = await _createProvider(tester, (_) {
      requests++;
      return available ? _libraryResponse() : http.Response('Unavailable', 503);
    });
    expect(requests, 1);

    for (final seconds in [1, 2, 4, 8, 16, 30, 30]) {
      final previous = requests;
      await tester.pump(Duration(milliseconds: seconds * 1000 - 1));
      expect(requests, previous);
      await tester.pump(const Duration(milliseconds: 1));
      expect(requests, previous + 1);
    }

    available = true;
    await tester.pump(const Duration(seconds: 30));
    expect(provider.hasReachableActiveHost, isTrue);
    expect(provider.animeSummaries.single.animeId, 61);
    expect(provider.errorMessage, isNull);
    final successfulRequests = requests;
    await tester.pump(const Duration(minutes: 2));
    expect(requests, successfulRequests);

    available = false;
    await provider.refreshLibrary(userInitiated: true);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, successfulRequests + 2,
        reason: 'A new failure starts with the shortest retry delay');
  });

  testWidgets('explicit connection failures also recover automatically',
      (tester) async {
    var requests = 0;
    final provider = await _createProvider(tester, (_) {
      return ++requests == 1
          ? http.Response('Unavailable', 503)
          : _libraryResponse();
    }, savedHost: false);

    await expectLater(
      provider.connectOrActivateHost(displayName: 'Mac', baseUrl: _macUrl),
      throwsA(isA<Exception>()),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 2);
    expect(provider.errorMessage, isNull);
    expect(provider.hasReachableActiveHost, isTrue);
  });

  testWidgets('concurrent refreshes share the current HTTP request',
      (tester) async {
    var requests = 0;
    final response = Completer<http.Response>();
    final provider = await _createProvider(tester, (_) {
      requests++;
      return response.future;
    });

    final refresh = provider.refreshLibrary(userInitiated: true);
    final reconnect = provider.setActiveHost('mac');
    await tester.pump(const Duration(seconds: 2));
    expect(requests, 1);
    expect(provider.isLoading, isTrue);

    response.complete(_libraryResponse());
    await tester.pump();
    await Future.wait([refresh, reconnect]);
    expect(provider.isLoading, isFalse);
    expect(provider.hasReachableActiveHost, isTrue);
  });

  testWidgets('a timed out request is automatically retried', (tester) async {
    var requests = 0;
    final stalledResponse = Completer<http.Response>();
    final provider = await _createProvider(tester, (_) {
      return ++requests == 1 ? stalledResponse.future : _libraryResponse();
    });

    await tester.pump(const Duration(seconds: 10));
    expect(provider.errorMessage, contains('连接超时'));
    expect(provider.errorMessage, contains('1 秒后自动重试'));
    expect(provider.isLoading, isFalse);
    await tester.pump(const Duration(seconds: 1));
    expect(requests, 2);
    expect(provider.hasReachableActiveHost, isTrue);

    stalledResponse.complete(_libraryResponse(animeId: 99));
    await tester.pump();
    expect(provider.animeSummaries.single.animeId, 61);
  });

  testWidgets('switching hosts ignores an old failure and cancels its retries',
      (tester) async {
    final response = Completer<http.Response>();
    final requests = <String>[];
    final provider = await _createProvider(tester, (request) {
      requests.add(request.url.host);
      if (request.url.host == '192.168.31.118') return response.future;
      return _libraryResponse(animeId: 99);
    }, secondHost: true);

    await provider.setActiveHost('other');
    response.completeError(http.ClientException('Connection closed'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));

    expect(requests, ['192.168.31.118', '192.168.31.119']);
    expect(provider.activeHostId, 'other');
    expect(provider.errorMessage, isNull);
    expect(provider.animeSummaries.single.animeId, 99);
  });

  testWidgets('removing the failed host cancels automatic retries',
      (tester) async {
    var requests = 0;
    final provider = await _createProvider(tester, (_) {
      requests++;
      return http.Response('Unavailable', 503);
    });

    await provider.removeHost('mac');
    await tester.pump(const Duration(minutes: 1));
    expect(requests, 1);
    expect(provider.hasActiveHost, isFalse);
  });

  testWidgets('disposing the provider cancels automatic retries',
      (tester) async {
    var requests = 0;
    final provider = await _createProvider(tester, (_) {
      requests++;
      return http.Response('Unavailable', 503);
    }, disposeAutomatically: false);

    provider.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(requests, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a response arriving after disposal cannot notify or retry',
      (tester) async {
    final response = Completer<http.Response>();
    final provider = await _createProvider(
      tester,
      (_) => response.future,
      disposeAutomatically: false,
    );

    provider.dispose();
    response.completeError(http.ClientException('Connection closed'));
    await tester.pump();
    await tester.pump(const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });
}

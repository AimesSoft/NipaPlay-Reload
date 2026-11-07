import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nipaplay/constants/settings_keys.dart';
import 'package:nipaplay/models/shared_remote_library.dart';
import 'package:nipaplay/next/ui/shell/next_ui_preference.dart';
import 'package:nipaplay/providers/labs_settings_provider.dart';
import 'package:nipaplay/providers/shared_remote_library_provider.dart';
import 'package:nipaplay/services/classic_mode_policy.dart';
import 'package:nipaplay/services/emby_service.dart';
import 'package:nipaplay/services/media_server_service_base.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/services/server_history_sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LabsSettingsProvider labs;
  late NextUiPreference preference;
  late void Function() unbind;
  late bool Function() supported;
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      SettingsKeys.labsEnableAgentEndpoint: true,
      NextUiPreference.key: true,
      'shared_remote_active_host': 'fixture',
      'shared_remote_hosts': SharedRemoteHost.encodeList([
        SharedRemoteHost(
            id: 'fixture',
            displayName: 'fixture',
            baseUrl: 'http://127.0.0.1:1180'),
      ]),
    });
    supported = NextUiPreference.deviceHasNext;
    NextUiPreference.deviceHasNext = () => true;
    labs = LabsSettingsProvider(sandboxStatus: () async => false);
    preference = NextUiPreference();
    unbind = ClassicModePolicy.bind(labs, preference);
    await Future.wait([labs.ready, preference.ready]);
    await ClassicModePolicy.acquire();
  });
  tearDown(() {
    unbind();
    labs.dispose();
    preference.dispose();
    NextUiPreference.deviceHasNext = supported;
  });

  test(
      'shared requests and queued retries stop in Next and refresh once on return',
      () async {
    var requests = 0;
    final first = Completer<void>(), restored = Completer<void>();
    final provider = SharedRemoteLibraryProvider(
        clientFactory: (_) => MockClient((_) async {
              requests++;
              if (requests == 1) {
                first.complete();
                return http.Response('{}', 503);
              }
              restored.complete();
              return http.Response('{"items":[]}', 200);
            }));
    addTearDown(provider.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await provider.refreshLibrary();
    expect(requests, 0);
    await preference.setEnabled(false);
    await first.future;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await preference.setEnabled(true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await provider.refreshLibrary();
    expect(requests, 1, reason: 'Next discarded the queued retry');
    await preference.setEnabled(false);
    await restored.future;
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(requests, 2, reason: 'returning to Classic refreshes exactly once');
    await preference.setEnabled(true);
    await provider.refreshLibrary();
    expect(requests, 2);
  });

  test(
      'Jellyfin and Emby history send zero requests in Next and resume when ready in Classic',
      () async {
    final previous = HttpOverrides.current;
    HttpOverrides.global = _DirectHttp();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var requests = 0;
    final received = StreamController<int>.broadcast();
    server.listen((request) async {
      requests++;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({'Items': []}));
      await request.response.close();
      received.add(requests);
    });
    final services = <MediaServerServiceBase>[
      JellyfinService.instance,
      EmbyService.instance
    ];
    final sync = ServerHistorySyncService.instance;
    addTearDown(() async {
      sync.dispose();
      for (final service in services) {
        service
          ..isReady = false
          ..isConnected = false
          ..accessToken = null
          ..userId = null
          ..serverUrl = null;
      }
      await server.close(force: true);
      await received.close();
      HttpOverrides.global = previous;
    });
    for (final service in services) {
      service
        ..currentProfile = null
        ..serverUrl = 'http://127.0.0.1:${server.port}'
        ..accessToken = 'fixture'
        ..userId = 'fixture'
        ..isReady = true
        ..isConnected = true;
    }
    sync.initialize();
    await sync.syncJellyfinResume();
    await sync.syncEmbyResume();
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(requests, 0);
    final resumed = received.stream.firstWhere((count) => count == 2);
    await preference.setEnabled(false);
    await resumed.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 40));
    await preference.setEnabled(true);
    await sync.syncJellyfinResume();
    await sync.syncEmbyResume();
    expect(requests, 2);
    final again = received.stream.firstWhere((count) => count == 4);
    await preference.setEnabled(false);
    await again.timeout(const Duration(seconds: 5));
    expect(requests, 4);
  });
}

class _DirectHttp extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nipaplay/models/server_profile_model.dart';
import 'package:nipaplay/models/watch_history_database.dart';
import 'package:nipaplay/models/watch_history_model.dart';
import 'package:nipaplay/providers/watch_history_provider.dart';
import 'package:nipaplay/services/jellyfin_playback_sync_service.dart';
import 'package:nipaplay/services/jellyfin_service.dart';
import 'package:nipaplay/utils/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  test('history reload waits for an in-flight remote update before reading DB',
      () async {
    final root = await Directory.systemTemp.createTemp('history-reload-race-');
    StorageService.debugAppStorageDirectoryOverride = root;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final baseUrl = 'http://${server.address.address}:${server.port}';
    final profile = ServerProfile(
      id: 'profile',
      serverName: 'Test',
      serverType: 'jellyfin',
      username: 'Test',
      userId: 'user',
      accessToken: 'token',
      addresses: [ServerAddress(id: 'lan', url: baseUrl, name: 'LAN')],
    );
    SharedPreferences.setMockInitialValues({
      'server_profiles': jsonEncode([profile.toJson()]),
      'jellyfin_current_profile_id': profile.id,
    });
    final requestStarted = Completer<void>();
    final releaseResponse = Completer<void>();
    var batches = 0;
    server.listen((request) async {
      if (request.uri.path != '/Users/user/Items') {
        request.response.statusCode = 404;
      } else {
        batches++;
        expect(request.uri.queryParameters['Ids'], 'episode');
        if (!requestStarted.isCompleted) requestStarted.complete();
        await releaseResponse.future;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'Items': [
            {
              'Id': 'episode',
              'RunTimeTicks': 1200000000,
              'UserData': {
                'Played': true,
                'PlaybackPositionTicks': 0,
                'LastPlayedDate': '2026-11-15T00:00:00Z',
              },
            }
          ],
        }));
      }
      await request.response.close();
    });
    final service = JellyfinService.instance
      ..isConnected = false
      ..currentProfile = profile
      ..userId = 'user'
      ..accessToken = 'token'
      ..serverUrl = baseUrl;
    final database = WatchHistoryDatabase.instance;
    final provider = WatchHistoryProvider();
    Future<void>? reload;
    addTearDown(() async {
      if (!releaseResponse.isCompleted) releaseResponse.complete();
      await reload;
      // Drain the normal refresh queued by loadHistory before closing its HTTP
      // server. A disconnected load cannot start another network request.
      service.isConnected = false;
      await provider.loadHistory();
      await Future<void>.delayed(Duration.zero);
      provider.dispose();
      JellyfinPlaybackSyncService().dispose();
      service
        ..isConnected = false
        ..currentProfile = null
        ..userId = null
        ..accessToken = null
        ..serverUrl = null;
      await server.close(force: true);
      await database.close();
      StorageService.debugAppStorageDirectoryOverride = null;
      await root.delete(recursive: true);
    });
    await database.insertOrUpdateWatchHistory(WatchHistoryItem(
      filePath: 'jellyfin://episode',
      animeName: 'Anime',
      watchProgress: .5,
      lastPosition: 60000,
      duration: 120000,
      lastWatchTime: DateTime.utc(2026, 11, 1),
    ));
    await provider.loadHistory();
    // Let the initial disconnected refresh settle, then start the remote call
    // before a later history reload (the opposite of resuming during loading).
    await Future<void>.delayed(Duration.zero);
    service.isConnected = true;
    provider.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await requestStarted.future.timeout(const Duration(seconds: 5));

    var reloadFinished = false;
    reload = provider.loadHistory().then((_) => reloadFinished = true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(reloadFinished, isFalse,
        reason: 'Reading the old DB while the remote update is pending lets '
            'path validation publish stale progress after that update.');
    expect(batches, 1);

    releaseResponse.complete();
    await reload;
    expect(provider.history.single.watchProgress, 1);
    expect(provider.history.single.lastPosition, 0);
    expect(provider.continueWatchingItems, isEmpty);
    final stored = (await database.getHistoryByFilePath('jellyfin://episode'))!;
    expect(stored.watchProgress, 1);
    expect(stored.lastPosition, 0);
  });
}
